#import "ReceptorPaths.h"
#include <sys/stat.h>

NSString * const RCDownloadsDirectory = @"/var/mobile/Media/Receptor";
NSString * const RCDownloadsChangedNotification = @"ReceptorDownloadsChanged";

NSError *RCError(NSString *message) {
    return [NSError errorWithDomain:@"com.receptor.downloadmanager" code:1
        userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

BOOL RCEnsureDownloadsDirectory(NSError **error) {
    struct stat info;
    if (lstat([RCDownloadsDirectory fileSystemRepresentation], &info) == 0) {
        if (S_ISDIR(info.st_mode)) return YES;
        if (error) *error = RCError(@"The Receptor storage path is not a real directory.");
        return NO;
    }
    if (![[NSFileManager defaultManager] createDirectoryAtPath:RCDownloadsDirectory
        withIntermediateDirectories:YES attributes:[NSDictionary dictionaryWithObject:
            [NSNumber numberWithUnsignedLong:0755] forKey:NSFilePosixPermissions] error:error]) return NO;
    if (lstat([RCDownloadsDirectory fileSystemRepresentation], &info) == 0 && S_ISDIR(info.st_mode)) return YES;
    if (error) *error = RCError(@"Unable to verify the Receptor storage directory.");
    return NO;
}

NSString *RCSafeFilename(NSString *name) {
    if (![name length]) name = @"Download";
    // Treat both URL and Windows separators as path separators; never trust headers.
    name = [[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *controls = [NSCharacterSet controlCharacterSet];
    for (NSUInteger i = 0; i < [name length]; ++i) {
        unichar c = [name characterAtIndex:i];
        if ([controls characterIsMember:c] || c == ':' || c == '/') c = '_';
        [result appendFormat:@"%C", c];
    }
    while ([result hasPrefix:@"."]) [result deleteCharactersInRange:NSMakeRange(0, 1)];
    while ([result lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 180 && [result length]) {
        [result deleteCharactersInRange:[result rangeOfComposedCharacterSequenceAtIndex:[result length] - 1]];
    }
    return [result length] ? result : @"Download";
}

BOOL RCIsRegularDownload(NSString *name) {
    if (![name length] || [name hasPrefix:@"."] || ![name isEqualToString:[name lastPathComponent]]) return NO;
    struct stat info;
    NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:name];
    return lstat([path fileSystemRepresentation], &info) == 0 && S_ISREG(info.st_mode);
}

BOOL RCIsDownloadRequest(NSURLRequest *request) {
    NSString *scheme = [[[request URL] scheme] lowercaseString];
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        && (![[request HTTPMethod] length] || [[request HTTPMethod] isEqualToString:@"GET"])
        && ![request HTTPBody] && ![request HTTPBodyStream];
}
