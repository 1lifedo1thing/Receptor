#import "ReceptorUI.h"
#import "DownloadManager.h"
#import "ReceptorPaths.h"

@interface ReceptorUI ()
- (void)presentNextAlert;
@end

@implementation ReceptorUI
+ (ReceptorUI *)sharedUI {
    NSAssert([NSThread isMainThread], @"Main thread required");
    static ReceptorUI *ui = nil;
    if (!ui) ui = [[self alloc] init];
    return ui;
}
+ (void)install { [self sharedUI]; }
+ (void)promptForRequest:(NSURLRequest *)request {
    ReceptorUI *ui = [self sharedUI];
    if ([ui->_requests count] >= 8 || [[ui->_promptRequest URL] isEqual:[request URL]]) return;
    for (NSURLRequest *queued in ui->_requests) if ([[queued URL] isEqual:[request URL]]) return;
    [ui->_requests addObject:[[request copy] autorelease]];
    [ui presentNextAlert];
}
- (id)init {
    if ((self = [super init])) {
        _requests = [[NSMutableArray alloc] init];
        _messages = [[NSMutableArray alloc] init];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}
- (void)becameActive:(NSNotification *)notification { (void)notification; [self presentNextAlert]; }
- (void)enteredBackground:(NSNotification *)notification {
    (void)notification;
    [_requests removeAllObjects];
    if (_alert) [_alert dismissWithClickedButtonIndex:0 animated:NO];
}
- (void)showFiles {
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.receptor.app"]) return;
    if (![[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"receptor://files"]]) {
        [self showMessage:@"Open the Receptor app on your Home screen. If its icon is missing, reinstall Receptor and respring."];
    }
}
- (void)showMessage:(NSString *)message {
    if (![message length]) return;
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.alertBody = [@"Receptor: " stringByAppendingString:message];
        notification.soundName = UILocalNotificationDefaultSoundName;
        [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
        [notification release];
        return;
    }
    if ([_messages count] < 16) [_messages addObject:message];
    [self presentNextAlert];
}
- (void)presentNextAlert {
    if (_alert || [[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) return;
    BOOL app = [[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.receptor.app"];
    if ([_requests count]) {
        _promptRequest = [[_requests objectAtIndex:0] retain];
        [_requests removeObjectAtIndex:0];
        NSString *message = [NSString stringWithFormat:@"Download %@ from %@?",
            RCSafeFilename([[[_promptRequest URL] path] lastPathComponent]), [[_promptRequest URL] host]];
        _alert = [[UIAlertView alloc] initWithTitle:@"Receptor" message:message delegate:self
            cancelButtonTitle:@"Cancel" otherButtonTitles:@"Download", nil];
        if (!app) [_alert addButtonWithTitle:@"Open Receptor"];
    } else if ([_messages count]) {
        NSString *message = [[[_messages objectAtIndex:0] retain] autorelease];
        [_messages removeObjectAtIndex:0];
        _alert = [[UIAlertView alloc] initWithTitle:@"Receptor" message:message delegate:self
            cancelButtonTitle:@"OK" otherButtonTitles:nil];
        if (!app) [_alert addButtonWithTitle:@"Open Receptor"];
    }
    [_alert show];
}
- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView != _alert) return;
    NSURLRequest *request = [_promptRequest autorelease]; _promptRequest = nil;
    [_alert autorelease]; _alert = nil;
    if (request && buttonIndex == 1) {
        NSError *error = nil;
        if (![[DownloadManager sharedManager] startDownloadWithRequest:request error:&error]) [self showMessage:[error localizedDescription]];
    } else if ((request && buttonIndex == 2) || (!request && buttonIndex == 1)) [self showFiles];
    [self presentNextAlert];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _alert.delegate = nil; [_alert dismissWithClickedButtonIndex:0 animated:NO];
    [_alert release]; [_requests release]; [_messages release]; [_promptRequest release];
    [super dealloc];
}
@end
