#import <UIKit/UIKit.h>
@protocol RCPackageManagerDelegate <NSObject>
- (void)packageOperationFinished:(NSDictionary *)result;
@end
@interface RCPackageManager : NSObject {
    id<RCPackageManagerDelegate> _delegate;
    BOOL _busy;
    NSString *_lastOutput;
    UIBackgroundTaskIdentifier _task;
}
@property(nonatomic, assign) id<RCPackageManagerDelegate> delegate;
@property(nonatomic, readonly) BOOL busy;
@property(nonatomic, readonly, copy) NSString *lastOutput;
+ (RCPackageManager *)sharedManager;
- (BOOL)run:(NSArray *)arguments delegate:(id<RCPackageManagerDelegate>)delegate;
@end
