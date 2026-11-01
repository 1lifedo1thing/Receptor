#import "RCAppDelegate.h"
#import "../FileBrowserViewController.h"
#import "../RCFilesystemViewController.h"
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
    navigation.tabBarItem = [[[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemDownloads tag:0] autorelease];
    navigation.tabBarItem.title = @"Files";
    RCFilesystemViewController *filesystem = [[RCFilesystemViewController alloc] initWithPath:@"/"];
    UINavigationController *systemNavigation = [[UINavigationController alloc] initWithRootViewController:filesystem];
    [filesystem release];
    systemNavigation.tabBarItem = [[[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemBookmarks tag:1] autorelease];
    systemNavigation.tabBarItem.title = @"Filesystem";
    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = [NSArray arrayWithObjects:navigation, systemNavigation, nil];
    _window.rootViewController = tabs;
    [tabs release]; [systemNavigation release];
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
    if ([[[url scheme] lowercaseString] isEqual:@"receptor"] && [[[url host] lowercaseString] isEqual:@"files"]) {
        ((UITabBarController *)_window.rootViewController).selectedIndex = 0; return YES;
    }
    NSURLRequest *request = RCRequestFromDownloadHandoff(url);
    if (!request) return NO;
    ((UITabBarController *)_window.rootViewController).selectedIndex = 0;
    // Every incoming download URL requires in-app consent, regardless of the caller.
    [ReceptorUI promptForRequest:request]; return YES;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation {
    (void)source; (void)annotation;
    return [self application:application handleOpenURL:url];
}
- (void)dealloc { [_window release]; [super dealloc]; }
@end
