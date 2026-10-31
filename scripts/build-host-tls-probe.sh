#!/usr/bin/env bash
set -euo pipefail
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
work="$(mktemp -d /tmp/receptor-host-tls.XXXXXX)"
trap 'case "$work" in /tmp/receptor-host-tls.*) rm -rf -- "$work" ;; esac' EXIT
tar -xf "$root/build/tls-cache/mbedtls-3.6.7.tar.bz2" -C "$work"
tar -xf "$root/build/tls-cache/curl-8.23.0.tar.xz" -C "$work"
flags="-O2 -DMBEDTLS_THREADING_C -DMBEDTLS_THREADING_PTHREAD"
make -C "$work/mbedtls-3.6.7" -j4 lib CC=cc AR=ar CFLAGS="$flags" > "$root/build/host-mbedtls.log" 2>&1
prefix="$work/prefix"
mkdir -p "$prefix/lib" "$prefix/include"
cp "$work/mbedtls-3.6.7/library/"*.a "$prefix/lib/"
cp -R "$work/mbedtls-3.6.7/include/mbedtls" "$work/mbedtls-3.6.7/include/psa" "$prefix/include/"
cd "$work/curl-8.23.0"
CFLAGS="$flags" ./configure --disable-shared --enable-static --with-mbedtls="$prefix" --without-openssl \
 --without-libpsl --without-libidn2 --without-zlib --without-brotli --without-zstd \
 --without-libssh2 --without-librtmp --without-nghttp2 --without-nghttp3 --without-ngtcp2 \
 --disable-ldap --disable-ldaps --disable-threaded-resolver --disable-ares \
 --disable-docs --disable-manual > "$root/build/host-curl-configure.log" 2>&1
make -j4 -C lib > "$root/build/host-curl.log" 2>&1
cc -Iinclude "$root/tests/tls_probe.c" lib/.libs/libcurl.a "$prefix/lib/libmbedtls.a" \
 "$prefix/lib/libmbedx509.a" "$prefix/lib/libmbedcrypto.a" -lpthread -lm -o "$root/build/tls-probe"
echo "Built native test probe with the same pinned TLS stack."
