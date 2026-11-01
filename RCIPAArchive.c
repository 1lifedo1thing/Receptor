#include "RCIPAArchive.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <zlib.h>

static uint16_t le16(const unsigned char *p) { return p[0] | ((uint16_t)p[1] << 8); }
static uint32_t le32(const unsigned char *p) { return le16(p) | ((uint32_t)le16(p + 2) << 16); }
static int read_at(int fd, void *data, size_t length, uint64_t offset) {
    unsigned char *p = data;
    while (length) {
        ssize_t n = pread(fd, p, length, (off_t)offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
        p += n; length -= (size_t)n; offset += (size_t)n;
    }
    return 1;
}
static int info_name(const unsigned char *name, size_t length) {
    const char prefix[] = "Payload/", suffix[] = ".app/Info.plist";
    if (length <= sizeof(prefix) - 1 + sizeof(suffix) - 1 || memchr(name, 0, length) ||
        memcmp(name, prefix, sizeof(prefix) - 1) || memcmp(name + length - (sizeof(suffix) - 1), suffix, sizeof(suffix) - 1)) return 0;
    size_t end = length - (sizeof(suffix) - 1);
    for (size_t i = sizeof(prefix) - 1; i < end; i++) if (name[i] == '/' || name[i] == '\\') return 0;
    return 1;
}
int RCIPAReadInfoPlist(const char *path, unsigned char **output, size_t *length) {
    if (!path || !output || !length) return 0;
    *output = NULL; *length = 0;
    int fd = open(path, O_RDONLY | O_NOFOLLOW); if (fd < 0) return 0;
    struct stat st;
    unsigned char *tail = NULL, *compressed = NULL, *plain = NULL;
    int ok = 0, found = 0;
    uint32_t compressedSize = 0, plainSize = 0, checksum = 0, localOffset = 0;
    uint16_t selectedMethod = 0, selectedFlags = 0, selectedNameLength = 0;
    unsigned char selectedName[1024];
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 22 || (uint64_t)st.st_size >= UINT32_MAX) goto done;
    size_t tailLength = (uint64_t)st.st_size < 65557 ? (size_t)st.st_size : 65557;
    uint64_t tailOffset = (uint64_t)st.st_size - tailLength;
    tail = malloc(tailLength); if (!tail || !read_at(fd, tail, tailLength, tailOffset)) goto done;
    const unsigned char *eocd = NULL; uint64_t endOffset = 0;
    for (size_t i = tailLength - 22 + 1; i-- > 0;) {
        if (le32(tail + i) == 0x06054b50 && i + 22 + le16(tail + i + 20) == tailLength) {
            eocd = tail + i; endOffset = tailOffset + i; break;
        }
    }
    if (!eocd || le16(eocd + 4) || le16(eocd + 6) || le16(eocd + 8) != le16(eocd + 10)) goto done;
    uint16_t entries = le16(eocd + 10);
    uint32_t directorySize = le32(eocd + 12), directoryOffset = le32(eocd + 16);
    if (!entries || entries == UINT16_MAX || directorySize == UINT32_MAX || directoryOffset == UINT32_MAX ||
        (uint64_t)directoryOffset + directorySize != endOffset) goto done;
    uint64_t cursor = directoryOffset;
    for (uint32_t i = 0; i < entries; i++) {
        unsigned char header[46], name[1024];
        if (cursor + sizeof(header) > endOffset || !read_at(fd, header, sizeof(header), cursor) || le32(header) != 0x02014b50) goto done;
        uint16_t nameLength = le16(header + 28), extraLength = le16(header + 30), commentLength = le16(header + 32);
        uint64_t next = cursor + sizeof(header) + nameLength + extraLength + commentLength;
        if (!nameLength || next > endOffset || le16(header + 34)) goto done;
        if (nameLength < sizeof(name)) {
            if (!read_at(fd, name, nameLength, cursor + sizeof(header))) goto done;
            if (info_name(name, nameLength)) {
                if (found++) goto done; // An ambiguous multi-app/duplicate Info.plist is not guessed.
                selectedFlags = le16(header + 8); selectedMethod = le16(header + 10);
                checksum = le32(header + 16); compressedSize = le32(header + 20); plainSize = le32(header + 24);
                localOffset = le32(header + 42); selectedNameLength = nameLength; memcpy(selectedName, name, nameLength);
                if ((selectedFlags & 0x41) || (selectedMethod != 0 && selectedMethod != 8) || !plainSize ||
                    plainSize > 2 * 1024 * 1024 || !compressedSize || compressedSize > 2 * 1024 * 1024 || localOffset >= directoryOffset) goto done;
            }
        }
        cursor = next;
    }
    if (found != 1 || cursor != endOffset) goto done;
    unsigned char local[30], name[1024];
    if ((uint64_t)localOffset + sizeof(local) > directoryOffset || !read_at(fd, local, sizeof(local), localOffset) ||
        le32(local) != 0x04034b50 || le16(local + 6) != selectedFlags || le16(local + 8) != selectedMethod ||
        le16(local + 26) != selectedNameLength) goto done;
    uint64_t dataOffset = (uint64_t)localOffset + sizeof(local) + selectedNameLength + le16(local + 28);
    if (dataOffset + compressedSize > directoryOffset || !read_at(fd, name, selectedNameLength, (uint64_t)localOffset + sizeof(local)) ||
        memcmp(name, selectedName, selectedNameLength)) goto done;
    if (!(selectedFlags & 8) && (le32(local + 14) != checksum || le32(local + 18) != compressedSize || le32(local + 22) != plainSize)) goto done;
    compressed = malloc(compressedSize); plain = malloc(plainSize);
    if (!compressed || !plain || !read_at(fd, compressed, compressedSize, dataOffset)) goto done;
    if (selectedMethod == 0) {
        if (compressedSize != plainSize) goto done;
        memcpy(plain, compressed, plainSize);
    } else {
        z_stream stream; memset(&stream, 0, sizeof(stream));
        stream.next_in = compressed; stream.avail_in = compressedSize; stream.next_out = plain; stream.avail_out = plainSize;
        if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) goto done;
        int result = inflate(&stream, Z_FINISH);
        int valid = result == Z_STREAM_END && stream.total_in == compressedSize && stream.total_out == plainSize;
        inflateEnd(&stream); if (!valid) goto done;
    }
    if ((uint32_t)crc32(0L, plain, plainSize) != checksum) goto done;
    *output = plain; *length = plainSize; plain = NULL; ok = 1;
done:
    free(tail); free(compressed); free(plain); close(fd); return ok;
}
