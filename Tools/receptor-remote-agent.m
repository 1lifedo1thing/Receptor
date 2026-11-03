#import <Foundation/Foundation.h>
#import "../RCRemoteCrypto.h"
#import "../RCRemoteSupport.h"
#include <curl/curl.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <limits.h>
#include <stdio.h>
#include <sys/file.h>
#include <fcntl.h>
static volatile sig_atomic_t stopping=0;
static void Stop(int value) { (void)value; stopping=1; }
static void Check(BOOL condition,NSString *message) { if(!condition)[NSException raise:@"RemoteAgent" format:@"%@",message]; }
static NSString *Private(NSString *name) { return RCRemotePath([@"/var/lib/receptor" stringByAppendingPathComponent:name]); }
static NSDictionary *Process(NSDictionary *command,NSString *session,NSDictionary *config) {
    NSString *identifier=[command objectForKey:@"id"],*device=[config objectForKey:@"device"];
    Check([identifier isKindOfClass:[NSString class]] && [identifier length]==32 && [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound,@"Invalid command identifier.");
    NSDictionary *last=RCRemoteRead(Private(@"remote-last-job.plist"));
    if([[last objectForKey:@"id"] isEqual:identifier] && [[last objectForKey:@"session"] isEqual:session] && [[last objectForKey:@"device"] isEqual:device]) {
        if([[last objectForKey:@"body"] isKindOfClass:[NSData class]])return last;
        NSError *error=nil; NSData *data=[NSPropertyListSerialization dataWithPropertyList:[NSDictionary dictionaryWithObject:@"The service was interrupted after recording this command. Its outcome is uncertain; inspect the package operation log before repeating it." forKey:@"error"] format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        NSMutableDictionary *uncertain=[[last mutableCopy] autorelease]; [uncertain setObject:data forKey:@"body"]; RCRemoteSave(Private(@"remote-last-job.plist"),uncertain); return uncertain;
    }
    NSDictionary *current=RCRemoteRead(Private(@"remote.plist"));
    Check(current && [[current objectForKey:@"device"] isEqual:device],@"Background access was revoked or its pairing changed.");
    NSDictionary *request=[command objectForKey:@"request"]; Check([request isKindOfClass:[NSDictionary class]],@"Invalid remote command.");
    NSMutableDictionary *state=[NSMutableDictionary dictionaryWithObjectsAndKeys:identifier,@"id",session,@"session",device,@"device",[NSDate date],@"started",nil];
    RCRemoteSave(Private(@"remote-last-job.plist"),state); // Persist before invoking a mutating helper; never automatically repeat an uncertain command.
    NSDictionary *result=RCRemoteInvoke(request); NSError *error=nil; NSData *data=[NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    Check(data && [data length]<=3*1024*1024,@"The operation result could not be recorded. Inspect the device log.");
    [state setObject:data forKey:@"body"]; [state setObject:[NSDate date] forKey:@"finished"]; RCRemoteSave(Private(@"remote-last-job.plist"),state); return state;
}
typedef struct { NSMutableData *body; NSString *auth; NSUInteger headers; BOOL bad; } Response;
static size_t Write(char *bytes,size_t size,size_t count,void *pointer) {
    Response *response=pointer; if(size && count>SIZE_MAX/size)return 0; size_t length=size*count;
    if(stopping || [response->body length]+length>4*1024*1024)return 0; [response->body appendBytes:bytes length:length]; return length;
}
static size_t Header(char *bytes,size_t size,size_t count,void *pointer) {
    Response *response=pointer; size_t length=size*count; response->headers+=length; if(response->headers>16384)return 0;
    NSString *line=[[[NSString alloc] initWithBytes:bytes length:length encoding:NSASCIIStringEncoding] autorelease]; if(!line)return 0;
    NSRange colon=[line rangeOfString:@":"]; if(colon.location!=NSNotFound && [[[line substringToIndex:colon.location] lowercaseString] isEqual:@"x-receptor-auth"]) {
        if(response->auth)response->bad=YES; else response->auth=[[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    }
    return length;
}
static int Progress(void *pointer,curl_off_t a,curl_off_t b,curl_off_t c,curl_off_t d) { (void)a;(void)b;(void)c;(void)d;return stopping || access((const char *)pointer,F_OK)!=0?1:0; }
static NSDictionary *Exchange(NSDictionary *config,NSDictionary *message) {
    NSData *seed=[config objectForKey:@"seed"]; NSString *device=[config objectForKey:@"device"],*nonce=[RCRemoteHash(RCRemoteRandom(32)) substringToIndex:32];
    NSError *error=nil; NSData *plain=[NSPropertyListSerialization dataWithPropertyList:message format:NSPropertyListXMLFormat_v1_0 options:0 error:&error],*frame=RCRemoteEncrypt(seed,plain); Check(frame!=nil,@"Cannot encrypt the request.");
    NSArray *lines=[NSArray arrayWithObjects:[@"X-RC-Device: " stringByAppendingString:device],[@"X-RC-Nonce: " stringByAppendingString:nonce],[@"X-RC-Sealed: " stringByAppendingString:RCRemoteBase64([config objectForKey:@"sealed"])],[@"X-RC-Enrollment: " stringByAppendingString:[config objectForKey:@"enrollment"]],[@"X-RC-Auth: " stringByAppendingString:RCRemoteMAC(seed,@"request",device,nonce,frame)],@"Content-Type: application/octet-stream",@"Expect:",nil];
    struct curl_slist *headers=NULL;
    for(NSString *line in lines) { struct curl_slist *next=curl_slist_append(headers,[line UTF8String]); if(!next) { curl_slist_free_all(headers); Check(NO,@"Cannot allocate request headers."); } headers=next; }
    CURL *curl=curl_easy_init(); if(!curl) { curl_slist_free_all(headers); Check(NO,@"Cannot initialize remote transport."); }
    Response response; memset(&response,0,sizeof(response)); response.body=[NSMutableData data];
    NSString *url=[NSString stringWithFormat:@"http://%@/v3/control",[config objectForKey:@"host"]];
    curl_easy_setopt(curl,CURLOPT_URL,[url UTF8String]); curl_easy_setopt(curl,CURLOPT_PROXY,""); curl_easy_setopt(curl,CURLOPT_PROTOCOLS_STR,"http"); curl_easy_setopt(curl,CURLOPT_FOLLOWLOCATION,0L);
    curl_easy_setopt(curl,CURLOPT_POST,1L); curl_easy_setopt(curl,CURLOPT_POSTFIELDS,[frame bytes]); curl_easy_setopt(curl,CURLOPT_POSTFIELDSIZE_LARGE,(curl_off_t)[frame length]); curl_easy_setopt(curl,CURLOPT_HTTPHEADER,headers);
    curl_easy_setopt(curl,CURLOPT_NOSIGNAL,1L); curl_easy_setopt(curl,CURLOPT_CONNECTTIMEOUT,5L); curl_easy_setopt(curl,CURLOPT_TIMEOUT,25L); curl_easy_setopt(curl,CURLOPT_WRITEFUNCTION,Write); curl_easy_setopt(curl,CURLOPT_WRITEDATA,&response); curl_easy_setopt(curl,CURLOPT_HEADERFUNCTION,Header); curl_easy_setopt(curl,CURLOPT_HEADERDATA,&response); curl_easy_setopt(curl,CURLOPT_NOPROGRESS,0L); curl_easy_setopt(curl,CURLOPT_XFERINFOFUNCTION,Progress);
    curl_easy_setopt(curl,CURLOPT_XFERINFODATA,[Private(@"remote.plist") fileSystemRepresentation]);
    CURLcode code=curl_easy_perform(curl); long status=0; curl_easy_getinfo(curl,CURLINFO_RESPONSE_CODE,&status); curl_easy_cleanup(curl); curl_slist_free_all(headers);
    BOOL authenticated=!response.bad && RCRemoteEqual(response.auth,RCRemoteMAC(seed,@"response",device,nonce,response.body)); [response.auth release];
    Check(code==CURLE_OK,[NSString stringWithFormat:@"Background connection failed (curl %d: %s). Check PC sharing, the saved address and Wi-Fi.",(int)code,curl_easy_strerror(code)]);
    Check(status==200,status==403?@"PC rejected background access. Connect / Refresh in Desktop, then enable background access again. Check the PC background-access checkbox.":[NSString stringWithFormat:@"PC returned HTTP %ld to the background connection. Check the PC address and sharing.",status]);
    Check(authenticated,@"PC response authentication failed. Connect / Refresh in Desktop and enable background access again after comparing the PC key.");
    NSData *decoded=RCRemoteDecrypt(seed,response.body); Check(decoded!=nil,@"Cannot decrypt the PC response.");
    id result=[NSPropertyListSerialization propertyListWithData:decoded options:NSPropertyListImmutable format:NULL error:&error]; Check([result isKindOfClass:[NSDictionary class]],@"Invalid PC response."); return result;
}
int main(int argc,char **argv) {
#ifndef RC_REMOTE_HOST_TEST
    (void)argc;(void)argv; if(geteuid()!=0)return 2;
#endif
    signal(SIGPIPE,SIG_IGN); signal(SIGTERM,Stop); signal(SIGINT,Stop); NSAutoreleasePool *startup=[[NSAutoreleasePool alloc] init];
#ifdef RC_REMOTE_HOST_TEST
    if(argc==2 && !strcmp(argv[1],"--process-fixture")) {
        NSMutableData *input=[NSMutableData data]; char bytes[4096]; ssize_t count; while((count=read(0,bytes,sizeof(bytes)))>0)[input appendBytes:bytes length:count];
        NSError *error=nil; NSDictionary *request=[NSPropertyListSerialization propertyListWithData:input options:NSPropertyListImmutable format:NULL error:&error]; NSDictionary *result=nil;
        @try { result=Process([request objectForKey:@"command"],[request objectForKey:@"session"],RCRemoteRead(Private(@"remote.plist"))); } @catch(NSException *exception) { result=[NSDictionary dictionaryWithObject:[exception reason] forKey:@"error"]; }
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListXMLFormat_v1_0 options:0 error:&error]; if(data)fwrite([data bytes],1,[data length],stdout); [startup drain]; return data?0:2;
    }
#endif
    int instance=-1;
    @try {
        if(!RCRemoteRead(Private(@"remote.plist"))) { [startup drain]; return 0; }
        instance=open([Private(@"remote-agent.lock") fileSystemRepresentation],O_RDWR|O_CREAT|O_NOFOLLOW,0600); struct stat info;
        Check(instance>=0 && !fstat(instance,&info) && S_ISREG(info.st_mode) && info.st_nlink==1 && info.st_uid==geteuid() && !(info.st_mode&077) && !flock(instance,LOCK_EX|LOCK_NB),@"Background service is already running or its lock is unsafe."); fcntl(instance,F_SETFD,FD_CLOEXEC);
    } @catch(NSException *exception) { @try { NSDictionary *config=RCRemoteRead(Private(@"remote.plist")); if(config)RCRemoteSave(Private(@"remote-status.plist"),[NSDictionary dictionaryWithObjectsAndKeys:[config objectForKey:@"device"],@"device",[NSDate date],@"updated",@"Background service could not initialize its private state or instance lock. Reinstall Receptor through Cydia, then retry.",@"message",nil]); } @catch(NSException *ignored) { (void)ignored; } if(instance>=0)close(instance); [startup drain]; return 2; }
    struct stat started; BOOL tracked=lstat([RCRemotePath(@"/usr/libexec/receptor-remote-agent") fileSystemRepresentation],&started)==0;
    curl_global_init(CURL_GLOBAL_DEFAULT); [startup drain]; NSString *session=nil,*identity=nil,*lastPeer=nil; long long counter=0; int backoff=2;
    while(!stopping) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; BOOL configured=NO;
        @try {
            NSDictionary *config=RCRemoteRead(Private(@"remote.plist")); if(!config) { [pool drain]; break; } configured=YES;
            NSData *seed=[config objectForKey:@"seed"]; NSString *device=[config objectForKey:@"device"];
            Check([seed isKindOfClass:[NSData class]] && [seed length]==32 && [[RCRemoteHash(seed) substringToIndex:32] isEqual:device] && [config objectForKey:@"host"] && [config objectForKey:@"sealed"] && [config objectForKey:@"enrollment"],@"Invalid background-access configuration.");
            if(![identity isEqual:device]) { [identity release]; identity=[device copy]; [session release]; session=nil; [lastPeer release]; lastPeer=nil; NSDictionary *transport=RCRemoteRead(Private(@"remote-transport.plist")); counter=[[transport objectForKey:@"device"] isEqual:device]?[[transport objectForKey:@"counter"] longLongValue]:0; if([[transport objectForKey:@"device"] isEqual:device])lastPeer=[[transport objectForKey:@"session"] copy]; }
            Check(!session || (counter>=0 && counter<LLONG_MAX-1),@"The transport counter is exhausted; pair background access again.");
            NSMutableDictionary *message=[NSMutableDictionary dictionaryWithObjectsAndKeys:session?:@"",@"session",[NSNumber numberWithLongLong:session?++counter:0],@"counter",nil];
            if(session) { Check(counter>0 && counter<LLONG_MAX,@"The transport counter is exhausted; pair background access again."); RCRemoteSave(Private(@"remote-transport.plist"),[NSDictionary dictionaryWithObjectsAndKeys:device,@"device",[NSNumber numberWithLongLong:counter],@"counter",session,@"session",nil]); }
            NSDictionary *last=RCRemoteRead(Private(@"remote-last-job.plist"));
            if(session && [[last objectForKey:@"session"] isEqual:session] && [[last objectForKey:@"device"] isEqual:device]) {
                if(![last objectForKey:@"body"]) last=Process([NSDictionary dictionaryWithObject:[last objectForKey:@"id"] forKey:@"id"],session,config);
                [message setObject:[NSDictionary dictionaryWithObjectsAndKeys:[last objectForKey:@"id"],@"id",[last objectForKey:@"body"],@"body",nil] forKey:@"reply"];
            }
            NSDictionary *version=[NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"]; if([[version objectForKey:@"ProductVersion"] isKindOfClass:[NSString class]])[message setObject:[version objectForKey:@"ProductVersion"] forKey:@"os"];
            if(!session)RCRemoteSave(Private(@"remote-status.plist"),[NSDictionary dictionaryWithObjectsAndKeys:device,@"device",[NSDate date],@"updated",@"Connecting to the PC…",@"message",nil]);
            NSDictionary *response=Exchange(config,message); NSString *peer=[response objectForKey:@"session"];
            Check([peer isKindOfClass:[NSString class]] && [peer length]==32,@"Invalid PC session.");
            long long floor=[[response objectForKey:@"counterFloor"] longLongValue]; if(floor>counter)counter=floor;
            BOOL changed=![lastPeer isEqual:peer]; [session release]; session=[peer copy]; [lastPeer release]; lastPeer=[peer copy];
            if(changed) (void)RCRemoteInvoke([NSDictionary dictionaryWithObjectsAndKeys:@"files",@"op",@"abort",@"action",nil]);
            if([[response objectForKey:@"ack"] isEqual:[last objectForKey:@"id"]]) unlink([Private(@"remote-last-job.plist") fileSystemRepresentation]);
            RCRemoteSave(Private(@"remote-status.plist"),[NSDictionary dictionaryWithObjectsAndKeys:device,@"device",[NSDate date],@"lastConnected",[NSDate date],@"updated",@"Connected",@"message",nil]); backoff=2;
            NSDictionary *command=[response objectForKey:@"command"];
            if(command) { Check([command isKindOfClass:[NSDictionary class]],@"Invalid command."); (void)Process(command,session,config); }
        } @catch(NSException *exception) {
#ifdef RC_REMOTE_HOST_TEST
            fprintf(stderr,"Remote fixture: %s\n",[[exception reason] UTF8String]); fflush(stderr);
#endif
            @try { RCRemoteSave(Private(@"remote-status.plist"),[NSDictionary dictionaryWithObjectsAndKeys:identity?:@"",@"device",[NSDate date],@"updated",[exception reason]?:@"Waiting for the PC. Check sharing, Wi-Fi and its saved pairing.",@"message",nil]); } @catch(NSException *ignored) { (void)ignored; }
            [session release]; session=nil;
            for(int i=0;i<backoff && !stopping;i++)sleep(1); backoff=MIN(30,backoff*2);
        }
        [pool drain]; if(!configured)break;
        struct stat current; if(tracked && (lstat([RCRemotePath(@"/usr/libexec/receptor-remote-agent") fileSystemRepresentation],&current) || current.st_ino!=started.st_ino || current.st_mtime!=started.st_mtime))break;
    }
    NSAutoreleasePool *cleanup=[[NSAutoreleasePool alloc] init]; @try { if(!RCRemoteRead(Private(@"remote.plist"))) (void)RCRemoteInvoke([NSDictionary dictionaryWithObjectsAndKeys:@"files",@"op",@"abort",@"action",nil]); } @catch(NSException *ignored) { (void)ignored; } [identity release]; [session release]; [lastPeer release]; curl_global_cleanup(); if(instance>=0)close(instance); [cleanup drain]; return 0;
}
