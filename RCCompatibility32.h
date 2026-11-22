#ifndef RC_COMPATIBILITY32_H
#define RC_COMPATIBILITY32_H
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#if RC_LEGACY32
@interface RC32Cache : NSObject {
    NSMutableDictionary *_objects;
    NSMutableDictionary *_costs;
    NSMutableArray *_keys;
    NSUInteger _cost, _totalCostLimit, _countLimit;
}
@property(nonatomic,assign) NSUInteger totalCostLimit;
@property(nonatomic,assign) NSUInteger countLimit;
- (id)objectForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost;
- (void)removeAllObjects;
@end
/* Prefix-included only by the separate iPhone OS 3.2 build. */
@interface NSPropertyListSerialization (RC32Plists)
+ (NSData *)rc32_dataWithPropertyList:(id)value format:(NSPropertyListFormat)format options:(NSUInteger)options error:(NSError **)error;
+ (id)rc32_propertyListWithData:(NSData *)data options:(NSPropertyListMutabilityOptions)options format:(NSPropertyListFormat *)format error:(NSError **)error;
@end
#define dataWithPropertyList rc32_dataWithPropertyList
#define propertyListWithData rc32_propertyListWithData
#if RC_UI_COMPAT
#import <UIKit/UIKit.h>
@interface UIApplication (RC32State)
- (UIApplicationState)rc32_applicationState;
@end
@interface UIWindow (RC32Root)
@property(nonatomic,retain) UIViewController *rc32_rootViewController;
@end
#define applicationState rc32_applicationState
#define rootViewController rc32_rootViewController
#define UIApplicationDidEnterBackgroundNotification UIApplicationWillResignActiveNotification
#define UIBackgroundTaskInvalid ((UIBackgroundTaskIdentifier)NSUIntegerMax)
/* Discard the block argument at preprocessing time: 3.2 has no Blocks runtime. */
#define RCBeginBackgroundTask(...) UIBackgroundTaskInvalid
#endif
#endif
#endif
#ifndef RCBeginBackgroundTask
#define RCBeginBackgroundTask(handler) [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:handler]
#endif
#endif
