#import "RCAppDelegate.h"
#import "../FileBrowserViewController.h"
#import "../ReceptorUI.h"

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
    return YES;
}
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    (void)application;
    return [[[url scheme] lowercaseString] isEqual:@"receptor"] && [[[url host] lowercaseString] isEqual:@"files"];
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation {
    (void)source; (void)annotation;
    return [self application:application handleOpenURL:url];
}
- (void)dealloc { [_window release]; [super dealloc]; }
@end
