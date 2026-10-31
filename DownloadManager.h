#import <UIKit/UIKit.h>

@interface DownloadManager : NSObject {
    NSMutableArray *_tasks;
}
+ (DownloadManager *)sharedManager;
// All public methods and delegate callbacks run on the main thread.
- (BOOL)startDownloadWithRequest:(NSURLRequest *)request error:(NSError **)error;
- (NSArray *)activeDownloads; // dictionaries: identifier, name, received, expected
- (void)cancelDownloadWithIdentifier:(NSString *)identifier;
@end
