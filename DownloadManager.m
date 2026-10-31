#import "DownloadManager.h"
#import "ReceptorPaths.h"
#import "ReceptorUI.h"
#import "RCCurlTransfer.h"
#import <MobileCoreServices/UTType.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <signal.h>

@class RCDownloadTask;
@interface DownloadManager (Internal)
- (void)task:(RCDownloadTask *)task finishedWithError:(NSError *)error;
- (NSArray *)localDownloads;
- (void)publishDownloads;
@end

@interface RCDownloadTask : NSObject <RCCurlTransferDelegate> {
@public
    NSString *_identifier;
    NSString *_name;
    long long _received;
    long long _expected;
@private
    DownloadManager *_manager; // process-lifetime singleton, does not retain tasks via this pointer
    RCCurlTransfer *_transfer;
    NSString *_temporaryPath;
    int _fd;
    UIBackgroundTaskIdentifier _backgroundTask;
    BOOL _finished;
    BOOL _hasResponse;
    BOOL _ownsTemporaryFile;
    BOOL _checkResponseLength;
    NSTimeInterval _lastUpdate;
}
- (id)initWithManager:(DownloadManager *)manager;
- (BOOL)start:(NSURLRequest *)request error:(NSError **)error;
- (void)finish:(NSError *)error;
@end

