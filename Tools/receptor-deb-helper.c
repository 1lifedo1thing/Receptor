/* Fixed-operation, rootful iOS package installer. No shell or user-supplied commands. */
#define _DARWIN_C_SOURCE 1
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
#include <grp.h>
#include <signal.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#if defined(RC_HELPER_TEST) && defined(__APPLE__)
#error Test mode must never be compiled into an Apple device helper.
#endif

#ifndef RC_HELPER_TEST
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/loader.h>
#include <sys/sysctl.h>
#include <dlfcn.h>
#define RC_DOWNLOADS_DIR "/var/mobile/Media/Receptor"
#define RC_DPKG_BINARY "/usr/bin/dpkg"
#define RC_STAGING_PARENT "/var/tmp"
#define RC_CALLER_UID 501
#define RC_APP_BINARY "/Applications/Receptor.app/ReceptorApp"
#endif

#define RC_MAX_LOG 65536
static int fail(const char *message) { fprintf(stderr, "Receptor: %s\n", message); return 2; }
static void cloexec(int fd) { (void)fcntl(fd, F_SETFD, FD_CLOEXEC); }

#ifndef RC_HELPER_TEST
static uint32_t read_be32(const unsigned char *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static int read_exact_at(int fd, void *data, size_t size, off_t offset) {
    unsigned char *p = data;
    while (size) {
        ssize_t n = pread(fd, p, size, offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
        p += n; size -= (size_t)n; offset += n;
    }
    return 1;
}
/* Compare the kernel's caller code hash with the signed, root-owned installed
 * app. An executable-path/argv string alone is not an authorization check. */
static int authorized_parent(void) {
    struct stat app, bundle;
    if (stat("/Applications/Receptor.app", &bundle) || !S_ISDIR(bundle.st_mode) || bundle.st_uid != 0 || (bundle.st_mode & 022)) return 0;
    int fd = open(RC_APP_BINARY, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return 0;
    cloexec(fd);
    int accepted = 0;
    struct mach_header header;
    if (fstat(fd, &app) || !S_ISREG(app.st_mode) || app.st_uid != 0 || (app.st_mode & 022) ||
        !read_exact_at(fd, &header, sizeof(header), 0) || header.magic != MH_MAGIC || header.ncmds > 256) goto done;
    off_t offset = sizeof(header);
    for (uint32_t i = 0; i < header.ncmds; ++i) {
        struct load_command command;
        if (!read_exact_at(fd, &command, sizeof(command), offset) || command.cmdsize < sizeof(command) ||
            offset + command.cmdsize > app.st_size) break;
        if (command.cmd == LC_CODE_SIGNATURE) {
            struct linkedit_data_command signature;
            if (command.cmdsize < sizeof(signature) || !read_exact_at(fd, &signature, sizeof(signature), offset) || signature.datasize < 60 ||
                signature.datasize > 1024 * 1024 || (off_t)signature.dataoff + signature.datasize > app.st_size) break;
            unsigned char *blob = malloc(signature.datasize);
            if (!blob) break;
            if (read_exact_at(fd, blob, signature.datasize, signature.dataoff) && read_be32(blob) == 0xfade0cc0) {
                uint32_t count = read_be32(blob + 8);
                if (count <= (signature.datasize - 12) / 8) for (uint32_t j = 0; j < count; ++j) {
                    if (read_be32(blob + 12 + j * 8) != 0) continue;
                    uint32_t start = read_be32(blob + 16 + j * 8);
                    if (start > signature.datasize - 40 || read_be32(blob + start) != 0xfade0c02 || blob[start + 37] != 1) continue;
                    uint32_t length = read_be32(blob + start + 4);
                    if (length < 40 || length > signature.datasize - start) continue;
                    unsigned char expected[CC_SHA1_DIGEST_LENGTH], actual[CC_SHA1_DIGEST_LENGTH];
                    CC_SHA1(blob + start, length, expected);
                    int (*csops_function)(pid_t, unsigned int, void *, size_t) =
                        (int (*)(pid_t, unsigned int, void *, size_t))dlsym(RTLD_DEFAULT, "csops");
                    if (csops_function && csops_function(getppid(), 5 /* CS_OPS_CDHASH */, actual, sizeof(actual)) == 0 &&
                        memcmp(expected, actual, sizeof(expected)) == 0) accepted = 1;
                }
            }
            free(blob);
            break;
        }
        offset += command.cmdsize;
    }
done:
    close(fd);
    return accepted;
}
#endif

static int valid_name(const char *name) {
    size_t length = strlen(name);
    return length > 22 && length <= 240 && strncmp(name, ".receptor-deb-", 14) == 0 &&
        strcmp(name + length - 4, ".deb") == 0 && !strchr(name, '/') && !strchr(name, '\\') && !strstr(name, "..");
}
static int copy_source(int source, int destination, off_t remaining) {
    char buffer[65536];
    for (;;) {
        if (!remaining) return fsync(destination) == 0;
        size_t requested = remaining < (off_t)sizeof(buffer) ? (size_t)remaining : sizeof(buffer);
        ssize_t count = read(source, buffer, requested);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) return 0;
        if (!count) return 0;
        remaining -= count;
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = write(destination, buffer + offset, (size_t)(count - offset));
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) return 0;
            offset += written;
        }
    }
}
static int run_dpkg(const char *package, int simulate, int output) {
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) {
        signal(SIGPIPE, SIG_DFL);
        int input = open("/dev/null", O_RDONLY);
        if (input < 0 || dup2(input, STDIN_FILENO) < 0 || dup2(output, STDOUT_FILENO) < 0 || dup2(output, STDERR_FILENO) < 0) _exit(126);
        if (input > 2) close(input);
        char *environment[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/var/root", "USER=root", "LOGNAME=root", "LANG=C", "LC_ALL=C", "TERM=dumb", NULL};
        char *install[] = {RC_DPKG_BINARY, "--install", (char *)package, NULL};
        char *check[] = {RC_DPKG_BINARY, "--no-act", "--install", (char *)package, NULL};
        execve(RC_DPKG_BINARY, simulate ? check : install, environment);
        _exit(127);
    }
    int status = 0;
    while (waitpid(child, &status, 0) < 0) { if (errno != EINTR) return 2; }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 2;
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN); // A disappearing UI must not kill a package transaction.
    umask(077);
    if (argc != 2 || !valid_name(argv[1])) return fail("Invalid staged package name.");
