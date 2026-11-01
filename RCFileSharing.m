#import "RCFileSharing.h"
#import "RCFileArtwork.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>

// UIActivityViewController is public on iOS 6; resolve it at runtime for SDK 5 / iOS 4–5.
@interface NSObject (RCLegacyActivityAPI)
- (id)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities;
- (void)setCompletionHandler:(void (^)(NSString *, BOOL))handler;
@end

static BOOL RCIsVideoFile(NSString *name) {
    NSString *extension = [[name pathExtension] lowercaseString];
    return [extension isEqualToString:@"mov"] || [extension isEqualToString:@"mp4"] || [extension isEqualToString:@"m4v"];
}
@interface RCPhotoSaver : NSObject {
    ALAssetsLibrary *_library;
    NSData *_data;
    UIImage *_image;
    NSString *_name;
    BOOL _busy;
    UIBackgroundTaskIdentifier _backgroundTask;
}
+ (RCPhotoSaver *)sharedSaver;
- (void)save:(NSString *)name;
- (void)saveOnWorker:(NSString *)name;
- (void)finished:(NSError *)error;
@end
@implementation RCPhotoSaver
+ (RCPhotoSaver *)sharedSaver {
    static RCPhotoSaver *saver = nil;
    if (!saver) saver = [[self alloc] init]; return saver;
}
- (id)init {
    if ((self = [super init])) { _library = [[ALAssetsLibrary alloc] init]; _backgroundTask = UIBackgroundTaskInvalid; }
    return self;
}
- (void)save:(NSString *)name {
    NSAssert([NSThread isMainThread], @"Main thread required");
    if (_busy) { [[ReceptorUI sharedUI] showMessage:@"A file is already being saved to Photos. Please wait."]; return; }
    if (!RCIsRegularDownload(name)) { [[ReceptorUI sharedUI] showMessage:@"This file is no longer available."]; return; }
    _busy = YES; _name = [name copy];
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        UIBackgroundTaskIdentifier task = _backgroundTask; _backgroundTask = UIBackgroundTaskInvalid;
        if (task != UIBackgroundTaskInvalid) [[UIApplication sharedApplication] endBackgroundTask:task];
    }];
    [NSThread detachNewThreadSelector:@selector(saveOnWorker:) toTarget:self withObject:name];
}
- (void)saveOnWorker:(NSString *)name {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:name];
    NSURL *url = [NSURL fileURLWithPath:path];
    void (^completion)(NSURL *, NSError *) = ^(NSURL *asset, NSError *error) {
        (void)asset; [self performSelectorOnMainThread:@selector(finished:) withObject:error waitUntilDone:NO];
    };
    NSError *failure = nil;
    if (!RCIsRegularDownload(name)) failure = RCError(@"This file is no longer available.");
    else if (RCIsVideoFile(name)) {
        if ([_library videoAtPathIsCompatibleWithSavedPhotosAlbum:url]) [_library writeVideoAtPathToSavedPhotosAlbum:url completionBlock:completion];
        else failure = RCError(@"This video's format or codec is not supported by Photos on this iOS version.");
    } else if (RCIsImageFile(name)) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&failure];
        if (!failure && [[attributes objectForKey:NSFileSize] unsignedLongLongValue] > 64ULL * 1024 * 1024)
            failure = RCError(@"This image is too large for the legacy Photos importer (64 MB limit). Use Open In with a compatible app.");
        if (!failure) _data = [[NSData alloc] initWithContentsOfFile:path options:NSMappedRead error:&failure];
        if (!failure && ![_data length]) failure = RCError(@"This is an empty image file.");
        if (!failure && [_library respondsToSelector:@selector(writeImageDataToSavedPhotosAlbum:metadata:completionBlock:)]) {
            // iOS 4.1+: supply original encoded bytes, not the bounded on-screen preview.
            [_library writeImageDataToSavedPhotosAlbum:_data metadata:nil completionBlock:completion];
        } else if (!failure) {
            // iOS 4.0 only has the CGImage API; cap decoding while preserving source dimensions/orientation.
            CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)_data, NULL);
            CFDictionaryRef properties = source ? CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) : NULL;
            double width = [[(NSDictionary *)properties objectForKey:(id)kCGImagePropertyPixelWidth] doubleValue];
            double height = [[(NSDictionary *)properties objectForKey:(id)kCGImagePropertyPixelHeight] doubleValue];
            if (properties) CFRelease(properties); if (source) CFRelease(source);
            if (width <= 0 || height <= 0 || width * height > 6000000) failure = RCError(@"This image exceeds the iOS 4.0 Photos importer limit (6 megapixels), or is unsupported.");
            else {
                _image = [[UIImage alloc] initWithData:_data];
                if (_image.CGImage) [_library writeImageToSavedPhotosAlbum:_image.CGImage orientation:(ALAssetOrientation)_image.imageOrientation completionBlock:completion];
                else failure = RCError(@"Photos could not decode this image.");
            }
        }
    } else failure = RCError(@"Photos accepts supported images and videos. Use Share or Open In for this file.");
    if (failure) [self performSelectorOnMainThread:@selector(finished:) withObject:failure waitUntilDone:NO];
    [pool drain];
}
- (void)finished:(NSError *)error {
    _busy = NO; [_data release]; _data = nil; [_image release]; _image = nil;
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask]; _backgroundTask = UIBackgroundTaskInvalid;
    }
    NSString *message = error ? [NSString stringWithFormat:@"Could not save to Photos: %@", [error localizedDescription]] : [NSString stringWithFormat:@"%@ was saved to Photos.", _name];
    [_name release]; _name = nil; [[ReceptorUI sharedUI] showMessage:message];
}
- (void)dealloc { [_library release]; [_data release]; [_image release]; [_name release]; [super dealloc]; }
@end

