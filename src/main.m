#import "cloudfile.h"
#import <dispatch/dispatch.h>
#import <stdatomic.h>

// Limit concurrent dispatches to avoid GCD thread pool starvation. Without this,
// hundreds of blocking poll loops (e.g. waitForMaterialization) exhaust the thread
// pool and cause dispatch_group_wait to hang indefinitely.
#define MAX_CONCURRENT_OPS 10

void printUsage() {
    printf("Usage: cloudfile <command> <path>\n");
    printf("Commands:\n");
    printf("  materialize      - Download file(s) from the cloud\n");
    printf("  materialize-sync - Download file(s) from the cloud (synchronously)\n");
    printf("  evict            - Remove local copy while keeping it in the cloud\n");
    printf("\n");
    printf("<path> can be a file or directory. Directories are processed recursively.\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            printUsage();
            return 1;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        NSString *path = [NSString stringWithUTF8String:argv[2]];

        NSArray<NSURL *> *fileURLs = collectFileURLs(path);
        if (!fileURLs) return 1;
        if (fileURLs.count == 0) {
            NSLog(@"No files found at path: %@", path);
            return 0;
        }

        NSLog(@"Processing %lu file(s)...", (unsigned long)fileURLs.count);

        if ([command isEqualToString:@"materialize"]) {
            __block atomic_int failureCount = 0;
            dispatch_group_t group = dispatch_group_create();
            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            // Semaphore ensures at most MAX_CONCURRENT_OPS blocks run at once
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(MAX_CONCURRENT_OPS);

            for (NSURL *fileURL in fileURLs) {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                dispatch_group_async(group, queue, ^{
                    int result = requestMaterialization(fileURL);
                    if (result != 0) {
                        atomic_fetch_add(&failureCount, 1);
                    }
                    dispatch_semaphore_signal(semaphore);
                });
            }
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

            int failed = atomic_load(&failureCount);
            if (failed > 0) {
                NSLog(@"%d file(s) failed to materialize.", failed);
                return 1;
            }

            NSLog(@"Requested materialization of %lu file(s).", (unsigned long)fileURLs.count);
        } else if ([command isEqualToString:@"materialize-sync"]) {
            // Kick off all downloads in parallel first
            __block atomic_int failureCount = 0;
            dispatch_group_t group = dispatch_group_create();
            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(MAX_CONCURRENT_OPS);

            for (NSURL *fileURL in fileURLs) {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                dispatch_group_async(group, queue, ^{
                    int result = requestMaterialization(fileURL);
                    if (result != 0) {
                        atomic_fetch_add(&failureCount, 1);
                    }
                    dispatch_semaphore_signal(semaphore);
                });
            }
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

            int failed = atomic_load(&failureCount);
            if (failed > 0) {
                NSLog(@"%d file(s) failed to start materializing.", failed);
                return 1;
            }

            NSLog(@"Materializing %lu file(s) ...", (unsigned long)fileURLs.count);

            // Wait for all downloads in parallel
            failureCount = 0;
            dispatch_group_t waitGroup = dispatch_group_create();
            dispatch_semaphore_t waitSemaphore = dispatch_semaphore_create(MAX_CONCURRENT_OPS);

            for (NSURL *fileURL in fileURLs) {
                dispatch_semaphore_wait(waitSemaphore, DISPATCH_TIME_FOREVER);
                dispatch_group_async(waitGroup, queue, ^{
                    int result = waitForMaterialization(fileURL);
                    if (result != 0) {
                        atomic_fetch_add(&failureCount, 1);
                    }
                    dispatch_semaphore_signal(waitSemaphore);
                });
            }
            dispatch_group_wait(waitGroup, DISPATCH_TIME_FOREVER);

            failed = atomic_load(&failureCount);
            if (failed > 0) {
                NSLog(@"%d file(s) failed to materialize.", failed);
                return 1;
            }

            NSLog(@"Materialized %lu file(s).", (unsigned long)fileURLs.count);
        } else if ([command isEqualToString:@"evict"]) {
            __block atomic_int failureCount = 0;
            dispatch_group_t group = dispatch_group_create();
            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(MAX_CONCURRENT_OPS);

            for (NSURL *fileURL in fileURLs) {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                dispatch_group_async(group, queue, ^{
                    NSFileManager *fileManager = [NSFileManager defaultManager];
                    NSError *error = nil;
                    if (![fileManager evictUbiquitousItemAtURL:fileURL error:&error]) {
                        NSLog(@"Error evicting file %@: %@", fileURL.path, error);
                        atomic_fetch_add(&failureCount, 1);
                    }
                    dispatch_semaphore_signal(semaphore);
                });
            }
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

            int failed = atomic_load(&failureCount);
            if (failed > 0) {
                NSLog(@"%d file(s) failed to evict.", failed);
                return 1;
            }

            NSLog(@"Evicted %lu file(s).", (unsigned long)fileURLs.count);
        } else {
            printUsage();
            return 1;
        }
    }
    return 0;
}

