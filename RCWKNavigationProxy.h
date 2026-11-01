#import <Foundation/Foundation.h>
@interface RCWKNavigationProxy : NSObject {
    id _originalWeak;
    BOOL _weakInitialized;
    NSMutableDictionary *_signatures;
    NSURLRequest *_mainRequest;
}
- (id)initWithDelegate:(id)delegate;
@end
BOOL RCWKDelegateIsCompatible(id delegate);
