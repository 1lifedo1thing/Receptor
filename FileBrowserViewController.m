#import "FileBrowserViewController.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "DownloadManager.h"
#import "RCIPAInstaller.h"
#import "RCDEBInstaller.h"
#import "RCCompanionViewController.h"
#import "RCFileArtwork.h"
#include <math.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static NSString *RCByteCount(long long bytes) {
    if (bytes < 0) return @"unknown size";
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
    if (bytes < 1024LL * 1024) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    if (bytes < 1024LL * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}
static BOOL RCInstallingPackage(void) {
    return [[RCIPAInstaller sharedInstaller] busy] || [[RCDEBInstaller sharedInstaller] busy];
}

@interface FileBrowserViewController ()
- (void)reloadFiles;
- (void)filterFiles;
- (void)previewFile:(NSString *)name;
- (void)showActionsForFile:(NSString *)name rect:(CGRect)rect;
- (void)deleteSelectedFile;
- (UIImage *)artworkForFile:(NSString *)name;
- (NSString *)artworkKeyForFile:(NSString *)name;
- (BOOL)selectFile:(NSString *)name rect:(CGRect)rect;
- (void)openSelectedFileInApp;
@end

@implementation FileBrowserViewController
- (id)initWithStyle:(UITableViewStyle)style {
    if ((self = [super initWithStyle:style])) {
        _grid = ![[[NSUserDefaults standardUserDefaults] stringForKey:@"RCBrowserLayout"] isEqualToString:@"list"];
        _columns = 2;
        _thumbnailCache = [[NSCache alloc] init]; _thumbnailCache.totalCostLimit = 6 * 1024 * 1024; _thumbnailCache.countLimit = 128;
        _thumbnailQueue = [[NSOperationQueue alloc] init]; _thumbnailQueue.maxConcurrentOperationCount = 1;
        _thumbnailPending = [[NSMutableSet alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadsChanged:)
            name:RCDownloadsChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadsChanged:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(installationChanged:)
            name:RCInstallationChangedNotification object:nil];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Browse";
    self.tableView.backgroundColor = [UIColor whiteColor];
    self.tableView.separatorStyle = _grid ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 132)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 6, 150, 40)];
    title.text = @"Browse"; title.font = [UIFont boldSystemFontOfSize:30]; [header addSubview:title]; [title release];
    UILabel *location = [[UILabel alloc] initWithFrame:CGRectMake(16, 48, header.bounds.size.width - 32, 22)];
    location.text = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? @"On My iPad · Receptor" : @"On My iPhone · Receptor";
    location.font = [UIFont systemFontOfSize:13]; location.textColor = [UIColor grayColor];
    location.autoresizingMask = UIViewAutoresizingFlexibleWidth; [header addSubview:location]; [location release];
    _layoutControl = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Grid", @"List", nil]];
    _layoutControl.frame = CGRectMake(header.bounds.size.width - 150, 14, 134, 30);
    _layoutControl.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _layoutControl.selectedSegmentIndex = _grid ? 0 : 1;
    [_layoutControl addTarget:self action:@selector(changeLayout) forControlEvents:UIControlEventValueChanged]; [header addSubview:_layoutControl];
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 80, header.bounds.size.width, 44)];
    _searchBar.placeholder = @"Search files"; _searchBar.delegate = self;
    _searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth; [header addSubview:_searchBar];
    self.tableView.tableHeaderView = header; [header release];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
        UIBarButtonSystemItemAdd target:self action:@selector(addURL)] autorelease];
    UIBarButtonItem *refresh = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
        UIBarButtonSystemItemRefresh target:self action:@selector(reloadFiles)] autorelease];
    UIBarButtonItem *space = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
        UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
    UIBarButtonItem *log = [[[UIBarButtonItem alloc] initWithTitle:@"Install Log" style:UIBarButtonItemStylePlain
        target:self action:@selector(showInstallLog)] autorelease];
    UIBarButtonItem *cydia = [[[UIBarButtonItem alloc] initWithTitle:@"Cydia" style:UIBarButtonItemStylePlain
        target:self action:@selector(openCydia)] autorelease];
    UIBarButtonItem *desktop = [[[UIBarButtonItem alloc] initWithTitle:@"Desktop" style:UIBarButtonItemStylePlain
        target:self action:@selector(openDesktop)] autorelease];
    self.toolbarItems = [NSArray arrayWithObjects:refresh, log, space, desktop, cydia, nil];
    [self reloadFiles];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self updateColumns];
    [self reloadFiles];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; [_searchBar resignFirstResponder];
    [_thumbnailQueue cancelAllOperations]; [_thumbnailPending removeAllObjects];
}
- (void)updateColumns {
    NSUInteger columns = MAX(2, MIN(8, (NSUInteger)floor(self.tableView.bounds.size.width / 140.0)));
    if (columns != _columns) { _columns = columns; [self.tableView reloadData]; }
}
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
    [super didRotateFromInterfaceOrientation:orientation]; [self updateColumns]; [self.tableView reloadData];
}
- (void)changeLayout {
    _grid = _layoutControl.selectedSegmentIndex == 0;
    [[NSUserDefaults standardUserDefaults] setObject:_grid ? @"grid" : @"list" forKey:@"RCBrowserLayout"];
    self.tableView.separatorStyle = _grid ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
    [self updateColumns]; [self.tableView reloadData];
}
- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    if (editing && RCInstallingPackage()) { [[ReceptorUI sharedUI] showMessage:@"Wait for installation to finish before deleting files."]; return; }
    [super setEditing:editing animated:animated]; [self.tableView reloadData];
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { (void)bar; (void)text; [self filterFiles]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [bar resignFirstResponder]; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (void)installationChanged:(NSNotification *)notification {
    (void)notification;
    self.navigationItem.prompt = [[RCDEBInstaller sharedInstaller] busy] ? [[RCDEBInstaller sharedInstaller] status] : [[RCIPAInstaller sharedInstaller] status];
}
- (void)showInstallLog {
    if ([[RCDEBInstaller sharedInstaller] busy]) {
        [[ReceptorUI sharedUI] showMessage:@"The DEB installation is still running. Its log will be available when the package manager finishes."];
        return;
    }
    UIViewController *controller = [[UIViewController alloc] init];
    controller.title = @"DEB Install Log";
    UITextView *text = [[UITextView alloc] initWithFrame:self.view.bounds];
    text.editable = NO;
    text.font = [UIFont fontWithName:@"Courier" size:12.0f];
    text.text = [[RCDEBInstaller sharedInstaller] lastOutput] ?: @"No DEB installation has completed yet.";
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    controller.view = text;
    [text release];
    [self.navigationController pushViewController:controller animated:YES];
    [controller release];
}
- (void)openCydia {
    if (![[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"cydia://"]]) {
        [[ReceptorUI sharedUI] showMessage:@"Cydia could not be opened on this device."];
    }
}
- (void)openDesktop {
    RCCompanionViewController *controller = [[RCCompanionViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
    [controller release];
}
- (void)addURL {
    if (_URLPrompt) return;
    _URLPrompt = [[UIAlertView alloc] initWithTitle:@"Download URL" message:@"Paste an HTTP or HTTPS file link." delegate:self
        cancelButtonTitle:@"Cancel" otherButtonTitles:@"Download", nil];
    if ([_URLPrompt respondsToSelector:@selector(setAlertViewStyle:)]) {
        _URLPrompt.alertViewStyle = UIAlertViewStylePlainTextInput;
        _URLField = [[_URLPrompt textFieldAtIndex:0] retain];
    } else {
        _URLPrompt.message = @"\n\n";
        _URLField = [[UITextField alloc] initWithFrame:CGRectMake(12, 50, 260, 32)];
        _URLField.borderStyle = UITextBorderStyleRoundedRect;
        [_URLPrompt addSubview:_URLField];
    }
    _URLField.placeholder = @"https://example.com/app.ipa";
    _URLField.keyboardType = UIKeyboardTypeURL;
    _URLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _URLField.autocorrectionType = UITextAutocorrectionTypeNo;
    [_URLPrompt show];
}
- (void)downloadsChanged:(NSNotification *)notification {
    (void)notification;
    if ([self isViewLoaded]) [self reloadFiles];
}
- (void)reloadFiles {
    NSError *error = nil;
    NSArray *names = nil;
    if (RCEnsureDownloadsDirectory(&error)) {
        names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:RCDownloadsDirectory error:&error];
    }
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in names) if (RCIsRegularDownload(name)) [files addObject:name];
    [files sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [_allFiles release]; _allFiles = [files copy];
    [_activeDownloads release]; _activeDownloads = [[[DownloadManager sharedManager] activeDownloads] copy];
    [_storageError release]; _storageError = [[error localizedDescription] copy];
    [self filterFiles];
}
- (void)filterFiles {
    NSString *query = _searchBar.text;
    NSMutableArray *visible = [NSMutableArray array];
    for (NSString *name in _allFiles) if (![query length] || [name rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [visible addObject:name];
    [_files release]; _files = [visible copy]; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? [_activeDownloads count] : (_grid ? ([_files count] + _columns - 1) / _columns : [_files count]);
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; return indexPath.section == 1 && _grid ? 170 : 64;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? @"Transfers" : @"Files";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return [_activeDownloads count] ? @"Swipe a transfer to cancel. Keep its app in the foreground." : @"Tap + to download, or Desktop to receive files from your PC.";
    if (_storageError) return _storageError;
    if (![_files count]) return [_allFiles count] ? @"No files match your search." : @"Your files appear here. Receive any file through Desktop or download a link with +.";
    return self.editing ? @"Tap a grid tile or swipe a list row to delete a file." : @"Tap to preview. Hold a file or tap ••• for Open In, installation and deletion. Open In requires an installed app that accepts the file type.";
}
- (NSString *)artworkKeyForFile:(NSString *)name {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[RCDownloadsDirectory stringByAppendingPathComponent:name] error:NULL];
    return [NSString stringWithFormat:@"%@:%@:%@:%@", name, [attributes objectForKey:NSFileSystemFileNumber], [attributes objectForKey:NSFileSize], [attributes objectForKey:NSFileModificationDate]];
}
- (UIImage *)artworkForFile:(NSString *)name {
    NSString *key = [self artworkKeyForFile:name];
    id image = [_thumbnailCache objectForKey:key];
    if ([image isKindOfClass:[UIImage class]]) return image;
    if (!image && RCIsImageFile(name) && ![_thumbnailPending containsObject:key] && [_thumbnailPending count] < 48) {
        [_thumbnailPending addObject:key];
        NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:name, @"name", key, @"key", nil];
        NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(loadThumbnail:) object:job];
        [_thumbnailQueue addOperation:operation]; [operation release];
    }
    NSString *genericKey = [@"generic:" stringByAppendingString:[[name pathExtension] uppercaseString]];
    UIImage *generic = [_thumbnailCache objectForKey:genericKey];
    if (!generic) { generic = RCFileIcon(name); if (generic) [_thumbnailCache setObject:generic forKey:genericKey cost:40000]; }
    return generic;
}
- (void)loadThumbnail:(NSDictionary *)job {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    UIImage *image = RCLoadImageThumbnail([job objectForKey:@"name"], 160);
    NSMutableDictionary *result = [[job mutableCopy] autorelease];
    [result setObject:image ?: (id)[NSNull null] forKey:@"image"];
    [self performSelectorOnMainThread:@selector(thumbnailLoaded:) withObject:result waitUntilDone:NO]; [pool drain];
}
- (void)thumbnailLoaded:(NSDictionary *)result {
    NSString *key = [result objectForKey:@"key"], *name = [result objectForKey:@"name"];
    [_thumbnailPending removeObject:key];
    id image = [result objectForKey:@"image"];
    [_thumbnailCache setObject:image forKey:key cost:[image isKindOfClass:[UIImage class]] ? 160 * 160 * 4 : 0];
    if (![self isViewLoaded] || ![image isKindOfClass:[UIImage class]] || ![[self artworkKeyForFile:name] isEqualToString:key]) return;
    for (UITableViewCell *cell in [self.tableView visibleCells]) {
        if ([self.tableView indexPathForCell:cell].section != 1) continue;
        if (_grid) {
            for (UIView *view in cell.contentView.subviews) if ([view isKindOfClass:[RCFileTile class]] && [[(RCFileTile *)view fileName] isEqualToString:name]) [(RCFileTile *)view artwork].image = image;
        } else if ([cell.textLabel.text isEqualToString:name]) cell.imageView.image = image;
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = indexPath.section == 0 ? @"Transfer" : (_grid ? @"Grid" : @"SavedList");
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        Class cellClass = [identifier isEqualToString:@"SavedList"] ? [RCFileListCell class] : [UITableViewCell class];
        cell = [[[cellClass alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
        if ([identifier isEqualToString:@"SavedList"]) {
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdListFile:)];
            [cell addGestureRecognizer:hold]; [hold release];
        }
    }
    cell.accessoryType = UITableViewCellAccessoryNone; cell.imageView.image = nil;
    if (indexPath.section == 0) {
        NSDictionary *task = [_activeDownloads objectAtIndex:indexPath.row];
        cell.textLabel.text = [task objectForKey:@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@ / %@", [task objectForKey:@"source"] ?: @"Safari", RCByteCount([[task objectForKey:@"received"] longLongValue]), RCByteCount([[task objectForKey:@"expected"] longLongValue])];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (_grid) {
        for (UIView *view in [[cell.contentView.subviews copy] autorelease]) [view removeFromSuperview];
        cell.textLabel.text = nil; cell.detailTextLabel.text = nil; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        CGFloat width = (tableView.bounds.size.width - 24) / _columns;
        for (NSUInteger column = 0; column < _columns; ++column) {
            NSUInteger index = indexPath.row * _columns + column; if (index >= [_files count]) break;
            NSString *name = [_files objectAtIndex:index];
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[RCDownloadsDirectory stringByAppendingPathComponent:name] error:NULL];
            RCFileTile *tile = [[RCFileTile alloc] initWithFrame:CGRectMake(12 + column * width, 6, width - 4, 158)];
            [tile setName:name size:RCByteCount([[attributes objectForKey:NSFileSize] longLongValue]) editing:self.editing];
            tile.artwork.image = [self artworkForFile:name];
            [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
            [tile.moreButton addTarget:self action:@selector(tileMore:) forControlEvents:UIControlEventTouchUpInside];
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdFile:)];
            [tile addGestureRecognizer:hold]; [hold release];
            [cell.contentView addSubview:tile]; [tile release];
        }
    } else {
        NSString *name = [_files objectAtIndex:indexPath.row];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[RCDownloadsDirectory stringByAppendingPathComponent:name] error:NULL];
        cell.textLabel.text = name; cell.detailTextLabel.text = RCByteCount([[attributes objectForKey:NSFileSize] unsignedLongLongValue]);
        cell.imageView.image = [self artworkForFile:name]; cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
    return cell;
}
- (void)tileTapped:(RCFileTile *)tile {
    if (self.editing) { if ([self selectFile:tile.fileName rect:[tile convertRect:tile.bounds toView:self.tableView]]) [self deleteSelectedFile]; }
    else [self previewFile:tile.fileName];
}
- (void)tileMore:(UIButton *)button { RCFileTile *tile = (RCFileTile *)button.superview; [self showActionsForFile:tile.fileName rect:[tile convertRect:tile.bounds toView:self.tableView]]; }
- (void)holdFile:(UILongPressGestureRecognizer *)hold { if (hold.state == UIGestureRecognizerStateBegan) { RCFileTile *tile = (RCFileTile *)hold.view; [self showActionsForFile:tile.fileName rect:[tile convertRect:tile.bounds toView:self.tableView]]; } }
- (void)holdListFile:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *index = [self.tableView indexPathForCell:(UITableViewCell *)hold.view];
    if (index.section == 1 && !_grid && index.row < (NSInteger)[_files count]) [self showActionsForFile:[_files objectAtIndex:index.row] rect:[self.tableView rectForRowAtIndexPath:index]];
}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && !_grid) [self showActionsForFile:[_files objectAtIndex:indexPath.row] rect:[tableView rectForRowAtIndexPath:indexPath]];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && !_grid) [self previewFile:[_files objectAtIndex:indexPath.row]];
}
- (BOOL)selectFile:(NSString *)name rect:(CGRect)rect {
    if (_fileActions || _installPrompt || _deletePrompt || !RCIsRegularDownload(name)) return NO;
    NSString *selection = [name copy]; [_selectedPackage release]; _selectedPackage = selection; _actionAnchor = rect; return YES;
}
- (void)showActionsForFile:(NSString *)name rect:(CGRect)rect {
    [_searchBar resignFirstResponder];
    if (![self selectFile:name rect:rect]) return;
    NSString *extension = [[name pathExtension] lowercaseString];
    BOOL package = [extension isEqualToString:@"deb"] || [extension isEqualToString:@"ipa"];
    NSMutableArray *titles = [NSMutableArray array];
    [titles addObject:package ? ([extension isEqualToString:@"deb"] ? @"Install DEB" : @"Install IPA") : @"Preview"];
    [titles addObject:@"Open In…"];
    [titles addObject:@"Delete"];
    [_actionTitles release]; _actionTitles = [titles copy];
    _fileActions = [[UIActionSheet alloc] initWithTitle:name delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *title in titles) [_fileActions addButtonWithTitle:title];
    _fileActions.destructiveButtonIndex = [titles count] - 1;
    _fileActions.cancelButtonIndex = [_fileActions addButtonWithTitle:@"Cancel"];
    [_fileActions showFromRect:rect inView:self.tableView animated:YES];
}
- (void)previewFile:(NSString *)name {
    [_searchBar resignFirstResponder];
    if (!RCIsRegularDownload(name)) { [self reloadFiles]; return; }
    if (_fileActions || _installPrompt || _deletePrompt) return;
    NSString *extension = [[name pathExtension] lowercaseString];
    if ([extension isEqualToString:@"deb"] || [extension isEqualToString:@"ipa"]) {
        [self showActionsForFile:name rect:self.tableView.bounds]; return;
    }
    if (RCIsImageFile(name)) {
        RCImagePreviewController *image = [[RCImagePreviewController alloc] initWithFileName:name];
        [self.navigationController pushViewController:image animated:YES]; [image release]; return;
    }
    NSURL *url = [NSURL fileURLWithPath:[RCDownloadsDirectory stringByAppendingPathComponent:name]];
    if ([QLPreviewController canPreviewItem:url]) {
        [_previewURLs release]; _previewURLs = [[NSArray alloc] initWithObjects:url, nil];
        QLPreviewController *preview = [[QLPreviewController alloc] init]; preview.dataSource = self;
        [self.navigationController pushViewController:preview animated:YES]; [preview release];
    } else {
        if ([self selectFile:name rect:self.tableView.bounds]) [self openSelectedFileInApp];
    }
}
- (void)openSelectedFileInApp {
    if (!RCIsRegularDownload(_selectedPackage)) return;
    [_documentController dismissMenuAnimated:NO]; _documentController.delegate = nil; [_documentController release];
    NSURL *url = [NSURL fileURLWithPath:[RCDownloadsDirectory stringByAppendingPathComponent:_selectedPackage]];
    _documentController = [[UIDocumentInteractionController interactionControllerWithURL:url] retain]; _documentController.delegate = self;
    if (![_documentController.UTI length]) _documentController.UTI = @"public.data";
    if (![_documentController presentOpenInMenuFromRect:_actionAnchor inView:self.tableView animated:YES])
        [[ReceptorUI sharedUI] showMessage:@"No installed app accepts this file type through Open In. Install a compatible app and try again."];
}
- (void)deleteSelectedFile {
    if (_deletePrompt || _fileActions || _installPrompt || RCInstallingPackage() || !RCIsRegularDownload(_selectedPackage)) return;
    _deletePrompt = [[UIAlertView alloc] initWithTitle:@"Delete file?" message:_selectedPackage delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Delete", nil]; [_deletePrompt show];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (sheet != _fileActions) return;
    [_fileActions autorelease]; _fileActions = nil;
    if (buttonIndex < 0 || buttonIndex >= (NSInteger)[_actionTitles count] || !RCIsRegularDownload(_selectedPackage)) return;
    NSString *action = [_actionTitles objectAtIndex:buttonIndex];
    if ([action isEqualToString:@"Open In…"]) [self openSelectedFileInApp];
    else if ([action isEqualToString:@"Delete"]) [self deleteSelectedFile];
    else if ([action isEqualToString:@"Preview"]) {
        NSString *extension = [[_selectedPackage pathExtension] lowercaseString];
        if ([extension isEqualToString:@"deb"] || [extension isEqualToString:@"ipa"]) [[ReceptorUI sharedUI] showMessage:@"Use Install to install this package, or Open In to send it to another app."];
        else [self previewFile:_selectedPackage];
    } else if (!RCInstallingPackage()) {
        BOOL deb = [[[_selectedPackage pathExtension] lowercaseString] isEqualToString:@"deb"];
        NSString *message = deb ? [NSString stringWithFormat:@"Install %@? Packages can run scripts as root. Close Cydia first; install missing dependencies through Cydia.", _selectedPackage] : [NSString stringWithFormat:@"Install %@? This may replace an existing app. Device compatibility and signing requirements apply.", _selectedPackage];
        _installPrompt = [[UIAlertView alloc] initWithTitle:action message:message delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Install", nil]; [_installPrompt show];
    }
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {
    if (alert == _installPrompt) {
        [_installPrompt autorelease]; _installPrompt = nil;
        if (index == 1) {
            if ([[[_selectedPackage pathExtension] lowercaseString] isEqual:@"deb"]) [[RCDEBInstaller sharedInstaller] installFileNamed:_selectedPackage];
            else [[RCIPAInstaller sharedInstaller] installFileNamed:_selectedPackage];
        }
    } else if (alert == _deletePrompt) {
        [_deletePrompt autorelease]; _deletePrompt = nil;
        if (index == 1 && !RCInstallingPackage() && RCIsRegularDownload(_selectedPackage)) {
            NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:_selectedPackage];
            if (unlink([path fileSystemRepresentation])) [[ReceptorUI sharedUI] showMessage:[NSString stringWithFormat:@"Cannot delete file: %s", strerror(errno)]];
            [self reloadFiles];
        }
    } else if (alert == _URLPrompt) {
        NSString *text = [[_URLField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
        [_URLField release]; _URLField = nil;
        [_URLPrompt autorelease]; _URLPrompt = nil;
        if (index == 1) {
            NSURL *url = [NSURL URLWithString:text];
            NSError *error = nil;
            if (!url || !RCIsDownloadRequest([NSURLRequest requestWithURL:url])) {
                [[ReceptorUI sharedUI] showMessage:@"Enter a valid HTTP or HTTPS file URL."];
            } else if (![[DownloadManager sharedManager] startDownloadWithRequest:[NSURLRequest requestWithURL:url] error:&error]) {
                [[ReceptorUI sharedUI] showMessage:[error localizedDescription]];
            }
        }
        [text release];
    }
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; return indexPath.section == 0 || (!_grid && !RCInstallingPackage());
}
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath { (void)tableView; return indexPath.section == 0 || !_grid; }
- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; return indexPath.section == 0 ? @"Cancel" : @"Delete";
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; if (style != UITableViewCellEditingStyleDelete) return;
    if (indexPath.section == 0) {
        NSString *identifier = [[[_activeDownloads objectAtIndex:indexPath.row] objectForKey:@"identifier"] copy];
        [[DownloadManager sharedManager] cancelDownloadWithIdentifier:identifier]; [identifier release];
    } else if (!_grid && !RCInstallingPackage()) {
        if ([self selectFile:[_files objectAtIndex:indexPath.row] rect:[self.tableView rectForRowAtIndexPath:indexPath]]) [self deleteSelectedFile];
    }
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning]; [_thumbnailCache removeAllObjects]; [_thumbnailQueue cancelAllOperations]; [_thumbnailPending removeAllObjects];
}
- (void)viewDidUnload {
    _searchBar.delegate = nil; [_searchBar release]; _searchBar = nil;
    [_layoutControl release]; _layoutControl = nil; [super viewDidUnload];
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    (void)controller; return [_previewURLs count];
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    (void)controller; return [_previewURLs objectAtIndex:index];
}
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    (void)controller; return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _documentController.delegate = nil;
    [_documentController dismissMenuAnimated:NO]; [_documentController release];
    [_files release]; [_activeDownloads release]; [_previewURLs release]; [_storageError release];
    _fileActions.delegate = nil; [_fileActions dismissWithClickedButtonIndex:_fileActions.cancelButtonIndex animated:NO]; [_fileActions release];
    _installPrompt.delegate = nil; [_installPrompt dismissWithClickedButtonIndex:0 animated:NO]; [_installPrompt release];
    _URLPrompt.delegate = nil; [_URLPrompt dismissWithClickedButtonIndex:0 animated:NO]; [_URLPrompt release]; [_URLField release];
    [_selectedPackage release]; [_allFiles release];
    _searchBar.delegate = nil; [_searchBar release]; [_layoutControl release];
    [_thumbnailQueue cancelAllOperations]; [_thumbnailQueue release]; [_thumbnailCache release]; [_thumbnailPending release]; [_actionTitles release];
    _deletePrompt.delegate = nil; [_deletePrompt dismissWithClickedButtonIndex:0 animated:NO]; [_deletePrompt release];
    [super dealloc];
}
@end
