#import <UIKit/UIKit.h>
@interface RCDEBInstaller : NSObject {
    BOOL _busy;
    NSString *_status;
    NSString *_lastOutput;
    UIBackgroundTaskIdentifier _backgroundTask;
}
@property(nonatomic, readonly) BOOL busy;
@property(nonatomic, readonly, copy) NSString *status;
@property(nonatomic, readonly, copy) NSString *lastOutput;
+ (RCDEBInstaller *)sharedInstaller;
- (void)installFileNamed:(NSString *)name;
@end
