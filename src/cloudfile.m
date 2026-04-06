#import "cloudfile.h"
#import <FileProvider/FileProvider.h>

NSArray<NSURL *> *collectFileURLs(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) {
        NSLog(@"Path does not exist: %@", path);
        return nil;
    }

    if (!isDir) {
        return @[[NSURL fileURLWithPath:path]];
    }

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [fm enumeratorAtURL:[NSURL fileURLWithPath:path]
         includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                            options:NSDirectoryEnumerationSkipsHiddenFiles
                       errorHandler:^BOOL(NSURL *url, NSError *error) {
            NSLog(@"Warning: error enumerating %@: %@", url, error);
            return YES; // continue enumeration
        }];

    for (NSURL *url in enumerator) {
        NSNumber *isFile = nil;
        [url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
        if ([isFile boolValue]) {
            [urls addObject:url];
        }
    }
    return urls;
}

int requestMaterialization(NSURL *fileURL) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fileManager startDownloadingUbiquitousItemAtURL:fileURL error:&error]) {
        NSLog(@"Error materializing file: %@", error);
        return 1;
    }
    return 0;
}

int waitForMaterialization(NSURL *fileURL) {
    NSError *error = nil;
    NSTimeInterval timeoutSeconds = 300;
    NSTimeInterval pollInterval = 0.2;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];

    while ([deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
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
                NSLog(@"Error reading resource values for %@: %@", fileURL.path, error);
                return 1;
            }

            error = values[NSURLUbiquitousItemDownloadingErrorKey];
            if (error) {
                NSLog(@"Download failed for %@: %@", fileURL.path, error);
                return 1;
            }

            NSString *status = values[NSURLUbiquitousItemDownloadingStatusKey];

            BOOL statusReady = [status isEqualToString:NSURLUbiquitousItemDownloadingStatusCurrent] ||
                               [status isEqualToString:NSURLUbiquitousItemDownloadingStatusDownloaded];

            if (statusReady) {
                return 0;
            }
        }

        [NSThread sleepForTimeInterval:pollInterval];
    }

    NSLog(@"Timed out waiting for materialization: %@", fileURL.path);
    return 1;
}
