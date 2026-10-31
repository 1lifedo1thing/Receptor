#!/usr/bin/env bash
# Rebuild the bundled armv7 HTTPS transport from checksum-pinned upstream releases.
set -euo pipefail
: "${THEOS:?Set THEOS first}"
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cache="$root/build/tls-cache"
mkdir -p "$cache" "$root/vendor/tls/lib" "$root/vendor/tls/include" "$root/vendor/tls/licenses"
fetch() {
    local name="$1" url="$2" expected="$3"
    if [ ! -f "$cache/$name" ]; then curl --fail --location --retry 2 "$url" -o "$cache/$name"; fi
    printf '%s  %s\n' "$expected" "$cache/$name" | sha256sum --check
}
fetch mbedtls-3.6.7.tar.bz2 https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2 a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6
fetch curl-8.23.0.tar.xz https://curl.se/download/curl-8.23.0.tar.xz 8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
work="$(mktemp -d /tmp/receptor-tls.XXXXXX)"
trap 'if [ -f "$work/curl-8.23.0/config.log" ]; then cp "$work/curl-8.23.0/config.log" "$root/build/curl-config.log"; fi; case "$work" in /tmp/receptor-tls.*) rm -rf -- "$work" ;; esac' EXIT
tar -xf "$cache/mbedtls-3.6.7.tar.bz2" -C "$work"
tar -xf "$cache/curl-8.23.0.tar.xz" -C "$work"
tool="$THEOS/toolchain/linux/iphone/bin"
sdk="$THEOS/sdks/iPhoneOS5.0.sdk"
flags="--target=armv7-apple-ios4.0 -B$tool -isysroot $sdk -miphoneos-version-min=4.0 -Os -fPIC -DMBEDTLS_PLATFORM_MS_TIME_ALT -DMBEDTLS_THREADING_C -DMBEDTLS_THREADING_PTHREAD"
make -C "$work/mbedtls-3.6.7" -j4 lib CC="$tool/clang" AR="$tool/llvm-ar" CFLAGS="$flags" > "$root/build/mbedtls-build.log" 2>&1
"$tool/clang" $flags -c "$root/scripts/tls-clock.c" -o "$work/tls-clock.o"
"$tool/llvm-ar" rcs "$work/mbedtls-3.6.7/library/libmbedcrypto.a" "$work/tls-clock.o"
prefix="$work/prefix"
mkdir -p "$prefix/lib" "$prefix/include"
cp "$work/mbedtls-3.6.7/library/"*.a "$prefix/lib/"
cp -R "$work/mbedtls-3.6.7/include/mbedtls" "$work/mbedtls-3.6.7/include/psa" "$prefix/include/"
cd "$work/curl-8.23.0"
CC="$tool/clang" AR="$tool/llvm-ar" RANLIB="$tool/llvm-ranlib" \
 CFLAGS="$flags" LDFLAGS="$flags" PKG_CONFIG=false ./configure \
 --host=arm-apple-darwin --prefix="$prefix" --disable-shared --enable-static \
 --with-mbedtls="$prefix" --without-openssl --without-libpsl --without-libidn2 \
 --without-zstd --without-brotli --without-zlib --without-libssh2 --without-librtmp \
 --without-nghttp2 --without-nghttp3 --without-ngtcp2 --disable-ldap --disable-ldaps \
 --disable-ftp --disable-file --disable-tftp --disable-telnet --disable-dict \
 --disable-gopher --disable-imap --disable-pop3 --disable-smtp --disable-rtsp \
 --disable-smb --disable-mqtt --disable-websockets --disable-threaded-resolver \
 --disable-ares --disable-manual --disable-docs --disable-libcurl-option \
 --without-ca-path --with-ca-bundle='/Library/Application Support/Receptor/cacert.pem' \
 > "$root/build/curl-configure.log" 2>&1
make -j4 -C lib > "$root/build/curl-build.log" 2>&1
cp lib/.libs/libcurl.a "$root/vendor/tls/lib/"
cp "$prefix/lib/"*.a "$root/vendor/tls/lib/"
mkdir -p "$root/vendor/tls/include/curl"
cp include/curl/*.h "$root/vendor/tls/include/curl/"
cp COPYING "$root/vendor/tls/licenses/curl.txt"
cp "$work/mbedtls-3.6.7/LICENSE" "$root/vendor/tls/licenses/mbedtls.txt"
printf 'Built curl 8.23.0 + Mbed TLS 3.6.7 for armv7 / iOS 4.0.\n'