@implementation RCDownloadTask
- (id)initWithManager:(DownloadManager *)manager {
    if ((self = [super init])) {
        _manager = manager;
        _fd = -1;
        _expected = -1;
        _backgroundTask = UIBackgroundTaskInvalid;
        _identifier = [[[NSProcessInfo processInfo] globallyUniqueString] copy];
    }
    return self;
}
- (BOOL)start:(NSURLRequest *)request error:(NSError **)error {
    _name = [RCSafeFilename([[[request URL] path] lastPathComponent]) copy];
    _temporaryPath = [[RCDownloadsDirectory stringByAppendingPathComponent:
        [NSString stringWithFormat:@".%@.part", _identifier]] copy];
    _fd = open([_temporaryPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (_fd < 0) {
        if (error) *error = RCError([NSString stringWithFormat:@"Cannot create download: %s", strerror(errno)]);
        return NO;
    }
    _ownsTemporaryFile = YES;
    NSMutableURLRequest *copy = [[request mutableCopy] autorelease];
    [copy setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [copy setTimeoutInterval:60.0];
    [copy setHTTPShouldHandleCookies:YES];
    [copy setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    // A new transfer always starts at byte zero.
    [copy setValue:nil forHTTPHeaderField:@"Range"];
    [copy setValue:nil forHTTPHeaderField:@"If-Range"];
    [copy setValue:nil forHTTPHeaderField:@"If-None-Match"];
    [copy setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
    _transfer = [[RCCurlTransfer alloc] initWithRequest:copy delegate:self];
    if (!_transfer) {
        if (error) *error = RCError(@"Unable to start the network connection.");
        return NO;
    }
    // The system grants finite execution time, not a persistent background session.
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self finish:RCError(@"Background time expired. Keep Safari open and retry the download.")];
    }];
    [_transfer start];
    return YES;
}
- (void)curlTransfer:(RCCurlTransfer *)connection didReceiveResponse:(NSURLResponse *)response {
    (void)connection;
    if (_finished) return;
    if (![response respondsToSelector:@selector(statusCode)] || ![response respondsToSelector:@selector(allHeaderFields)]) {
        [self finish:RCError(@"The server did not return an HTTP response.")]; return;
    }
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (status < 200 || status >= 300 || status == 206) {
        [self finish:RCError([NSString stringWithFormat:@"The server returned HTTP %ld.", (long)status])]; return;
    }
    // Multipart responses must not append unrelated data to an existing transfer.
    if (_hasResponse || ftruncate(_fd, 0) != 0 || lseek(_fd, 0, SEEK_SET) < 0) {
        [self finish:RCError(@"Unable to initialize the response file.")]; return;
    }
    _hasResponse = YES;
    _expected = [response expectedContentLength];
    _checkResponseLength = _expected >= 0;
    NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
    for (NSString *key in headers) {
        if ([key caseInsensitiveCompare:@"Content-Encoding"] == NSOrderedSame) {
            NSString *encoding = [[[headers objectForKey:key] description]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([encoding length] && [encoding caseInsensitiveCompare:@"identity"] != NSOrderedSame) {
                // Foundation delivers decompressed bytes; wire Content-Length is not comparable.
                _checkResponseLength = NO;
            }
        }
    }
    NSString *name = RCSafeFilename([response suggestedFilename]);
    if (![[name pathExtension] length] && [[response MIMEType] length]) {
        CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType,
            (CFStringRef)[response MIMEType], NULL);
        CFStringRef ext = uti ? UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension) : NULL;
        if (ext) { name = RCSafeFilename([name stringByAppendingPathExtension:(NSString *)ext]); CFRelease(ext); }
        if (uti) CFRelease(uti);
    }
    [_name release]; _name = [name copy];
}
- (void)curlTransfer:(RCCurlTransfer *)connection didReceiveData:(NSData *)data {
    (void)connection;
    if (_finished) return;
    if (!_hasResponse) { [self finish:RCError(@"Received data without a valid response.")]; return; }
    const unsigned char *bytes = [data bytes];
    NSUInteger remaining = [data length];
    while (remaining) {
        ssize_t count = write(_fd, bytes, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            [self finish:RCError([NSString stringWithFormat:@"Cannot save download: %s", strerror(errno)])]; return;
        }
        remaining -= (NSUInteger)count; bytes += count; _received += count;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastUpdate >= 0.5) {
        _lastUpdate = now;
        [[NSNotificationCenter defaultCenter] postNotificationName:RCDownloadsChangedNotification object:_manager];
    }
}
- (void)curlTransfer:(RCCurlTransfer *)connection didFailWithError:(NSError *)error {
    (void)connection; [self finish:error];
}
- (void)curlTransferDidFinish:(RCCurlTransfer *)connection {
    (void)connection;
    if (_finished) return;
    if (!_hasResponse) { [self finish:RCError(@"The server returned no response.")]; return; }
    if (_checkResponseLength && _received != _expected) {
        [self finish:RCError(@"The download ended with an unexpected file length.")]; return;
    }
    if (fsync(_fd) != 0) { [self finish:RCError(@"Unable to flush the download to disk.")]; return; }
    int result = close(_fd); _fd = -1;
    if (result != 0) { [self finish:RCError(@"Unable to close the downloaded file.")]; return; }
    NSString *base = [_name stringByDeletingPathExtension];
    NSString *ext = [_name pathExtension];
    for (NSUInteger i = 0; i < 10000; ++i) {
        NSString *candidate = _name;
        if (i) {
            candidate = [NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)i];
            if ([ext length]) candidate = [candidate stringByAppendingPathExtension:ext];
        }
        NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:candidate];
        // Atomic no-clobber publish on the same filesystem; never replace existing files/symlinks.
        if (link([_temporaryPath fileSystemRepresentation], [path fileSystemRepresentation]) == 0) {
            NSString *publishedName = [candidate copy];
            [_name release]; _name = publishedName;
            [self finish:nil]; return;
        }
        if (errno != EEXIST) { [self finish:RCError(@"Unable to publish the downloaded file.")]; return; }
    }
    [self finish:RCError(@"Too many files with this name.")];
}
- (void)finish:(NSError *)error {
    if (_finished) return;
    [self retain]; // Removing the manager's ownership and connection delegate can release us.
    _finished = YES;
    [_transfer cancel]; [_transfer release]; _transfer = nil;
    if (_fd >= 0) { close(_fd); _fd = -1; }
    if (_ownsTemporaryFile) { unlink([_temporaryPath fileSystemRepresentation]); _ownsTemporaryFile = NO; }
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        UIBackgroundTaskIdentifier task = _backgroundTask;
        _backgroundTask = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask:task];
    }
    [_manager task:self finishedWithError:error];
    [self autorelease];
}
- (void)dealloc {
    [_transfer cancel]; [_transfer release];
    if (_fd >= 0) close(_fd);
    if (_ownsTemporaryFile) unlink([_temporaryPath fileSystemRepresentation]);
    [_temporaryPath release]; [_identifier release]; [_name release];
    [super dealloc];
}
@end

