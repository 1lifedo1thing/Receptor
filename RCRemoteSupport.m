#import "RCRemoteSupport.h"
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <grp.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
NSString *RCRemotePath(NSString *path) {
#ifdef RC_REMOTE_HOST_TEST
    return [@RC_REMOTE_TEST_ROOT stringByAppendingString:path];
#else
    return path;
#endif
}
static void Require(BOOL condition,NSString *message) { if(!condition)[NSException raise:@"RemoteService" format:@"%@",message]; }
NSDictionary *RCRemoteRead(NSString *path) {
    int fd=open([path fileSystemRepresentation],O_RDONLY|O_NOFOLLOW|O_NONBLOCK); if(fd<0 && errno==ENOENT)return nil;
    struct stat info; Require(fd>=0,@"Cannot read private remote state.");
    if(fstat(fd,&info) || !S_ISREG(info.st_mode) || info.st_nlink!=1 || info.st_uid!=geteuid() || (info.st_mode&077) || info.st_size<0 || info.st_size>4*1024*1024) { close(fd); Require(NO,@"Private remote state has unsafe ownership, permissions or size."); }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)info.st_size]; NSUInteger done=0;
    while(done<[data length]) { ssize_t count=read(fd,(unsigned char *)[data mutableBytes]+done,[data length]-done); if(count<0 && errno==EINTR)continue; if(count<=0)break; done+=(NSUInteger)count; } close(fd); Require(done==[data length],@"Cannot read remote state.");
    NSError *error=nil; id result=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error]; Require([result isKindOfClass:[NSDictionary class]],@"Private remote state is invalid."); return result;
}
void RCRemoteSave(NSString *path,NSDictionary *value) {
    NSString *directory=[path stringByDeletingLastPathComponent]; struct stat info;
    if(mkdir([directory fileSystemRepresentation],0700) && errno!=EEXIST)Require(NO,@"Cannot create private remote state.");
    Require(!lstat([directory fileSystemRepresentation],&info) && S_ISDIR(info.st_mode) && info.st_uid==geteuid() && !(info.st_mode&077),@"Unsafe remote-state directory.");
    if(!lstat([path fileSystemRepresentation],&info)) Require(S_ISREG(info.st_mode) && info.st_uid==geteuid() && info.st_nlink==1 && !(info.st_mode&077),@"Unsafe remote-state file.");
    NSError *error=nil; NSData *data=[NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:&error]; Require(data && [data length]<=4*1024*1024,@"Remote state is too large.");
    char *temporary=strdup([[path stringByAppendingString:@".XXXXXX"] fileSystemRepresentation]); int fd=temporary?mkstemp(temporary):-1; Require(fd>=0,@"Cannot stage remote state.");
    const unsigned char *bytes=[data bytes]; NSUInteger remaining=[data length]; BOOL okay=YES;
    while(remaining) { ssize_t count=write(fd,bytes,remaining); if(count<0 && errno==EINTR)continue; if(count<=0) { okay=NO; break; } bytes+=count; remaining-=(NSUInteger)count; }
    if(fchmod(fd,0600) || fsync(fd))okay=NO; close(fd); if(okay && rename(temporary,[path fileSystemRepresentation]))okay=NO;
    if(!okay)unlink(temporary); free(temporary); Require(okay,@"Could not save private remote state.");
    fd=open([directory fileSystemRepresentation],O_RDONLY); if(fd>=0) { (void)fsync(fd); close(fd); }
}
NSDictionary *RCRemoteInvoke(NSDictionary *request) {
    @try {
        NSString *kind=[request objectForKey:@"op"]; BOOL files=[kind isEqual:@"files"];
        Require(files || [kind isEqual:@"packages"] || [kind isEqual:@"respring"],@"This remote operation is not allowed.");
        NSArray *arguments=nil; NSString *binary=nil; NSData *input=nil;
        if(files) {
            binary=RCRemotePath(@"/usr/libexec/receptor-file-helper"); arguments=[NSArray array];
            NSError *error=nil; input=[NSPropertyListSerialization dataWithPropertyList:request format:NSPropertyListXMLFormat_v1_0 options:0 error:&error]; Require(input && [input length]<=1024*1024,@"File request is too large.");
        } else if([kind isEqual:@"respring"]) {
            binary=RCRemotePath(@"/usr/libexec/receptor-deb-helper");
#ifdef RC_REMOTE_HOST_TEST
            arguments=[NSArray arrayWithObject:@"--respring"];
#else
            arguments=[NSArray arrayWithObject:kCFCoreFoundationVersionNumber>=700?@"--respring-backboard":@"--respring"];
#endif
        } else {
            arguments=[request objectForKey:@"args"];
            Require([arguments isKindOfClass:[NSArray class]] && [arguments count]>=1 && [arguments count]<=3,@"Invalid package arguments.");
            for(id value in arguments)Require([value isKindOfClass:[NSString class]] && [value length]<=2048,@"Invalid package argument.");
            NSArray *allowed=[NSArray arrayWithObjects:@"sources",@"source-add",@"source-remove",@"installed",@"search",@"details",@"refresh",@"last-result",@"plan-install",@"plan-remove",@"apply-install",@"apply-unsigned-install",@"apply-remove",nil];
            Require([allowed containsObject:[arguments objectAtIndex:0]],@"This package operation is not exposed remotely."); binary=RCRemotePath(@"/usr/libexec/receptor-package-helper");
        }
        char inputTemplate[4096],outputTemplate[4096]; snprintf(inputTemplate,sizeof(inputTemplate),"%s/receptor-remote-in.XXXXXX",[RCRemotePath(@"/var/tmp") fileSystemRepresentation]); snprintf(outputTemplate,sizeof(outputTemplate),"%s/receptor-remote-out.XXXXXX",[RCRemotePath(@"/var/tmp") fileSystemRepresentation]);
        int in=mkstemp(inputTemplate),out=mkstemp(outputTemplate); if(in>=0)unlink(inputTemplate); if(out>=0)unlink(outputTemplate);
        if(in>=0 && in<=2) { int copy=fcntl(in,F_DUPFD,3); close(in); in=copy; } if(out>=0 && out<=2) { int copy=fcntl(out,F_DUPFD,3); close(out); out=copy; }
        if(in<0 || out<0) { if(in>=0)close(in); if(out>=0)close(out); Require(NO,@"Cannot create private operation streams."); }
        @try {
            if(input) { const unsigned char *bytes=[input bytes]; NSUInteger remaining=[input length]; while(remaining) { ssize_t count=write(in,bytes,remaining); if(count<0 && errno==EINTR)continue; Require(count>0,@"Cannot prepare file request."); bytes+=count; remaining-=(NSUInteger)count; } }
            lseek(in,0,SEEK_SET); fcntl(in,F_SETFD,FD_CLOEXEC); fcntl(out,F_SETFD,FD_CLOEXEC);
            pid_t child=fork(); Require(child>=0,@"Cannot start the remote operation.");
            if(child==0) {
                if(dup2(in,0)<0 || dup2(out,1)<0 || dup2(out,2)<0)_exit(126);
#ifndef RC_REMOTE_HOST_TEST
                if(files && (setgroups(0,NULL) || setgid(501) || setuid(501)))_exit(126);
#endif
                char **argv=calloc([arguments count]+2,sizeof(char *)); if(!argv)_exit(126); argv[0]=(char *)[binary fileSystemRepresentation]; for(NSUInteger i=0;i<[arguments count];i++)argv[i+1]=(char *)[[arguments objectAtIndex:i] UTF8String];
                char *environment[]={"PATH=/usr/bin:/bin:/usr/sbin:/sbin","HOME=/var/mobile","LANG=C","LC_ALL=C",NULL}; execve(argv[0],argv,environment); _exit(127);
            }
            int status=0; pid_t waited; do { waited=waitpid(child,&status,0); } while(waited<0 && errno==EINTR);
            off_t size=lseek(out,0,SEEK_END); Require(size>=0 && size<=3*1024*1024,@"The remote result is too large. Refine the request and inspect the device's operation log.");
            lseek(out,0,SEEK_SET); NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)size]; NSUInteger done=0;
            while(done<[data length]) { ssize_t count=read(out,(unsigned char *)[data mutableBytes]+done,[data length]-done); if(count<0 && errno==EINTR)continue; Require(count>0,@"Could not read the operation result."); done+=(NSUInteger)count; }
            if([kind isEqual:@"respring"]) return waited==child && WIFEXITED(status) && WEXITSTATUS(status)==0?[NSDictionary dictionaryWithObject:@"Respring requested." forKey:@"output"]:[NSDictionary dictionaryWithObject:@"The respring request failed. Close package managers and inspect the helper permissions." forKey:@"error"];
            Require(waited==child && WIFEXITED(status) && WEXITSTATUS(status)==0,@"The helper did not finish normally. Inspect the package log before repeating an interrupted install.");
            NSError *error=nil; id result=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error]; Require([result isKindOfClass:[NSDictionary class]],@"Invalid helper result."); return result;
        } @finally { close(in); close(out); }
    } @catch(NSException *exception) { return [NSDictionary dictionaryWithObject:[exception reason]?:@"Remote operation failed." forKey:@"error"]; }
}
