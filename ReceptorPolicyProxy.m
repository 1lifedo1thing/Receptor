#import "ReceptorPolicyProxy.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCSystemContent.h"
#include <string.h>

@protocol RCPolicyDecisionListener <NSObject>
- (void)ignore;
- (void)use;
@end

// Narrow declarations only; no link dependency on private WebKit frameworks.
@interface NSObject (RCWebKitPolicy)
- (id)mainFrame;
- (id)provisionalDataSource;
- (NSURLResponse *)response;
+ (BOOL)canShowMIMEType:(NSString *)MIMEType;
- (void)webView:(id)view decidePolicyForNavigationAction:(NSDictionary *)action
        request:(NSURLRequest *)request frame:(id)frame decisionListener:(id)listener;
- (void)webView:(id)view decidePolicyForMIMEType:(NSString *)MIMEType
        request:(NSURLRequest *)request frame:(id)frame decisionListener:(id)listener;
- (void)webView:(id)view decidePolicyForNewWindowAction:(NSDictionary *)action
        request:(NSURLRequest *)request newFrameName:(NSString *)name decisionListener:(id)listener;
@end

BOOL RCMethodHasObjectArguments(id target, SEL selector, NSUInteger count) {
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || [signature numberOfArguments] != count || strcmp([signature methodReturnType], "v")) return NO;
    for (NSUInteger i = 2; i < count; ++i) {
        if (strcmp([signature getArgumentTypeAtIndex:i], "@")) return NO;
    }
    return YES;
}

static BOOL RCIsMainFrame(id view, id frame) {
    return frame && [view respondsToSelector:@selector(mainFrame)] && [view mainFrame] == frame;
}
static BOOL RCNativeInstaller(const char *extension, const char *mime) {
    return RCIsSystemInstallerContentOnIOS(extension, mime, (int)[[[UIDevice currentDevice] systemVersion] integerValue]);
}

static BOOL RCKnownFileExtension(NSURLRequest *request) {
    return RCIsKnownDownloadExtension([[[request URL] path] pathExtension].UTF8String);
}

static BOOL RCIsClickedFile(NSDictionary *action, NSURLRequest *request) {
    if (![action isKindOfClass:[NSDictionary class]]) return NO;
    id type = [action objectForKey:@"WebActionNavigationTypeKey"];
    return [type respondsToSelector:@selector(integerValue)] && [type integerValue] == 0
        && RCKnownFileExtension(request);
}

static BOOL RCConsume(NSURLRequest *request, id listener) {
    if (RCNativeInstaller([[[request URL] path] pathExtension].UTF8String, NULL)) return NO;
    if (!RCIsDownloadRequest(request) || ![listener respondsToSelector:@selector(ignore)]) return NO;
    // Resolve policy synchronously on WebKit's calling thread. Never carry a listener
    // across threads or leave a navigation suspended while a UIKit alert is visible.
    [(id<RCPolicyDecisionListener>)listener ignore];
    NSURLRequest *snapshot = [request copy];
    [[ReceptorUI class] performSelectorOnMainThread:@selector(promptForRequest:)
        withObject:snapshot waitUntilDone:NO];
    [snapshot release];
    return YES;
}

@implementation ReceptorPolicyProxy
@synthesize originalDelegate = _originalDelegate;
- (id)initWithDelegate:(id)delegate {
    if ((self = [super init])) _originalDelegate = delegate;
    return self;
}
- (BOOL)respondsToSelector:(SEL)selector {
    // Do not add optional callbacks Safari did not originally implement.
    if (selector == @selector(webView:decidePolicyForMIMEType:request:frame:decisionListener:) ||
        selector == @selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:) ||
        selector == @selector(webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener:)) {
        return [_originalDelegate respondsToSelector:selector];
    }
    return [super respondsToSelector:selector] || [_originalDelegate respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector { return _originalDelegate; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [super methodSignatureForSelector:selector] ?: [_originalDelegate methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:_originalDelegate]; }
- (void)webView:(id)view decidePolicyForNavigationAction:(NSDictionary *)action
        request:(NSURLRequest *)request frame:(id)frame decisionListener:(id)listener {
    if (RCMethodHasObjectArguments(_originalDelegate, _cmd, 7) && RCIsMainFrame(view, frame)
        && RCIsClickedFile(action, request) && RCConsume(request, listener)) return;
    [_originalDelegate webView:view decidePolicyForNavigationAction:action request:request frame:frame decisionListener:listener];
}
- (void)webView:(id)view decidePolicyForNewWindowAction:(NSDictionary *)action
        request:(NSURLRequest *)request newFrameName:(NSString *)name decisionListener:(id)listener {
    if (RCMethodHasObjectArguments(_originalDelegate, _cmd, 7) && RCIsClickedFile(action, request)
        && RCConsume(request, listener)) return;
    [_originalDelegate webView:view decidePolicyForNewWindowAction:action request:request newFrameName:name decisionListener:listener];
}
- (void)webView:(id)view decidePolicyForMIMEType:(NSString *)MIMEType
        request:(NSURLRequest *)request frame:(id)frame decisionListener:(id)listener {
    // Native system installers must see these responses even if WebView cannot render them.
    if (RCNativeInstaller([[[request URL] path] pathExtension].UTF8String, [MIMEType UTF8String])) {
        [_originalDelegate webView:view decidePolicyForMIMEType:MIMEType request:request frame:frame decisionListener:listener];
        return;
    }
    BOOL downloadable = NO;
    BOOL systemInstaller = NO;
    if (RCMethodHasObjectArguments(_originalDelegate, _cmd, 7) && RCIsMainFrame(view, frame)) {
        if ([[view class] respondsToSelector:@selector(canShowMIMEType:)]) {
            downloadable = ![[view class] canShowMIMEType:MIMEType];
        }
        if ([frame respondsToSelector:@selector(provisionalDataSource)]) {
            id source = [frame provisionalDataSource];
            NSURLResponse *response = [source respondsToSelector:@selector(response)] ? [source response] : nil;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                systemInstaller = RCNativeInstaller([[response suggestedFilename] pathExtension].UTF8String, [[response MIMEType] UTF8String]);
                NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
                for (NSString *key in headers) {
                    if ([key caseInsensitiveCompare:@"Content-Disposition"] == NSOrderedSame) {
                        NSString *value = [[headers objectForKey:key] description];
                        NSString *disposition = [[[value componentsSeparatedByString:@";"] objectAtIndex:0]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        if ([disposition caseInsensitiveCompare:@"attachment"] == NSOrderedSame) downloadable = YES;
                    }
                }
            }
        }
    }
    if (!systemInstaller && downloadable && RCConsume(request, listener)) return;
    [_originalDelegate webView:view decidePolicyForMIMEType:MIMEType request:request frame:frame decisionListener:listener];
}
@end
