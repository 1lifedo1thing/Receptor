#ifndef RC_OPERATION_LOCK_H
#define RC_OPERATION_LOCK_H
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
/* The nonprivileged IPA installer and both privileged helpers share this lock. */
static inline int RCAcquireMobileOperationLock(const char *directory,uid_t owner) {
    int parent=open(directory,O_RDONLY|O_NOFOLLOW); struct stat info;
    if(parent<0)return -1;
    if(fstat(parent,&info) || !S_ISDIR(info.st_mode) || info.st_uid!=owner) { close(parent); return -1; }
    char path[4096]; int length=snprintf(path,sizeof(path),"%s/.receptor-operation.lock",directory);
    if(length<0 || length>=(int)sizeof(path)) { close(parent); return -1; }
    int previous=-1;
    if(geteuid()==0) { previous=open(".",O_RDONLY); if(previous<0 || fchdir(parent)) { if(previous>=0)close(previous); close(parent); return -1; } }
    const char *target=previous>=0?".receptor-operation.lock":path;
    int fd=open(target,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW,0600); int created=fd>=0;
    if(fd<0 && errno==EEXIST)fd=open(target,O_RDWR|O_NOFOLLOW|O_NONBLOCK);
    if(previous>=0) { if(fchdir(previous)) { if(fd>=0)close(fd); fd=-1; } close(previous); } close(parent);
    if(fd<0)return -1;
    if(fstat(fd,&info) || !S_ISREG(info.st_mode) || info.st_nlink!=1 || (info.st_mode&022)) { close(fd); return -1; }
    if(info.st_uid!=owner && (!created || geteuid()!=0 || fchown(fd,owner,(gid_t)owner))) { close(fd); return -1; }
    if(flock(fd,LOCK_EX|LOCK_NB)) { close(fd); return -1; }
    fcntl(fd,F_SETFD,FD_CLOEXEC); return fd;
}
#endif
