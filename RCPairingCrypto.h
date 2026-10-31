#ifndef RC_PAIRING_CRYPTO_H
#define RC_PAIRING_CRYPTO_H
/* PBKDF2-HMAC-SHA256, 100000 iterations, 16-byte salt, 32-byte result. */
void RCPairingDerive(const char *code, const unsigned char salt[16], unsigned char output[32]);
#endif
