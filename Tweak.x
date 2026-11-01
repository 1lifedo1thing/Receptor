#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <string.h>
#import "ReceptorPolicyProxy.h"
#import "ReceptorUI.h"
#import "RCWKNavigationProxy.h"

@interface WebView : NSObject
- (void)setPolicyDelegate:(id)delegate;
@end
@interface WKWebView : NSObject
- (void)setNavigationDelegate:(id)delegate;
@end

static char RCPolicyProxyKey;
static char RCWKProxyKey;

static BOOL RCDelegateHasCompatiblePolicyMethods(id delegate) {
    SEL selectors[] = {
        @selector(webView:decidePolicyForMIMEType:request:frame:decisionListener:),
        @selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:),
        @selector(webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener:)
    };
    for (NSUInteger i = 0; i < sizeof(selectors) / sizeof(selectors[0]); ++i) {
        if ([delegate respondsToSelector:selectors[i]] && !RCMethodHasObjectArguments(delegate, selectors[i], 7)) return NO;
    }
    return YES;
}

%group ReceptorLegacyWebKit
%hook WebView
- (void)setPolicyDelegate:(id)delegate {
    if ([delegate isKindOfClass:[ReceptorPolicyProxy class]]) {
        %orig(delegate);
        return;
    }
    if (!RCDelegateHasCompatiblePolicyMethods(delegate)) {
        id old = [objc_getAssociatedObject(self, &RCPolicyProxyKey) retain];
        %orig(delegate);
        objc_setAssociatedObject(self, &RCPolicyProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [old release];
        NSLog(@"[Receptor] Unrecognized policy delegate ABI; preserving Safari's delegate.");
        return;
    }
    ReceptorPolicyProxy *proxy = delegate ? [[ReceptorPolicyProxy alloc] initWithDelegate:delegate] : nil;
    // Keep the old proxy alive until WebKit has stopped referring to it.
    id old = [objc_getAssociatedObject(self, &RCPolicyProxyKey) retain];
    objc_setAssociatedObject(self, &RCPolicyProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(proxy);
    [old release];
    [proxy release];
}
%end
%end

%group ReceptorWKWebKit
%hook WKWebView
- (void)setNavigationDelegate:(id)delegate {
    if ([delegate isKindOfClass:[RCWKNavigationProxy class]]) { %orig(delegate); return; }
    id old = [objc_getAssociatedObject(self, &RCWKProxyKey) retain];
    RCWKNavigationProxy *proxy = delegate ? [[RCWKNavigationProxy alloc] initWithDelegate:delegate] : nil;
    if (delegate && !proxy) NSLog(@"[Receptor] WK delegate ABI/weak runtime unavailable; preserving Safari's delegate.");
    objc_setAssociatedObject(self, &RCWKProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(proxy ?: delegate);
    [proxy release]; [old release];
}
%end
%end

%ctor {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.mobilesafari"]) {
        NSInteger major = [[[UIDevice currentDevice] systemVersion] integerValue];
        if (major >= 8 && major < 9) {
            Class wkView = NSClassFromString(@"WKWebView");
            if (!wkView) {
                dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY);
                wkView = NSClassFromString(@"WKWebView");
            }
            NSMethodSignature *setter = [wkView instanceMethodSignatureForSelector:@selector(setNavigationDelegate:)];
            if (setter && [setter numberOfArguments] == 3 && !strcmp([setter methodReturnType], "v") && !strcmp([setter getArgumentTypeAtIndex:2], "@")) {
                %init(ReceptorWKWebKit);
                NSLog(@"[Receptor] iOS 8 WKWebView interception enabled (experimental, 32-bit).");
            } else NSLog(@"[Receptor] WKWebView delegate setter unavailable; Safari interception disabled.");
        } else if (major < 8) {
            Class webView = NSClassFromString(@"WebView");
            if (!webView) {
                // UIKit can load legacy WebKit lazily. Resolve it before Safari creates tabs.
                // Keep the handle open for the process lifetime: installed IMPs belong to it.
                dlopen("/System/Library/PrivateFrameworks/WebKit.framework/WebKit", RTLD_LAZY);
                webView = NSClassFromString(@"WebView");
            }
            NSMethodSignature *signature = [webView instanceMethodSignatureForSelector:@selector(setPolicyDelegate:)];
            if (signature && [signature numberOfArguments] == 3 &&
                strcmp([signature methodReturnType], "v") == 0 &&
                strcmp([signature getArgumentTypeAtIndex:2], "@") == 0) {
                %init(ReceptorLegacyWebKit);
            } else {
                NSLog(@"[Receptor] Legacy WebView policy setter unavailable; interception disabled.");
            }
        }
        [ReceptorUI performSelectorOnMainThread:@selector(install) withObject:nil waitUntilDone:NO];
    }
    [pool drain];
}
