#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

@interface RCFilesystemViewController : UITableViewController <QLPreviewControllerDataSource, UIActionSheetDelegate> {
    NSString *_path;
    NSArray *_entries;
    NSString *_status;
    NSURL *_selectedURL;
    UIActionSheet *_actions;
    NSUInteger _generation;
    NSUInteger _limit;
    BOOL _more;
    BOOL _loading;
}
- (id)initWithPath:(NSString *)path;
@end
