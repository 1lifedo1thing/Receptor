#import "RCCompanionClient.h"
#import "ReceptorPaths.h"
#import "RCCurlTransfer.h"
#import "RCPairingCrypto.h"
#import <Security/Security.h>
#include <curl/curl.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <spawn.h>
#include <sys/wait.h>

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
static NSMutableDictionary *RCConnectionQuery(void) {
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:(id)kSecClassGenericPassword, (id)kSecClass,
        @"com.receptor.desktop", (id)kSecAttrService, @"saved-connection-v2", (id)kSecAttrAccount,
        @"com.receptor.app", (id)kSecAttrAccessGroup, nil];
}
static BOOL RCValidFile(id file) {
    if (![file isKindOfClass:[NSDictionary class]]) return NO;
    id name = [file objectForKey:@"name"], size = [file objectForKey:@"size"];
    return RCHexString([file objectForKey:@"id"], 32) && RCHexString([file objectForKey:@"sha256"], 64) &&
        [name isKindOfClass:[NSString class]] && [name length] &&
        [size isKindOfClass:[NSNumber class]] && [size longLongValue] >= 0 && [size longLongValue] <= 2147483647LL;
}

@interface RCCompanionClient ()
- (BOOL)isCancelled;
- (void)run:(NSDictionary *)operation;
- (void)finish:(NSDictionary *)result;
- (void)runUpload:(NSString *)path;
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
static NSArray *RCFetchPairingInfo(RCCompanionClient *client, NSString *host) {
    RCCompanionContext context; memset(&context, 0, sizeof(context));
    context.client = client; context.descriptor = -1; context.body = [NSMutableData data]; context.limit = 128;
    CC_SHA256_Init(&context.hash);
    CURL *curl = curl_easy_init(); if (!curl) return nil;
    NSString *url = [NSString stringWithFormat:@"http://%@/v2/pairing?nonce=%@", host, RCNonce()];
    curl_easy_setopt(curl, CURLOPT_URL, [url UTF8String]);
    curl_easy_setopt(curl, CURLOPT_PROXY, ""); curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http");
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L); curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L); curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, RCCompanionWrite); curl_easy_setopt(curl, CURLOPT_WRITEDATA, &context);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, RCCompanionHeader); curl_easy_setopt(curl, CURLOPT_HEADERDATA, &context);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L); curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, RCCompanionProgress);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, client);
    CURLcode code = curl_easy_perform(curl); long status = 0; curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(curl); [context.auth release];
    if (code != CURLE_OK || status != 200) return nil;
    NSString *text = [[[NSString alloc] initWithData:context.body encoding:NSASCIIStringEncoding] autorelease];
    NSArray *parts = [text componentsSeparatedByString:@"\n"];
    return [parts count] == 3 && [[parts objectAtIndex:0] isEqualToString:@"2"] &&
        RCHexString([parts objectAtIndex:1], 32) && RCHexString([parts objectAtIndex:2], 32) ? parts : nil;
}
static NSString *RCBase64(NSData *data) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char *bytes = [data bytes]; NSUInteger length = [data length];
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < length; i += 3) {
        unsigned int value = (unsigned int)bytes[i] << 16;
        if (i + 1 < length) value |= (unsigned int)bytes[i + 1] << 8;
        if (i + 2 < length) value |= bytes[i + 2];
        [text appendFormat:@"%c%c%c%c", alphabet[(value >> 18) & 63], alphabet[(value >> 12) & 63],
            i + 1 < length ? alphabet[(value >> 6) & 63] : '=', i + 2 < length ? alphabet[value & 63] : '='];
    }
    return text;
}
typedef struct { RCCompanionClient *client; int descriptor; } RCUploadReader;
static size_t RCCompanionRead(char *bytes, size_t size, size_t count, void *pointer) {
    RCUploadReader *reader = pointer;
    if ([reader->client isCancelled] || (size && count > SIZE_MAX / size)) return CURL_READFUNC_ABORT;
    ssize_t length;
    do { length = read(reader->descriptor, bytes, size * count); } while (length < 0 && errno == EINTR);
    return length < 0 ? CURL_READFUNC_ABORT : (size_t)length;
}

