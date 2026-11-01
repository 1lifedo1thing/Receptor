#import <UIKit/UIKit.h>

@interface RCFileShareController : NSObject <UIActionSheetDelegate, UIDocumentInteractionControllerDelegate, UIPopoverControllerDelegate> {
    UIViewController *_owner; // owning controller retains this helper
    NSString *_name;
    CGRect _rect;
    UIActionSheet *_sheet;
    UIDocumentInteractionController *_document;
    UIViewController *_activity;
    UIPopoverController *_popover;
}
- (id)initWithViewController:(UIViewController *)controller;
- (void)shareFile:(NSString *)name fromRect:(CGRect)rect;
- (void)openFileInApp:(NSString *)name fromRect:(CGRect)rect;
+ (BOOL)canSaveToPhotos:(NSString *)name;
+ (void)saveToPhotos:(NSString *)name;
@end
