#import "RCCompanionClient.h"
#import "ReceptorPaths.h"
#import "RCCurlTransfer.h"
#include <curl/curl.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

static NSString *RCHex(const unsigned char *bytes, size_t count) {
    NSMutableString *text = [NSMutableString stringWithCapacity:count * 2];
    for (size_t i = 0; i < count; ++i) [text appendFormat:@"%02x", bytes[i]];
    return text;
}
static NSString *RCNonce(void) {
    unsigned int bytes[4]; for (int i = 0; i < 4; ++i) bytes[i] = arc4random();
    return RCHex((const unsigned char *)bytes, sizeof(bytes));
}
static NSString *RCMac(NSString *key, NSString *text) {
    NSData *secret = [key dataUsingEncoding:NSASCIIStringEncoding], *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, [secret bytes], [secret length], [data bytes], [data length], digest);
    return RCHex(digest, sizeof(digest));
}
static BOOL RCEqual(NSString *a, NSString *b) {
    if (![a isKindOfClass:[NSString class]] || ![b isKindOfClass:[NSString class]] || [a length] != [b length]) return NO;
    unsigned int difference = 0;
    for (NSUInteger i = 0; i < [a length]; ++i) difference |= [a characterAtIndex:i] ^ [b characterAtIndex:i];
    return difference == 0;
}
static BOOL RCHexString(id value, NSUInteger length) {
    return [value isKindOfClass:[NSString class]] && [value length] == length &&
        [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location == NSNotFound;
}
static BOOL RCValidFile(id file) {
    if (![file isKindOfClass:[NSDictionary class]]) return NO;
    id name = [file objectForKey:@"name"], size = [file objectForKey:@"size"];
    return RCHexString([file objectForKey:@"id"], 32) && RCHexString([file objectForKey:@"sha256"], 64) &&
        [name isKindOfClass:[NSString class]] && [name length] &&
        [[[name pathExtension] lowercaseString] isEqualToString:@"deb"] &&
        [size isKindOfClass:[NSNumber class]] && [size longLongValue] >= 8 && [size longLongValue] <= 2147483647LL;
}

@interface RCCompanionClient ()
- (BOOL)isCancelled;
- (void)run:(NSDictionary *)operation;
- (void)finish:(NSDictionary *)result;
@end
typedef struct {
    RCCompanionClient *client;
    NSMutableData *body;
    int descriptor;
    long long received, limit;
    CC_SHA256_CTX hash;
    NSString *auth;
    BOOL badHeader;
    size_t headerBytes;
} RCCompanionContext;
static size_t RCCompanionWrite(char *bytes, size_t size, size_t count, void *pointer) {
    RCCompanionContext *context = pointer;
    size_t length = size * count;
    if ([context->client isCancelled] || (unsigned long long)length > (unsigned long long)(context->limit - context->received)) return 0;
    if (context->descriptor >= 0) {
        size_t offset = 0;
        while (offset < length) {
            ssize_t written = write(context->descriptor, bytes + offset, length - offset);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) return 0;
            offset += (size_t)written;
        }
    } else [context->body appendBytes:bytes length:length];
    CC_SHA256_Update(&context->hash, bytes, (CC_LONG)length);
    context->received += length;
    return length;
}
static size_t RCCompanionHeader(char *bytes, size_t size, size_t count, void *pointer) {
    RCCompanionContext *context = pointer;
    size_t length = size * count;
    context->headerBytes += length;
    if (context->headerBytes > 16384) return 0;
    NSString *line = [[[NSString alloc] initWithBytes:bytes length:length encoding:NSASCIIStringEncoding] autorelease];
    if (!line) return 0;
    NSRange colon = [line rangeOfString:@":"];
    if (colon.location != NSNotFound && [[[line substringToIndex:colon.location] lowercaseString] isEqualToString:@"x-receptor-auth"]) {
        if (context->auth) context->badHeader = YES;
        else context->auth = [[[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    }
    return length;
}
static int RCCompanionProgress(void *pointer, curl_off_t total, curl_off_t current, curl_off_t uploadTotal, curl_off_t uploaded) {
    (void)total; (void)current; (void)uploadTotal; (void)uploaded;
    return [(RCCompanionClient *)pointer isCancelled] ? 1 : 0;
}

@implementation RCCompanionClient
@synthesize delegate = _delegate, busy = _busy;
- (id)init {
    if ((self = [super init])) {
        // Share the transport class's once-per-process main-thread initialization.
        [RCCurlTransfer class];
    }
    return self;
}
- (BOOL)isCancelled { @synchronized(self) { return _cancelled; } }
- (void)cancel { @synchronized(self) { _cancelled = YES; } }
- (BOOL)connectToHost:(NSString *)host code:(NSString *)code error:(NSError **)error {
    if (_busy) { if (error) *error = RCError(@"Wait for the current transfer to stop."); return NO; }
    host = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *parts = [host componentsSeparatedByString:@":"];
    struct in_addr address;
    BOOL valid = [parts count] == 2 && inet_pton(AF_INET, [[parts objectAtIndex:0] UTF8String], &address) == 1;
    if (valid) {
        uint32_t ip = ntohl(address.s_addr);
        valid = (ip >> 24) == 10 || (ip >> 20) == 0xac1 || (ip >> 16) == 0xc0a8 || (ip >> 16) == 0xa9fe;
        NSString *port = [parts objectAtIndex:1];
        valid = valid && [port length] && [port length] <= 5 &&
            [port rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound &&
            [port intValue] > 0 && [port intValue] <= 65535;
    }
    NSString *key = [[[code stringByReplacingOccurrencesOfString:@"-" withString:@""]
        stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
    if (!valid || !RCHexString([key lowercaseString], 20)) {
        if (error) *error = RCError(@"Enter the PC's private IPv4 address and port (for example 192.168.1.20:12345), plus its 20-character pairing code.");
        return NO;
    }
    [_host release]; _host = [host copy]; [_key release]; _key = [key copy];
    _busy = YES; @synchronized(self) { _cancelled = NO; }
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:[NSDictionary dictionary]];
    return YES;
}
- (BOOL)receiveFile:(NSDictionary *)file error:(NSError **)error {
    if (_busy || !_host || !RCValidFile(file)) { if (error) *error = RCError(@"Connect to the desktop and choose a valid DEB first."); return NO; }
    _busy = YES; @synchronized(self) { _cancelled = NO; }
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:[NSDictionary dictionaryWithObject:file forKey:@"file"]];
    return YES;
}
- (void)run:(NSDictionary *)operation {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *file = [operation objectForKey:@"file"];
    NSString *nonce = RCNonce();
    NSString *route = file ? [@"/v1/files/" stringByAppendingString:[file objectForKey:@"id"]] : @"/v1/manifest";
    NSString *url = [NSString stringWithFormat:@"http://%@%@?nonce=%@", _host, route, nonce];
    NSString *mac = RCMac(_key, [NSString stringWithFormat:@"GET\n%@\n%@", route, nonce]);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    RCCompanionContext context;
    memset(&context, 0, sizeof(context)); context.client = self; context.descriptor = -1;
    context.body = [NSMutableData data]; context.limit = file ? [[file objectForKey:@"size"] longLongValue] : 131072;
    CC_SHA256_Init(&context.hash);
    NSError *directoryError = nil;
    NSString *partial = nil, *failure = nil;
    if (file) {
        if (RCEnsureDownloadsDirectory(&directoryError)) {
            partial = [RCDownloadsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@".desktop-%@.part", nonce]];
            context.descriptor = open([partial fileSystemRepresentation], O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        }
        if (context.descriptor < 0) { failure = [directoryError localizedDescription] ?: @"Cannot create a transfer file. Check free space."; partial = nil; }
    }
    CURL *curl = failure ? NULL : curl_easy_init();
    struct curl_slist *headers = NULL;
    if (!failure && !curl) failure = @"Could not initialize the desktop connection.";
    if (curl) {
        headers = curl_slist_append(headers, [[@"X-Receptor-Auth: " stringByAppendingString:mac] UTF8String]);
        if (!headers) failure = @"Could not initialize request authentication.";
        curl_easy_setopt(curl, CURLOPT_URL, [url UTF8String]);
        curl_easy_setopt(curl, CURLOPT_PROXY, "");
        curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http");
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, file ? 1800L : 20L);
        curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, 1L);
        curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, 30L);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, RCCompanionWrite);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &context);
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, RCCompanionHeader);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &context);
        curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
        curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, RCCompanionProgress);
        curl_easy_setopt(curl, CURLOPT_XFERINFODATA, self);
        CURLcode code = failure ? CURLE_FAILED_INIT : curl_easy_perform(curl);
        long status = 0; curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &context.hash);
        NSString *hash = RCHex(digest, sizeof(digest));
        NSString *responseMAC = RCMac(_key, [NSString stringWithFormat:@"response\n%@\n%@", nonce, hash]);
        if (!failure) {
            if ([self isCancelled]) failure = @"Transfer cancelled.";
            else if (status == 403) failure = @"Pairing failed. Check the code shown on your PC.";
            else if (code != CURLE_OK || status != 200) failure = @"Could not receive the DEB list or file. Keep the desktop app open, check both devices are on the same Wi-Fi, and allow it through the PC's private-network firewall. Try refreshing the connection.";
            else if (context.badHeader || !RCEqual(context.auth, responseMAC)) failure = @"Desktop authentication failed. Nothing was installed. Check the pairing code and reconnect.";
            else if (file && (context.received != context.limit || !RCEqual(hash, [file objectForKey:@"sha256"]))) failure = @"The DEB failed its integrity check. Nothing was installed. Refresh the list and retry.";
        }
        curl_easy_cleanup(curl);
    }
    curl_slist_free_all(headers); [context.auth release];
    if (!failure && file) {
        char magic[8];
        if (pread(context.descriptor, magic, 8, 0) != 8 || memcmp(magic, "!<arch>\n", 8) || fsync(context.descriptor)) failure = @"The received file is not a readable Debian archive, or could not be saved.";
    }
    if (context.descriptor >= 0 && close(context.descriptor) && !failure) failure = @"Could not finish saving the DEB. Check free space.";
    if (!failure && file) {
        NSString *safe = RCSafeFilename([file objectForKey:@"name"]);
        NSString *saved = nil;
        for (int i = 0; i < 10000; ++i) {
            NSString *candidate = i ? [NSString stringWithFormat:@"%@ (%d).deb", [safe stringByDeletingPathExtension], i] : safe;
            NSString *destination = [RCDownloadsDirectory stringByAppendingPathComponent:candidate];
            if (link([partial fileSystemRepresentation], [destination fileSystemRepresentation]) == 0) { saved = candidate; break; }
            if (errno != EEXIST) break;
        }
        if (saved) [result setObject:saved forKey:@"saved"];
        else failure = @"Could not publish the received DEB. Existing files were preserved.";
    }
    if (partial) unlink([partial fileSystemRepresentation]);
    if (!failure && !file) {
        NSString *parseError = nil;
        id plist = [NSPropertyListSerialization propertyListFromData:context.body mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&parseError];
        [parseError release];
        id version = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"protocol"] : nil;
        id files = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"files"] : nil;
        BOOL valid = [version isKindOfClass:[NSNumber class]] && [version intValue] == 1 && [files isKindOfClass:[NSArray class]] && [files count] <= 32;
        if (valid) for (id item in files) if (!RCValidFile(item)) { valid = NO; break; }
        if (valid) [result setObject:files forKey:@"files"];
        else failure = @"The desktop returned an invalid package list. Update both apps and reconnect.";
    }
    if (failure) [result setObject:failure forKey:@"error"];
    [self performSelectorOnMainThread:@selector(finish:) withObject:result waitUntilDone:NO];
    [pool drain];
}
- (void)finish:(NSDictionary *)result {
    _busy = NO;
    if ([self isCancelled]) {
        if ([result objectForKey:@"saved"]) [[NSNotificationCenter defaultCenter] postNotificationName:RCDownloadsChangedNotification object:nil];
        result = [NSDictionary dictionaryWithObject:@"Transfer cancelled. Any file already fully received is available in Files." forKey:@"error"];
    }
    [_delegate companion:self finished:result];
}
- (void)dealloc { [_host release]; [_key release]; [super dealloc]; }
@end
