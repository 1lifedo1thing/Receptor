#import <Foundation/Foundation.h>
extern NSString * const RCInstallationChangedNotification;
@interface RCIPAInstaller : NSObject {
    BOOL _busy;
    NSString *_status;
}
@property(nonatomic, readonly) BOOL busy;
@property(nonatomic, readonly, copy) NSString *status;
+ (RCIPAInstaller *)sharedInstaller;
- (void)installFileNamed:(NSString *)name;
@end
