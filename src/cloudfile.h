#import <Foundation/Foundation.h>

NSArray<NSURL *> *collectFileURLs(NSString *path);
int requestMaterialization(NSURL *fileURL);
int waitForMaterialization(NSURL *fileURL);
