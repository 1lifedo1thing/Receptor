#import "RCPackageManager.h"
#import "RCDEBInstaller.h"
#import "RCIPAInstaller.h"
#import "RCRespring.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

@implementation RCPackageManager
@synthesize delegate = _delegate, busy = _busy, lastOutput = _lastOutput;
+ (RCPackageManager *)sharedManager { static RCPackageManager *manager = nil; if (!manager) manager = [[self alloc] init]; return manager; }
- (id)init { if ((self = [super init])) { _task = UIBackgroundTaskInvalid; NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:@".last-packages.log"]; if ([[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] objectForKey:NSFileSize] unsignedLongLongValue] <= 2 * 1024 * 1024) _lastOutput = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]; } return self; }
- (BOOL)run:(NSArray *)arguments delegate:(id<RCPackageManagerDelegate>)delegate {
    NSAssert([NSThread isMainThread], @"Main thread required");
    if (_busy || [[RCDEBInstaller sharedInstaller] busy] || [[RCIPAInstaller sharedInstaller] busy] || [[RCRespring sharedController] busy]) { [[ReceptorUI sharedUI] showMessage:@"Wait for the current installation, package operation or respring request to finish."]; return NO; }
    _busy = YES; _delegate = delegate;
    _task = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ UIBackgroundTaskIdentifier task = _task; _task = UIBackgroundTaskInvalid; if (task != UIBackgroundTaskInvalid) [[UIApplication sharedApplication] endBackgroundTask:task]; }];
    [NSThread detachNewThreadSelector:@selector(worker:) toTarget:self withObject:[[arguments copy] autorelease]]; return YES;
}
- (void)worker:(NSArray *)arguments {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; NSMutableDictionary *result = [NSMutableDictionary dictionary];
    const char *helper = "/usr/libexec/receptor-package-helper"; struct stat info;
    if (stat(helper, &info) || !S_ISREG(info.st_mode) || info.st_uid != 0 || !(info.st_mode & S_ISUID) || (info.st_mode & 022)) [result setObject:@"The package helper is missing or has incorrect permissions. Reinstall Receptor through Cydia." forKey:@"error"];
    else {
        int descriptors[2];
        if (pipe(descriptors)) [result setObject:@"Cannot create package-manager output pipe." forKey:@"error"];
        else {
            // Reserve ordinary fds even if this process inherited a closed standard stream.
            for (int i = 0; i < 2; i++) if (descriptors[i] <= 2) { int copy = fcntl(descriptors[i], F_DUPFD, 3); close(descriptors[i]); descriptors[i] = copy; }
            if (descriptors[0] < 0 || descriptors[1] < 0) [result setObject:@"Cannot reserve package-manager output descriptors." forKey:@"error"];
            else {
                fcntl(descriptors[0], F_SETFD, FD_CLOEXEC); fcntl(descriptors[1], F_SETFD, FD_CLOEXEC);
                posix_spawn_file_actions_t actions; int setup = posix_spawn_file_actions_init(&actions); BOOL initialized = setup == 0;
                if (!setup) setup = posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
                if (!setup) setup = posix_spawn_file_actions_adddup2(&actions, descriptors[1], 1);
                if (!setup) setup = posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
                if (!setup) setup = posix_spawn_file_actions_addclose(&actions, descriptors[0]);
                if (!setup) setup = posix_spawn_file_actions_addclose(&actions, descriptors[1]);
                char **argv = calloc([arguments count] + 2, sizeof(char *));
                if (argv) { argv[0] = (char *)helper; for (NSUInteger i = 0; i < [arguments count]; i++) argv[i + 1] = (char *)[[arguments objectAtIndex:i] UTF8String]; }
                char *environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/var/mobile", "LANG=C", NULL}; pid_t child = 0;
                int error = setup ? setup : argv ? posix_spawn(&child, helper, &actions, NULL, argv, environment) : ENOMEM;
                free(argv); if (initialized) posix_spawn_file_actions_destroy(&actions); close(descriptors[1]); descriptors[1] = -1;
                if (!error) {
                    NSMutableData *data = [NSMutableData data]; char bytes[16384]; ssize_t count; BOOL overflow = NO;
                    while ((count = read(descriptors[0], bytes, sizeof(bytes))) != 0) {
                        if (count < 0 && errno == EINTR) continue; if (count < 0) { overflow = YES; break; }
                        if ([data length] + (NSUInteger)count <= 8 * 1024 * 1024) [data appendBytes:bytes length:(NSUInteger)count]; else overflow = YES;
                    }
                    int status = 0; pid_t waited; do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
                    NSString *parseError = nil; id plist = overflow ? nil : [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&parseError]; [parseError release];
                    if (waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0 && [plist isKindOfClass:[NSDictionary class]]) [result addEntriesFromDictionary:plist];
                    else [result setObject:@"Package operation did not return a valid result. Keep Receptor open; inspect the package database in Cydia before retrying an interrupted installation." forKey:@"error"];
                } else [result setObject:@"Could not launch the package helper." forKey:@"error"];
            }
            if (descriptors[0] >= 0) close(descriptors[0]); if (descriptors[1] >= 0) close(descriptors[1]);
        }
    }
    [result setObject:[arguments objectAtIndex:0] forKey:@"operation"];
    [self performSelectorOnMainThread:@selector(finished:) withObject:result waitUntilDone:NO]; [pool drain];
}
- (void)finished:(NSDictionary *)result {
    _busy = NO;
    if (_task != UIBackgroundTaskInvalid) { UIBackgroundTaskIdentifier task = _task; _task = UIBackgroundTaskInvalid; [[UIApplication sharedApplication] endBackgroundTask:task]; }
    if ([result objectForKey:@"output"] || [result objectForKey:@"error"]) {
        [_lastOutput release]; _lastOutput = [[result objectForKey:@"error"] ?: [result objectForKey:@"output"] copy];
        NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:@".last-packages.log"]; [_lastOutput writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; chmod([path fileSystemRepresentation], 0600);
    }
    [_delegate packageOperationFinished:result];
}
- (void)dealloc { [_lastOutput release]; [super dealloc]; }
@end
