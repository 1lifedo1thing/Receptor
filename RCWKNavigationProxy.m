#import "RCWKNavigationProxy.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCSystemContent.h"
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>

// Public iOS 8 interfaces, declared narrowly so the binary still builds with SDK 5.
@interface NSObject (RCWKNavigationAPI)
- (NSURLRequest *)request;
- (id)targetFrame;
- (BOOL)isMainFrame;
- (BOOL)isForMainFrame;
- (NSInteger)navigationType;
- (NSURLResponse *)response;
- (BOOL)canShowMIMEType;
- (void)webView:(id)view decidePolicyForNavigationAction:(id)action decisionHandler:(void (^)(NSInteger))handler;
- (void)webView:(id)view decidePolicyForNavigationResponse:(id)response decisionHandler:(void (^)(NSInteger))handler;
- (void)webView:(id)view didReceiveAuthenticationChallenge:(id)challenge completionHandler:(void (^)(NSInteger, id))handler;
- (void)_webView:(id)view didReceiveAuthenticationChallenge:(id)challenge;
- (id)sender;
- (void)performDefaultHandlingForAuthenticationChallenge:(id)challenge;
- (void)cancelAuthenticationChallenge:(id)challenge;
@end
static id (*RCInitWeak)(id *, id);
static id (*RCLoadWeakRetained)(id *);
static void (*RCDestroyWeak)(id *);

static BOOL RCWKCallbackSignature(NSMethodSignature *signature) {
    return signature && [signature numberOfArguments] == 5 && !strcmp([signature methodReturnType], "v") &&
        !strcmp([signature getArgumentTypeAtIndex:2], "@") && !strcmp([signature getArgumentTypeAtIndex:3], "@") &&
        !strncmp([signature getArgumentTypeAtIndex:4], "@?", 2);
}
BOOL RCWKDelegateIsCompatible(id delegate) {
    SEL selectors[] = {@selector(webView:decidePolicyForNavigationAction:decisionHandler:),
        @selector(webView:decidePolicyForNavigationResponse:decisionHandler:),
        @selector(webView:didReceiveAuthenticationChallenge:completionHandler:)};
    for (size_t i = 0; i < sizeof(selectors) / sizeof(*selectors); ++i)
        if ([delegate respondsToSelector:selectors[i]] && !RCWKCallbackSignature([delegate methodSignatureForSelector:selectors[i]])) return NO;
    SEL privateAuth = @selector(_webView:didReceiveAuthenticationChallenge:);
    if ([delegate respondsToSelector:privateAuth]) {
        NSMethodSignature *signature = [delegate methodSignatureForSelector:privateAuth];
        if (!signature || [signature numberOfArguments] != 4 || strcmp([signature methodReturnType], "v") ||
            strcmp([signature getArgumentTypeAtIndex:2], "@") || strcmp([signature getArgumentTypeAtIndex:3], "@")) return NO;
    }
    return YES;
}
static BOOL RCSameWKOrigin(NSURL *a, NSURL *b) {
    NSNumber *ap = [a port] ?: [NSNumber numberWithInt:[[[a scheme] lowercaseString] isEqualToString:@"https"] ? 443 : 80];
    NSNumber *bp = [b port] ?: [NSNumber numberWithInt:[[[b scheme] lowercaseString] isEqualToString:@"https"] ? 443 : 80];
    return [[[a scheme] lowercaseString] isEqualToString:[[b scheme] lowercaseString]] &&
        [[[a host] lowercaseString] isEqualToString:[[b host] lowercaseString]] && [ap isEqual:bp];
}
static BOOL RCWKSystemResponse(NSURLResponse *response) {
    return RCIsSystemInstallerContentOnIOS([[response suggestedFilename] pathExtension].UTF8String, [response MIMEType].UTF8String, 8) ||
        RCIsSystemInstallerContentOnIOS([[[response URL] path] pathExtension].UTF8String, NULL, 8);
}

