#import <UIKit/UIKit.h>
@interface RCRespring : NSObject <UIAlertViewDelegate> {
    UIAlertView *_prompt;
    BOOL _busy;
}
@property(nonatomic, readonly) BOOL busy;
+ (RCRespring *)sharedController;
- (void)requestRespring;
@end
