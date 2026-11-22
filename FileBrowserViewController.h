#import <UIKit/UIKit.h>
#if !RC_LEGACY32
#import <QuickLook/QuickLook.h>
#endif
@class RCFileShareController;

@interface FileBrowserViewController : UITableViewController <
#if !RC_LEGACY32
QLPreviewControllerDataSource,
#endif
UIDocumentInteractionControllerDelegate, UIActionSheetDelegate, UIAlertViewDelegate, UISearchBarDelegate> {
    UIDocumentInteractionController *_legacyDocument;
    NSArray *_allFiles;
    NSArray *_files;
    NSArray *_activeDownloads;
    NSArray *_previewURLs;
    RCFileShareController *_sharing;
    NSString *_storageError;
    UIActionSheet *_fileActions;
    NSString *_selectedPackage;
    UIAlertView *_installPrompt;
    UIAlertView *_URLPrompt;
    UITextField *_URLField;
    UISearchBar *_searchBar;
    UISegmentedControl *_layoutControl;
#if RC_LEGACY32
    RC32Cache *_thumbnailCache;
#else
    NSCache *_thumbnailCache;
#endif
    NSOperationQueue *_thumbnailQueue;
    NSMutableSet *_thumbnailPending;
    NSArray *_actionTitles;
    UIAlertView *_deletePrompt;
    CGRect _actionAnchor;
    BOOL _grid;
    NSUInteger _columns;
}
@end
