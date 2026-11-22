#import <UIKit/UIKit.h>
#if !RC_LEGACY32
#import <QuickLook/QuickLook.h>
#endif

@interface RCFilesystemViewController : UITableViewController <
#if !RC_LEGACY32
QLPreviewControllerDataSource,
#endif
UIDocumentInteractionControllerDelegate, UIActionSheetDelegate> {
    UIDocumentInteractionController *_legacyDocument;
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
