#import <UIKit/UIKit.h>

@interface ReceptorUI : NSObject <UIAlertViewDelegate> {
    NSMutableArray *_requests;
    NSMutableArray *_messages;
    NSURLRequest *_promptRequest;
    UIAlertView *_alert;
    UIButton *_filesButton;
    UIWindow *_browserWindow;
    UIWindow *_previousWindow;
}
+ (ReceptorUI *)sharedUI;
+ (void)install;
+ (void)promptForRequest:(NSURLRequest *)request;
- (void)showMessage:(NSString *)message;
- (void)showFiles;
- (void)closeFiles;
@end
