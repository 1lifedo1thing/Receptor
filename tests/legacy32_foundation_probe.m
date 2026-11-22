#import <Foundation/Foundation.h>
#import "../RCCompatibility32.h"
static void Check(BOOL condition) {if(!condition)[NSException raise:@"Test" format:@"Legacy Foundation compatibility failed"] ;}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];NSError *error=nil;
    NSDictionary *source=[NSDictionary dictionaryWithObjectsAndKeys:@"Unicode ☃",@"name",[NSData dataWithBytes:"\0\xff" length:2],@"bytes",[NSNumber numberWithBool:YES],@"enabled",nil];
    for(int binary=0;binary<2;binary++) {
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:source format:binary?NSPropertyListBinaryFormat_v1_0:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        Check(data && !error);id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];Check([value isEqual:source] && !error);
    }
    Check(![NSPropertyListSerialization propertyListWithData:[@"not a plist" dataUsingEncoding:NSUTF8StringEncoding] options:NSPropertyListImmutable format:NULL error:&error] && error);
    RC32Cache *cache=[[RC32Cache alloc] init];cache.countLimit=2;cache.totalCostLimit=10;
    [cache setObject:@"A" forKey:@"a" cost:4];[cache setObject:@"B" forKey:@"b" cost:4];[cache setObject:@"C" forKey:@"c" cost:4];
    Check(![cache objectForKey:@"a"] && [[cache objectForKey:@"b"] isEqual:@"B"]);
    [cache setObject:@"D" forKey:@"d" cost:7];Check(![cache objectForKey:@"b"] && ![cache objectForKey:@"c"] && [cache objectForKey:@"d"]);
    cache.totalCostLimit=3;[cache setObject:@"E" forKey:@"e" cost:2];Check(![cache objectForKey:@"d"] && [cache objectForKey:@"e"]);
    [cache removeAllObjects];Check(![cache objectForKey:@"e"]);[cache release];
    puts("PASS: legacy plist XML/binary/Unicode/data round trips, error bridging, and bounded cache count/cost eviction");[pool drain];return 0;
}
