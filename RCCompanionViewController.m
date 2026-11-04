#import "RCCompanionViewController.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCDEBInstaller.h"
#import "RCIPAInstaller.h"
#import "RCBackgroundViewController.h"

@interface RCCompanionViewController ()
- (void)setStatus:(NSString *)status;
- (void)cancelTransfer;
- (void)connect;
- (void)forgetConnection;
- (void)reconnectSaved:(NSNotification *)notification;
@end
@implementation RCCompanionViewController
- (id)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _client = [[RCCompanionClient alloc] init]; _client.delegate = self;
        _address = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
        _code = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
        _address.placeholder = @"192.168.1.20:12345";
        _code.placeholder = @"ABCD-EFGH";
        NSDictionary *saved = [RCCompanionClient savedConnection];
        if (saved) { _address.text = [saved objectForKey:@"host"]; _code.placeholder = @"Saved pairing"; }
        _address.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        _code.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        _address.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _address.autocorrectionType = _code.autocorrectionType = UITextAutocorrectionTypeNo;
        _address.delegate = self; _code.delegate = self;
        _address.returnKeyType = _code.returnKeyType = UIReturnKeyDone;
        _address.font = _code.font = [UIFont systemFontOfSize:15];
        _address.contentVerticalAlignment = _code.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _status = [@"Enter the PC address and short code once. Receptor remembers the connection and reconnects next time." copy];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reconnectSaved:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Desktop";
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTransfer)] autorelease];
    self.navigationItem.rightBarButtonItem.enabled = NO;
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; _visible = YES; [self reconnectSaved:nil]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; _visible = NO; _resumeConnection = NO; [_client cancel]; }
- (void)reconnectSaved:(NSNotification *)notification {
    (void)notification;
    if (!_visible || _installPrompt || _forgetPrompt || [UIApplication sharedApplication].applicationState != UIApplicationStateActive || [_code.text length]) return;
    NSDictionary *saved = [RCCompanionClient savedConnection];
    if (!saved || ![[saved objectForKey:@"host"] isEqualToString:_address.text]) return;
    if (_client.busy) { _resumeConnection = YES; return; }
    _resumeConnection = NO; [self connect];
}
- (void)connect {
    [_address resignFirstResponder]; [_code resignFirstResponder];
    [_packages release]; _packages = nil;
    NSError *error = nil;
    if ([_client connectToHost:_address.text code:_code.text error:&error]) [self setStatus:@"Connecting to the desktop…"];
    else [self setStatus:[error localizedDescription]];
}
- (void)setStatus:(NSString *)status {
    [_status release]; _status = [status copy];
    self.navigationItem.rightBarButtonItem.enabled = _client.busy;
    _address.enabled = _code.enabled = !_client.busy;
    [self.tableView reloadData];
}
- (void)cancelTransfer {
    if (_client.busy) { [_client cancel]; [self setStatus:@"Stopping transfer…"]; }
}
- (void)didEnterBackground:(NSNotification *)notification { (void)notification; [_forgetPrompt dismissWithClickedButtonIndex:0 animated:NO]; [self cancelTransfer]; }
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? 5 : [_packages count];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; return section == 0 ? @"Pair with your PC" : @"Files on desktop";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? _status : @"Tap any file to receive it. Open it from Browse to preview, share or install a package. Keep Receptor open. Both devices must be on the same Wi-Fi. File contents are not encrypted in transit; authentication and integrity are checked before installation.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    if (indexPath.section == 0 && indexPath.row < 2) {
        UITextField *field = indexPath.row == 0 ? _address : _code;
        cell.textLabel.text = indexPath.row == 0 ? @"Address" : @"Code";
        field.frame = CGRectMake(100, 0, MAX(150, self.tableView.bounds.size.width - 145), 44);
        field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:field]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 0) {
        cell.textLabel.text = indexPath.row == 2 ? @"Connect / Refresh" : indexPath.row==3 ? @"Forget saved connection" : @"Background desktop access…";
        cell.textLabel.textColor = _client.busy ? [UIColor grayColor] : [UIColor colorWithRed:0 green:0.35f blue:0.75f alpha:1];
    } else {
        NSDictionary *file = [_packages objectAtIndex:indexPath.row];
        cell.textLabel.text = [file objectForKey:@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f MB • Tap to receive", [[file objectForKey:@"size"] doubleValue] / (1024.0 * 1024.0)];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_client.busy || _installPrompt || _forgetPrompt || (indexPath.section == 0 && indexPath.row < 2)) return;
    [_address resignFirstResponder]; [_code resignFirstResponder];
    NSError *error = nil;
    if (indexPath.section == 0) {
        if(indexPath.row==4) { RCBackgroundViewController *controller=[[RCBackgroundViewController alloc] initWithPublicKey:_client.remotePublicKey host:_client.host]; [self.navigationController pushViewController:controller animated:YES]; [controller release]; return; }
        if (indexPath.row == 3) {
            _forgetPrompt=[[UIAlertView alloc] initWithTitle:@"Forget saved connection?" message:@"This removes the saved PC pairing from this device and revokes background desktop access. You will need to pair again. A package operation already running may finish." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Forget",nil];
            [_forgetPrompt show];
        } else [self connect];
    } else {
        if ([[RCDEBInstaller sharedInstaller] busy] || [[RCIPAInstaller sharedInstaller] busy]) {
            [self setStatus:@"Wait for the current installation to finish first."]; return;
        }
        // The client uses the last authenticated session, rather than unsaved field edits.
        if ([_client receiveFile:[_packages objectAtIndex:indexPath.row] error:&error]) [self setStatus:@"Receiving file… Keep Receptor open. Cancel stops the transfer."];
        else [self setStatus:[error localizedDescription]];
    }
}
- (void)forgetConnection {
    if (![RCCompanionClient forgetSavedConnection]) { [self setStatus:@"Could not revoke background access or remove the saved pairing. Unlock the device, check the package helper and try again. The saved connection has been kept."]; return; }
    _resumeConnection = NO; _client.delegate = nil; [_client release];
    _client = [[RCCompanionClient alloc] init]; _client.delegate = self;
    [_packages release]; _packages = nil;
    _address.text = @""; _code.text = @""; _code.placeholder = @"ABCD-EFGH";
    [self setStatus:@"Saved connection forgotten and background access revoked on this device. Enter an address and short code to pair again."];
}
- (void)companion:(RCCompanionClient *)client finished:(NSDictionary *)result {
    (void)client;
    if (_resumeConnection) { _resumeConnection = NO; [self reconnectSaved:nil]; if (_client.busy) return; }
    NSString *failure = [result objectForKey:@"error"];
    if (failure) { [self setStatus:failure]; return; }
    NSArray *files = [result objectForKey:@"files"];
    if (files) {
        [_packages release]; _packages = [files copy];
        NSString *warning = [result objectForKey:@"saveWarning"];
        if (!warning) { _code.text = @""; _code.placeholder = @"Saved pairing"; }
        [self setStatus:warning ?: ([files count] ? @"Paired and remembered. Choose a file below." : @"Connection remembered. Add files on the PC, then tap Connect / Refresh.")];
    }
    NSString *saved = [result objectForKey:@"saved"];
    if (saved) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RCDownloadsChangedNotification object:nil];
        [self setStatus:[NSString stringWithFormat:@"Received and verified %@. Saved in Receptor.", saved]];
        if (self.navigationController.topViewController != self || [UIApplication sharedApplication].applicationState != UIApplicationStateActive || ![[[saved pathExtension] lowercaseString] isEqualToString:@"deb"]) return;
        [_pendingName release]; _pendingName = [saved copy];
        _installPrompt = [[UIAlertView alloc] initWithTitle:@"Install received DEB?"
            message:[NSString stringWithFormat:@"%@\n\nPackages can run scripts as root. Install only a package you trust. Close Cydia before continuing.", saved]
            delegate:self cancelButtonTitle:@"Keep File" otherButtonTitles:@"Install", nil];
        [_installPrompt show];
    }
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {
    if(alert==_forgetPrompt) {
        [_forgetPrompt autorelease];_forgetPrompt=nil;
        if(index==1 && _visible && !_client.busy && [UIApplication sharedApplication].applicationState==UIApplicationStateActive)[self forgetConnection];
        return;
    }
    if (alert != _installPrompt) return;
    [_installPrompt autorelease]; _installPrompt = nil;
    if (index == 1 && RCIsRegularDownload(_pendingName)) {
        [[RCDEBInstaller sharedInstaller] installFileNamed:_pendingName];
        [self setStatus:@"Installation requested. Return to Files → Install Log for the result; reopen Cydia afterward."];
    }
    [_pendingName release]; _pendingName = nil;
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _client.delegate = nil; [_client cancel]; [_client release];
    _address.delegate = nil; _code.delegate = nil; [_address release]; [_code release];
    _installPrompt.delegate = nil; [_installPrompt dismissWithClickedButtonIndex:0 animated:NO]; [_installPrompt release];
    _forgetPrompt.delegate = nil; [_forgetPrompt dismissWithClickedButtonIndex:0 animated:NO]; [_forgetPrompt release];
    [_pendingName release]; [_packages release]; [_status release]; [super dealloc];
}
@end