@interface RCFileShareController ()
- (void)dismissSharing;
- (void)activityFinished;
- (BOOL)selectFile:(NSString *)name rect:(CGRect)rect;
@end
@implementation RCFileShareController
- (id)initWithViewController:(UIViewController *)controller {
    if ((self = [super init])) _owner = controller; return self;
}
+ (BOOL)canSaveToPhotos:(NSString *)name { return RCIsImageFile(name) || RCIsVideoFile(name); }
+ (void)saveToPhotos:(NSString *)name { [[RCPhotoSaver sharedSaver] save:name]; }
- (void)dismissSharing {
    _sheet.delegate = nil; [_sheet dismissWithClickedButtonIndex:_sheet.cancelButtonIndex animated:NO]; [_sheet release]; _sheet = nil;
    _document.delegate = nil; [_document dismissMenuAnimated:NO]; [_document release]; _document = nil;
    if ([_activity respondsToSelector:@selector(setCompletionHandler:)]) [_activity setCompletionHandler:nil];
    _popover.delegate = nil; [_popover dismissPopoverAnimated:NO]; [_popover release]; _popover = nil;
    if (_activity && _owner.modalViewController == _activity) [_owner dismissModalViewControllerAnimated:NO];
    [_activity release]; _activity = nil;
}
- (BOOL)selectFile:(NSString *)name rect:(CGRect)rect {
    if (!RCIsRegularDownload(name)) { [[ReceptorUI sharedUI] showMessage:@"This file is no longer available."]; return NO; }
    NSString *copy = [name copy]; [self dismissSharing]; [_name release]; _name = copy; _rect = rect; return YES;
}
- (void)shareFile:(NSString *)name fromRect:(CGRect)rect {
    if (![self selectFile:name rect:rect]) return;
    Class activityClass = NSClassFromString(@"UIActivityViewController");
    if (activityClass) {
        NSURL *url = [NSURL fileURLWithPath:[RCDownloadsDirectory stringByAppendingPathComponent:_name]];
        _activity = [[activityClass alloc] initWithActivityItems:[NSArray arrayWithObject:url] applicationActivities:nil];
        __block RCFileShareController *unretainedSelf = self; // MRC __block avoids a controller/block retain cycle.
        if ([_activity respondsToSelector:@selector(setCompletionHandler:)]) [_activity setCompletionHandler:^(NSString *type, BOOL completed) { (void)type; (void)completed; [unretainedSelf activityFinished]; }];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            _popover = [[UIPopoverController alloc] initWithContentViewController:_activity]; _popover.delegate = self;
            [_popover presentPopoverFromRect:rect inView:_owner.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
        } else [_owner presentModalViewController:_activity animated:YES];
    } else {
        _sheet = [[UIActionSheet alloc] initWithTitle:_name delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        if ([[self class] canSaveToPhotos:_name]) [_sheet addButtonWithTitle:@"Save to Photos"];
        [_sheet addButtonWithTitle:@"Open In…"];
        _sheet.cancelButtonIndex = [_sheet addButtonWithTitle:@"Cancel"];
        [_sheet showFromRect:rect inView:_owner.view animated:YES];
    }
}
- (void)openFileInApp:(NSString *)name fromRect:(CGRect)rect {
    if (![self selectFile:name rect:rect]) return;
    NSURL *url = [NSURL fileURLWithPath:[RCDownloadsDirectory stringByAppendingPathComponent:_name]];
    _document = [[UIDocumentInteractionController interactionControllerWithURL:url] retain]; _document.delegate = self;
    if (![_document.UTI length]) _document.UTI = @"public.data";
    if (![_document presentOpenInMenuFromRect:rect inView:_owner.view animated:YES])
        [[ReceptorUI sharedUI] showMessage:@"No installed app registers support for this file type. Open In is an app picker; use Share or Save to Photos for other actions."];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    if (sheet != _sheet) return;
    NSString *title = index >= 0 ? [sheet buttonTitleAtIndex:index] : nil;
    [_sheet autorelease]; _sheet = nil;
    if ([title isEqualToString:@"Save to Photos"]) [[self class] saveToPhotos:_name];
    else if ([title isEqualToString:@"Open In…"]) [self openFileInApp:_name fromRect:_rect];
}
- (void)activityFinished {
    _popover.delegate = nil; [_popover dismissPopoverAnimated:YES]; [_popover autorelease]; _popover = nil;
    if (_owner.modalViewController == _activity) [_owner dismissModalViewControllerAnimated:YES];
    [_activity autorelease]; _activity = nil;
}
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popover { (void)popover; [self dismissSharing]; }
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller { (void)controller; return _owner; }
- (void)dealloc { [self dismissSharing]; [_name release]; [super dealloc]; }
@end
