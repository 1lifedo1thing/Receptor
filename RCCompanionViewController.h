#import <UIKit/UIKit.h>
#import "RCCompanionClient.h"
@interface RCCompanionViewController : UITableViewController <RCCompanionClientDelegate, UIAlertViewDelegate, UITextFieldDelegate> {
    RCCompanionClient *_client;
    UITextField *_address;
    UITextField *_code;
    NSArray *_packages;
    NSString *_status;
    NSString *_pendingName;
    UIAlertView *_installPrompt;
}
@end
