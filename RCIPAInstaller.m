#import "RCIPAInstaller.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCDEBInstaller.h"
#import "RCIPAArchive.h"
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

NSString * const RCInstallationChangedNotification = @"ReceptorInstallationChanged";
typedef void (*RCMobileInstallationCallback)(CFDictionaryRef information);
typedef int (*RCMobileInstallationInstall)(CFStringRef path, CFDictionaryRef options,
    RCMobileInstallationCallback callback, CFStringRef backpath);

@interface NSObject (RCWorkspaceInstallerAPI)
+ (id)defaultWorkspace;
- (BOOL)installApplication:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
@end
static NSString *RCIPAIdentifier(NSString *path) {
    unsigned char *bytes = NULL; size_t length = 0;
    if (!RCIPAReadInfoPlist([path fileSystemRepresentation], &bytes, &length)) return nil;
    NSData *data = [NSData dataWithBytes:bytes length:length]; free(bytes);
    NSString *error = nil;
    id plist = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&error];
    [error release];
    id identifier = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"CFBundleIdentifier"] : nil;
    if (![identifier isKindOfClass:[NSString class]] || ![identifier length] || [identifier length] > 255 ||
        [identifier rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) return nil;
    return identifier;
}
static BOOL RCWorkspaceHasInstallABI(id workspace) {
    NSMethodSignature *signature = [workspace methodSignatureForSelector:@selector(installApplication:withOptions:error:)];
    if (!signature || [signature numberOfArguments] != 5 ||
        (strcmp([signature methodReturnType], "c") && strcmp([signature methodReturnType], "B")) ||
        strcmp([signature getArgumentTypeAtIndex:2], "@") || strcmp([signature getArgumentTypeAtIndex:3], "@")) return NO;
    const char *error = [signature getArgumentTypeAtIndex:4];
    while (*error && strchr("rnNoORV", *error)) error++;
    return !strcmp(error, "^@");
}

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
- (id)init { if ((self = [super init])) _backgroundTask = UIBackgroundTaskInvalid; return self; }
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
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        UIBackgroundTaskIdentifier task = _backgroundTask; _backgroundTask = UIBackgroundTaskInvalid;
        if (task != UIBackgroundTaskInvalid) [[UIApplication sharedApplication] endBackgroundTask:task];
    }];
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
    NSInteger major = [[[UIDevice currentDevice] systemVersion] integerValue];
    if (!message && major == 8) {
        NSString *identifier = RCIPAIdentifier(stagedIPA);
        if (!identifier) message = @"Cannot read a unique app Info.plist/bundle identifier from this IPA. Encrypted/ZIP64 archives, ambiguous app roots and plists larger than 2 MB are not supported by this reader.";
        else {
            image = dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
            Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
            NSMethodSignature *factory = [workspaceClass methodSignatureForSelector:@selector(defaultWorkspace)];
            id workspace = factory && [factory numberOfArguments] == 2 && !strcmp([factory methodReturnType], "@") ? [workspaceClass defaultWorkspace] : nil;
            if (!RCWorkspaceHasInstallABI(workspace)) message = @"This firmware/jailbreak does not expose the expected iOS 8 application installer interface.";
            else {
                NSError *error = nil;
                @try {
                    BOOL installed = [workspace installApplication:[NSURL fileURLWithPath:stagedIPA] withOptions:[NSDictionary dictionaryWithObject:identifier forKey:@"CFBundleIdentifier"] error:&error];
                    message = installed ? [NSString stringWithFormat:@"Installed %@. Check your Home screen.", name] :
                        [NSString stringWithFormat:@"Installation failed: %@ (%@ %ld). Check device/iOS compatibility and your signing/AppSync setup.", [error localizedDescription] ?: @"No error details returned", [error domain] ?: @"installer", (long)[error code]];
                } @catch (NSException *exception) { message = [NSString stringWithFormat:@"The iOS 8 installer failed: %@", [exception reason]]; }
            }
        }
    } else if (!message && major > 8) message = @"This build targets iOS 4 through 8 on 32-bit devices.";
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
    if (_backgroundTask != UIBackgroundTaskInvalid) { [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask]; _backgroundTask = UIBackgroundTaskInvalid; }
    [self setInstallStatus:nil];
    [[ReceptorUI sharedUI] showMessage:message];
}
- (void)dealloc { [_status release]; [super dealloc]; }
@end
