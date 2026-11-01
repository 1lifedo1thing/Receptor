#ifndef RC_SYSTEM_CONTENT_H
#define RC_SYSTEM_CONTENT_H
/* These downloads belong to Safari's system profile/certificate installer. */
int RCIsSystemInstallerContent(const char *extension, const char *mime);
int RCIsSystemInstallerContentOnIOS(const char *extension, const char *mime, int major);
int RCIsKnownDownloadExtension(const char *extension);
#endif
