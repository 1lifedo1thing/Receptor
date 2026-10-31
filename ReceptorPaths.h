#import <Foundation/Foundation.h>

extern NSString * const RCDownloadsDirectory;
extern NSString * const RCDownloadsChangedNotification;
NSError *RCError(NSString *message);
BOOL RCEnsureDownloadsDirectory(NSError **error);
NSString *RCSafeFilename(NSString *name);
BOOL RCIsRegularDownload(NSString *name);
BOOL RCIsDownloadRequest(NSURLRequest *request);
