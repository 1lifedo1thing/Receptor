#import <UIKit/UIKit.h>
#import "RCAppDelegate.h"

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int result = UIApplicationMain(argc, argv, nil, NSStringFromClass([RCAppDelegate class]));
    [pool drain];
    return result;
}
