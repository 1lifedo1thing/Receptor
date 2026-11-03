#import <UIKit/UIKit.h>
#import "RCPackageManager.h"
@interface RCPackagesViewController : UITableViewController <RCPackageManagerDelegate, UISearchBarDelegate, UIAlertViewDelegate> {
    NSString *_mode;
    NSArray *_items;
    NSArray *_visible;
    NSDictionary *_selection;
    NSDictionary *_plan;
    NSArray *_pending;
    NSString *_message;
    UISearchBar *_search;
    UIAlertView *_prompt;
    UITextField *_field;
    BOOL _remove;
    BOOL _unsigned;
}
- (id)initWithMode:(NSString *)mode item:(NSDictionary *)item;
@end
