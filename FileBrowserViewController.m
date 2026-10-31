#import "FileBrowserViewController.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "DownloadManager.h"
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

@interface FileBrowserViewController ()
- (void)reloadFiles;
@end

@implementation FileBrowserViewController
- (id)initWithStyle:(UITableViewStyle)style {
    if ((self = [super initWithStyle:style])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadsChanged:)
            name:RCDownloadsChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadsChanged:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Receptor";
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
        UIBarButtonSystemItemDone target:self action:@selector(done)] autorelease];
    UIBarButtonItem *refresh = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
        UIBarButtonSystemItemRefresh target:self action:@selector(reloadFiles)] autorelease];
    UIBarButtonItem *space = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
        UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
    UIBarButtonItem *label = [[[UIBarButtonItem alloc] initWithTitle:@"Downloads" style:UIBarButtonItemStylePlain
        target:nil action:NULL] autorelease];
    self.toolbarItems = [NSArray arrayWithObjects:refresh, space, label, nil];
    [self reloadFiles];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self reloadFiles];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (void)done { [[ReceptorUI sharedUI] closeFiles]; }
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
    [_files release]; _files = [files copy];
    [_activeDownloads release]; _activeDownloads = [[[DownloadManager sharedManager] activeDownloads] copy];
    [_storageError release]; _storageError = [[error localizedDescription] copy];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? [_activeDownloads count] : [_files count];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? @"Downloading (swipe to cancel)" : @"Saved files";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return [_activeDownloads count] ? @"Keep Safari open for long downloads." : @"No active downloads.";
    return _storageError ?: ([_files count] ? @"/var/mobile/Media/Receptor/" : @"No saved files. Tap a downloadable link in Safari to begin.");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"File"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"File"] autorelease];
    cell.accessoryType = UITableViewCellAccessoryNone;
    if ([indexPath section] == 0) {
        NSDictionary *task = [_activeDownloads objectAtIndex:[indexPath row]];
        cell.textLabel.text = [task objectForKey:@"name"];
        long long received = [[task objectForKey:@"received"] longLongValue];
        long long expected = [[task objectForKey:@"expected"] longLongValue];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ received • %@ total", RCByteCount(received), RCByteCount(expected)];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSString *name = [_files objectAtIndex:[indexPath row]];
        NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        cell.textLabel.text = name;
        cell.detailTextLabel.text = RCByteCount([[attributes objectForKey:NSFileSize] longLongValue]);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([indexPath section] == 0) return;
    NSString *name = [_files objectAtIndex:[indexPath row]];
    if (!RCIsRegularDownload(name)) { [self reloadFiles]; return; }
    NSURL *url = [NSURL fileURLWithPath:[RCDownloadsDirectory stringByAppendingPathComponent:name]];
    if ([QLPreviewController canPreviewItem:url]) {
        // Freeze this list so completion notifications cannot change a live preview's indexes.
        [_previewURLs release]; _previewURLs = [[NSArray alloc] initWithObjects:url, nil];
        QLPreviewController *preview = [[QLPreviewController alloc] init];
        preview.dataSource = self;
        preview.currentPreviewItemIndex = 0;
        [self.navigationController pushViewController:preview animated:YES];
        [preview release];
    } else {
        [_documentController dismissMenuAnimated:NO];
        _documentController.delegate = nil;
        [_documentController release];
        _documentController = [[UIDocumentInteractionController interactionControllerWithURL:url] retain];
        _documentController.delegate = self;
        CGRect row = [tableView rectForRowAtIndexPath:indexPath];
        if (![_documentController presentOptionsMenuFromRect:row inView:tableView animated:YES]) {
            [[ReceptorUI sharedUI] showMessage:@"No installed application can preview or open this file."];
        }
    }
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return YES;
}
- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; return [indexPath section] == 0 ? @"Cancel" : @"Delete";
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
        forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (style != UITableViewCellEditingStyleDelete) return;
    if ([indexPath section] == 0) {
        NSString *identifier = [[[_activeDownloads objectAtIndex:[indexPath row]] objectForKey:@"identifier"] copy];
        [[DownloadManager sharedManager] cancelDownloadWithIdentifier:identifier];
        [identifier release];
    } else {
        NSString *name = [_files objectAtIndex:[indexPath row]];
        NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:name];
        if (RCIsRegularDownload(name) && unlink([path fileSystemRepresentation]) != 0) {
            [[ReceptorUI sharedUI] showMessage:[NSString stringWithFormat:@"Cannot delete file: %s", strerror(errno)]];
        }
        [self reloadFiles];
    }
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
    [super dealloc];
}
@end
