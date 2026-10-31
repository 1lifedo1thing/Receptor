#import "RCIPAInstaller.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCDEBInstaller.h"
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

NSString * const RCInstallationChangedNotification = @"ReceptorInstallationChanged";
typedef void (*RCMobileInstallationCallback)(CFDictionaryRef information);
typedef int (*RCMobileInstallationInstall)(CFStringRef path, CFDictionaryRef options,
    RCMobileInstallationCallback callback, CFStringRef backpath);

@interface RCIPAInstaller ()
- (void)setInstallStatus:(NSString *)status;
@end
static void RCInstallProgress(CFDictionaryRef information) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *info = (NSDictionary *)information;
    NSNumber *percent = [info objectForKey:@"PercentComplete"];
    NSString *status = percent ? [NSString stringWithFormat:@"Installing… %@%%", percent] : @"Installing…";
    [[RCIPAInstaller sharedInstaller] performSelectorOnMainThread:@selector(setInstallStatus:) withObject:status waitUntilDone:NO];
    [pool drain];
}

@implementation RCIPAInstaller
@synthesize busy = _busy, status = _status;
+ (RCIPAInstaller *)sharedInstaller {
    static RCIPAInstaller *installer = nil;
    @synchronized(self) { if (!installer) installer = [[self alloc] init]; }
    return installer;
}
- (void)setInstallStatus:(NSString *)status {
    [_status release]; _status = [status copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCInstallationChangedNotification object:self];
}
- (void)installFileNamed:(NSString *)name {
    NSAssert([NSThread isMainThread], @"Main thread required");
    if (_busy || [[RCDEBInstaller sharedInstaller] busy]) { [[ReceptorUI sharedUI] showMessage:@"An installation is already running."]; return; }
    if (!RCIsRegularDownload(name) || ![[[name pathExtension] lowercaseString] isEqual:@"ipa"]) {
        [[ReceptorUI sharedUI] showMessage:@"Choose a saved IPA file."]; return;
    }
    _busy = YES;
    [self setInstallStatus:@"Installing…"];
    [NSThread detachNewThreadSelector:@selector(installOnWorker:) toTarget:self withObject:[[name copy] autorelease]];
}
- (void)installOnWorker:(NSString *)name {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *message = nil;
    NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:name];
    NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Receptor-install-%@", RCSafeFilename([[NSProcessInfo processInfo] globallyUniqueString])]];
    NSString *stagedIPA = [staging stringByAppendingPathComponent:@"payload.ipa"];
    BOOL ownsStaging = NO;
    void *image = NULL;
    if (!RCIsRegularDownload(name)) message = @"The IPA file no longer exists.";
    if (!message) {
        NSError *error = nil;
        ownsStaging = [[NSFileManager defaultManager] createDirectoryAtPath:staging withIntermediateDirectories:NO
            attributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0755] forKey:NSFilePosixPermissions] error:&error];
        if (!ownsStaging || ![[NSFileManager defaultManager] copyItemAtPath:path toPath:stagedIPA error:&error] ||
            chmod([stagedIPA fileSystemRepresentation], 0644) != 0) {
            message = [NSString stringWithFormat:@"Unable to stage the IPA. Check free space. %@", [error localizedDescription] ?: @""];
        }
    }
    if (!message) image = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_LAZY);
    if (!message && !image) message = @"The iOS application installer could not be loaded.";
    if (!message) {
        RCMobileInstallationInstall install = (RCMobileInstallationInstall)dlsym(image, "MobileInstallationInstall");
        if (!install) message = @"This firmware does not expose the legacy application installer.";
        else {
            NSDictionary *options = [NSDictionary dictionaryWithObject:@"User" forKey:@"ApplicationType"];
            @try {
                int result = install((CFStringRef)stagedIPA, (CFDictionaryRef)options, RCInstallProgress, (CFStringRef)stagedIPA);
                message = result == 0 ? [NSString stringWithFormat:@"Installed %@. Check your Home screen.", name] :
                    [NSString stringWithFormat:@"Installation failed (%d). Check that the IPA supports this device and iOS version. Unsigned IPAs require a compatible AppSync installation; FairPlay-protected apps require their original authorization.", result];
            } @catch (NSException *exception) {
                message = [NSString stringWithFormat:@"The iOS installer failed: %@", [exception reason]];
            }
        }
    }
    if (image) dlclose(image);
    if (ownsStaging) { unlink([stagedIPA fileSystemRepresentation]); rmdir([staging fileSystemRepresentation]); }
    [self performSelectorOnMainThread:@selector(finished:) withObject:message waitUntilDone:YES];
    [pool drain];
}
- (void)finished:(NSString *)message {
    _busy = NO;
    [self setInstallStatus:nil];
    [[ReceptorUI sharedUI] showMessage:message];
}
- (void)dealloc { [_status release]; [super dealloc]; }
@end
