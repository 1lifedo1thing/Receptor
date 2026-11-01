#import <UIKit/UIKit.h>
#import "RCCompanionClient.h"
@interface RCSendFileViewController : UITableViewController <RCCompanionClientDelegate> {
    NSString *_path;
    NSString *_status;
    RCCompanionClient *_client;
    BOOL _sending;
    BOOL _changedIdle;
    BOOL _previousIdle;
}
- (id)initWithPath:(NSString *)path;
@end
