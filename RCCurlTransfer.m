#import "RCCurlTransfer.h"
#import "ReceptorPaths.h"
#include <curl/curl.h>

static NSString *RCHeader(NSDictionary *headers, NSString *name) {
    for (NSString *key in headers) if ([key caseInsensitiveCompare:name] == NSOrderedSame) return [headers objectForKey:key];
    return nil;
}

// NSURLResponse's public initializer is available on iOS 4, unlike the modern
// NSHTTPURLResponse initializer. Supply the HTTP fields required by the engine.
@interface RCCurlResponse : NSURLResponse {
    NSDictionary *_headers;
    NSInteger _code;
    long long _length;
}
- (id)initWithURL:(NSURL *)url status:(NSInteger)status headers:(NSDictionary *)headers;
- (NSInteger)statusCode;
- (NSDictionary *)allHeaderFields;
@end
@implementation RCCurlResponse
- (id)initWithURL:(NSURL *)url status:(NSInteger)status headers:(NSDictionary *)headers {
    NSString *type = [[RCHeader(headers, @"Content-Type") componentsSeparatedByString:@";"] objectAtIndex:0];
    NSString *length = RCHeader(headers, @"Content-Length");
    if ((self = [super initWithURL:url MIMEType:type expectedContentLength:length ? [length longLongValue] : -1 textEncodingName:nil])) {
        _headers = [headers copy]; _code = status; _length = length ? [length longLongValue] : -1;
    }
    return self;
}
- (NSInteger)statusCode { return _code; }
- (NSDictionary *)allHeaderFields { return _headers; }
- (long long)expectedContentLength { return _length; }
- (NSString *)suggestedFilename {
    NSString *disposition = RCHeader(_headers, @"Content-Disposition");
    NSString *plain = nil;
    for (NSString *piece in [disposition componentsSeparatedByString:@";"]) {
        NSString *part = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange equal = [part rangeOfString:@"="];
        if (equal.location == NSNotFound) continue;
        NSString *key = [[part substringToIndex:equal.location] lowercaseString];
        NSString *value = [[part substringFromIndex:equal.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && [value length] >= 2) value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];
        if ([key isEqual:@"filename*"]) {
            NSRange encoding = [value rangeOfString:@"''"];
            if (encoding.location != NSNotFound) {
                NSString *decoded = [[value substringFromIndex:encoding.location + 2] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                if ([decoded length]) return decoded;
            }
        }
        if ([key isEqual:@"filename"]) plain = value;
    }
    return [plain length] ? plain : [[[self URL] path] lastPathComponent];
}
- (void)dealloc { [_headers release]; [super dealloc]; }
@end

@interface RCCurlTransfer ()
- (BOOL)isCancelled;
- (BOOL)receiveHeader:(NSData *)data;
- (BOOL)receiveData:(NSData *)data;
- (void)run;
@end

static size_t RCHeaderCallback(char *bytes, size_t size, size_t count, void *context) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    size_t length = size * count;
    BOOL accepted = [(RCCurlTransfer *)context receiveHeader:[NSData dataWithBytes:bytes length:length]];
    [pool drain];
    return accepted ? length : 0;
}
static size_t RCDataCallback(char *bytes, size_t size, size_t count, void *context) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    size_t length = size * count;
    BOOL accepted = [(RCCurlTransfer *)context receiveData:[NSData dataWithBytes:bytes length:length]];
    [pool drain];
    return accepted ? length : 0;
}
static int RCProgressCallback(void *context, curl_off_t total, curl_off_t now, curl_off_t uploadTotal, curl_off_t uploadNow) {
    (void)total; (void)now; (void)uploadTotal; (void)uploadNow;
    return [(RCCurlTransfer *)context isCancelled] ? 1 : 0;
}
static BOOL RCSameOrigin(NSURL *a, NSURL *b) {
    NSNumber *ap = [a port] ?: [NSNumber numberWithInt:[[[a scheme] lowercaseString] isEqual:@"https"] ? 443 : 80];
    NSNumber *bp = [b port] ?: [NSNumber numberWithInt:[[[b scheme] lowercaseString] isEqual:@"https"] ? 443 : 80];
    return [[[a scheme] lowercaseString] isEqual:[[b scheme] lowercaseString]] &&
        [[[a host] lowercaseString] isEqual:[[b host] lowercaseString]] && [ap isEqual:bp];
}

