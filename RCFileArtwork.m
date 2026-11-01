#import "RCFileArtwork.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCFileSharing.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/UTType.h>
#import <MobileCoreServices/UTCoreTypes.h>

BOOL RCIsImageFile(NSString *name) {
    CFStringRef type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[name pathExtension], NULL);
    BOOL image = type && UTTypeConformsTo(type, kUTTypeImage);
    if (type) CFRelease(type);
    return image;
}
UIImage *RCLoadImageThumbnail(NSString *name, NSUInteger pixels) {
    if (!RCIsRegularDownload(name)) return nil;
    NSURL *url = [NSURL fileURLWithPath:[RCDownloadsDirectory stringByAppendingPathComponent:name]];
    NSDictionary *sourceOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:(id)kCGImageSourceShouldCache];
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, (CFDictionaryRef)sourceOptions);
    if (!source) return nil;
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    NSDictionary *info = (NSDictionary *)properties;
    double width = [[info objectForKey:(id)kCGImagePropertyPixelWidth] doubleValue];
    double height = [[info objectForKey:(id)kCGImagePropertyPixelHeight] doubleValue];
    // Bound work on memory-constrained legacy devices; unsupported/oversize images can still be shared.
    BOOL reasonable = width > 0 && height > 0 && width <= 20000 && height <= 20000 && width * height <= 25000000;
    if (properties) CFRelease(properties);
    CGImageRef image = NULL;
    if (reasonable) {
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailFromImageAlways,
            [NSNumber numberWithBool:YES], (id)kCGImageSourceCreateThumbnailWithTransform,
            [NSNumber numberWithBool:NO], (id)kCGImageSourceShouldCache,
            [NSNumber numberWithUnsignedInteger:pixels], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
        image = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
    }
    CFRelease(source);
    UIImage *result = image ? [UIImage imageWithCGImage:image] : nil;
    if (image) CGImageRelease(image);
    return result;
}
UIImage *RCFileIcon(NSString *name) {
    NSString *extension = [[name pathExtension] uppercaseString];
    if (![extension length] || [extension length] > 6) extension = @"FILE";
    UIColor *blue = [UIColor colorWithRed:0.12f green:0.47f blue:0.89f alpha:1];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(100, 100), NO, 1);
    UIBezierPath *paper = [UIBezierPath bezierPath];
    [paper moveToPoint:CGPointMake(22, 5)]; [paper addLineToPoint:CGPointMake(64, 5)];
    [paper addLineToPoint:CGPointMake(82, 23)]; [paper addLineToPoint:CGPointMake(82, 94)];
    [paper addLineToPoint:CGPointMake(22, 94)]; [paper closePath];
    [[UIColor colorWithWhite:0.95f alpha:1] setFill]; [paper fill];
    [[UIColor colorWithWhite:0.80f alpha:1] setStroke]; [paper stroke];
    UIBezierPath *fold = [UIBezierPath bezierPath];
    [fold moveToPoint:CGPointMake(64, 5)]; [fold addLineToPoint:CGPointMake(64, 23)];
    [fold addLineToPoint:CGPointMake(82, 23)]; [fold closePath];
    [[UIColor colorWithWhite:0.84f alpha:1] setFill]; [fold fill];
    [blue setFill]; UIRectFill(CGRectMake(12, 48, 80, 27));
    [[UIColor whiteColor] set];
    [extension drawInRect:CGRectMake(14, 52, 76, 23) withFont:[UIFont boldSystemFontOfSize:15]
        lineBreakMode:UILineBreakModeTailTruncation alignment:UITextAlignmentCenter];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return image;
}

@implementation RCFileListCell
- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageView.frame = CGRectMake(8, 7, 50, 50); self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    CGFloat width = MAX(20, self.contentView.bounds.size.width - 78);
    self.textLabel.frame = CGRectMake(68, 8, width, 26);
    self.textLabel.font = [UIFont systemFontOfSize:16]; self.textLabel.lineBreakMode = UILineBreakModeMiddleTruncation;
    self.detailTextLabel.frame = CGRectMake(68, 34, width, 20); self.detailTextLabel.font = [UIFont systemFontOfSize:12];
}
@end
@implementation RCFileTile
@synthesize fileName = _fileName, artwork = _artwork, moreButton = _moreButton;
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _artwork = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100, 94)];
        _artwork.contentMode = UIViewContentModeScaleAspectFit; [self addSubview:_artwork];
        _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 96, frame.size.width, 36)];
        _nameLabel.font = [UIFont systemFontOfSize:13]; _nameLabel.numberOfLines = 2;
        _nameLabel.textAlignment = UITextAlignmentCenter; _nameLabel.lineBreakMode = UILineBreakModeMiddleTruncation;
        _nameLabel.backgroundColor = [UIColor clearColor]; [self addSubview:_nameLabel];
        _sizeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 134, frame.size.width, 18)];
        _sizeLabel.font = [UIFont systemFontOfSize:11]; _sizeLabel.textAlignment = UITextAlignmentCenter;
        _sizeLabel.textColor = [UIColor grayColor]; _sizeLabel.backgroundColor = [UIColor clearColor]; [self addSubview:_sizeLabel];
        _moreButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_moreButton setTitle:@"•••" forState:UIControlStateNormal];
        [_moreButton setTitleColor:[UIColor colorWithRed:0 green:0.35f blue:0.8f alpha:1] forState:UIControlStateNormal];
        _moreButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:_moreButton];
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _artwork.frame = CGRectMake((width - 100) / 2, 0, 100, 94);
    _nameLabel.frame = CGRectMake(2, 96, width - 4, 36);
    _sizeLabel.frame = CGRectMake(2, 134, width - 4, 18);
    _moreButton.frame = CGRectMake(width - 35, 0, 35, 32);
}
- (void)setName:(NSString *)name size:(NSString *)size editing:(BOOL)editing {
    self.fileName = name; _nameLabel.text = name; _sizeLabel.text = editing ? @"Tap to delete" : size;
    _sizeLabel.textColor = editing ? [UIColor redColor] : [UIColor grayColor];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name, size];
    _moreButton.accessibilityLabel = [@"Actions for " stringByAppendingString:name];
}
- (void)dealloc {
    [_fileName release]; [_artwork release]; [_nameLabel release]; [_sizeLabel release]; [_moreButton release]; [super dealloc];
}
@end

