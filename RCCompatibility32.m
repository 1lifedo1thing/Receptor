#import "RCCompatibility32.h"
#if RC_LEGACY32
@implementation RC32Cache
@synthesize totalCostLimit=_totalCostLimit,countLimit=_countLimit;
- (id)init {if((self=[super init])) {_objects=[[NSMutableDictionary alloc] init];_costs=[[NSMutableDictionary alloc] init];_keys=[[NSMutableArray alloc] init];_totalCostLimit=6*1024*1024;_countLimit=128;}return self;}
- (id)objectForKey:(id)key {return [_objects objectForKey:key];}
- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost {
    if(!object || !key || cost>_totalCostLimit || !_countLimit)return;
    _cost-=[[_costs objectForKey:key] unsignedIntegerValue];[_objects removeObjectForKey:key];[_costs removeObjectForKey:key];[_keys removeObject:key];
    while([_keys count] && ([_keys count]>=_countLimit || _cost>_totalCostLimit || cost>_totalCostLimit-_cost)) {
        id oldest=[[_keys objectAtIndex:0] retain];_cost-=[[_costs objectForKey:oldest] unsignedIntegerValue];[_objects removeObjectForKey:oldest];[_costs removeObjectForKey:oldest];[_keys removeObjectAtIndex:0];[oldest release];
    }
    [_objects setObject:object forKey:key];[_costs setObject:[NSNumber numberWithUnsignedInteger:cost] forKey:key];[_keys addObject:key];_cost+=cost;
}
- (void)removeAllObjects {[_objects removeAllObjects];[_costs removeAllObjects];[_keys removeAllObjects];_cost=0;}
- (void)dealloc {[_objects release];[_costs release];[_keys release];[super dealloc];}
@end
@implementation NSPropertyListSerialization (RC32Plists)
+ (NSData *)rc32_dataWithPropertyList:(id)value format:(NSPropertyListFormat)format options:(NSUInteger)options error:(NSError **)error {
    (void)options; NSString *description=nil;
    NSData *data=[self dataFromPropertyList:value format:format errorDescription:&description];
    if(!data && error)*error=[NSError errorWithDomain:@"ReceptorLegacyPlist" code:1 userInfo:[NSDictionary dictionaryWithObject:description?:@"Cannot encode property list." forKey:NSLocalizedDescriptionKey]];
#ifndef GNUSTEP
    [description release]; // Apple's legacy API returns an owned error description.
#endif
    return data;
}
+ (id)rc32_propertyListWithData:(NSData *)data options:(NSPropertyListMutabilityOptions)options format:(NSPropertyListFormat *)format error:(NSError **)error {
    NSString *description=nil; id value=[self propertyListFromData:data mutabilityOption:options format:format errorDescription:&description];
    if(!value && error)*error=[NSError errorWithDomain:@"ReceptorLegacyPlist" code:2 userInfo:[NSDictionary dictionaryWithObject:description?:@"Cannot decode property list." forKey:NSLocalizedDescriptionKey]];
#ifndef GNUSTEP
    [description release]; // GNUstep's host adapter returns an autoreleased string.
#endif
    return value;
}
@end
#if RC_UI_COMPAT
#import <objc/runtime.h>
static char RCRootKey;
static BOOL RC32Active=YES;
@interface RC32Lifecycle : NSObject
- (void)active:(NSNotification *)notification;
- (void)inactive:(NSNotification *)notification;
@end
@implementation RC32Lifecycle
- (void)active:(NSNotification *)notification {(void)notification;RC32Active=YES;}
- (void)inactive:(NSNotification *)notification {(void)notification;RC32Active=NO;}
@end
@implementation UIApplication (RC32State)
- (UIApplicationState)rc32_applicationState {
    static RC32Lifecycle *lifecycle=nil;
    if(!lifecycle) {lifecycle=[[RC32Lifecycle alloc] init]; NSNotificationCenter *center=[NSNotificationCenter defaultCenter];[center addObserver:lifecycle selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];[center addObserver:lifecycle selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];}
    return RC32Active?UIApplicationStateActive:UIApplicationStateInactive;
}
@end
@implementation UIWindow (RC32Root)
- (UIViewController *)rc32_rootViewController {return objc_getAssociatedObject(self,&RCRootKey);}
- (void)setRc32_rootViewController:(UIViewController *)controller {
    UIViewController *old=[self rc32_rootViewController];if(old==controller)return;[old.view removeFromSuperview];
    objc_setAssociatedObject(self,&RCRootKey,controller,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(controller) {controller.view.frame=[[UIScreen mainScreen] applicationFrame];controller.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self addSubview:controller.view];}
}
@end
#endif
#endif
