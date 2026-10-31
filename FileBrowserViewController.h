#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

@interface FileBrowserViewController : UITableViewController <QLPreviewControllerDataSource, UIDocumentInteractionControllerDelegate> {
    NSArray *_files;
    NSArray *_activeDownloads;
    NSArray *_previewURLs;
    UIDocumentInteractionController *_documentController;
    NSString *_storageError;
}
@end
