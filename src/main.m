#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>

void printUsage() {
    printf("Usage: cloudfile <command> <file-path>\n");
    printf("Commands:\n");
    printf("  materialize - Download the file from the cloud\n");
    printf("  materialize-sync - Download the file from the cloud (synchronously)\n");
    printf("  evict - Remove local copy while keeping it in the cloud\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            printUsage();
            return 1;
        }
        
        NSString *command = [NSString stringWithUTF8String:argv[1]];
        NSString *filePath = [NSString stringWithUTF8String:argv[2]];

        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        if ([command isEqualToString:@"materialize"]) {
            NSError *error = nil;
            if (![fileManager startDownloadingUbiquitousItemAtURL:fileURL error:&error]) {
                NSLog(@"Error materializing file: %@", error);
                return 1;
            }
            NSLog(@"Requested materialization of file: %@", filePath);
        } else if ([command isEqualToString:@"materialize-sync"]) {
            NSError *error = nil;
            if (![fileManager startDownloadingUbiquitousItemAtURL:fileURL error:&error]) {
                NSLog(@"Error materializing file: %@", error);
                return 1;
            }
            NSLog(@"Materializing file: %@ ...", filePath);

            // Wait until downloaded locally
            NSTimeInterval timeoutSeconds = 300; // adjust as desired
            NSTimeInterval pollInterval = 0.2;
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];

            while ([deadline timeIntervalSinceNow] > 0) {
                @autoreleasepool {
                    // Ask for relevant iCloud resource values
                    // NSURL caches resource values, so clear between polls.
                    [fileURL removeCachedResourceValueForKey:NSURLUbiquitousItemDownloadingStatusKey];
                    [fileURL removeCachedResourceValueForKey:NSURLUbiquitousItemIsDownloadingKey];
                    [fileURL removeCachedResourceValueForKey:NSURLUbiquitousItemDownloadingErrorKey];

                    NSDictionary<NSURLResourceKey, id> *values =
                        [fileURL resourceValuesForKeys:@[
                            NSURLUbiquitousItemDownloadingStatusKey,
                            NSURLUbiquitousItemIsDownloadingKey,
                            NSURLUbiquitousItemDownloadingErrorKey
                        ] error:&error];

                    if (!values) {
                        // If the file provider is slow to answer, you can choose to keep waiting,
                        // but usually better to fail fast.
                        NSLog(@"Error reading resource values: %@", error);
                        return 1;
                    }

                    error = values[NSURLUbiquitousItemDownloadingErrorKey];
                    if (error) {
                        NSLog(@"Download failed: %@", error);
                        return 1;
                    }

                    NSString *status = values[NSURLUbiquitousItemDownloadingStatusKey];
                    NSNumber *isDownloading = values[NSURLUbiquitousItemIsDownloadingKey];

                    // "Current" means fully downloaded locally.
                    BOOL statusReady = [status isEqualToString:NSURLUbiquitousItemDownloadingStatusCurrent] ||
                                       [status isEqualToString:NSURLUbiquitousItemDownloadingStatusDownloaded];

                    if (statusReady) {
                        NSLog(@"Materialization complete: %@", filePath);
                        break;
                    }

                    // Otherwise keep waiting.
                    // (Even if isDownloading==NO, status may still be "NotDownloaded" or "Downloaded" etc.)
                    (void)isDownloading;
                }

                [NSThread sleepForTimeInterval:pollInterval];
            }

            if ([deadline timeIntervalSinceNow] <= 0) {
                NSLog(@"Timed out waiting for materialization: %@", filePath);
                return 1;
            }
        } else if ([command isEqualToString:@"evict"]) {
            NSError *error = nil;
            if (![fileManager evictUbiquitousItemAtURL:fileURL error:&error]) {
                NSLog(@"Error evicting file: %@", error);
                return 1;
            }
            NSLog(@"Evicted file: %@", filePath);
        } else {
            printUsage();
            return 1;
        }
    }
    return 0;
}

