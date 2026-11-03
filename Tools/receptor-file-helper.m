/* Runs as mobile, never setuid. Only visible regular files in Receptor's folder. */
#import <Foundation/Foundation.h>
#import "../RCRemoteCrypto.h"
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#ifdef RC_REMOTE_HOST_TEST
#include <openssl/evp.h>
#else
#include <CommonCrypto/CommonDigest.h>
#endif
#ifdef RC_REMOTE_HOST_TEST
#define FILE_UID RC_FILE_TEST_UID
#define DOWNLOADS @RC_FILE_TEST_DIRECTORY
#else
#define FILE_UID 501
#define DOWNLOADS @"/var/mobile/Media/Receptor"
#endif
static void Check(BOOL condition,NSString *message) { if(!condition)[NSException raise:@"RemoteFiles" format:@"%@",message]; }
static BOOL Name(NSString *name) {
    return [name isKindOfClass:[NSString class]] && [name length] && [name length]<=255 && ![name hasPrefix:@"."] && [name rangeOfString:@"/"].location==NSNotFound && [name rangeOfString:@"\\"].location==NSNotFound && [name rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location==NSNotFound;
}
static NSDictionary *State(void) {
    int fd=open(".receptor-remote-upload.plist",O_RDONLY|O_NOFOLLOW|O_NONBLOCK); if(fd<0)return nil; struct stat info;
    Check(!fstat(fd,&info) && S_ISREG(info.st_mode) && info.st_uid==FILE_UID && info.st_nlink==1 && info.st_size>0 && info.st_size<8192,@"Invalid upload state.");
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)info.st_size]; ssize_t count=read(fd,[data mutableBytes],[data length]); close(fd); Check(count==(ssize_t)[data length],@"Cannot read upload state.");
    NSError *error=nil; id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error]; Check([value isKindOfClass:[NSDictionary class]],@"Invalid upload state."); return value;
}
static BOOL UploadID(NSString *identifier) { return [identifier isKindOfClass:[NSString class]] && [identifier length]==32 && [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound; }
static NSString *Partial(NSDictionary *state) { NSString *identifier=[state objectForKey:@"id"]; Check(UploadID(identifier) && Name([state objectForKey:@"name"]),@"Invalid upload identifier or filename."); return [NSString stringWithFormat:@".receptor-remote-%@.part",identifier]; }
static int Open(NSString *name,int flags,BOOL hidden) {
    Check(hidden || Name(name),@"Choose a regular file name in Receptor's download folder.");
    int fd=open([name fileSystemRepresentation],flags|O_NOFOLLOW|O_NONBLOCK,0600); struct stat info;
    if(fd<0)return -1;
    if(fstat(fd,&info) || !S_ISREG(info.st_mode) || info.st_nlink!=1 || (info.st_mode&022)) { close(fd); return -1; }
    return fd;
}
static NSString *Token(NSString *name,struct stat *info) {
#ifdef RC_REMOTE_HOST_TEST
    long nanos=info->st_mtim.tv_nsec,change=info->st_ctim.tv_nsec;
#else
    long nanos=info->st_mtimespec.tv_nsec,change=info->st_ctimespec.tv_nsec;
#endif
    return RCRemoteHash([[NSString stringWithFormat:@"%@:%llu:%llu:%lld:%lld:%ld:%lld:%ld",name,(unsigned long long)info->st_dev,(unsigned long long)info->st_ino,(long long)info->st_size,(long long)info->st_mtime,nanos,(long long)info->st_ctime,change] dataUsingEncoding:NSUTF8StringEncoding]);
}
static NSString *FileHash(int fd) {
    // Stream the digest using the same system/OpenSSL primitive as the transport.
#ifdef RC_REMOTE_HOST_TEST
    EVP_MD_CTX *hash=EVP_MD_CTX_new(); EVP_DigestInit_ex(hash,EVP_sha256(),NULL);
#else
    CC_SHA256_CTX hash; CC_SHA256_Init(&hash);
#endif
    lseek(fd,0,SEEK_SET); unsigned char buffer[65536],digest[32]; ssize_t count;
    while((count=read(fd,buffer,sizeof(buffer)))!=0) { if(count<0 && errno==EINTR)continue; Check(count>0,@"Cannot read the selected file.");
#ifdef RC_REMOTE_HOST_TEST
        EVP_DigestUpdate(hash,buffer,(size_t)count);
#else
        CC_SHA256_Update(&hash,buffer,(CC_LONG)count);
#endif
    }
#ifdef RC_REMOTE_HOST_TEST
    unsigned int length=32; EVP_DigestFinal_ex(hash,digest,&length); EVP_MD_CTX_free(hash);
#else
    CC_SHA256_Final(digest,&hash);
#endif
    NSMutableString *text=[NSMutableString string]; for(int i=0;i<32;i++)[text appendFormat:@"%02x",digest[i]]; return text;
}
static void Abort(void) {
    NSDictionary *state=State(); if(state) { NSString *partial=Partial(state); int fd=Open(partial,O_RDONLY,YES); if(fd>=0) { close(fd); unlink([partial fileSystemRepresentation]); } }
    unlink(".receptor-remote-upload.plist");
}
static NSDictionary *Execute(NSDictionary *request) {
    NSString *action=[request objectForKey:@"action"],*name=[request objectForKey:@"name"];
    if([action isEqual:@"list"]) {
        NSMutableArray *items=[NSMutableArray array]; NSArray *names=[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"." error:NULL] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for(NSString *candidate in names) { if(!Name(candidate))continue; int fd=Open(candidate,O_RDONLY,NO); if(fd<0)continue; struct stat info; fstat(fd,&info); close(fd); [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:candidate,@"name",[NSNumber numberWithLongLong:info.st_size],@"size",nil]]; if([items count]>=5000)break; }
        return [NSDictionary dictionaryWithObject:items forKey:@"items"];
    }
    if([action isEqual:@"abort"]) { Abort(); return [NSDictionary dictionaryWithObject:@"Incomplete upload discarded." forKey:@"output"]; }
    if([action isEqual:@"write-start"]) {
        Check(Name(name),@"Invalid destination filename."); long long size=[[request objectForKey:@"size"] longLongValue]; NSString *digest=[request objectForKey:@"sha256"];
        Check(size>=0 && size<=2147483647LL && [digest isKindOfClass:[NSString class]] && [digest length]==64 && [digest rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound,@"Invalid upload size or hash.");
        Abort(); NSString *identifier=[RCRemoteHash(RCRemoteRandom(32)) substringToIndex:32]; NSDictionary *state=[NSDictionary dictionaryWithObjectsAndKeys:identifier,@"id",name,@"name",[NSNumber numberWithLongLong:size],@"size",digest,@"sha256",nil];
        int fd=Open(Partial(state),O_WRONLY|O_CREAT|O_EXCL,YES); Check(fd>=0,@"Cannot create upload staging. Check free space."); close(fd);
        NSError *error=nil; NSData *data=[NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        fd=open(".receptor-remote-upload.plist",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600); Check(fd>=0,@"Cannot create upload state."); ssize_t count=write(fd,[data bytes],[data length]); BOOL okay=count==(ssize_t)[data length] && fsync(fd)==0; close(fd); Check(okay,@"Could not save upload state."); return [NSDictionary dictionaryWithObject:identifier forKey:@"id"];
    }
    if([action isEqual:@"write-chunk"] || [action isEqual:@"write-finish"]) {
        NSDictionary *state=State(); Check(state && [[state objectForKey:@"id"] isEqual:[request objectForKey:@"id"]],@"Upload expired. Start again.");
        NSString *partial=Partial(state); int fd=Open(partial,O_RDWR,YES); Check(fd>=0,@"Upload staging is unavailable.");
        @try {
            struct stat info; Check(!fstat(fd,&info),@"Cannot inspect upload.");
            if([action isEqual:@"write-chunk"]) {
                NSData *data=[request objectForKey:@"data"]; long long offset=[[request objectForKey:@"offset"] longLongValue];
                Check([data isKindOfClass:[NSData class]] && [data length]<=65536 && offset==info.st_size && offset+(long long)[data length]<=[[state objectForKey:@"size"] longLongValue],@"Invalid upload chunk or offset.");
                Check(lseek(fd,offset,SEEK_SET)==offset,@"Cannot seek upload."); const unsigned char *bytes=[data bytes]; NSUInteger remaining=[data length];
                while(remaining) { ssize_t count=write(fd,bytes,remaining); if(count<0 && errno==EINTR)continue; Check(count>0,@"Cannot save upload. Check free space."); bytes+=count; remaining-=(NSUInteger)count; }
                return [NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:offset+[data length]] forKey:@"offset"];
            }
            Check(info.st_size==[[state objectForKey:@"size"] longLongValue] && fsync(fd)==0 && [FileHash(fd) isEqual:[state objectForKey:@"sha256"]],@"Upload is incomplete or failed SHA-256 verification.");
            NSString *original=[state objectForKey:@"name"],*saved=nil;
            for(int i=0;i<10000;i++) { NSString *candidate=i?[NSString stringWithFormat:@"%@ (%d)%@%@",[original stringByDeletingPathExtension],i,[[original pathExtension] length]?@".":@"",[original pathExtension]]:original;
                if(link([partial fileSystemRepresentation],[candidate fileSystemRepresentation])==0) { saved=candidate; break; } if(errno!=EEXIST)break; }
            Check(saved!=nil,@"Cannot publish this file. Existing files were preserved."); unlink([partial fileSystemRepresentation]); unlink(".receptor-remote-upload.plist"); return [NSDictionary dictionaryWithObject:saved forKey:@"saved"];
        } @finally { close(fd); }
    }
    Check(Name(name),@"Invalid file name."); int fd=Open(name,O_RDONLY,NO); Check(fd>=0,@"This readable regular file is unavailable.");
    @try {
        struct stat before,after; Check(!fstat(fd,&before) && before.st_size>=0 && before.st_size<=2147483647LL,@"Choose a file no larger than 2 GB."); NSString *token=Token(name,&before);
        if([action isEqual:@"info"]) { NSString *digest=FileHash(fd); Check(!fstat(fd,&after) && [token isEqual:Token(name,&after)],@"The file changed while hashing. Retry when it is no longer being written."); return [NSDictionary dictionaryWithObjectsAndKeys:name,@"name",token,@"token",digest,@"sha256",[NSNumber numberWithLongLong:before.st_size],@"size",nil]; }
        Check([action isEqual:@"read"] && [token isEqual:[request objectForKey:@"token"]],@"The file changed. Restart the download.");
        long long offset=[[request objectForKey:@"offset"] longLongValue]; NSInteger length=[[request objectForKey:@"length"] integerValue]; Check(offset>=0 && offset<=before.st_size && length>0 && length<=65536,@"Invalid file chunk.");
        NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)MIN((long long)length,before.st_size-offset)]; Check(lseek(fd,offset,SEEK_SET)==offset,@"Cannot seek file.");
        NSUInteger done=0; while(done<[data length]) { ssize_t count=read(fd,(unsigned char *)[data mutableBytes]+done,[data length]-done); if(count<0 && errno==EINTR)continue; Check(count>0,@"Cannot read file chunk."); done+=(NSUInteger)count; }
        Check(!fstat(fd,&after) && [token isEqual:Token(name,&after)],@"The file changed during transfer."); return [NSDictionary dictionaryWithObjectsAndKeys:data,@"data",[NSNumber numberWithLongLong:offset],@"offset",nil];
    } @finally { close(fd); }
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; NSDictionary *result=nil; int directory=-1,lock=-1;
    @try {
        Check(geteuid()==FILE_UID,@"File operations must run as the mobile user."); struct stat info;
        directory=open([DOWNLOADS fileSystemRepresentation],O_RDONLY|O_NOFOLLOW); Check(directory>=0 && !fstat(directory,&info) && S_ISDIR(info.st_mode) && info.st_uid==FILE_UID && !fchdir(directory),@"Receptor's download folder is unavailable.");
        lock=open(".receptor-remote-files.lock",O_RDWR|O_CREAT|O_NOFOLLOW,0600); Check(lock>=0 && !fstat(lock,&info) && S_ISREG(info.st_mode) && info.st_nlink==1 && info.st_uid==FILE_UID && !flock(lock,LOCK_EX|LOCK_NB),@"Another remote file operation is running.");
        NSMutableData *data=[NSMutableData data]; char bytes[16384]; ssize_t count;
        while((count=read(0,bytes,sizeof(bytes)))>0) { Check([data length]+count<=1024*1024,@"File request is too large."); [data appendBytes:bytes length:(NSUInteger)count]; }
        NSError *error=nil; id request=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error]; Check([request isKindOfClass:[NSDictionary class]],@"Invalid file request."); result=Execute(request);
    } @catch(NSException *exception) { result=[NSDictionary dictionaryWithObject:[exception reason]?:@"File operation failed." forKey:@"error"]; }
    NSError *error=nil; NSData *data=[NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListXMLFormat_v1_0 options:0 error:&error]; if(data)fwrite([data bytes],1,[data length],stdout); if(lock>=0)close(lock); if(directory>=0)close(directory); int status=data?0:2; [pool drain]; return status;
}