@implementation RCCurlTransfer
+ (void)initialize { if (self == [RCCurlTransfer class]) curl_global_init(CURL_GLOBAL_DEFAULT); }
- (id)initWithRequest:(NSURLRequest *)request delegate:(id<RCCurlTransferDelegate>)delegate {
    if ((self = [super init])) { _request = [request copy]; _delegate = [delegate retain]; }
    return self;
}
- (void)start { [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil]; }
- (void)cancel { __sync_lock_test_and_set(&_cancelled, 1); }
- (BOOL)isCancelled { return __sync_fetch_and_add(&_cancelled, 0) != 0; }
- (void)deliverResponse:(NSURLResponse *)response { if (![self isCancelled]) [_delegate curlTransfer:self didReceiveResponse:response]; }
- (void)deliverData:(NSData *)data { if (![self isCancelled]) [_delegate curlTransfer:self didReceiveData:data]; }
- (void)deliverError:(NSError *)error { if (![self isCancelled]) [_delegate curlTransfer:self didFailWithError:error]; }
- (void)deliverCompletion { if (![self isCancelled]) [_delegate curlTransferDidFinish:self]; }
- (BOOL)receiveHeader:(NSData *)data {
    if ([self isCancelled]) return NO;
    NSString *line = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if ([line hasPrefix:@"HTTP/"]) {
        NSArray *pieces = [line componentsSeparatedByString:@" "];
        _status = [pieces count] > 1 ? [[pieces objectAtIndex:1] integerValue] : 0;
        [_responseHeaders removeAllObjects];
    } else if ([line isEqual:@"\r\n"] || [line isEqual:@"\n"]) {
        if (_status >= 200 && _status < 300 && !_sentResponse) {
            _sentResponse = YES;
            RCCurlResponse *response = [[RCCurlResponse alloc] initWithURL:_currentURL status:_status headers:_responseHeaders];
            [self performSelectorOnMainThread:@selector(deliverResponse:) withObject:response waitUntilDone:YES];
            [response release];
        }
    } else {
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location != NSNotFound) {
            NSString *key = [line substringToIndex:separator.location];
            NSString *value = [[line substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            // Set-Cookie is handled by libcurl's cookie engine, not this display dictionary.
            [_responseHeaders setObject:value forKey:key];
        }
    }
    return ![self isCancelled];
}
- (BOOL)receiveData:(NSData *)data {
    if ([self isCancelled]) return NO;
    if (_status >= 200 && _status < 300 && _sentResponse) {
        [self performSelectorOnMainThread:@selector(deliverData:) withObject:data waitUntilDone:YES];
    }
    return ![self isCancelled];
}
- (void)run {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CURL *curl = curl_easy_init();
    NSError *failure = nil;
    NSString *caPath = @"/Library/Application Support/Receptor/cacert.pem";
    if (!curl || ![[NSFileManager defaultManager] fileExistsAtPath:caPath]) failure = RCError(@"The modern HTTPS transport or CA bundle is missing. Reinstall Receptor.");
    if (!failure) {
        char errorBuffer[CURL_ERROR_SIZE] = {0};
        curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errorBuffer);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        curl_easy_setopt(curl, CURLOPT_PROXY, "");
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 30L);
        curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, 1L);
        curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, 60L);
        curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
        curl_easy_setopt(curl, CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2);
        curl_easy_setopt(curl, CURLOPT_CAINFO, [caPath fileSystemRepresentation]);
        curl_easy_setopt(curl, CURLOPT_COOKIEFILE, "");
        curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "identity");
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, RCHeaderCallback);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, self);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, RCDataCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, self);
        curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
        curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, RCProgressCallback);
        curl_easy_setopt(curl, CURLOPT_XFERINFODATA, self);
        NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:[_request allHTTPHeaderFields] ?: [NSDictionary dictionary]];
        if (!RCHeader(headers, @"Cookie")) {
            NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[_request URL]];
            [headers addEntriesFromDictionary:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies ?: [NSArray array]]];
        }
        _currentURL = [[_request URL] retain];
        _responseHeaders = [[NSMutableDictionary alloc] init];
        for (NSUInteger hop = 0; hop <= 10 && ![self isCancelled]; ++hop) {
            _status = 0; _sentResponse = NO; [_responseHeaders removeAllObjects];
            errorBuffer[0] = 0;
            struct curl_slist *list = NULL;
            for (NSString *key in headers) {
                NSString *lower = [key lowercaseString];
                if ([lower isEqual:@"host"] || [lower isEqual:@"content-length"] || [lower isEqual:@"transfer-encoding"] ||
                    [lower isEqual:@"connection"] || [lower isEqual:@"range"] || [lower isEqual:@"accept-encoding"] ||
                    [lower isEqual:@"proxy-authorization"]) continue;
                NSString *line = [NSString stringWithFormat:@"%@: %@", key, [headers objectForKey:key]];
                if ([line rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location == NSNotFound) list = curl_slist_append(list, [line UTF8String]);
            }
            curl_easy_setopt(curl, CURLOPT_HTTPHEADER, list);
            curl_easy_setopt(curl, CURLOPT_URL, [[_currentURL absoluteString] UTF8String]);
            CURLcode result = curl_easy_perform(curl);
            curl_easy_setopt(curl, CURLOPT_HTTPHEADER, NULL);
            curl_slist_free_all(list);
            if ([self isCancelled]) break;
            if (result != CURLE_OK) {
                NSString *detail = [NSString stringWithUTF8String:errorBuffer[0] ? errorBuffer : curl_easy_strerror(result)];
                failure = RCError([NSString stringWithFormat:@"Download failed at %@ (curl %d): %@", [_currentURL host], (int)result, detail]);
                break;
            }
            if (_status >= 300 && _status < 400) {
                NSString *location = RCHeader(_responseHeaders, @"Location");
                NSURL *next = [location length] ? [[NSURL URLWithString:location relativeToURL:_currentURL] absoluteURL] : nil;
                if (hop == 10 || !next || !RCIsDownloadRequest([NSURLRequest requestWithURL:next])) { failure = RCError(@"Too many redirects or an unsupported redirect target."); break; }
                if ([[[_currentURL scheme] lowercaseString] isEqual:@"https"] && ![[[next scheme] lowercaseString] isEqual:@"https"]) { failure = RCError(@"An HTTPS to HTTP downgrade was blocked."); break; }
                if (!RCSameOrigin(_currentURL, next)) {
                    // The build omits libpsl. Do not carry a server's cookie jar to
                    // another origin, where public-suffix scoping cannot be checked.
                    curl_easy_setopt(curl, CURLOPT_COOKIELIST, "ALL");
                    for (NSString *key in [[[headers allKeys] copy] autorelease]) {
                        NSString *lower = [key lowercaseString];
                        if ([lower isEqual:@"cookie"] || [lower isEqual:@"authorization"] || [lower isEqual:@"proxy-authorization"] || [lower isEqual:@"referer"]) [headers removeObjectForKey:key];
                    }
                }
                [_currentURL release]; _currentURL = [next retain];
                continue;
            }
            if (_status < 200 || _status >= 300 || !_sentResponse) failure = RCError([NSString stringWithFormat:@"The server returned HTTP %ld.", (long)_status]);
            break;
        }
    }
    if (curl) curl_easy_cleanup(curl);
    if (![self isCancelled]) {
        if (failure) [self performSelectorOnMainThread:@selector(deliverError:) withObject:failure waitUntilDone:YES];
        else [self performSelectorOnMainThread:@selector(deliverCompletion) withObject:nil waitUntilDone:YES];
    }
    [_delegate release]; _delegate = nil; // Break the task/transport cycle after the worker stops.
    [pool drain];
}
- (void)dealloc {
    [_delegate release]; [_request release]; [_currentURL release]; [_responseHeaders release];
    [super dealloc];
}
@end
