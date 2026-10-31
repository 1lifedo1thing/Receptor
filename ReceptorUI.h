#import <UIKit/UIKit.h>

@interface ReceptorUI : NSObject <UIAlertViewDelegate> {
    NSMutableArray *_requests;
    NSMutableArray *_messages;
    NSURLRequest *_promptRequest;
    UIAlertView *_alert;
}
+ (ReceptorUI *)sharedUI;
+ (void)install;
+ (void)promptForRequest:(NSURLRequest *)request;
- (void)showMessage:(NSString *)message;
- (void)showFiles;
@end
