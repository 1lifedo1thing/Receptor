#import "ReceptorUI.h"
#import "DownloadManager.h"
#import "FileBrowserViewController.h"
#import "ReceptorPaths.h"

@interface ReceptorUI ()
- (void)attachButton;
- (void)presentNextAlert;
@end

@implementation ReceptorUI
+ (ReceptorUI *)sharedUI {
    NSAssert([NSThread isMainThread], @"ReceptorUI must run on the main thread");
    static ReceptorUI *ui = nil;
    if (!ui) ui = [[self alloc] init];
    return ui;
}
+ (void)install { [[self sharedUI] attachButton]; }
+ (void)promptForRequest:(NSURLRequest *)request {
    ReceptorUI *ui = [self sharedUI];
    // A bounded queue prevents a page with many navigations from exhausting memory.
    if ([ui->_requests count] >= 8) return;
    if ([[ui->_promptRequest URL] isEqual:[request URL]]) return;
    for (NSURLRequest *queued in ui->_requests) if ([[queued URL] isEqual:[request URL]]) return;
    [ui->_requests addObject:[[request copy] autorelease]];
    [ui presentNextAlert];
}
- (id)init {
    if ((self = [super init])) {
        _requests = [[NSMutableArray alloc] init];
        _messages = [[NSMutableArray alloc] init];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(windowChanged:) name:UIWindowDidBecomeKeyNotification object:nil];
        [center addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}
- (void)windowChanged:(NSNotification *)notification {
    (void)notification; [self attachButton];
}
- (void)becameActive:(NSNotification *)notification {
    (void)notification; [self attachButton]; [self presentNextAlert];
}
- (void)enteredBackground:(NSNotification *)notification {
    (void)notification;
    // A pending consent must never silently become a download after suspension.
    [_requests removeAllObjects];
    if (_alert) [_alert dismissWithClickedButtonIndex:0 animated:NO];
}
- (void)attachButton {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window || window == _browserWindow || [window windowLevel] != UIWindowLevelNormal) return;
    if (!_filesButton) {
        _filesButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
        [_filesButton setTitle:@"Files" forState:UIControlStateNormal];
        [_filesButton addTarget:self action:@selector(showFiles) forControlEvents:UIControlEventTouchUpInside];
        _filesButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        _filesButton.accessibilityLabel = @"Receptor downloads";
    }
    _filesButton.frame = CGRectMake(MAX(0.0f, window.bounds.size.width - 66.0f),
        MAX(0.0f, window.bounds.size.height - 84.0f), 60.0f, 32.0f);
    [window addSubview:_filesButton];
}
- (void)showFiles {
    if (_browserWindow) return;
    _previousWindow = [[[UIApplication sharedApplication] keyWindow] retain];
    FileBrowserViewController *browser = [[FileBrowserViewController alloc] initWithStyle:UITableViewStylePlain];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:browser];
    [browser release];
    // Safari's root controller differs across iOS releases. Own our presentation window.
    _browserWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _browserWindow.windowLevel = UIWindowLevelNormal + 1.0f;
    _browserWindow.rootViewController = navigation;
    [navigation release];
    [_browserWindow makeKeyAndVisible];
}
- (void)closeFiles {
    _browserWindow.hidden = YES;
    [_previousWindow makeKeyWindow];
    [_browserWindow release]; _browserWindow = nil;
    [_previousWindow release]; _previousWindow = nil;
    [self attachButton];
}
- (void)showMessage:(NSString *)message {
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
    if ([_requests count]) {
        _promptRequest = [[_requests objectAtIndex:0] retain];
        [_requests removeObjectAtIndex:0];
        NSString *filename = RCSafeFilename([[[_promptRequest URL] path] lastPathComponent]);
        NSString *message = [NSString stringWithFormat:@"Download %@ from %@?\n\nThe current navigation has been stopped.",
            [filename length] ? filename : @"this file", [[_promptRequest URL] host]];
        _alert = [[UIAlertView alloc] initWithTitle:@"Receptor" message:message delegate:self
            cancelButtonTitle:@"Cancel" otherButtonTitles:@"Download", @"Files", nil];
    } else if ([_messages count]) {
        NSString *message = [[[_messages objectAtIndex:0] retain] autorelease];
        [_messages removeObjectAtIndex:0];
        _alert = [[UIAlertView alloc] initWithTitle:@"Receptor" message:message delegate:self
            cancelButtonTitle:@"OK" otherButtonTitles:@"Files", nil];
    }
    [_alert show];
}
- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView != _alert) return;
    NSURLRequest *request = [_promptRequest autorelease]; _promptRequest = nil;
    [_alert autorelease]; _alert = nil;
    if (request && buttonIndex == 1) {
        NSError *error = nil;
        if (![[DownloadManager sharedManager] startDownloadWithRequest:request error:&error]) {
            [self showMessage:[error localizedDescription]];
        }
    } else if ((request && buttonIndex == 2) || (!request && buttonIndex == 1)) {
        [self showFiles];
    }
    [self presentNextAlert];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _alert.delegate = nil; [_alert dismissWithClickedButtonIndex:0 animated:NO];
    [_alert release]; [_requests release]; [_messages release]; [_promptRequest release];
    [_filesButton removeFromSuperview]; [_filesButton release];
    [_browserWindow release]; [_previousWindow release];
    [super dealloc];
}
@end
