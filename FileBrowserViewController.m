#import "FileBrowserViewController.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "DownloadManager.h"
#import "RCIPAInstaller.h"
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(installationChanged:)
            name:RCInstallationChangedNotification object:nil];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Receptor";
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:
        UIBarButtonSystemItemAdd target:self action:@selector(addURL)] autorelease];
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
- (void)installationChanged:(NSNotification *)notification {
    (void)notification;
    self.navigationItem.prompt = [[RCIPAInstaller sharedInstaller] status];
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
    if (section == 0) return [_activeDownloads count] ? @"Keep the app that started a long download in the foreground." : @"No active downloads. Tap + to download a file URL.";
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
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@ / %@", [task objectForKey:@"source"] ?: @"Safari", RCByteCount(received), RCByteCount(expected)];
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
    if ([[[name pathExtension] lowercaseString] isEqual:@"ipa"]) {
        if (_fileActions || _installPrompt) return;
        [_selectedIPA release]; _selectedIPA = [name copy];
        _fileActions = [[UIActionSheet alloc] initWithTitle:name delegate:self cancelButtonTitle:@"Cancel"
            destructiveButtonTitle:nil otherButtonTitles:@"Install IPA", @"Open In…", nil];
        [_fileActions showFromRect:[tableView rectForRowAtIndexPath:indexPath] inView:tableView animated:YES];
        return;
    }
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
    (void)tableView; return [indexPath section] == 0 || ![[RCIPAInstaller sharedInstaller] busy];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (sheet != _fileActions) return;
    [_fileActions autorelease]; _fileActions = nil;
    if (buttonIndex == 0) {
        NSString *message = [NSString stringWithFormat:@"Install %@? This may replace an existing version of the app. The IPA must be compatible with your device and signing setup.", _selectedIPA];
        _installPrompt = [[UIAlertView alloc] initWithTitle:@"Install IPA" message:message delegate:self
            cancelButtonTitle:@"Cancel" otherButtonTitles:@"Install", nil];
        [_installPrompt show];
    } else if (buttonIndex == 1 && RCIsRegularDownload(_selectedIPA)) {
        [_documentController dismissMenuAnimated:NO];
        _documentController.delegate = nil; [_documentController release];
        NSURL *url = [NSURL fileURLWithPath:[RCDownloadsDirectory stringByAppendingPathComponent:_selectedIPA]];
        _documentController = [[UIDocumentInteractionController interactionControllerWithURL:url] retain];
        _documentController.delegate = self;
        if (![_documentController presentOptionsMenuFromRect:self.view.bounds inView:self.view animated:YES]) {
            [[ReceptorUI sharedUI] showMessage:@"No installed application can open this IPA."];
        }
    }
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {
    if (alert == _installPrompt) {
        [_installPrompt autorelease]; _installPrompt = nil;
        if (index == 1) [[RCIPAInstaller sharedInstaller] installFileNamed:_selectedIPA];
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
- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; return [indexPath section] == 0 ? @"Cancel" : @"Delete";
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
        forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (style != UITableViewCellEditingStyleDelete) return;
    if ([indexPath section] != 0 && [[RCIPAInstaller sharedInstaller] busy]) return;
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
    _fileActions.delegate = nil; [_fileActions dismissWithClickedButtonIndex:_fileActions.cancelButtonIndex animated:NO]; [_fileActions release];
    _installPrompt.delegate = nil; [_installPrompt dismissWithClickedButtonIndex:0 animated:NO]; [_installPrompt release];
    _URLPrompt.delegate = nil; [_URLPrompt dismissWithClickedButtonIndex:0 animated:NO]; [_URLPrompt release]; [_URLField release];
    [_selectedIPA release];
    [super dealloc];
}
@end
