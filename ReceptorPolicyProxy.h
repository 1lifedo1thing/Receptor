#import <Foundation/Foundation.h>

@interface ReceptorPolicyProxy : NSObject {
    id _originalDelegate; // assign, matching WebView's policy-delegate contract
}
@property(nonatomic, assign) id originalDelegate;
- (id)initWithDelegate:(id)delegate;
@end

// Validate private ABI before installing the hook or taking over a callback.
BOOL RCMethodHasObjectArguments(id target, SEL selector, NSUInteger count);
