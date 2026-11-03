/* Fixed APT/source operations. No shell, arbitrary paths, apt options or commands. */
#import <Foundation/Foundation.h>
#ifndef RC_PACKAGE_TEST
#import <CoreFoundation/CoreFoundation.h>
#endif
#if defined(RC_PACKAGE_TEST) && defined(__APPLE__)
#error Host test mode must never ship on a device.
#endif
#ifdef RC_PACKAGE_TEST
#define RC_HELPER_TEST 1
#include <openssl/sha.h>
#define CC_SHA256 SHA256
#define CC_SHA256_DIGEST_LENGTH SHA256_DIGEST_LENGTH
#endif
#define main RCUnusedInstallerMain
#include "receptor-deb-helper.c"
#undef main

static NSString *Path(NSString *path) {
#ifdef RC_PACKAGE_TEST
    return [@RC_PKG_TEST_ROOT stringByAppendingString:path];
#else
    return path;
#endif
}
static void Require(BOOL condition, NSString *message) { if (!condition) [NSException raise:@"ReceptorPackageError" format:@"%@", message]; }
static NSString *Digest(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256([data bytes], (unsigned int)[data length], hash);
    NSMutableString *text = [NSMutableString string]; for (NSUInteger i = 0; i < sizeof(hash); i++) [text appendFormat:@"%02x", hash[i]]; return text;
}
static NSData *ReadFile(NSString *path, NSUInteger limit, BOOL optional) {
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW | O_NONBLOCK); struct stat info;
    if (fd < 0 && errno == ENOENT && optional) return nil;
    Require(fd >= 0, [@"Cannot read " stringByAppendingString:path]);
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_nlink != 1 || info.st_size < 0 || (unsigned long long)info.st_size > limit) { close(fd); Require(NO, @"Unexpected file type or size."); }
    NSMutableData *data = [NSMutableData data]; unsigned char bytes[16384]; ssize_t count;
    while ((count = read(fd, bytes, sizeof(bytes))) != 0) {
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 || [data length] + (NSUInteger)count > limit) { close(fd); Require(NO, @"Cannot read a bounded file snapshot."); }
        [data appendBytes:bytes length:(NSUInteger)count];
    }
    close(fd); return data;
}
static NSString *Text(NSData *data) {
    if (!data) return @"";
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return text ?: [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
}
static BOOL Identifier(NSString *value) {
    if ([value length] < 2 || [value length] > 160 || [value hasPrefix:@"-"] || [value hasSuffix:@"-"] || [value hasSuffix:@"+"]) return NO;
    if ([[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"] characterIsMember:[value characterAtIndex:0]] == NO) return NO;
    return [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789+.-"] invertedSet]].location == NSNotFound;
}
static NSArray *Records(NSString *text) {
    NSMutableArray *records = [NSMutableArray array]; NSMutableDictionary *record = [NSMutableDictionary dictionary]; NSString *previous = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (![line length]) { if ([record count]) [records addObject:[NSDictionary dictionaryWithDictionary:record]]; [record removeAllObjects]; previous = nil; continue; }
        if (([line hasPrefix:@" "] || [line hasPrefix:@"\t"]) && previous) { [record setObject:[[record objectForKey:previous] stringByAppendingFormat:@"\n%@", line] forKey:previous]; continue; }
        NSRange colon = [line rangeOfString:@": "]; if (colon.location == NSNotFound) continue;
        previous = [line substringToIndex:colon.location]; [record setObject:[line substringFromIndex:colon.location + 2] forKey:previous];
    }
    if ([record count]) [records addObject:record]; return records;
}
static NSArray *Installed(void) { return Records(Text(ReadFile(Path(@"/var/lib/dpkg/status"), 32 * 1024 * 1024, NO))); }
static BOOL Protected(NSString *identifier, NSArray *installed) {
    identifier = [[identifier componentsSeparatedByString:@":"] objectAtIndex:0];
    NSArray *fixed = [NSArray arrayWithObjects:@"cydia", @"dpkg", @"firmware", @"mobilesubstrate", @"com.saurik.substrate.safemode", @"launchctl", @"uikittools", @"base", @"essential", @"bash", @"coreutils", @"com.receptor.downloadmanager", nil];
    if ([fixed containsObject:identifier] || [identifier hasPrefix:@"apt"] || [identifier hasPrefix:@"libapt"]) return YES;
    for (NSDictionary *record in installed) if ([[record objectForKey:@"Package"] isEqual:identifier])
        return [[record objectForKey:@"Essential"] isEqual:@"yes"] || [[record objectForKey:@"Priority"] isEqual:@"required"];
    return NO;
}
static NSDictionary *Run(NSString *binary, NSArray *arguments) {
    Require(access([binary fileSystemRepresentation], X_OK) == 0, @"APT command-line tools are missing. Install APT 0.7 Strict (apt7), or the compatible apt package, through Cydia first.");
    NSString *template = [Path(@"/var/tmp") stringByAppendingPathComponent:@"receptor-apt.XXXXXX"];
    char *temporary = strdup([template fileSystemRepresentation]); int fd = temporary ? mkstemp(temporary) : -1;
    Require(fd >= 0, @"Cannot create private package-manager output."); unlink(temporary); free(temporary); cloexec(fd);
    pid_t child = fork();
    if (child < 0) { close(fd); Require(NO, @"Cannot start APT."); }
    if (child == 0) {
        int input = open("/dev/null", O_RDONLY);
        if (input < 0 || dup2(input, 0) < 0 || dup2(fd, 1) < 0 || dup2(fd, 2) < 0) _exit(126);
        char **argv = calloc([arguments count] + 2, sizeof(char *)); if (!argv) _exit(126);
        argv[0] = (char *)[binary fileSystemRepresentation];
        for (NSUInteger i = 0; i < [arguments count]; i++) argv[i + 1] = (char *)[[arguments objectAtIndex:i] UTF8String];
        char *environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/var/root", "USER=root", "LOGNAME=root", "LANG=C", "LC_ALL=C", "DEBIAN_FRONTEND=noninteractive", NULL};
        execve(argv[0], argv, environment); _exit(127);
    }
    int status = 0; pid_t waited;
    do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
    off_t size = lseek(fd, 0, SEEK_END); BOOL truncated = size > 256 * 1024;
    lseek(fd, truncated ? size - 256 * 1024 : 0, SEEK_SET);
    NSMutableData *data = [NSMutableData data]; char bytes[16384]; off_t remaining = size < 256 * 1024 ? size : 256 * 1024;
    while (remaining > 0) { ssize_t count = read(fd, bytes, remaining < (off_t)sizeof(bytes) ? (size_t)remaining : sizeof(bytes)); if (count < 0 && errno == EINTR) continue; if (count <= 0) break; [data appendBytes:bytes length:(NSUInteger)count]; remaining -= count; } close(fd);
    return [NSDictionary dictionaryWithObjectsAndKeys:Text(data) ?: @"", @"output", [NSNumber numberWithInt:waited == child && WIFEXITED(status) ? WEXITSTATUS(status) : 2], @"status", [NSNumber numberWithBool:truncated], @"truncated", nil];
}
static NSString *URL(NSString *input) {
    Require([input length] > 0 && [input length] <= 1024 && [input canBeConvertedToEncoding:NSASCIIStringEncoding], @"Enter an ASCII HTTP(S) repository URL.");
    Require([input rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound && [input rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound && [input rangeOfString:@"#"].location == NSNotFound, @"Repository URLs cannot contain whitespace or fragments.");
    NSURL *url = [NSURL URLWithString:input]; NSString *scheme = [[url scheme] lowercaseString];
    Require(([scheme isEqual:@"http"] || [scheme isEqual:@"https"]) && [[url host] length] && ![url user] && ![url password] && ![url query], @"Use an HTTP(S) source without credentials or a query.");
    return [input hasSuffix:@"/"] ? input : [input stringByAppendingString:@"/"];
}
/* This file is deliberately separate from Cydia's generated cydia.list.
 * Cydia's APT loader reads additional .list files as well as its own sources. */
static NSArray *SourceFiles(void) {
    NSMutableArray *files = [NSMutableArray arrayWithObject:Path(@"/etc/apt/sources.list")];
    NSString *directory = Path(@"/etc/apt/sources.list.d");
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) if ([name hasSuffix:@".list"] && ![name hasPrefix:@"."] && [name rangeOfString:@"/"].location == NSNotFound) [files addObject:[directory stringByAppendingPathComponent:name]];
    return files;
}
static NSArray *Sources(void) {
    NSMutableArray *sources = [NSMutableArray array];
    for (NSString *path in SourceFiles()) {
        NSString *actual = path;
        if ([[path lastPathComponent] isEqual:@"cydia.list"]) {
            struct stat info; if (lstat([path fileSystemRepresentation], &info) == 0 && S_ISLNK(info.st_mode)) {
                char link[PATH_MAX]; ssize_t length = readlink([path fileSystemRepresentation], link, sizeof(link) - 1);
                Require(length > 0, @"Cannot read Cydia source link."); link[length] = 0;
                NSString *target = [NSString stringWithUTF8String:link];
                if ([target hasPrefix:@"/private/var/"]) target = [target substringFromIndex:8];
                Require([[NSArray arrayWithObjects:@"/var/mobile/Library/Caches/com.saurik.Cydia/sources.list", @"/var/root/Library/Caches/com.saurik.Cydia/sources.list", @"/var/lib/cydia/sources.list", nil] containsObject:target], @"Unexpected Cydia source link; leave it unchanged.");
                actual = Path(target);
            }
        }
        NSData *data = ReadFile(actual, 1024 * 1024, YES); if (!data) continue;
        for (NSString *line in [Text(data) componentsSeparatedByString:@"\n"]) {
            NSArray *raw = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray *parts = [NSMutableArray array]; for (NSString *part in raw) if ([part length]) [parts addObject:part];
            if ([parts count] < 3 || ![[parts objectAtIndex:0] isEqual:@"deb"]) continue;
            NSString *name = [parts objectAtIndex:1];
            NSString *identity = Digest([[path stringByAppendingFormat:@"\n%@", line] dataUsingEncoding:NSUTF8StringEncoding]);
            [sources addObject:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", line, @"line", path, @"file", actual, @"actual", identity, @"id", [NSNumber numberWithBool:[[path lastPathComponent] isEqual:@"receptor.list"]], @"managed", nil]];
        }
    }
    return sources;
}
static void CydiaClosed(void) {
#ifndef RC_PACKAGE_TEST
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0}; size_t length = 0;
    Require(sysctl(mib, 4, NULL, &length, NULL, 0) == 0 && length < 16 * 1024 * 1024, @"Cannot check whether Cydia is closed.");
    struct kinfo_proc *processes = malloc(length + 4096); Require(processes != NULL, @"Cannot inspect package-manager state."); length += 4096;
    if (sysctl(mib, 4, processes, &length, NULL, 0)) { free(processes); Require(NO, @"Cannot check whether Cydia is closed. Retry."); }
    BOOL open = NO; for (size_t i = 0; i < length / sizeof(*processes); i++) if (!strcmp(processes[i].kp_proc.p_comm, "Cydia")) open = YES;
    free(processes); Require(!open, @"Fully close Cydia in the app switcher before changing sources or packages in Receptor.");
#endif
}
static void Atomic(NSString *path, NSData *data) {
    struct stat original; BOOL existed = lstat([path fileSystemRepresentation], &original) == 0;
    Require(!existed || (S_ISREG(original.st_mode) && original.st_nlink == 1), @"Refusing an unsafe configuration file.");
    char *temporary = strdup([[path stringByAppendingString:@".XXXXXX"] fileSystemRepresentation]); int fd = temporary ? mkstemp(temporary) : -1;
    Require(fd >= 0, @"Cannot stage source configuration."); BOOL valid = YES; const unsigned char *bytes = [data bytes]; NSUInteger remaining = [data length];
    while (remaining) { ssize_t count = write(fd, bytes, remaining); if (count < 0 && errno == EINTR) continue; if (count <= 0) { valid = NO; break; } bytes += count; remaining -= (NSUInteger)count; }
    if (existed && fchown(fd, original.st_uid, original.st_gid)) valid = NO;
    if (fchmod(fd, existed ? original.st_mode & 0777 : 0600) || fsync(fd)) valid = NO; close(fd);
    if (valid && rename(temporary, [path fileSystemRepresentation])) valid = NO;
    if (!valid) unlink(temporary); free(temporary); Require(valid, @"Could not atomically save source configuration.");
}
static NSString *PrivateDirectory(void) {
    NSString *path = Path(@"/var/lib/receptor"); struct stat info;
    if (mkdir([path fileSystemRepresentation], 0700) && errno != EEXIST) Require(NO, @"Cannot create private package-manager state.");
    Require(!lstat([path fileSystemRepresentation], &info) && S_ISDIR(info.st_mode) && info.st_uid == geteuid() && !(info.st_mode & 077), @"The package-state directory is unsafe."); return path;
}
static void Journal(NSDictionary *result) {
    NSError *error = nil; NSData *data = [NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    Require(data != nil, @"Cannot serialize the operation journal."); Atomic([PrivateDirectory() stringByAppendingPathComponent:@"last-operation.plist"], data);
}
static void SyncCydiaPreferences(NSData *data, NSString *user) {
#ifndef RC_PACKAGE_TEST
    if (!data) return;
    NSError *error = nil; NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    id sources = [plist objectForKey:@"CydiaSources"]; if (!sources) return;
    CFPreferencesSetValue(CFSTR("CydiaSources"), (CFPropertyListRef)sources, CFSTR("com.saurik.Cydia"), (CFStringRef)user, kCFPreferencesAnyHost);
    Require(CFPreferencesSynchronize(CFSTR("com.saurik.Cydia"), (CFStringRef)user, kCFPreferencesAnyHost), @"Could not synchronize Cydia’s preferences. Source files were rolled back; keep Cydia closed and retry.");
#else
    (void)data; (void)user;
#endif
}
static void RemoveSource(NSString *identity) {
    NSArray *allSources = Sources();
    NSDictionary *selected = nil; for (NSDictionary *source in allSources) if ([[source objectForKey:@"id"] isEqual:identity]) selected = source;
    Require(selected != nil, @"The source list changed. Reload it and select the source again.");
    NSMutableDictionary *oldFiles = [NSMutableDictionary dictionary], *newFiles = [NSMutableDictionary dictionary];
    NSString *path = [selected objectForKey:@"actual"], *line = [selected objectForKey:@"line"];
    NSData *old = ReadFile(path, 1024 * 1024, NO); NSMutableArray *lines = [NSMutableArray arrayWithArray:[Text(old) componentsSeparatedByString:@"\n"]]; [lines removeObject:line];
    [oldFiles setObject:old forKey:path]; [newFiles setObject:[[lines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] forKey:path];
    if ([[[selected objectForKey:@"file"] lastPathComponent] isEqual:@"cydia.list"]) {
        BOOL metadata = NO;
        for (NSString *relative in [NSArray arrayWithObjects:@"/var/mobile/Library/Preferences/com.saurik.Cydia.plist", @"/var/root/Library/Preferences/com.saurik.Cydia.plist", @"/var/lib/cydia/metadata.plist", nil]) {
            NSString *file = Path(relative); NSData *data = ReadFile(file, 8 * 1024 * 1024, YES); if (!data) continue;
            NSError *error = nil; id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:&error];
            Require([plist isKindOfClass:[NSMutableDictionary class]], @"Unrecognized Cydia source metadata; nothing was changed.");
            NSString *key = [relative hasSuffix:@"metadata.plist"] ? @"Sources" : @"CydiaSources"; id sources = [plist objectForKey:key]; if (!sources) continue;
            Require([sources isKindOfClass:[NSMutableDictionary class]], @"Unrecognized Cydia sources; nothing was changed.");
            NSMutableArray *remove = [NSMutableArray array];
            for (id sourceKey in sources) { id record = [sources objectForKey:sourceKey]; if ([record isKindOfClass:[NSDictionary class]] && [[record objectForKey:@"URI"] isEqual:[selected objectForKey:@"name"]]) [remove addObject:sourceKey]; }
            if (![remove count]) continue; metadata = YES; [sources removeObjectsForKeys:remove];
            error = nil; NSData *updated = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error]; Require(updated != nil, @"Cannot serialize Cydia source metadata.");
            [oldFiles setObject:data forKey:file]; [newFiles setObject:updated forKey:file];
        }
        Require(metadata, @"Cydia’s metadata layout is not recognized. This source was left unchanged.");
        // A Cydia URI can own multiple distributions. Keep its generated file consistent.
        NSMutableArray *kept = [NSMutableArray array]; for (NSString *candidate in [Text(old) componentsSeparatedByString:@"\n"]) {
            BOOL sameURI = NO; for (NSDictionary *source in allSources) if ([[source objectForKey:@"actual"] isEqual:path] && [[source objectForKey:@"name"] isEqual:[selected objectForKey:@"name"]] && [[source objectForKey:@"line"] isEqual:candidate]) sameURI = YES;
            if (!sameURI) [kept addObject:candidate];
        }
        [newFiles setObject:[[kept componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] forKey:path];
    }
    NSString *backupDirectory = PrivateDirectory();
    NSError *serializationError = nil; NSData *backup = [NSPropertyListSerialization dataWithPropertyList:oldFiles format:NSPropertyListXMLFormat_v1_0 options:0 error:&serializationError];
    Require(backup != nil, @"Cannot serialize source backups."); Atomic([backupDirectory stringByAppendingPathComponent:@"last-source-removal.plist"], backup);
    NSMutableArray *written = [NSMutableArray array];
    NSString *preferences = Path(@"/var/mobile/Library/Preferences/com.saurik.Cydia.plist");
    NSString *rootPreferences = Path(@"/var/root/Library/Preferences/com.saurik.Cydia.plist");
    @try { for (NSString *file in [[newFiles allKeys] sortedArrayUsingSelector:@selector(compare:)]) { Atomic(file, [newFiles objectForKey:file]); [written addObject:file]; } SyncCydiaPreferences([newFiles objectForKey:preferences], @"mobile"); SyncCydiaPreferences([newFiles objectForKey:rootPreferences], @"root"); }
    @catch (NSException *exception) {
        for (NSString *file in written) { @try { Atomic(file, [oldFiles objectForKey:file]); } @catch (NSException *rollback) { (void)rollback; } }
        @try { SyncCydiaPreferences([oldFiles objectForKey:preferences], @"mobile"); SyncCydiaPreferences([oldFiles objectForKey:rootPreferences], @"root"); } @catch (NSException *rollback) { (void)rollback; }
        @throw exception;
    }
}
static void WriteManagedSource(NSString *uri, BOOL remove) {
    uri = URL(uri); NSString *path = Path(@"/etc/apt/sources.list.d/receptor.list");
    NSData *old = ReadFile(path, 1024 * 1024, YES);
    NSMutableArray *lines = [NSMutableArray array]; NSString *wanted = [NSString stringWithFormat:@"deb %@ ./", uri]; BOOL found = NO;
    for (NSString *line in [Text(old) componentsSeparatedByString:@"\n"]) {
        if ([line isEqual:wanted]) { found = YES; if (remove) continue; }
        if ([line length]) [lines addObject:line];
    }
    Require(!remove || found, @"This source is not in Receptor’s source file.");
    if (!remove && !found) [lines addObject:wanted];
    NSData *data = [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    NSString *temporary = [path stringByAppendingString:@".XXXXXX"]; char *buffer = strdup([temporary fileSystemRepresentation]); int fd = buffer ? mkstemp(buffer) : -1;
    Require(fd >= 0, @"Cannot stage source configuration.");
    const unsigned char *bytes = [data bytes]; NSUInteger remaining = [data length]; BOOL valid = YES;
    while (remaining) { ssize_t count = write(fd, bytes, remaining); if (count < 0 && errno == EINTR) continue; if (count <= 0) { valid = NO; break; } bytes += count; remaining -= (NSUInteger)count; }
    if (fchmod(fd, 0644) || fsync(fd)) valid = NO; close(fd);
    if (valid && rename(buffer, [path fileSystemRepresentation])) valid = NO;
    if (!valid) unlink(buffer); free(buffer); Require(valid, @"Could not save sources; the old file was preserved.");
}
static NSDictionary *Execute(NSArray *args) {
    Require([args count] >= 1 && [args count] <= 3, @"Invalid operation arguments.");
    NSString *operation = [args objectAtIndex:0], *value = [args count] > 1 ? [args objectAtIndex:1] : @"";
    if ([operation isEqual:@"last-result"] && [args count] == 1) {
        NSData *data = ReadFile([PrivateDirectory() stringByAppendingPathComponent:@"last-operation.plist"], 4 * 1024 * 1024, YES);
        if (!data) return [NSDictionary dictionaryWithObject:@"No package operation has been recorded yet." forKey:@"output"];
        NSError *error = nil; id result = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
        Require([result isKindOfClass:[NSDictionary class]], @"The operation journal is invalid."); return result;
    }
    if ([operation isEqual:@"sources"] && [args count] == 1) return [NSDictionary dictionaryWithObject:Sources() forKey:@"items"];
    if ([operation isEqual:@"installed"] && [args count] == 1) {
        NSArray *installed = Installed();
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *record in installed) if ([[record objectForKey:@"Status"] isEqual:@"install ok installed"]) {
            NSMutableDictionary *item = [[record mutableCopy] autorelease]; [item setObject:[NSNumber numberWithBool:Protected([record objectForKey:@"Package"], installed)] forKey:@"protected"]; [items addObject:item];
        }
        return [NSDictionary dictionaryWithObject:items forKey:@"items"];
    }
    if ([operation isEqual:@"source-add"] || [operation isEqual:@"source-remove"]) {
        Require([args count] == 2, @"Expected one source argument."); CydiaClosed();
        if ([operation isEqual:@"source-remove"]) RemoveSource(value);
        else { NSString *uri = URL(value); for (NSDictionary *source in Sources()) Require(![[source objectForKey:@"name"] isEqual:uri], @"This source is already present. Nothing was changed."); WriteManagedSource(uri, NO); }
        return [NSDictionary dictionaryWithObject:@"Sources saved. Refresh indexes before searching. Close and reopen Cydia to reload its sources." forKey:@"output"];
    }
    if ([operation isEqual:@"refresh"] && [args count] == 1) { CydiaClosed(); return Run(Path(@"/usr/bin/apt-get"), [NSArray arrayWithObjects:@"-o", @"Acquire::Retries=0", @"-o", @"Acquire::http::Timeout=30", @"update", nil]); }
    if ([operation isEqual:@"search"] && [args count] == 2) {
        Require([value length] >= 2 && [value length] <= 64 && [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_"] invertedSet]].location == NSNotFound, @"Search with 2–64 letters, digits, spaces, hyphens or underscores.");
        NSDictionary *run = Run(Path(@"/usr/bin/apt-cache"), [NSArray arrayWithObjects:@"search", @"--names-only", value, nil]);
        Require(![[run objectForKey:@"status"] intValue] && ![[run objectForKey:@"truncated"] boolValue], [run objectForKey:@"output"]);
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *line in [[run objectForKey:@"output"] componentsSeparatedByString:@"\n"]) {
            NSRange separator = [line rangeOfString:@" - "]; if (separator.location == NSNotFound) continue;
            NSString *identifier = [line substringToIndex:separator.location]; if (!Identifier(identifier)) continue;
            [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:identifier, @"Package", [line substringFromIndex:separator.location + 3], @"Description", nil]];
            if ([items count] == 500) break;
        }
        return [NSDictionary dictionaryWithObjectsAndKeys:items, @"items", @"Up to 500 matches. Refine the search if needed.", @"output", nil];
    }
    Require(Identifier(value), @"Choose an exact package identifier; options and patterns are not accepted.");
    if ([operation isEqual:@"details"] && [args count] == 2) return Run(Path(@"/usr/bin/apt-cache"), [NSArray arrayWithObjects:@"show", value, nil]);
    BOOL remove = [operation hasSuffix:@"remove"], apply = [operation hasPrefix:@"apply-"];
    BOOL unsignedInstall = [operation isEqual:@"apply-unsigned-install"];
    Require([operation isEqual:@"plan-install"] || [operation isEqual:@"plan-remove"] || [operation isEqual:@"apply-install"] || [operation isEqual:@"apply-remove"] || unsignedInstall, @"Unknown operation.");
    Require([args count] == (apply ? 3 : 2), @"Invalid transaction arguments.");
    CydiaClosed();
    NSArray *installed = Installed(); Require(!remove || !Protected(value, installed), @"This system/package-manager component is protected. Use Cydia for advanced system maintenance.");
    NSString *target = value;
    if (!remove) {
        NSDictionary *policy = Run(Path(@"/usr/bin/apt-cache"), [NSArray arrayWithObjects:@"policy", value, nil]); NSString *candidate = nil;
        Require(![[policy objectForKey:@"status"] intValue] && ![[policy objectForKey:@"truncated"] boolValue] && [[policy objectForKey:@"output"] hasPrefix:[value stringByAppendingString:@":\n"]], @"APT did not return a policy for that exact package identifier.");
        for (NSString *line in [[policy objectForKey:@"output"] componentsSeparatedByString:@"\n"]) {
            NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trim hasPrefix:@"Candidate: "]) candidate = [trim substringFromIndex:11];
        }
        Require([candidate length] && ![candidate isEqual:@"(none)"] && [candidate rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.+:~_-"] invertedSet]].location == NSNotFound, @"No exact install candidate. Refresh sources and check the package identifier.");
        target = [value stringByAppendingFormat:@"=%@", candidate];
    } else {
        BOOL exists = NO; for (NSDictionary *record in installed) if ([[record objectForKey:@"Package"] isEqual:value] && [[record objectForKey:@"Status"] isEqual:@"install ok installed"]) exists = YES;
        Require(exists, @"This exact package is not installed.");
    }
    NSMutableArray *command = [NSMutableArray arrayWithObjects:@"-o", unsignedInstall ? @"APT::Get::AllowUnauthenticated=true" : @"APT::Get::AllowUnauthenticated=false", @"-o", @"APT::Get::AutomaticRemove=false", @"-o", @"Dpkg::Options::=--force-confold", @"-o", @"Acquire::Retries=0", @"-o", @"Acquire::http::Timeout=30", @"-o", @"Acquire::https::Timeout=30", nil];
    if (!remove) [command addObject:@"--no-remove"];
    NSMutableArray *simulation = [[command mutableCopy] autorelease]; [simulation addObject:@"--simulate"]; [simulation addObject:remove ? @"remove" : @"install"]; [simulation addObject:target];
    NSDictionary *plan = Run(Path(@"/usr/bin/apt-get"), simulation);
    Require(![[plan objectForKey:@"status"] intValue] && ![[plan objectForKey:@"truncated"] boolValue], [plan objectForKey:@"output"]);
    NSMutableString *fingerprint = [NSMutableString stringWithFormat:@"%@\n%@\n%@", remove ? @"remove" : @"install", target, Digest(ReadFile(Path(@"/var/lib/dpkg/status"), 32 * 1024 * 1024, NO))];
    for (NSDictionary *source in Sources()) [fingerprint appendFormat:@"\nsource:%@", [source objectForKey:@"id"]];
    for (NSString *line in [[plan objectForKey:@"output"] componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"Remv "]) { NSArray *parts = [line componentsSeparatedByString:@" "]; Require([parts count] > 1 && !Protected([parts objectAtIndex:1], installed), @"The dependency plan would remove a protected system component. Nothing was changed."); }
        if ([line hasPrefix:@"Inst "] || [line hasPrefix:@"Remv "] || [line hasPrefix:@"Conf "]) [fingerprint appendFormat:@"\n%@", line];
    }
    NSString *token = Digest([fingerprint dataUsingEncoding:NSUTF8StringEncoding]);
    if (!apply) return [NSDictionary dictionaryWithObjectsAndKeys:[plan objectForKey:@"output"], @"output", token, @"token", nil];
    Require([[args objectAtIndex:2] isEqual:token], @"The dependency plan or installed state changed. Review a fresh preview before confirming.");
    [command addObject:@"--assume-yes"]; [command addObject:remove ? @"remove" : @"install"]; [command addObject:target];
    return Run(Path(@"/usr/bin/apt-get"), command);
}
int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN); umask(077);
#ifndef RC_PACKAGE_TEST
    if (geteuid() != 0 || (getuid() != 0 && (getuid() != RC_CALLER_UID || !authorized_parent())) || setgroups(0, NULL) || setgid(0) || setuid(0)) return fail("This package helper can only be started by the installed Receptor app.");
#endif
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; NSDictionary *result = nil; int lock = -1; NSString *journalOperation = nil;
    @try {
        Require(argc >= 2 && argc <= 4, @"Invalid arguments.");
        lock = open([Path(@"/var/tmp/receptor-packages.lock") fileSystemRepresentation], O_CREAT | O_RDWR | O_NOFOLLOW, 0600); struct stat info;
        Require(lock >= 0 && !fstat(lock, &info) && S_ISREG(info.st_mode) && info.st_nlink == 1 && info.st_uid == geteuid() && !(info.st_mode & 022) && !flock(lock, LOCK_EX | LOCK_NB), @"Another Receptor package operation is running or its lock is unsafe."); cloexec(lock);
        NSMutableArray *args = [NSMutableArray array]; for (int i = 1; i < argc; i++) { NSString *arg = [NSString stringWithUTF8String:argv[i]]; Require(arg != nil, @"Invalid UTF-8 argument."); [args addObject:arg]; }
        NSString *operation = [args objectAtIndex:0];
        if ([operation hasPrefix:@"apply-"] || [operation hasPrefix:@"source-"] || [operation isEqual:@"refresh"]) {
            journalOperation = operation;
            Journal([NSDictionary dictionaryWithObjectsAndKeys:@"Operation started; no completion result is recorded yet. Check the package database in Cydia before retrying an interrupted install.", @"output", operation, @"requested", [NSDate date], @"started", nil]);
        }
        result = Execute(args);
    } @catch (NSException *exception) { result = [NSDictionary dictionaryWithObject:[exception reason] ?: @"Package operation failed." forKey:@"error"]; }
    if (journalOperation) { @try { NSMutableDictionary *record = [[result mutableCopy] autorelease]; [record setObject:journalOperation forKey:@"requested"]; [record setObject:[NSDate date] forKey:@"finished"]; Journal(record); } @catch (NSException *exception) { NSMutableDictionary *record = [[result mutableCopy] autorelease]; [record setObject:@"The operation completed but its durable journal could not be saved." forKey:@"journalWarning"]; result = record; } }
    NSError *error = nil; NSData *data = [NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (data) fwrite([data bytes], 1, [data length], stdout); if (lock >= 0) close(lock);
    int status = data ? 0 : 2; [pool drain]; return status;
}
