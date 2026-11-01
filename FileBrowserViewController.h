#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

@interface FileBrowserViewController : UITableViewController <QLPreviewControllerDataSource, UIDocumentInteractionControllerDelegate, UIActionSheetDelegate, UIAlertViewDelegate, UISearchBarDelegate> {
    NSArray *_allFiles;
    NSArray *_files;
    NSArray *_activeDownloads;
    NSArray *_previewURLs;
    UIDocumentInteractionController *_documentController;
    NSString *_storageError;
    UIActionSheet *_fileActions;
    NSString *_selectedPackage;
    UIAlertView *_installPrompt;
    UIAlertView *_URLPrompt;
    UITextField *_URLField;
    UISearchBar *_searchBar;
    UISegmentedControl *_layoutControl;
    NSCache *_thumbnailCache;
    NSOperationQueue *_thumbnailQueue;
    NSMutableSet *_thumbnailPending;
    NSArray *_actionTitles;
    UIAlertView *_deletePrompt;
    CGRect _actionAnchor;
    BOOL _grid;
    NSUInteger _columns;
}
@end