@interface RCWKNavigationProxy ()
- (id)originalDelegate;
- (void)rememberSignature:(SEL)selector fromDelegate:(id)delegate;
@end
@implementation RCWKNavigationProxy
+ (void)initialize {
    if (self != [RCWKNavigationProxy class]) return;
    // Zeroing weak references exist on iOS 8. Resolve dynamically to avoid iOS 4 link dependencies.
    RCInitWeak = (id (*)(id *, id))dlsym(RTLD_DEFAULT, "objc_initWeak");
    RCLoadWeakRetained = (id (*)(id *))dlsym(RTLD_DEFAULT, "objc_loadWeakRetained");
    RCDestroyWeak = (void (*)(id *))dlsym(RTLD_DEFAULT, "objc_destroyWeak");
}
- (id)initWithDelegate:(id)delegate {
    if ((self = [super init])) {
        if (!RCInitWeak || !RCLoadWeakRetained || !RCDestroyWeak || !RCWKDelegateIsCompatible(delegate)) { [self release]; return nil; }
        _signatures = [[NSMutableDictionary alloc] init]; RCInitWeak(&_originalWeak, delegate); _weakInitialized = YES;
    }
    return self;
}
- (id)originalDelegate { return [RCLoadWeakRetained(&_originalWeak) autorelease]; }
- (void)rememberSignature:(SEL)selector fromDelegate:(id)delegate {
    NSMethodSignature *signature = [delegate methodSignatureForSelector:selector];
    if (signature) @synchronized(self) { [_signatures setObject:signature forKey:NSStringFromSelector(selector)]; }
}
- (BOOL)respondsToSelector:(SEL)selector {
    // Do not replace Safari's private challenge UI with a public/default handler.
    if (selector == @selector(webView:didReceiveAuthenticationChallenge:completionHandler:) ||
        selector == @selector(_webView:didReceiveAuthenticationChallenge:)) return [[self originalDelegate] respondsToSelector:selector];
    if ([super respondsToSelector:selector]) return YES;
    id delegate = [self originalDelegate];
    BOOL responds = [delegate respondsToSelector:selector];
    if (responds) [self rememberSignature:selector fromDelegate:delegate];
    return responds;
}
- (BOOL)conformsToProtocol:(Protocol *)protocol { return [super conformsToProtocol:protocol] || [[self originalDelegate] conformsToProtocol:protocol]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    if (signature) return signature;
    signature = [[self originalDelegate] methodSignatureForSelector:selector];
    if (signature) return signature;
    @synchronized(self) { return [_signatures objectForKey:NSStringFromSelector(selector)]; }
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    id delegate = [self originalDelegate];
    if ([delegate respondsToSelector:invocation.selector]) [invocation invokeWithTarget:delegate];
    else {
        // WebKit caches optional-selector availability; emulate messaging nil if its weak owner vanished.
        NSUInteger length = [[invocation methodSignature] methodReturnLength];
        if (length) { void *zero = calloc(1, length); if (zero) { [invocation setReturnValue:zero]; free(zero); } }
    }
}
- (void)webView:(id)view decidePolicyForNavigationAction:(id)action decisionHandler:(void (^)(NSInteger))handler {
    id frame = [action respondsToSelector:@selector(targetFrame)] ? [action targetFrame] : nil;
    NSURLRequest *request = [action respondsToSelector:@selector(request)] ? [action request] : nil;
    BOOL main = frame && [frame respondsToSelector:@selector(isMainFrame)] && [frame isMainFrame];
    if (main) { [_mainRequest release]; _mainRequest = [request copy]; }
    BOOL native = RCIsSystemInstallerContentOnIOS([[[request URL] path] pathExtension].UTF8String, NULL, 8);
    BOOL clicked = [action respondsToSelector:@selector(navigationType)] && [action navigationType] == 0;
    if (handler && !native && (main || !frame) && clicked && RCIsDownloadRequest(request) &&
        RCIsKnownDownloadExtension([[[request URL] path] pathExtension].UTF8String)) {
        handler(0); // WKNavigationActionPolicyCancel; resolve before presenting consent UI.
        if (main) { [_mainRequest release]; _mainRequest = nil; }
        [ReceptorUI performSelectorOnMainThread:@selector(promptForRequest:) withObject:request waitUntilDone:NO];
        return;
    }
    id delegate = [self originalDelegate];
    if ([delegate respondsToSelector:_cmd]) [delegate webView:view decidePolicyForNavigationAction:action decisionHandler:handler];
    else if (handler) handler(1); // WKNavigationActionPolicyAllow
}
- (void)webView:(id)view decidePolicyForNavigationResponse:(id)navigationResponse decisionHandler:(void (^)(NSInteger))handler {
    NSURLResponse *response = [navigationResponse respondsToSelector:@selector(response)] ? [navigationResponse response] : nil;
    BOOL main = [navigationResponse respondsToSelector:@selector(isForMainFrame)] && [navigationResponse isForMainFrame];
    BOOL canShow = [navigationResponse respondsToSelector:@selector(canShowMIMEType)] && [navigationResponse canShowMIMEType];
    BOOL downloadable = !canShow;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
        for (NSString *key in headers) if ([key caseInsensitiveCompare:@"Content-Disposition"] == NSOrderedSame) {
            NSString *value = [[[headers objectForKey:key] componentsSeparatedByString:@";"] objectAtIndex:0];
            if ([[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] caseInsensitiveCompare:@"attachment"] == NSOrderedSame) downloadable = YES;
        }
    }
    // Never turn POST/one-time body responses into GETs. WK's private cookie store is not copied.
    BOOL downgrade = [[[[_mainRequest URL] scheme] lowercaseString] isEqualToString:@"https"] && ![[[[response URL] scheme] lowercaseString] isEqualToString:@"https"];
    if (handler && main && response && !downgrade && !RCWKSystemResponse(response) && downloadable && RCIsDownloadRequest(_mainRequest)) {
        NSMutableURLRequest *request = [[_mainRequest mutableCopy] autorelease];
        if (!RCSameWKOrigin([request URL], [response URL])) {
            NSMutableDictionary *safe = [NSMutableDictionary dictionary];
            NSSet *allowed = [NSSet setWithObjects:@"user-agent", @"accept", @"accept-language", @"accept-encoding", nil];
            NSDictionary *headers = [request allHTTPHeaderFields];
            for (NSString *key in headers) if ([allowed containsObject:[key lowercaseString]]) [safe setObject:[headers objectForKey:key] forKey:key];
            [request setAllHTTPHeaderFields:safe];
        }
        request.URL = [response URL];
        if (RCIsDownloadRequest(request)) {
            handler(0); // WKNavigationResponsePolicyCancel
            [_mainRequest release]; _mainRequest = nil;
            [ReceptorUI performSelectorOnMainThread:@selector(promptForRequest:) withObject:request waitUntilDone:NO]; return;
        }
    }
    id delegate = [self originalDelegate];
    if ([delegate respondsToSelector:_cmd]) [delegate webView:view decidePolicyForNavigationResponse:navigationResponse decisionHandler:handler];
    else if (handler) handler(canShow ? 1 : 0);
}
- (void)webView:(id)view didReceiveAuthenticationChallenge:(id)challenge completionHandler:(void (^)(NSInteger, id))handler {
    id delegate = [self originalDelegate];
    if ([delegate respondsToSelector:_cmd]) [delegate webView:view didReceiveAuthenticationChallenge:challenge completionHandler:handler];
    else if (handler) handler(1, nil); // NSURLSessionAuthChallengePerformDefaultHandling; never trust a certificate here.
}
- (void)_webView:(id)view didReceiveAuthenticationChallenge:(id)challenge {
    id delegate = [self originalDelegate];
    if ([delegate respondsToSelector:_cmd]) [delegate _webView:view didReceiveAuthenticationChallenge:challenge];
    else {
        id sender = [challenge respondsToSelector:@selector(sender)] ? [challenge sender] : nil;
        if ([sender respondsToSelector:@selector(performDefaultHandlingForAuthenticationChallenge:)]) [sender performDefaultHandlingForAuthenticationChallenge:challenge];
        else if ([sender respondsToSelector:@selector(cancelAuthenticationChallenge:)]) [sender cancelAuthenticationChallenge:challenge];
    }
}
- (void)dealloc {
    if (_weakInitialized) RCDestroyWeak(&_originalWeak);
    [_mainRequest release]; [_signatures release]; [super dealloc];
}
@end
