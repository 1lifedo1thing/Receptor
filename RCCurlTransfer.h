#import <Foundation/Foundation.h>
@class RCCurlTransfer;
@protocol RCCurlTransferDelegate <NSObject>
- (void)curlTransfer:(RCCurlTransfer *)transfer didReceiveResponse:(NSURLResponse *)response;
- (void)curlTransfer:(RCCurlTransfer *)transfer didReceiveData:(NSData *)data;
- (void)curlTransfer:(RCCurlTransfer *)transfer didFailWithError:(NSError *)error;
- (void)curlTransferDidFinish:(RCCurlTransfer *)transfer;
@end

@interface RCCurlTransfer : NSObject {
    id<RCCurlTransferDelegate> _delegate;
    NSURLRequest *_request;
    NSURL *_currentURL;
    NSMutableDictionary *_responseHeaders;
    NSInteger _status;
    BOOL _sentResponse;
    volatile int32_t _cancelled;
}
- (id)initWithRequest:(NSURLRequest *)request delegate:(id<RCCurlTransferDelegate>)delegate;
- (void)start;
- (void)cancel;
@end
