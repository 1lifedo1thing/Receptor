#import "RCDEBInstaller.h"
#import "RCIPAInstaller.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCRespring.h"
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static NSString * const RCDebHelper = @"/usr/libexec/receptor-deb-helper";
static NSString *RCDebLogPath(void) { return [RCDownloadsDirectory stringByAppendingPathComponent:@".last-deb-install.log"]; }
static BOOL RCDebCreatePipe(int descriptors[2]) {
    if (pipe(descriptors)) return NO;
    for (int i = 0; i < 2; ++i) {
        if (descriptors[i] <= STDERR_FILENO) {
            int duplicate = fcntl(descriptors[i], F_DUPFD, STDERR_FILENO + 1);
            if (duplicate < 0) { close(descriptors[0]); close(descriptors[1]); return NO; }
            close(descriptors[i]); descriptors[i] = duplicate;
        }
    }
    return YES;
}

@interface RCDEBInstaller ()
- (void)setInstallStatus:(NSString *)status;
@end
@implementation RCDEBInstaller
@synthesize busy = _busy, status = _status, lastOutput = _lastOutput;
+ (RCDEBInstaller *)sharedInstaller {
    static RCDEBInstaller *installer = nil;
    if (!installer) installer = [[self alloc] init];
    return installer;
}
- (id)init {
    if ((self = [super init])) {
        _backgroundTask = UIBackgroundTaskInvalid;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:RCDebLogPath() error:NULL];
        if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] <= 1024 * 1024) {
            _lastOutput = [[NSString alloc] initWithContentsOfFile:RCDebLogPath() encoding:NSUTF8StringEncoding error:NULL];
        }
    }
    return self;
}
- (void)setInstallStatus:(NSString *)status {
    [_status release]; _status = [status copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCInstallationChangedNotification object:self];
}
- (void)installFileNamed:(NSString *)name {
    NSAssert([NSThread isMainThread], @"Main thread required");
    if ([[RCRespring sharedController] busy]) { [[ReceptorUI sharedUI] showMessage:@"A respring has been requested. Wait for it to finish before installing."]; return; }
    if (_busy || [[RCIPAInstaller sharedInstaller] busy]) { [[ReceptorUI sharedUI] showMessage:@"An installation is already running."]; return; }
    if (!RCIsRegularDownload(name) || ![[[name pathExtension] lowercaseString] isEqual:@"deb"]) {
        [[ReceptorUI sharedUI] showMessage:@"Choose a saved DEB file."]; return;
    }
    struct stat helper;
    if (stat([RCDebHelper fileSystemRepresentation], &helper) || helper.st_uid != 0 || !(helper.st_mode & S_ISUID) ||
        (helper.st_mode & 022) || access([RCDebHelper fileSystemRepresentation], X_OK)) {
        [[ReceptorUI sharedUI] showMessage:@"The package-install helper is missing or has incorrect permissions. Reinstall Receptor through Cydia."]; return;
    }
    _busy = YES;
    [self setInstallStatus:@"Preparing DEB…"];
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        // Never kill dpkg halfway through a transaction. The helper can finish
        // independently; the UI reads its result when execution resumes.
        UIBackgroundTaskIdentifier task = _backgroundTask;
        _backgroundTask = UIBackgroundTaskInvalid;
        if (task != UIBackgroundTaskInvalid) [[UIApplication sharedApplication] endBackgroundTask:task];
    }];
    [NSThread detachNewThreadSelector:@selector(installOnWorker:) toTarget:self withObject:[[name copy] autorelease]];
}
- (void)installOnWorker:(NSString *)name {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *stagedName = [NSString stringWithFormat:@".receptor-deb-%@.deb", RCSafeFilename([[NSProcessInfo processInfo] globallyUniqueString])];
    NSString *stagedPath = [RCDownloadsDirectory stringByAppendingPathComponent:stagedName];
    NSString *source = [RCDownloadsDirectory stringByAppendingPathComponent:name];
    NSError *error = nil;
    NSMutableData *captured = [NSMutableData data];
    int result = 2;
    BOOL staged = NO;
    if (RCIsRegularDownload(name)) staged = [[NSFileManager defaultManager] copyItemAtPath:source toPath:stagedPath error:&error];
    if (!staged || chmod([stagedPath fileSystemRepresentation], 0600)) {
        NSString *message = [NSString stringWithFormat:@"Cannot stage the DEB. Check free space. %@", [error localizedDescription] ?: @""];
        [captured appendData:[message dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        int descriptors[2];
        if (RCDebCreatePipe(descriptors)) {
            fcntl(descriptors[0], F_SETFD, FD_CLOEXEC); fcntl(descriptors[1], F_SETFD, FD_CLOEXEC);
            posix_spawn_file_actions_t actions;
            int setup = posix_spawn_file_actions_init(&actions);
            BOOL initialized = setup == 0;
            if (!setup) setup = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
            if (!setup) setup = posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO);
            if (!setup) setup = posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO);
            if (!setup) setup = posix_spawn_file_actions_addclose(&actions, descriptors[0]);
            if (!setup) setup = posix_spawn_file_actions_addclose(&actions, descriptors[1]);
            char *arguments[] = {(char *)[RCDebHelper fileSystemRepresentation], (char *)[stagedName fileSystemRepresentation], NULL};
            char *environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/var/mobile", "LANG=C", NULL};
            pid_t child = 0;
            int spawnError = setup ? setup : posix_spawn(&child, [RCDebHelper fileSystemRepresentation], &actions, NULL, arguments, environment);
            if (initialized) posix_spawn_file_actions_destroy(&actions);
            close(descriptors[1]);
            if (!spawnError) {
                char buffer[4096];
                BOOL installing = NO;
                [self performSelectorOnMainThread:@selector(setInstallStatus:) withObject:@"Checking DEB…" waitUntilDone:NO];
                for (;;) {
                    ssize_t count = read(descriptors[0], buffer, sizeof(buffer));
                    if (count < 0 && errno == EINTR) continue;
                    if (count <= 0) break;
                    [captured appendBytes:buffer length:(NSUInteger)count];
                    if ([captured length] > 65536) [captured replaceBytesInRange:NSMakeRange(0, [captured length] - 65536) withBytes:NULL length:0];
                    if (!installing) {
                        NSString *text = [[[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] autorelease];
                        if (text && [text rangeOfString:@"Installing with dpkg"].location != NSNotFound) {
                            installing = YES;
                            [self performSelectorOnMainThread:@selector(setInstallStatus:) withObject:@"Installing DEB…" waitUntilDone:NO];
                        }
                    }
                }
                int status = 0;
                pid_t waited;
                do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
                result = waited == child && WIFEXITED(status) ? WEXITSTATUS(status) : 2;
            } else {
                NSString *message = [NSString stringWithFormat:@"Unable to start the package installer: %s", strerror(spawnError)];
                [captured appendData:[message dataUsingEncoding:NSUTF8StringEncoding]];
            }
            close(descriptors[0]);
        } else {
            [captured appendData:[@"Unable to capture package-manager output." dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    if (staged) unlink([stagedPath fileSystemRepresentation]);
    NSString *output = [[[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] autorelease];
    if (!output) output = [[[NSString alloc] initWithData:captured encoding:NSISOLatin1StringEncoding] autorelease];
    NSDictionary *completion = [NSDictionary dictionaryWithObjectsAndKeys:output ?: @"No package-manager output was returned.", @"output",
        [NSNumber numberWithInt:result], @"result", name, @"name", nil];
    [self performSelectorOnMainThread:@selector(finished:) withObject:completion waitUntilDone:YES];
    [pool drain];
}
- (void)finished:(NSDictionary *)completion {
    [_lastOutput release]; _lastOutput = [[completion objectForKey:@"output"] copy];
    [_lastOutput writeToFile:RCDebLogPath() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    chmod([RCDebLogPath() fileSystemRepresentation], 0600);
    _busy = NO;
    [self setInstallStatus:nil];
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        UIBackgroundTaskIdentifier task = _backgroundTask; _backgroundTask = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask:task];
    }
    NSString *message = [[completion objectForKey:@"result"] intValue] == 0 ?
        [NSString stringWithFormat:@"Installed %@. Reopen Cydia and check Installed. If the package requires a respring, use Respring in the Files toolbar or Install Log. Receptor does not automatically determine whether one is required.", [completion objectForKey:@"name"]] :
        @"The DEB installation did not complete. Tap Install Log for the package-manager output. Close Cydia if its database is locked; install missing dependencies through Cydia and retry. No force options were used.";
    [[ReceptorUI sharedUI] showMessage:message];
}
- (void)dealloc { [_status release]; [_lastOutput release]; [super dealloc]; }
@end
