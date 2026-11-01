#include "RCSystemContent.h"
#include <string.h>
#include <strings.h>
#include <ctype.h>
static int mime_equal(const char *value, const char *expected) {
    if (!value) return 0;
    while (*value && isspace((unsigned char)*value)) value++;
    const char *end = strchr(value, ';'); if (!end) end = value + strlen(value);
    while (end > value && isspace((unsigned char)end[-1])) end--;
    return (size_t)(end - value) == strlen(expected) && !strncasecmp(value, expected, (size_t)(end - value));
}
int RCIsSystemInstallerContent(const char *extension, const char *mime) {
    static const char *extensions[] = {"mobileconfig", "cer", "crt", "der", "p12", "pfx"};
    static const char *types[] = {"application/x-apple-aspen-config", "application/x-x509-ca-cert",
        "application/x-x509-user-cert", "application/pkix-cert", "application/x-pkcs12", "application/pkcs12"};
    for (size_t i = 0; i < sizeof(extensions) / sizeof(*extensions); ++i)
        if (extension && !strcasecmp(extension, extensions[i])) return 1;
    for (size_t i = 0; i < sizeof(types) / sizeof(*types); ++i) if (mime_equal(mime, types[i])) return 1;
    return 0;
}
int RCIsSystemInstallerContentOnIOS(const char *extension, const char *mime, int major) {
    return RCIsSystemInstallerContent(extension, mime) ||
        (major >= 6 && ((extension && !strcasecmp(extension, "pkpass")) || mime_equal(mime, "application/vnd.apple.pkpass")));
}
int RCIsKnownDownloadExtension(const char *extension) {
    static const char *types[] = {"zip", "rar", "7z", "tar", "gz", "bz2", "xz", "deb", "ipa", "dmg", "iso", "exe", "bin", "torrent", "pdf",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "epub", "txt", "csv", "log", "c", "h", "m", "cpp", "py", "sh", "plist", "mp3", "m4a", "mp4", "mov"};
    for (size_t i = 0; i < sizeof(types) / sizeof(*types); ++i) if (extension && !strcasecmp(extension, types[i])) return 1;
    return 0;
}
