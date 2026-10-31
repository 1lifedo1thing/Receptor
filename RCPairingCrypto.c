#include "RCPairingCrypto.h"
#include <string.h>
#ifdef RC_PAIRING_HOST_TEST
#include <openssl/hmac.h>
static void pairing_hmac(const char *code, const unsigned char *bytes, size_t length, unsigned char output[32]) {
    unsigned int size = 32;
    HMAC(EVP_sha256(), code, (int)strlen(code), bytes, length, output, &size);
}
#else
#include <CommonCrypto/CommonHMAC.h>
static void pairing_hmac(const char *code, const unsigned char *bytes, size_t length, unsigned char output[32]) {
    CCHmac(kCCHmacAlgSHA256, code, strlen(code), bytes, length, output);
}
#endif
void RCPairingDerive(const char *code, const unsigned char salt[16], unsigned char output[32]) {
    unsigned char first[20], u[32], next[32];
    memcpy(first, salt, 16); first[16] = first[17] = first[18] = 0; first[19] = 1;
    pairing_hmac(code, first, sizeof(first), u); memcpy(output, u, 32);
    for (unsigned int iteration = 1; iteration < 100000; ++iteration) {
        pairing_hmac(code, u, 32, next); memcpy(u, next, 32);
        for (int j = 0; j < 32; ++j) output[j] ^= u[j];
    }
    memset(first, 0, sizeof(first)); memset(u, 0, sizeof(u)); memset(next, 0, sizeof(next));
}
