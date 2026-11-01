#import <UIKit/UIKit.h>

BOOL RCIsImageFile(NSString *name);
UIImage *RCFileIcon(NSString *name);
// Returns a bounded, orientation-correct image; never caches the full-size source.
UIImage *RCLoadImageThumbnail(NSString *name, NSUInteger pixels);
@interface RCFileListCell : UITableViewCell
@end

@interface RCFileTile : UIControl {
    NSString *_fileName;
    UIImageView *_artwork;
    UILabel *_nameLabel;
    UILabel *_sizeLabel;
    UIButton *_moreButton;
}
@property(nonatomic, copy) NSString *fileName;
@property(nonatomic, readonly) UIImageView *artwork;
@property(nonatomic, readonly) UIButton *moreButton;
- (void)setName:(NSString *)name size:(NSString *)size editing:(BOOL)editing;
@end

@interface RCImagePreviewController : UIViewController <UIScrollViewDelegate, UIDocumentInteractionControllerDelegate> {
    NSString *_name;
    UIScrollView *_scroll;
    UIImageView *_imageView;
    UIActivityIndicatorView *_spinner;
    UILabel *_message;
    UIDocumentInteractionController *_documentController;
}
- (id)initWithFileName:(NSString *)name;
@end
