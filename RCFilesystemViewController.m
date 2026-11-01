#import "RCFilesystemViewController.h"
#import "RCSendFileViewController.h"
#include <sys/stat.h>
#include <limits.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

@interface RCFilesystemViewController ()
- (void)refresh;
- (void)readDirectory:(NSDictionary *)job;
- (void)loaded:(NSDictionary *)result;
@end

@implementation RCFilesystemViewController
- (id)initWithPath:(NSString *)path {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _path = [path copy]; _limit = 500;
        _entries = [[NSArray alloc] init]; _status = [@"Loading…" copy];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [_path isEqualToString:@"/"] ? @"Filesystem" : [_path lastPathComponent];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)] autorelease];
    [self refresh];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:YES animated:animated]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [_actions dismissWithClickedButtonIndex:_actions.cancelButtonIndex animated:NO]; }
- (void)refresh {
    _loading = YES; ++_generation; [self.tableView reloadData];
    NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:_path, @"path", [NSNumber numberWithUnsignedInteger:_generation], @"generation", [NSNumber numberWithUnsignedInteger:_limit], @"limit", nil];
    [NSThread detachNewThreadSelector:@selector(readDirectory:) toTarget:self withObject:job];
}
- (void)readDirectory:(NSDictionary *)job {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSError *error = nil;
    NSString *directory = [job objectForKey:@"path"];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:&error];
    NSMutableArray *entries = [NSMutableArray array]; NSUInteger limit = [[job objectForKey:@"limit"] unsignedIntegerValue];
    names = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in names) {
        if ([entries count] >= limit) break;
        struct stat info; BOOL available = lstat([[directory stringByAppendingPathComponent:name] fileSystemRepresentation], &info) == 0;
        NSString *kind = !available ? @"Unavailable" : S_ISDIR(info.st_mode) ? @"Folder" : S_ISLNK(info.st_mode) ? @"Symbolic link" : S_ISREG(info.st_mode) ? @"File" : @"Special file — cannot open";
        NSString *detail = available && S_ISREG(info.st_mode) ? [NSString stringWithFormat:@"%lld bytes", (long long)info.st_size] : kind;
        [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", detail, @"detail", [NSNumber numberWithBool:available && S_ISDIR(info.st_mode)], @"directory", nil]];
    }
    NSString *status = error ? [error localizedDescription] : [NSString stringWithFormat:@"%lu of %lu entries. Hidden files are included.", (unsigned long)[entries count], (unsigned long)[names count]];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:entries, @"entries", status, @"status", [job objectForKey:@"generation"], @"generation", [NSNumber numberWithBool:[names count] > [entries count]], @"more", nil];
    [self performSelectorOnMainThread:@selector(loaded:) withObject:result waitUntilDone:NO]; [pool drain];
}
- (void)loaded:(NSDictionary *)result {
    if ([[result objectForKey:@"generation"] unsignedIntegerValue] != _generation) return;
    [_entries release]; _entries = [[result objectForKey:@"entries"] copy];
    [_status release]; _status = [[result objectForKey:@"status"] copy];
    _more = [[result objectForKey:@"more"] boolValue]; _loading = NO; [self.tableView reloadData];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; (void)section; return _path; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return [NSString stringWithFormat:@"%@\nRead-only browser. Access uses Receptor’s existing permissions; some system folders cannot be read. Select a regular file to preview it or send it to your PC.", _loading ? @"Loading…" : _status];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return [_entries count] + (_more ? 1 : 0); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"filesystem"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"filesystem"] autorelease];
    cell.accessoryType = UITableViewCellAccessoryNone; cell.detailTextLabel.text = nil;
    if ((NSUInteger)index.row == [_entries count]) cell.textLabel.text = @"Load 500 more…";
    else {
        NSDictionary *entry = [_entries objectAtIndex:index.row]; cell.textLabel.text = [entry objectForKey:@"name"];
        cell.detailTextLabel.text = [entry objectForKey:@"detail"];
        if ([[entry objectForKey:@"directory"] boolValue]) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.textLabel.lineBreakMode = UILineBreakModeMiddleTruncation; return cell;
}
- (void)showError:(NSString *)message {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Filesystem" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil]; [alert show]; [alert release];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES]; if (_loading) return;
    if ((NSUInteger)index.row == [_entries count]) { _limit += 500; [self refresh]; return; }
    NSString *candidate = [_path stringByAppendingPathComponent:[[_entries objectAtIndex:index.row] objectForKey:@"name"]];
    char resolved[PATH_MAX]; struct stat info;
    if (!realpath([candidate fileSystemRepresentation], resolved) || stat(resolved, &info) != 0) {
        [self showError:[NSString stringWithFormat:@"Cannot open this path: %s", strerror(errno)]]; return;
    }
    NSString *canonical = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
    if (S_ISDIR(info.st_mode)) {
        for (UIViewController *controller in self.navigationController.viewControllers) {
            if ([controller isKindOfClass:[RCFilesystemViewController class]] && [((RCFilesystemViewController *)controller)->_path isEqualToString:canonical]) {
                [self.navigationController popToViewController:controller animated:YES]; return;
            }
        }
        RCFilesystemViewController *directory = [[RCFilesystemViewController alloc] initWithPath:canonical];
        [self.navigationController pushViewController:directory animated:YES]; [directory release]; return;
    }
    if (!S_ISREG(info.st_mode)) { [self showError:@"Only folders and regular files can be opened. Devices, sockets and other special files are excluded."]; return; }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:canonical]) { [self showError:@"Receptor does not have permission to read this file."]; return; }
    [_selectedURL release]; _selectedURL = [[NSURL fileURLWithPath:canonical] retain];
    [_actions release]; _actions = [[UIActionSheet alloc] initWithTitle:[canonical lastPathComponent] delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Preview", @"Send to PC", nil];
    [_actions showFromTabBar:self.tabBarController.tabBar];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    if (sheet != _actions || index < 0 || index == sheet.cancelButtonIndex) return;
    if (index == 0) {
        if (![QLPreviewController canPreviewItem:_selectedURL]) { [self showError:@"Quick Look cannot preview this file type. You can send it to your PC instead."]; return; }
        QLPreviewController *preview = [[QLPreviewController alloc] init]; preview.dataSource = self;
        [self.navigationController pushViewController:preview animated:YES]; [preview release];
    } else if (index == 1) {
        RCSendFileViewController *send = [[RCSendFileViewController alloc] initWithPath:[_selectedURL path]];
        [self.navigationController pushViewController:send animated:YES]; [send release];
    }
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller { (void)controller; return _selectedURL ? 1 : 0; }
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index { (void)controller; (void)index; return _selectedURL; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown; }
- (void)dealloc {
    _actions.delegate = nil; [_actions dismissWithClickedButtonIndex:_actions.cancelButtonIndex animated:NO]; [_actions release];
    [_path release]; [_entries release]; [_status release]; [_selectedURL release]; [super dealloc];
}
@end
