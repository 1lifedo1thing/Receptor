#import <Foundation/Foundation.h>
NSString *RCRemotePath(NSString *path);
NSDictionary *RCRemoteRead(NSString *path);
void RCRemoteSave(NSString *path,NSDictionary *value);
NSDictionary *RCRemoteInvoke(NSDictionary *request);