@interface RCImagePreviewController ()
- (void)loadImage;
- (void)displayImage:(UIImage *)image;
- (void)fitImage;
@end
@implementation RCImagePreviewController
- (id)initWithFileName:(NSString *)name {
    if ((self = [super init])) { _name = [name copy]; self.title = name; _sharing = [[RCFileShareController alloc] initWithViewController:self]; }
    return self;
}
- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    view.backgroundColor = [UIColor blackColor]; self.view = view; [view release];
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds]; _scroll.delegate = self;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.showsVerticalScrollIndicator = _scroll.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:_scroll];
    _imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)]; [_scroll addSubview:_imageView];
    _message = [[UILabel alloc] initWithFrame:self.view.bounds];
    _message.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _message.numberOfLines = 0; _message.textAlignment = UITextAlignmentCenter;
    _message.backgroundColor = [UIColor clearColor]; _message.textColor = [UIColor whiteColor];
    _message.font = [UIFont systemFontOfSize:16]; [_scroll addSubview:_message];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_spinner]; [_spinner startAnimating];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    tap.numberOfTapsRequired = 2; [_scroll addGestureRecognizer:tap]; [tap release];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)] autorelease];
    UIBarButtonItem *save = [[[UIBarButtonItem alloc] initWithTitle:@"Save to Photos" style:UIBarButtonItemStylePlain target:self action:@selector(saveToPhotos)] autorelease];
    UIBarButtonItem *space = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
    UIBarButtonItem *open = [[[UIBarButtonItem alloc] initWithTitle:@"Open In…" style:UIBarButtonItemStylePlain target:self action:@selector(openIn)] autorelease];
    self.toolbarItems = [NSArray arrayWithObjects:save, space, open, nil];
    [NSThread detachNewThreadSelector:@selector(loadImage) toTarget:self withObject:nil];
}
- (void)loadImage {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    UIImage *image = RCLoadImageThumbnail(_name, 1600);
    [self performSelectorOnMainThread:@selector(displayImage:) withObject:image waitUntilDone:NO]; [pool drain];
}
- (void)displayImage:(UIImage *)image {
    [_spinner stopAnimating]; _imageView.image = image;
    _message.text = image ? nil : @"This image is unsupported or too large for legacy preview.\nUse the action button to open it in another app.";
    [self fitImage];
}
- (void)fitImage {
    if (!_imageView.image) return;
    _scroll.minimumZoomScale = 0.01f; _scroll.maximumZoomScale = 32;
    _scroll.zoomScale = 1;
    CGSize size = _imageView.image.size;
    _imageView.frame = CGRectMake(0, 0, size.width, size.height); _scroll.contentSize = size;
    CGFloat scale = MIN(1, MIN(_scroll.bounds.size.width / size.width, _scroll.bounds.size.height / size.height));
    _scroll.maximumZoomScale = MAX(1, scale * 4); _scroll.minimumZoomScale = scale; _scroll.zoomScale = scale;
    [self scrollViewDidZoom:_scroll];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scroll { (void)scroll; return _imageView; }
- (void)scrollViewDidZoom:(UIScrollView *)scroll {
    _imageView.center = CGPointMake(MAX(scroll.contentSize.width, scroll.bounds.size.width) / 2,
        MAX(scroll.contentSize.height, scroll.bounds.size.height) / 2);
}
- (void)doubleTap:(UITapGestureRecognizer *)tap {
    if (!_imageView.image) return;
    CGFloat scale = _scroll.zoomScale > _scroll.minimumZoomScale * 1.1f ? _scroll.minimumZoomScale : MIN(_scroll.maximumZoomScale, _scroll.minimumZoomScale * 2.5f);
    CGPoint point = [tap locationInView:_imageView];
    CGSize size = CGSizeMake(_scroll.bounds.size.width / scale, _scroll.bounds.size.height / scale);
    [_scroll zoomToRect:CGRectMake(point.x - size.width / 2, point.y - size.height / 2, size.width, size.height) animated:YES];
}
- (void)openIn {
    [_sharing openFileInApp:_name fromRect:CGRectMake(self.view.bounds.size.width - 44, 0, 44, 1)];
}
- (void)share { [_sharing shareFile:_name fromRect:CGRectMake(self.view.bounds.size.width - 44, 0, 44, 1)]; }
- (void)saveToPhotos { [RCFileShareController saveToPhotos:_name]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:NO animated:animated]; }
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation { [super didRotateFromInterfaceOrientation:orientation]; [self fitImage]; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (void)viewDidUnload {
    _scroll.delegate = nil; [_scroll release]; _scroll = nil;
    [_imageView release]; _imageView = nil; [_spinner release]; _spinner = nil; [_message release]; _message = nil;
    [super viewDidUnload];
}
- (void)dealloc {
    _scroll.delegate = nil; [_sharing release];
    [_name release]; [_scroll release]; [_imageView release]; [_spinner release]; [_message release]; [super dealloc];
}
@end
