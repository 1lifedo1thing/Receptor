#import "RCSendFileViewController.h"
#import "RCCompanionViewController.h"

@interface RCSendFileViewController ()
- (void)setStatus:(NSString *)status;
- (void)cancel;
- (void)restoreIdle;
@end
@implementation RCSendFileViewController
- (id)initWithPath:(NSString *)path {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _path = [path copy]; _client = [[RCCompanionClient alloc] init]; _client.delegate = self;
        _status = [@"Enable receiving in Receptor Desktop, choose its destination folder and keep sharing running. Then tap Send to PC below. You can enable receiving without stopping sharing in Desktop 1.6.0 beta 2." copy];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Send to PC";
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)] autorelease];
    self.navigationItem.rightBarButtonItem.enabled = NO;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:YES animated:animated]; [self.tableView reloadData]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self cancel]; }
- (void)enteredBackground:(NSNotification *)notification { (void)notification; [self cancel]; }
- (void)restoreIdle {
    if (_changedIdle) { [UIApplication sharedApplication].idleTimerDisabled = _previousIdle; _changedIdle = NO; }
}
- (void)setStatus:(NSString *)status {
    [_status release]; _status = [status copy]; self.navigationItem.rightBarButtonItem.enabled = _client.busy;
    [self.tableView reloadData];
}
- (void)cancel {
    if (_client.busy) { [_client cancel]; _sending = NO; [self setStatus:@"Stopping transfer… A copy already fully delivered may remain on your PC."]; }
    [self restoreIdle];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return 4; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index { (void)tableView; return index.row < 2 ? 68 : 48; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return [NSString stringWithFormat:@"%@\n\nOnly the selected regular file is sent. The source stays unchanged. Keep both apps open. Transfers are authenticated but not encrypted.", _status];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)tableView;
    UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    if (index.row == 0) {
        cell.textLabel.text = [_path lastPathComponent]; cell.textLabel.lineBreakMode = UILineBreakModeMiddleTruncation;
        cell.detailTextLabel.text = _path; cell.detailTextLabel.numberOfLines = 2; cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    } else if (index.row == 1) {
        cell.textLabel.text = @"Paired PC";
        cell.detailTextLabel.text = [[RCCompanionClient savedConnection] objectForKey:@"host"] ?: @"Not paired — use Manage pairing below";
    } else {
        cell.textLabel.text = index.row == 2 ? (_sending ? @"Preparing / sending…" : @"Send to PC") : @"Manage pairing";
        cell.textLabel.textColor = _client.busy ? [UIColor grayColor] : [UIColor colorWithRed:0 green:0.35f blue:0.8f alpha:1];
    }
    cell.selectionStyle = index.row < 2 || _client.busy ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES]; if (_client.busy || index.row < 2) return;
    if (index.row == 3) {
        RCCompanionViewController *pair = [[RCCompanionViewController alloc] init];
        [self.navigationController pushViewController:pair animated:YES]; [pair release]; return;
    }
    NSDictionary *saved = [RCCompanionClient savedConnection];
    if (!saved) { [self setStatus:@"Pair with your PC using Manage pairing first, then return here to send this file."]; return; }
    NSError *error = nil;
    if ([_client connectToHost:[saved objectForKey:@"host"] code:@"" error:&error]) {
        _sending = YES; _previousIdle = [UIApplication sharedApplication].idleTimerDisabled; _changedIdle = YES;
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        [self setStatus:@"Connecting to your paired PC…"];
    } else [self setStatus:[error localizedDescription]];
}
- (void)companion:(RCCompanionClient *)client finished:(NSDictionary *)result {
    NSString *failure = [result objectForKey:@"error"];
    if (failure) { _sending = NO; [self restoreIdle]; [self setStatus:failure]; return; }
    if ([result objectForKey:@"files"] && _sending) {
        if (!client.canUpload) {
            _sending = NO; [self restoreIdle]; [self setStatus:@"On the PC, enable Receive files sent from the device and choose a writable folder. Keep sharing running, then tap Send to PC again. Update to Desktop 1.6.0 beta 2 to enable receiving without disconnecting."]; return;
        }
        NSError *error = nil;
        if ([client sendFileAtPath:_path error:&error]) [self setStatus:@"Preparing a private file snapshot, then sending it to the PC…"];
        else { _sending = NO; [self restoreIdle]; [self setStatus:[error localizedDescription]]; }
        return;
    }
    _sending = NO; [self restoreIdle];
    NSString *saved = [result objectForKey:@"uploaded"];
    [self setStatus:saved ? [NSString stringWithFormat:@"Delivery verified. Saved on your PC as %@. Use Open folder in the companion to find it.", saved] : @"No delivery was confirmed."];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self]; _client.delegate = nil; [_client cancel]; [_client release];
    [self restoreIdle]; [_path release]; [_status release]; [super dealloc];
}
@end
