#import <Foundation/Foundation.h>
@class RCCompanionClient;
@protocol RCCompanionClientDelegate <NSObject>
- (void)companion:(RCCompanionClient *)client finished:(NSDictionary *)result;
@end
@interface RCCompanionClient : NSObject {
    id<RCCompanionClientDelegate> _delegate;
    NSString *_host;
    NSString *_key;
    NSString *_pairingCode;
    NSString *_salt;
    NSString *_session;
    BOOL _busy;
    BOOL _cancelled;
}
@property(nonatomic, assign) id<RCCompanionClientDelegate> delegate;
@property(nonatomic, readonly) BOOL busy;
+ (NSDictionary *)savedConnection;
+ (BOOL)forgetSavedConnection;
- (BOOL)connectToHost:(NSString *)host code:(NSString *)code error:(NSError **)error;
- (BOOL)receiveFile:(NSDictionary *)file error:(NSError **)error;
- (void)cancel;
@end
