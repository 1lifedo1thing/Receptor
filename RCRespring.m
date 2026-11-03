#import "RCRespring.h"
#import "RCDEBInstaller.h"
#import "RCPackageManager.h"
#import "RCIPAInstaller.h"
#import "DownloadManager.h"
#import "ReceptorUI.h"
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

@implementation RCRespring
@synthesize busy = _busy;
+ (RCRespring *)sharedController {
    static RCRespring *controller = nil;
    if (!controller) controller = [[self alloc] init];
    return controller;
}
- (id)init {
    if ((self = [super init])) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}
- (void)enteredBackground:(NSNotification *)notification { (void)notification; [_prompt dismissWithClickedButtonIndex:0 animated:NO]; }
- (void)requestRespring {
    NSAssert([NSThread isMainThread], @"Main thread required");
    if (_prompt || _busy) return;
    if ([[RCDEBInstaller sharedInstaller] busy] || [[RCIPAInstaller sharedInstaller] busy] || [[RCPackageManager sharedManager] busy]) {
        [[ReceptorUI sharedUI] showMessage:@"Wait for the installation to finish before respringing."]; return;
    }
    _prompt = [[UIAlertView alloc] initWithTitle:@"Respring?" message:@"Restart the Home and lock-screen interface now? Close Cydia and finish transfers first. Apps and transfers may be interrupted. This does not reboot the iPad or iPhone." delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Respring", nil];
    [_prompt show];
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index {
    if (alert != _prompt) return;
    [_prompt autorelease]; _prompt = nil;
    if (index != 1 || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if ([[RCDEBInstaller sharedInstaller] busy] || [[RCIPAInstaller sharedInstaller] busy] || [[RCPackageManager sharedManager] busy] || [[[DownloadManager sharedManager] activeDownloads] count]) {
        [[ReceptorUI sharedUI] showMessage:@"Finish installations and downloads before respringing."]; return;
    }
    _busy = YES;
    NSString *operation = [[[UIDevice currentDevice] systemVersion] integerValue] >= 6 ? @"--respring-backboard" : @"--respring";
    [NSThread detachNewThreadSelector:@selector(runRespring:) toTarget:self withObject:operation];
}
- (void)runRespring:(NSString *)operation {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const char *helper = "/usr/libexec/receptor-deb-helper"; struct stat info;
    int result = 2;
    if (stat(helper, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == 0 && (info.st_mode & S_ISUID) && !(info.st_mode & 022)) {
        posix_spawn_file_actions_t actions; int setup = posix_spawn_file_actions_init(&actions); BOOL initialized = setup == 0;
        if (!setup) setup = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
        if (!setup) setup = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
        if (!setup) setup = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
        char *arguments[] = {(char *)helper, (char *)[operation UTF8String], NULL};
        char *environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/var/mobile", "LANG=C", NULL};
        pid_t child = 0; int error = setup ? setup : posix_spawn(&child, helper, &actions, NULL, arguments, environment);
        if (initialized) posix_spawn_file_actions_destroy(&actions);
        if (!error) {
            int status = 0; pid_t waited;
            do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
            result = waited == child && WIFEXITED(status) ? WEXITSTATUS(status) : 2;
        }
    }
    [self performSelectorOnMainThread:@selector(finished:) withObject:[NSNumber numberWithInt:result] waitUntilDone:NO]; [pool drain];
}
- (void)finished:(NSNumber *)result {
    _busy = NO;
    if ([result intValue]) [[ReceptorUI sharedUI] showMessage:@"The respring request failed. Wait for all package managers to finish, close Cydia and retry. If it still fails, reinstall Receptor through Cydia to restore its helper permissions."];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self]; _prompt.delegate = nil;
    [_prompt dismissWithClickedButtonIndex:0 animated:NO]; [_prompt release]; [super dealloc];
}
@end
