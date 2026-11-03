#import "RCRemoteCrypto.h"
#include <stdlib.h>
#include <string.h>
#ifdef RC_REMOTE_HOST_TEST
#if defined(__APPLE__)
#error Remote host test mode must never be used for an Apple binary.
#endif
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/sha.h>
#else
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <mbedtls/pk.h>
#include <mbedtls/rsa.h>
#endif

NSData *RCRemoteRandom(NSUInteger count) {
    NSMutableData *data=[NSMutableData dataWithLength:count]; unsigned char *bytes=[data mutableBytes];
    for(NSUInteger i=0;i<count;) { uint32_t value=arc4random(); NSUInteger amount=MIN((NSUInteger)4,count-i); memcpy(bytes+i,&value,amount); i+=amount; } return data;
}
static NSData *Hash(NSData *data) {
    unsigned char hash[32];
#ifdef RC_REMOTE_HOST_TEST
    SHA256([data bytes],[data length],hash);
#else
    CC_SHA256([data bytes],(CC_LONG)[data length],hash);
#endif
    return [NSData dataWithBytes:hash length:32];
}
static NSData *Mac(NSData *key, NSData *message) {
    unsigned char bytes[32];
#ifdef RC_REMOTE_HOST_TEST
    unsigned int size=32; HMAC(EVP_sha256(),[key bytes],(int)[key length],[message bytes],[message length],bytes,&size);
#else
    CCHmac(kCCHmacAlgSHA256,[key bytes],[key length],[message bytes],[message length],bytes);
#endif
    return [NSData dataWithBytes:bytes length:32];
}
static NSString *Hex(NSData *data) { const unsigned char *bytes=[data bytes]; NSMutableString *text=[NSMutableString string]; for(NSUInteger i=0;i<[data length];i++) [text appendFormat:@"%02x",bytes[i]]; return text; }
NSString *RCRemoteHash(NSData *data) { return Hex(Hash(data)); }
static NSData *Key(NSData *seed,NSString *purpose) { return Mac(seed,[[@"Receptor remote v3 " stringByAppendingString:purpose] dataUsingEncoding:NSASCIIStringEncoding]); }
NSString *RCRemoteBase64(NSData *data) {
    const char *alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; const unsigned char *bytes=[data bytes]; NSUInteger length=[data length]; NSMutableString *text=[NSMutableString string];
    for(NSUInteger i=0;i<length;i+=3) { unsigned int value=(unsigned int)bytes[i]<<16; if(i+1<length)value|=(unsigned int)bytes[i+1]<<8; if(i+2<length)value|=bytes[i+2]; [text appendFormat:@"%c%c%c%c",alphabet[(value>>18)&63],alphabet[(value>>12)&63],i+1<length?alphabet[(value>>6)&63]:'=',i+2<length?alphabet[value&63]:'=']; } return text;
}
NSData *RCRemoteUnbase64(NSString *text) {
    if(![text isKindOfClass:[NSString class]] || [text length]>6*1024*1024) return nil;
    NSString *clean=[[text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    if([clean length]%4 || ![clean canBeConvertedToEncoding:NSASCIIStringEncoding]) return nil;
    const char *alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",*input=[clean UTF8String]; NSMutableData *data=[NSMutableData data];
    for(NSUInteger i=0;i<[clean length];i+=4) {
        unsigned int value=0; int pad=0;
        for(int j=0;j<4;j++) { const char *found=input[i+j]=='='?NULL:strchr(alphabet,input[i+j]); if(input[i+j]=='=') { if(j<2 || i+4!=[clean length]) return nil; pad++; value<<=6; } else { if(!found || pad) return nil; value=(value<<6)|(unsigned int)(found-alphabet); } }
        unsigned char bytes[3]={(unsigned char)(value>>16),(unsigned char)(value>>8),(unsigned char)value}; [data appendBytes:bytes length:3-pad];
    }
    return [RCRemoteBase64(data) isEqual:clean]?data:nil;
}
NSString *RCRemoteFingerprint(NSString *pem) {
    if(![pem hasPrefix:@"-----BEGIN PUBLIC KEY-----"] || [pem length]>4096) return nil;
    NSString *base=[pem stringByReplacingOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----" withString:@""]; base=[base stringByReplacingOccurrencesOfString:@"-----END PUBLIC KEY-----" withString:@""];
    NSData *data=RCRemoteUnbase64(base); return data?RCRemoteHash(data):nil;
}
#ifndef RC_REMOTE_HOST_TEST
static int RandomCallback(void *context,unsigned char *output,size_t length) { (void)context; NSData *random=RCRemoteRandom(length); memcpy(output,[random bytes],length); return 0; }
#endif
NSData *RCRemoteSeal(NSString *pem,NSData *seed) {
    if([seed length]!=32 || !RCRemoteFingerprint(pem)) return nil; unsigned char output[512]; size_t length=sizeof(output); int success=0;
#ifdef RC_REMOTE_HOST_TEST
    BIO *bio=BIO_new_mem_buf((void *)[pem UTF8String],(int)[pem lengthOfBytesUsingEncoding:NSUTF8StringEncoding]); EVP_PKEY *key=bio?PEM_read_bio_PUBKEY(bio,NULL,NULL,NULL):NULL; EVP_PKEY_CTX *context=key?EVP_PKEY_CTX_new(key,NULL):NULL;
    if(context && EVP_PKEY_bits(key)==2048 && EVP_PKEY_encrypt_init(context)>0 && EVP_PKEY_CTX_set_rsa_padding(context,RSA_PKCS1_OAEP_PADDING)>0 && EVP_PKEY_CTX_set_rsa_oaep_md(context,EVP_sha1())>0 && EVP_PKEY_encrypt(context,output,&length,[seed bytes],[seed length])>0) success=1;
    if(context)EVP_PKEY_CTX_free(context); if(key)EVP_PKEY_free(key); if(bio)BIO_free(bio);
#else
    mbedtls_pk_context key; mbedtls_pk_init(&key);
    if(mbedtls_pk_parse_public_key(&key,(const unsigned char *)[pem UTF8String],[pem lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+1)==0 && mbedtls_pk_get_type(&key)==MBEDTLS_PK_RSA && mbedtls_pk_get_bitlen(&key)==2048) {
        mbedtls_rsa_set_padding(mbedtls_pk_rsa(key),MBEDTLS_RSA_PKCS_V21,MBEDTLS_MD_SHA1);
        if(mbedtls_pk_encrypt(&key,[seed bytes],[seed length],output,&length,sizeof(output),RandomCallback,NULL)==0) success=1;
    }
    mbedtls_pk_free(&key);
#endif
    return success && length==256?[NSData dataWithBytes:output length:length]:nil;
}
static NSData *Cipher(BOOL encrypt,NSData *key,NSData *iv,NSData *input) {
    NSMutableData *output=[NSMutableData dataWithLength:[input length]+16]; size_t length=0;
#ifdef RC_REMOTE_HOST_TEST
    EVP_CIPHER_CTX *context=EVP_CIPHER_CTX_new(); int count=0,last=0; BOOL okay=context && EVP_CipherInit_ex(context,EVP_aes_256_cbc(),NULL,[key bytes],[iv bytes],encrypt?1:0)==1 && EVP_CipherUpdate(context,[output mutableBytes],&count,[input bytes],(int)[input length])==1 && EVP_CipherFinal_ex(context,(unsigned char *)[output mutableBytes]+count,&last)==1; if(context)EVP_CIPHER_CTX_free(context); if(!okay)return nil; length=(size_t)(count+last);
#else
    if(CCCrypt(encrypt?kCCEncrypt:kCCDecrypt,kCCAlgorithmAES128,kCCOptionPKCS7Padding,[key bytes],[key length],[iv bytes],[input bytes],[input length],[output mutableBytes],[output length],&length)!=kCCSuccess)return nil;
#endif
    [output setLength:length]; return output;
}
NSData *RCRemoteEncrypt(NSData *seed,NSData *plain) {
    if([seed length]!=32 || [plain length]>3*1024*1024)return nil; NSData *iv=RCRemoteRandom(16),*cipher=Cipher(YES,Key(seed,@"encryption"),iv,plain); if(!cipher)return nil;
    unsigned char version=3; NSMutableData *frame=[NSMutableData dataWithBytes:&version length:1]; [frame appendData:iv]; [frame appendData:cipher]; return frame;
}
NSData *RCRemoteDecrypt(NSData *seed,NSData *frame) {
    if([seed length]!=32 || [frame length]<33 || [frame length]>4*1024*1024 || ((const unsigned char *)[frame bytes])[0]!=3 || ([frame length]-17)%16)return nil;
    return Cipher(NO,Key(seed,@"encryption"),[frame subdataWithRange:NSMakeRange(1,16)],[frame subdataWithRange:NSMakeRange(17,[frame length]-17)]);
}
NSString *RCRemoteMAC(NSData *seed,NSString *direction,NSString *device,NSString *nonce,NSData *frame) {
    NSString *message=[NSString stringWithFormat:@"%@\n/v3/control\n%@\n%@\n%@",direction,device,nonce,RCRemoteHash(frame)]; return Hex(Mac(Key(seed,@"authentication"),[message dataUsingEncoding:NSASCIIStringEncoding]));
}
NSString *RCRemoteEnrollment(NSString *pairingKey,NSString *device,NSData *sealed) { return Hex(Mac([pairingKey dataUsingEncoding:NSASCIIStringEncoding],[[NSString stringWithFormat:@"enroll\n%@\n%@",device,RCRemoteHash(sealed)] dataUsingEncoding:NSASCIIStringEncoding])); }
BOOL RCRemoteEqual(NSString *a,NSString *b) { if(!a || !b || [a length]!=[b length])return NO; unsigned int diff=0; for(NSUInteger i=0;i<[a length];i++)diff|=[a characterAtIndex:i]^[b characterAtIndex:i]; return diff==0; }
