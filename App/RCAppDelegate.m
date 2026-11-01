#import "RCAppDelegate.h"
#import "../FileBrowserViewController.h"
#import "../ReceptorUI.h"
#import "../ReceptorPaths.h"

@interface NSObject (RCNotificationSettingsAPI)
+ (id)settingsForTypes:(NSUInteger)types categories:(NSSet *)categories;
- (void)registerUserNotificationSettings:(id)settings;
@end

@implementation RCAppDelegate
@synthesize window = _window;
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    FileBrowserViewController *browser = [[FileBrowserViewController alloc] initWithStyle:UITableViewStylePlain];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:browser];
    [browser release];
    _window.rootViewController = navigation;
    [navigation release];
    [_window makeKeyAndVisible];
    [ReceptorUI install];
    if ([[[UIDevice currentDevice] systemVersion] integerValue] == 8) {
        Class settingsClass = NSClassFromString(@"UIUserNotificationSettings");
        if ([settingsClass respondsToSelector:@selector(settingsForTypes:categories:)] && [application respondsToSelector:@selector(registerUserNotificationSettings:)])
            [application registerUserNotificationSettings:[settingsClass settingsForTypes:6 categories:nil]]; // Alert | Sound
    }
    return YES;
}
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    (void)application;
    if ([[[url scheme] lowercaseString] isEqual:@"receptor"] && [[[url host] lowercaseString] isEqual:@"files"]) return YES;
    NSURLRequest *request = RCRequestFromDownloadHandoff(url);
    if (!request) return NO;
    // Every incoming download URL requires in-app consent, regardless of the caller.
    [ReceptorUI promptForRequest:request]; return YES;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation {
    (void)source; (void)annotation;
    return [self application:application handleOpenURL:url];
}
- (void)dealloc { [_window release]; [super dealloc]; }
@end