#ifndef RC_HELPER_TEST
    if (geteuid() != 0) return fail("Root helper is not enabled. Reinstall Receptor through Cydia.");
    if (getuid() != 0 && (getuid() != RC_CALLER_UID || !authorized_parent())) return fail("This installer can only be started by Receptor.");
    if (setgroups(0, NULL) || setgid(0) || setuid(0)) return fail("Unable to acquire package-manager privileges.");
#endif
    struct stat info;
    int directory = open(RC_DOWNLOADS_DIR, O_RDONLY | O_NOFOLLOW);
    if (directory < 0) return fail("Download directory is unavailable.");
    cloexec(directory);
    if (fstat(directory, &info) || !S_ISDIR(info.st_mode) || info.st_uid != RC_CALLER_UID || fchdir(directory)) { close(directory); return fail("Invalid download directory."); }
    int source = open(argv[1], O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    close(directory);
    if (source < 0) return fail("Staged package cannot be opened.");
    cloexec(source);
    if (fstat(source, &info) || !S_ISREG(info.st_mode) || info.st_uid != RC_CALLER_UID ||
        info.st_nlink != 1 || (info.st_mode & 022) || info.st_size < 8 || info.st_size > (off_t)8 * 1024 * 1024 * 1024) {
        close(source); return fail("Staged package has invalid ownership, permissions, size or type.");
    }
    char magic[8];
    if (read(source, magic, sizeof(magic)) != (ssize_t)sizeof(magic) || memcmp(magic, "!<arch>\n", 8) || lseek(source, 0, SEEK_SET) < 0) {
        close(source); return fail("This is not a Debian package archive.");
    }
    char staging[PATH_MAX], package[PATH_MAX], logpath[PATH_MAX];
    if (snprintf(staging, sizeof(staging), "%s/receptor-deb.XXXXXX", RC_STAGING_PARENT) >= (int)sizeof(staging) || !mkdtemp(staging)) {
        close(source); return fail("Cannot create private installation staging.");
    }
    if (snprintf(package, sizeof(package), "%s/package.deb", staging) >= (int)sizeof(package) ||
        snprintf(logpath, sizeof(logpath), "%s/install.log", staging) >= (int)sizeof(logpath)) {
        close(source); rmdir(staging); return fail("Installation staging path is too long.");
    }
    int destination = open(package, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    int copied = destination >= 0 && copy_source(source, destination, info.st_size);
    close(source);
    if (destination >= 0 && close(destination) != 0) copied = 0;
    if (!copied) { unlink(package); rmdir(staging); return fail("Cannot copy package into private staging. Check free space."); }
    int log = open(logpath, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (log < 0) { unlink(package); rmdir(staging); return fail("Cannot create installation log."); }
    cloexec(log);
    puts("Checking package and dependencies…"); fflush(stdout);
    int result = run_dpkg(package, 1, log);
    if (!result) {
        puts("Installing with dpkg…"); fflush(stdout);
        result = run_dpkg(package, 0, log);
    }
    /* Collect the tail, clean private staging, then send output to the UI.
     * dpkg writes a regular file, so UI termination cannot break its stdout. */
    off_t end = lseek(log, 0, SEEK_END);
    if (end > RC_MAX_LOG) lseek(log, end - RC_MAX_LOG, SEEK_SET); else lseek(log, 0, SEEK_SET);
    char output[RC_MAX_LOG];
    ssize_t length = read(log, output, sizeof(output));
    close(log);
    unlink(logpath); unlink(package); rmdir(staging);
    if (length > 0) (void)fwrite(output, 1, (size_t)length, stdout);
    printf("\nReceptor package-manager exit status: %d\n", result);
    return result;
}
