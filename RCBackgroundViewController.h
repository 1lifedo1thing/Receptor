#import <UIKit/UIKit.h>
#import "RCPackageManager.h"
@interface RCBackgroundViewController : UITableViewController <RCPackageManagerDelegate,UIAlertViewDelegate> {
    NSString *_publicKey;
    NSString *_host;
    NSString *_message;
    NSString *_staged;
    NSDictionary *_status;
    UIAlertView *_prompt;
    NSTimer *_refreshTimer;
}
- (id)initWithPublicKey:(NSString *)key host:(NSString *)host;
@end
