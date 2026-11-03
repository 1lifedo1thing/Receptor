#import <Foundation/Foundation.h>
#import "../RCRemoteCrypto.h"
#include <stdio.h>
#include <unistd.h>
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; NSMutableData *data=[NSMutableData data];char buffer[8192];ssize_t count;
    while((count=read(0,buffer,sizeof(buffer)))>0)[data appendBytes:buffer length:count]; NSError *error=nil;
    NSDictionary *request=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error]; NSMutableDictionary *result=[NSMutableDictionary dictionary];
    @try {
        NSString *action=[request objectForKey:@"action"];NSData *seed=[request objectForKey:@"seed"];
        if([action isEqual:@"seal"]) {NSData *sealed=RCRemoteSeal([request objectForKey:@"publicKey"],seed);if(!sealed)[NSException raise:@"Crypto" format:@"Seal failed"];NSString *device=[RCRemoteHash(seed) substringToIndex:32];[result setObject:sealed forKey:@"sealed"];[result setObject:device forKey:@"device"];[result setObject:RCRemoteEnrollment([request objectForKey:@"pairingKey"],device,sealed) forKey:@"enrollment"];[result setObject:RCRemoteFingerprint([request objectForKey:@"publicKey"]) forKey:@"fingerprint"];}
        else if([action isEqual:@"encrypt"]) {NSData *frame=RCRemoteEncrypt(seed,[request objectForKey:@"plain"]);[result setObject:frame forKey:@"frame"];[result setObject:RCRemoteMAC(seed,[request objectForKey:@"direction"],[request objectForKey:@"device"],[request objectForKey:@"nonce"],frame) forKey:@"auth"];}
        else if([action isEqual:@"decrypt"]) {NSData *plain=RCRemoteDecrypt(seed,[request objectForKey:@"frame"]);if(plain)[result setObject:plain forKey:@"plain"];else[result setObject:@"Invalid frame" forKey:@"error"];}
        else if([action isEqual:@"mac"]) [result setObject:RCRemoteMAC(seed,[request objectForKey:@"direction"],[request objectForKey:@"device"],[request objectForKey:@"nonce"],[request objectForKey:@"frame"]) forKey:@"auth"];
    } @catch(NSException *exception) {[result setObject:[exception reason] forKey:@"error"];}
    NSData *output=[NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListXMLFormat_v1_0 options:0 error:&error]; if(output)fwrite([output bytes],1,[output length],stdout);[pool drain];return output?0:2;
}