@implementation DownloadManager
+ (DownloadManager *)sharedManager {
    NSAssert([NSThread isMainThread], @"DownloadManager must run on the main thread");
    static DownloadManager *manager = nil;
    if (!manager) manager = [[self alloc] init];
    return manager;
}
- (id)init {
    if ((self = [super init])) {
        _tasks = [[NSMutableArray alloc] init];
        _statusTimer = [[NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(poll:) userInfo:nil repeats:YES] retain];
        [[NSRunLoop mainRunLoop] addTimer:_statusTimer forMode:NSRunLoopCommonModes];
    }
    return self;
}
- (BOOL)startDownloadWithRequest:(NSURLRequest *)request error:(NSError **)error {
    NSAssert([NSThread isMainThread], @"Main thread required");
    if (!RCIsDownloadRequest(request)) {
        if (error) *error = RCError(@"Only HTTP and HTTPS GET downloads are supported."); return NO;
    }
    if ([_tasks count] >= 3) {
        if (error) *error = RCError(@"Three downloads are already running. Wait or cancel one in Files."); return NO;
    }
    if (!RCEnsureDownloadsDirectory(error)) return NO;
    RCDownloadTask *task = [[RCDownloadTask alloc] initWithManager:self];
    [_tasks addObject:task];
    BOOL started = [task start:request error:error];
    if (!started) [_tasks removeObjectIdenticalTo:task];
    [task release];
    [self publishDownloads];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCDownloadsChangedNotification object:self];
    return started;
}
- (NSArray *)localDownloads {
    NSMutableArray *result = [NSMutableArray array];
    for (RCDownloadTask *task in _tasks) {
        [result addObject:[NSDictionary dictionaryWithObjectsAndKeys:task->_identifier, @"identifier",
            task->_name, @"name", [NSNumber numberWithLongLong:task->_received], @"received",
            [NSNumber numberWithLongLong:task->_expected], @"expected",
            [NSNumber numberWithInt:getpid()], @"ownerPID",
            [[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.receptor.app"] ? @"Receptor" : @"Safari", @"source", nil]];
    }
    return result;
}
- (void)publishDownloads {
    if (!RCEnsureDownloadsDirectory(NULL)) return;
    BOOL app = [[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.receptor.app"];
    NSString *name = app ? @".status-App.plist" : @".status-Safari.plist";
    NSDictionary *snapshot = [NSDictionary dictionaryWithObjectsAndKeys:[self localDownloads], @"tasks",
        [NSDate date], @"updated", [NSNumber numberWithInt:getpid()], @"pid", nil];
    [snapshot writeToFile:[RCDownloadsDirectory stringByAppendingPathComponent:name] atomically:YES];
}
- (NSArray *)activeDownloads {
    NSMutableArray *result = [NSMutableArray arrayWithArray:[self localDownloads]];
    BOOL app = [[[NSBundle mainBundle] bundleIdentifier] isEqual:@"com.receptor.app"];
    NSString *name = app ? @".status-Safari.plist" : @".status-App.plist";
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:[RCDownloadsDirectory stringByAppendingPathComponent:name]];
    NSDate *updated = [snapshot objectForKey:@"updated"];
    int pid = [[snapshot objectForKey:@"pid"] intValue];
    NSArray *tasks = [snapshot objectForKey:@"tasks"];
    if ([updated isKindOfClass:[NSDate class]] && [updated timeIntervalSinceNow] > -30 && pid > 0 &&
        (kill(pid, 0) == 0 || errno == EPERM) && [tasks isKindOfClass:[NSArray class]]) {
        for (id value in tasks) {
            if (![value isKindOfClass:[NSDictionary class]]) continue;
            NSString *identifier = [value objectForKey:@"identifier"];
            if (![identifier isKindOfClass:[NSString class]] || ![identifier length] ||
                ![[value objectForKey:@"name"] isKindOfClass:[NSString class]]) continue;
            [result addObject:value];
        }
    }
    return result;
}
- (void)poll:(NSTimer *)timer {
    (void)timer;
    for (RCDownloadTask *task in [[_tasks copy] autorelease]) {
        NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@".cancel-%@.plist", RCSafeFilename(task->_identifier)]];
        NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([[request objectForKey:@"identifier"] isEqual:task->_identifier] && [[request objectForKey:@"ownerPID"] intValue] == getpid()) {
            unlink([path fileSystemRepresentation]);
            [task finish:RCError(@"Download cancelled.")];
        }
    }
    [self publishDownloads];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCDownloadsChangedNotification object:self];
}
- (void)cancelDownloadWithIdentifier:(NSString *)identifier {
    for (RCDownloadTask *task in [[_tasks copy] autorelease]) {
        if ([task->_identifier isEqual:identifier]) { [task finish:RCError(@"Download cancelled.")]; return; }
    }
    for (NSDictionary *task in [self activeDownloads]) {
        if ([[task objectForKey:@"identifier"] isEqual:identifier]) {
            NSString *path = [RCDownloadsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@".cancel-%@.plist", RCSafeFilename(identifier)]];
            [task writeToFile:path atomically:YES];
            return;
        }
    }
}
- (void)task:(RCDownloadTask *)task finishedWithError:(NSError *)error {
    NSString *message = error ? [error localizedDescription] : [NSString stringWithFormat:@"Saved %@", task->_name];
    [_tasks removeObjectIdenticalTo:task];
    [self publishDownloads];
    [[NSNotificationCenter defaultCenter] postNotificationName:RCDownloadsChangedNotification object:self];
    [[ReceptorUI sharedUI] showMessage:message];
}
- (void)dealloc { [_statusTimer invalidate]; [_statusTimer release]; [_tasks release]; [super dealloc]; }
@end
