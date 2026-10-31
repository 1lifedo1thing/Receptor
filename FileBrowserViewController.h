#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

@interface FileBrowserViewController : UITableViewController <QLPreviewControllerDataSource, UIDocumentInteractionControllerDelegate, UIActionSheetDelegate, UIAlertViewDelegate> {
    NSArray *_files;
    NSArray *_activeDownloads;
    NSArray *_previewURLs;
    UIDocumentInteractionController *_documentController;
    NSString *_storageError;
    UIActionSheet *_fileActions;
    NSString *_selectedIPA;
    UIAlertView *_installPrompt;
    UIAlertView *_URLPrompt;
    UITextField *_URLField;
}
@end