@implementation RCCompanionClient
@synthesize delegate = _delegate, busy = _busy, canUpload = _canUpload, remotePublicKey = _remotePublicKey, host = _host;
+ (NSDictionary *)savedConnection {
    NSMutableDictionary *query = RCConnectionQuery();
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    [query setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
    CFTypeRef value = NULL;
    if (SecItemCopyMatching((CFDictionaryRef)query, &value) != errSecSuccess) return nil;
    NSString *parseError = nil;
    id saved = [NSPropertyListSerialization propertyListFromData:(NSData *)value mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&parseError];
    CFRelease(value); [parseError release];
    return [saved isKindOfClass:[NSDictionary class]] && [[saved objectForKey:@"host"] isKindOfClass:[NSString class]] &&
        RCHexString([saved objectForKey:@"key"], 64) && RCHexString([saved objectForKey:@"salt"], 32) ? saved : nil;
}
+ (BOOL)forgetSavedConnection {
    // Revoke the separate background grant before removing the foreground Keychain record.
    const char *helper="/usr/libexec/receptor-package-helper";
    struct stat info;
    if(stat(helper,&info) || info.st_uid!=0 || !(info.st_mode&S_ISUID) || (info.st_mode&022))return NO;
    char *temporary=strdup([[NSTemporaryDirectory() stringByAppendingPathComponent:@"receptor-revoke-XXXXXX"] fileSystemRepresentation]); int fd=temporary?mkstemp(temporary):-1;
    if(fd<0) { free(temporary); return NO; } unlink(temporary); free(temporary);
    if(fd<=2) { int copy=fcntl(fd,F_DUPFD,3); close(fd); fd=copy; if(fd<0)return NO; } fcntl(fd,F_SETFD,FD_CLOEXEC);
    posix_spawn_file_actions_t actions; int setup=posix_spawn_file_actions_init(&actions); BOOL initialized=setup==0;
    if(!setup)setup=posix_spawn_file_actions_addopen(&actions,0,"/dev/null",O_RDONLY,0);
    if(!setup)setup=posix_spawn_file_actions_adddup2(&actions,fd,1);
    if(!setup)setup=posix_spawn_file_actions_addopen(&actions,2,"/dev/null",O_WRONLY,0);
    if(!setup)setup=posix_spawn_file_actions_addclose(&actions,fd);
    char *arguments[]={(char *)helper,"remote-disable",NULL},*environment[]={"PATH=/usr/bin:/bin:/usr/sbin:/sbin","HOME=/var/mobile","LANG=C",NULL}; pid_t child=0;
    int error=setup?setup:posix_spawn(&child,helper,&actions,NULL,arguments,environment); if(initialized)posix_spawn_file_actions_destroy(&actions);
    BOOL revoked=NO;
    if(!error) { int result=0; pid_t waited; do { waited=waitpid(child,&result,0); } while(waited<0 && errno==EINTR);
        off_t size=lseek(fd,0,SEEK_END); if(waited==child && WIFEXITED(result) && WEXITSTATUS(result)==0 && size>0 && size<8192) {
            lseek(fd,0,SEEK_SET); NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)size]; if(read(fd,[data mutableBytes],[data length])==size) { NSError *parseError=nil; id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&parseError]; revoked=[value isKindOfClass:[NSDictionary class]] && [value objectForKey:@"enabled"] && ![[value objectForKey:@"enabled"] boolValue]; }
        }
    } close(fd); if(!revoked)return NO;
    OSStatus status = SecItemDelete((CFDictionaryRef)RCConnectionQuery());
    return status == errSecSuccess || status == errSecItemNotFound;
}
- (BOOL)saveConnection {
    NSDictionary *saved = [NSDictionary dictionaryWithObjectsAndKeys:_host, @"host", _key, @"key", _salt, @"salt", nil];
    NSString *error = nil;
    NSData *data = [NSPropertyListSerialization dataFromPropertyList:saved format:NSPropertyListBinaryFormat_v1_0 errorDescription:&error];
    [error release]; if (!data) return NO;
    NSMutableDictionary *query = RCConnectionQuery();
    NSDictionary *updates = [NSDictionary dictionaryWithObject:data forKey:(id)kSecValueData];
    OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)updates);
    if (status == errSecItemNotFound) {
        [query addEntriesFromDictionary:updates];
        [query setObject:(id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly forKey:(id)kSecAttrAccessible];
        status = SecItemAdd((CFDictionaryRef)query, NULL);
    }
    return status == errSecSuccess;
}
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
    NSDictionary *saved = [[self class] savedConnection];
    BOOL useSaved = ![key length] && saved != nil;
    BOOL validCode = [key length] == 8 && [key rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"] invertedSet]].location == NSNotFound;
    if (!valid || (!useSaved && !validCode)) {
        if (error) *error = RCError(@"Enter the PC address and its 8-character code. For a saved connection, leave the code blank. Both apps must be version 1.3.1 or later.");
        return NO;
    }
    [_host release]; _host = [host copy]; [_key release]; _key = useSaved ? [[saved objectForKey:@"key"] copy] : nil;
    [_salt release]; _salt = useSaved ? [[saved objectForKey:@"salt"] copy] : nil;
    [_pairingCode release]; _pairingCode = useSaved ? nil : [key copy];
    [_session release]; _session = nil;
    _canUpload = NO;
    [_remotePublicKey release]; _remotePublicKey=nil;
    _busy = YES; @synchronized(self) { _cancelled = NO; }
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:[NSDictionary dictionary]];
    return YES;
}
- (BOOL)receiveFile:(NSDictionary *)file error:(NSError **)error {
    if (_busy || !_host || !_key || !_session || !RCValidFile(file)) { if (error) *error = RCError(@"Connect to the desktop and choose a valid file first."); return NO; }
    _busy = YES; @synchronized(self) { _cancelled = NO; }
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:[NSDictionary dictionaryWithObject:file forKey:@"file"]];
    return YES;
}
- (BOOL)sendFileAtPath:(NSString *)path error:(NSError **)error {
    if (_busy || !_host || !_key || !_session || !_canUpload || ![path isAbsolutePath]) {
        if (error) *error = RCError(@"Connect to Receptor Desktop 1.6.0 or later with receiving enabled before sending a file."); return NO;
    }
    _busy = YES; @synchronized(self) { _cancelled = NO; }
    [NSThread detachNewThreadSelector:@selector(runUpload:) toTarget:self withObject:[[path copy] autorelease]]; return YES;
}
- (void)runUpload:(NSString *)path {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"upload"];
    NSString *failure = nil;
    int source = -1, snapshot = -1;
    do {
        source = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
        struct stat before, after;
        if (source < 0 || fstat(source, &before) || !S_ISREG(before.st_mode) || before.st_size < 0 || before.st_size > 2147483647LL) {
            failure = @"Choose a readable regular file no larger than 2 GB. Protected paths, devices and unresolved symbolic links cannot be sent."; break;
        }
        (void)fcntl(source, F_SETFD, FD_CLOEXEC);
        NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@".receptor-send-XXXXXX"];
        char *temporary = strdup([template fileSystemRepresentation]);
        if (temporary) snapshot = mkstemp(temporary);
        if (snapshot < 0) { free(temporary); failure = @"Cannot create a private upload snapshot. Check free space."; break; }
        (void)fcntl(snapshot, F_SETFD, FD_CLOEXEC);
        if (unlink(temporary)) { close(snapshot); snapshot = -1; free(temporary); failure = @"Could not secure the temporary upload file."; break; }
        free(temporary); // Anonymous private fd is cleaned by close, including after a process exit.
        CC_SHA256_CTX hash; CC_SHA256_Init(&hash);
        unsigned char buffer[65536]; long long copied = 0;
        for (;;) {
            if ([self isCancelled]) { failure = @"Transfer cancelled."; break; }
            ssize_t count = read(source, buffer, sizeof(buffer));
            if (count < 0 && errno == EINTR) continue;
            if (count < 0) { failure = @"Cannot read this file with Receptor's current permissions."; break; }
            if (count == 0) break;
            if (copied + count > before.st_size) { failure = @"The source file changed while preparing. Retry when it is no longer being written."; break; }
            ssize_t offset = 0;
            while (offset < count) {
                ssize_t written = write(snapshot, buffer + offset, (size_t)(count - offset));
                if (written < 0 && errno == EINTR) continue;
                if (written <= 0) { failure = @"Cannot prepare the upload snapshot. Check free space."; break; }
                offset += written;
            }
            if (failure) break;
            CC_SHA256_Update(&hash, buffer, (CC_LONG)count); copied += count;
        }
        if (failure) break;
        if (fstat(source, &after) || copied != before.st_size || before.st_size != after.st_size || before.st_mtime != after.st_mtime ||
            before.st_ctime != after.st_ctime || before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec) {
            failure = @"The source changed while preparing. Retry with a file that is no longer being written."; break;
        }
        close(source); source = -1;
        if (fsync(snapshot) || lseek(snapshot, 0, SEEK_SET) < 0) { failure = @"Cannot finish preparing the upload snapshot."; break; }
        if ([self isCancelled]) { failure = @"Transfer cancelled."; break; }
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &hash);
        NSString *checksum = RCHex(digest, sizeof(digest));
        NSString *encodedName = RCBase64([RCSafeFilename([path lastPathComponent]) dataUsingEncoding:NSUTF8StringEncoding]);
        NSString *nonce = RCNonce(), *length = [NSString stringWithFormat:@"%lld", copied];
        NSString *mac = RCMac(_key, [NSString stringWithFormat:@"PUT\n/v2/uploads\n%@\n%@\n%@\n%@\n%@", nonce, _session, length, checksum, encodedName]);
        NSString *url = [NSString stringWithFormat:@"http://%@/v2/uploads?nonce=%@", _host, nonce];
        struct curl_slist *headers = NULL;
        NSArray *lines = [NSArray arrayWithObjects:[@"X-Receptor-Auth: " stringByAppendingString:mac],
            [@"X-Receptor-Name: " stringByAppendingString:encodedName], [@"X-Receptor-SHA256: " stringByAppendingString:checksum],
            @"Content-Type: application/octet-stream", @"Expect:", nil];
        for (NSString *line in lines) {
            struct curl_slist *next = curl_slist_append(headers, [line UTF8String]);
            if (!next) { failure = @"Cannot allocate upload headers."; break; } headers = next;
        }
        if (failure) { curl_slist_free_all(headers); break; }
        CURL *curl = curl_easy_init();
        if (!curl) { curl_slist_free_all(headers); failure = @"Cannot initialize upload transport."; break; }
        RCCompanionContext context; memset(&context, 0, sizeof(context));
        context.client = self; context.descriptor = -1; context.body = [NSMutableData data]; context.limit = 2048; CC_SHA256_Init(&context.hash);
        RCUploadReader reader = {self, snapshot};
        curl_easy_setopt(curl, CURLOPT_URL, [url UTF8String]); curl_easy_setopt(curl, CURLOPT_PROXY, "");
        curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http"); curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
        curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L); curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)copied);
        curl_easy_setopt(curl, CURLOPT_READFUNCTION, RCCompanionRead); curl_easy_setopt(curl, CURLOPT_READDATA, &reader);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers); curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L); curl_easy_setopt(curl, CURLOPT_TIMEOUT, 1800L);
        curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, 1L); curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, 30L);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, RCCompanionWrite); curl_easy_setopt(curl, CURLOPT_WRITEDATA, &context);
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, RCCompanionHeader); curl_easy_setopt(curl, CURLOPT_HEADERDATA, &context);
        curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L); curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, RCCompanionProgress); curl_easy_setopt(curl, CURLOPT_XFERINFODATA, self);
        CURLcode code = curl_easy_perform(curl); long status = 0; curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
        unsigned char receiptHash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(receiptHash, &context.hash);
        NSString *expected = RCMac(_key, [NSString stringWithFormat:@"response\n%@\n%@\n%@", nonce, RCHex(receiptHash, sizeof(receiptHash)), _session]);
        if ([self isCancelled]) failure = @"Transfer cancelled.";
        else if (status == 403) failure = @"The PC rejected this upload. Enable receiving in the updated companion and reconnect.";
        else if (status == 409) failure = @"The PC is busy or this session expired. Reconnect and retry.";
        else if (status == 429) failure = @"The PC has received 32 files this session. Stop and start sharing, then reconnect.";
        else if (code != CURLE_OK || status != 201) failure = @"The PC did not confirm delivery. Check the connection and receive folder. A fully delivered copy may already exist on the PC.";
        else if (context.badHeader || !RCEqual(context.auth, expected)) failure = @"The PC receipt failed authentication. Delivery is not confirmed.";
        else {
            NSString *saved = [[[NSString alloc] initWithData:context.body encoding:NSUTF8StringEncoding] autorelease];
            if (![saved length] || [saved rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound ||
                [saved rangeOfString:@"/"].location != NSNotFound || [saved rangeOfString:@"\\"].location != NSNotFound) failure = @"The PC returned an invalid delivery receipt.";
            else [result setObject:saved forKey:@"uploaded"];
        }
        [context.auth release]; curl_easy_cleanup(curl); curl_slist_free_all(headers);
    } while (0);
    if (source >= 0) close(source); if (snapshot >= 0) close(snapshot);
    if (failure) [result setObject:failure forKey:@"error"];
    [self performSelectorOnMainThread:@selector(finish:) withObject:result waitUntilDone:NO]; [pool drain];
}
- (void)run:(NSDictionary *)operation {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *file = [operation objectForKey:@"file"];
    NSString *failure = nil;
    if (!file) {
        NSArray *info = RCFetchPairingInfo(self, _host);
        if (!info) failure = @"Could not reach the desktop. Keep Receptor Desktop 1.3.1 or later open, check the PC address and Wi-Fi, then tap Connect / Refresh. Saved pairing is kept.";
        else if (!_pairingCode && !RCEqual(_salt, [info objectAtIndex:1])) failure = @"The PC's pairing was reset. Enter the new short code shown on the PC and connect again.";
        else {
            if (_pairingCode) {
                unsigned char salt[16], derived[32];
                const char *hex = [[info objectAtIndex:1] UTF8String];
                for (int i = 0; i < 16; ++i) { char pair[3] = {hex[i * 2], hex[i * 2 + 1], 0}; salt[i] = (unsigned char)strtoul(pair, NULL, 16); }
                RCPairingDerive([_pairingCode UTF8String], salt, derived);
                [_key release]; _key = [RCHex(derived, sizeof(derived)) copy]; memset(derived, 0, sizeof(derived));
                [_salt release]; _salt = [[info objectAtIndex:1] copy];
                [_pairingCode release]; _pairingCode = nil;
            }
            [_session release]; _session = [[info objectAtIndex:2] copy];
        }
    }
    if (failure) {
        [self performSelectorOnMainThread:@selector(finish:) withObject:[NSDictionary dictionaryWithObject:failure forKey:@"error"] waitUntilDone:NO];
        [pool drain]; return;
    }
    NSString *nonce = RCNonce();
    NSString *route = file ? [@"/v2/files/" stringByAppendingString:[file objectForKey:@"id"]] : @"/v2/manifest";
    NSString *url = [NSString stringWithFormat:@"http://%@%@?nonce=%@", _host, route, nonce];
    NSString *mac = RCMac(_key, [NSString stringWithFormat:@"GET\n%@\n%@\n%@", route, nonce, _session]);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    RCCompanionContext context;
    memset(&context, 0, sizeof(context)); context.client = self; context.descriptor = -1;
    context.body = [NSMutableData data]; context.limit = file ? [[file objectForKey:@"size"] longLongValue] : 131072;
    CC_SHA256_Init(&context.hash);
    NSError *directoryError = nil;
    NSString *partial = nil;
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
        NSString *responseMAC = RCMac(_key, [NSString stringWithFormat:@"response\n%@\n%@\n%@", nonce, hash, _session]);
        if (!failure) {
            if ([self isCancelled]) failure = @"Transfer cancelled.";
            else if (status == 403) failure = @"Pairing failed. Check the code shown on your PC.";
            else if (code != CURLE_OK || status != 200) failure = @"Could not receive the file list or file. Keep the desktop app open, check both devices are on the same Wi-Fi, and allow it through the PC's private-network firewall. Try refreshing the connection.";
            else if (context.badHeader || !RCEqual(context.auth, responseMAC)) failure = @"Desktop authentication failed. Nothing was installed. Check the pairing code and reconnect.";
            else if (file && (context.received != context.limit || !RCEqual(hash, [file objectForKey:@"sha256"]))) failure = @"The file failed its integrity check. Nothing was installed. Refresh the list and retry.";
        }
        curl_easy_cleanup(curl);
    }
    curl_slist_free_all(headers); [context.auth release];
    if (!failure && file) {
        if (fsync(context.descriptor)) failure = @"The received file could not be saved. Check free space.";
    }
    if (context.descriptor >= 0 && close(context.descriptor) && !failure) failure = @"Could not finish saving the file. Check free space.";
    if (!failure && file) {
        NSString *safe = RCSafeFilename([file objectForKey:@"name"]);
        NSString *saved = nil;
        for (int i = 0; i < 10000; ++i) {
            NSString *candidate = safe;
            if (i) {
                NSString *extension = [safe pathExtension];
                candidate = [NSString stringWithFormat:@"%@ (%d)", [safe stringByDeletingPathExtension], i];
                if ([extension length]) candidate = [candidate stringByAppendingPathExtension:extension];
            }
            NSString *destination = [RCDownloadsDirectory stringByAppendingPathComponent:candidate];
            if (link([partial fileSystemRepresentation], [destination fileSystemRepresentation]) == 0) { saved = candidate; break; }
            if (errno != EEXIST) break;
        }
        if (saved) [result setObject:saved forKey:@"saved"];
        else failure = @"Could not publish the received file. Existing files were preserved.";
    }
    if (partial) unlink([partial fileSystemRepresentation]);
    if (!failure && !file) {
        NSString *parseError = nil;
        id plist = [NSPropertyListSerialization propertyListFromData:context.body mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&parseError];
        [parseError release];
        id version = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"protocol"] : nil;
        id files = [plist isKindOfClass:[NSDictionary class]] ? [plist objectForKey:@"files"] : nil;
        BOOL valid = [version isKindOfClass:[NSNumber class]] && [version intValue] == 2 && [files isKindOfClass:[NSArray class]] && [files count] <= 32;
        if (valid) for (id item in files) if (!RCValidFile(item)) { valid = NO; break; }
        if (valid) {
            [result setObject:files forKey:@"files"];
            id accepts = [plist objectForKey:@"accepts_uploads"];
            [result setObject:[NSNumber numberWithBool:[accepts isKindOfClass:[NSNumber class]] && [accepts boolValue]] forKey:@"canUpload"];
            id publicKey=[plist objectForKey:@"remote_public_key"];
            if([publicKey isKindOfClass:[NSString class]] && [publicKey length]<4096 && [publicKey hasPrefix:@"-----BEGIN PUBLIC KEY-----"]) [result setObject:publicKey forKey:@"remotePublicKey"];
        }
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
        result = [NSDictionary dictionaryWithObject:[result objectForKey:@"upload"] ? @"Transfer cancelled. A file already delivered may remain on your PC." : @"Transfer cancelled. Any file already fully received is available in Files." forKey:@"error"];
    }
    else if ([result objectForKey:@"files"]) {
        _canUpload = [[result objectForKey:@"canUpload"] boolValue];
        if (![self saveConnection]) {
            NSMutableDictionary *updated = [[result mutableCopy] autorelease];
            [updated setObject:@"Connected, but iOS could not save the pairing in Keychain. Unlock the device and try connecting again." forKey:@"saveWarning"];
            result = updated;
        } else { [_remotePublicKey release]; _remotePublicKey=[[result objectForKey:@"remotePublicKey"] copy]; }
    }
    [_delegate companion:self finished:result];
}
- (void)dealloc { [_remotePublicKey release]; [_host release]; [_key release]; [_pairingCode release]; [_salt release]; [_session release]; [super dealloc]; }
@end
