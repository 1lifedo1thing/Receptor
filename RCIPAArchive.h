#ifndef RC_IPA_ARCHIVE_H
#define RC_IPA_ARCHIVE_H
#include <stddef.h>
/* Read exactly one Payload/<name>.app/Info.plist. No filesystem extraction.
 * Caller owns *output (free()). Unsupported ZIP64/encryption/oversized plists fail. */
int RCIPAReadInfoPlist(const char *path, unsigned char **output, size_t *length);
#endif
