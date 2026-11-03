#import <Foundation/Foundation.h>
NSData *RCRemoteRandom(NSUInteger count);
NSString *RCRemoteHash(NSData *data);
NSString *RCRemoteBase64(NSData *data);
NSData *RCRemoteUnbase64(NSString *text);
NSString *RCRemoteFingerprint(NSString *pem);
NSData *RCRemoteSeal(NSString *pem, NSData *seed);
NSData *RCRemoteEncrypt(NSData *seed, NSData *plain);
NSData *RCRemoteDecrypt(NSData *seed, NSData *frame);
NSString *RCRemoteMAC(NSData *seed, NSString *direction, NSString *device, NSString *nonce, NSData *frame);
NSString *RCRemoteEnrollment(NSString *pairingKey, NSString *device, NSData *sealed);
BOOL RCRemoteEqual(NSString *a, NSString *b);
