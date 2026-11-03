#import "RCBackgroundViewController.h"
#import "RCCompanionClient.h"
#import "RCRemoteCrypto.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

@implementation RCBackgroundViewController
- (id)initWithPublicKey:(NSString *)key host:(NSString *)host {
    if((self=[super initWithStyle:UITableViewStyleGrouped])) { _publicKey=[key copy]; _host=[host copy]; _message=[@"Loading background access status…" copy]; } return self;
}
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Background access"; [self run:[NSArray arrayWithObject:@"remote-status"]]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:YES animated:animated]; if(!_refreshTimer)_refreshTimer=[[NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(refreshStatus:) userInfo:nil repeats:YES] retain]; }
- (void)viewWillDisappear:(BOOL)animated { [_refreshTimer invalidate]; [_refreshTimer release]; _refreshTimer=nil; [super viewWillDisappear:animated]; }
- (void)refreshStatus:(NSTimer *)timer { (void)timer; if(!_prompt && ![[RCPackageManager sharedManager] busy])[[RCPackageManager sharedManager] run:[NSArray arrayWithObject:@"remote-status"] delegate:self]; }
- (void)run:(NSArray *)arguments { if([[RCPackageManager sharedManager] run:arguments delegate:self]) { [_message release]; _message=[@"Updating background access…" copy]; [self.tableView reloadData]; } }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView;(void)section;return 4; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index { (void)tableView;return index.row==0?80:50; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;(void)section;
    return [NSString stringWithFormat:@"%@\n\nThis optional service lets the trusted PC manage packages, sources and Receptor’s download folder while the app is closed, including while locked. Enable background access and keep sharing running in Receptor Desktop 1.8.0. The iPad/iPhone must remain powered on and reachable on Wi-Fi. Background networking can use more battery. Disable below to revoke access; an install already running may finish safely.",_message];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    (void)tableView; UITableViewCell *cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    if(index.row==0) { BOOL enabled=[[_status objectForKey:@"enabled"] boolValue]; cell.textLabel.text=enabled?@"Background permission saved":@"Background access disabled";
        NSString *device=[_status objectForKey:@"device"]; cell.detailTextLabel.numberOfLines=2; cell.detailTextLabel.text=enabled?[NSString stringWithFormat:@"%@\nDevice %@",[_status objectForKey:@"host"],device?[device substringToIndex:MIN((NSUInteger)8,[device length])]:@""]:@"Requires one-time approval here before desktop control."; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else { cell.textLabel.text=index.row==1?@"Enable for the paired PC…":index.row==2?@"Disable background access":@"Restart service / Retry connection"; cell.textLabel.textColor=[[RCPackageManager sharedManager] busy]?[UIColor grayColor]:[UIColor colorWithRed:0 green:0.35 blue:0.8 alpha:1]; }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES]; if(index.row==0 || _prompt || [[RCPackageManager sharedManager] busy])return;
    if(index.row==2) { [self run:[NSArray arrayWithObject:@"remote-disable"]]; return; }
    if(index.row==3) { [self run:[NSArray arrayWithObject:@"remote-start"]]; return; }
    NSDictionary *saved=[RCCompanionClient savedConnection]; NSString *fingerprint=RCRemoteFingerprint(_publicKey);
    if(!saved || ![[saved objectForKey:@"host"] isEqual:_host] || !fingerprint) { [[ReceptorUI sharedUI] showMessage:@"On the PC, enable background device access in Desktop 1.8.0 and start sharing. Return to Desktop in Receptor, Connect / Refresh successfully, then open this screen again."]; return; }
    _prompt=[[UIAlertView alloc] initWithTitle:@"Trust this PC in the background?" message:[NSString stringWithFormat:@"%@\nPC key: %@\n\nCompare this key with the PC. This PC will be able to install/remove packages, change sources, respring and transfer files in Receptor’s folder while this app is closed or the device is locked. Desktop confirmations replace on-device confirmations until you disable access.",_host,[fingerprint substringToIndex:16]] delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Enable access",nil]; [_prompt show];
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {
    if(alert!=_prompt)return; [_prompt autorelease]; _prompt=nil;
    if(index!=1 || [UIApplication sharedApplication].applicationState!=UIApplicationStateActive)return;
    NSDictionary *saved=[RCCompanionClient savedConnection]; if(!saved || ![[saved objectForKey:@"host"] isEqual:_host])return;
    NSData *seed=RCRemoteRandom(32),*sealed=RCRemoteSeal(_publicKey,seed); if(!sealed) { [[ReceptorUI sharedUI] showMessage:@"The PC’s remote key is invalid. Update the desktop companion and reconnect."]; return; }
    NSString *device=[RCRemoteHash(seed) substringToIndex:32]; NSDictionary *config=[NSDictionary dictionaryWithObjectsAndKeys:_host,@"host",_publicKey,@"publicKey",seed,@"seed",sealed,@"sealed",RCRemoteEnrollment([saved objectForKey:@"key"],device,sealed),@"enrollment",nil];
    NSError *error=nil; NSData *data=[NSPropertyListSerialization dataWithPropertyList:config format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    NSString *name=[NSString stringWithFormat:@".receptor-remote-config-%@.plist",[RCRemoteHash(RCRemoteRandom(32)) substringToIndex:32]]; NSString *path=[RCDownloadsDirectory stringByAppendingPathComponent:name];
    int fd=open([path fileSystemRepresentation],O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600); BOOL okay=fd>=0 && data && write(fd,[data bytes],[data length])==(ssize_t)[data length] && fsync(fd)==0; if(fd>=0)close(fd);
    if(!okay) { unlink([path fileSystemRepresentation]); [[ReceptorUI sharedUI] showMessage:@"Cannot stage background settings. Check free space."]; return; }
    [_staged release]; _staged=[path copy];
    if(![[RCPackageManager sharedManager] run:[NSArray arrayWithObjects:@"remote-enable",name,nil] delegate:self]) { unlink([_staged fileSystemRepresentation]); [_staged release]; _staged=nil; }
    else { [_message release]; _message=[@"Enabling the background service…" copy]; [self.tableView reloadData]; }
}
- (void)packageOperationFinished:(NSDictionary *)result {
    if(_staged) { unlink([_staged fileSystemRepresentation]); [_staged release]; _staged=nil; }
    NSString *failure=[result objectForKey:@"error"]; [_message release]; _message=[failure?:[result objectForKey:@"output"]?:@"Ready." copy];
    if([result objectForKey:@"enabled"]) { [_status release]; _status=[result copy]; }
    [self.tableView reloadData];
    if(!failure && [[result objectForKey:@"operation"] isEqual:@"remote-enable"]) [self run:[NSArray arrayWithObject:@"remote-status"]];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad || orientation!=UIInterfaceOrientationPortraitUpsideDown; }
- (void)dealloc {
    [_refreshTimer invalidate]; [_refreshTimer release];
    if([RCPackageManager sharedManager].delegate==self)[RCPackageManager sharedManager].delegate=nil;
    _prompt.delegate=nil; [_prompt dismissWithClickedButtonIndex:0 animated:NO]; [_prompt release];
    [_publicKey release]; [_host release]; [_message release]; [_status release]; [_staged release]; [super dealloc];
}
@end
