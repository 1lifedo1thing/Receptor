#!/usr/bin/env bash
# Build on a native Linux filesystem so DrvFS permissions cannot break dpkg-deb.
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos installation}"
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
output_dir="$project_dir/build"
legacy_args=()
if [ "${RECEPTOR_LEGACY32:-0}" = 1 ]; then output_dir="$project_dir/build/ios32"; legacy_args=(RECEPTOR_LEGACY32=1); fi
build_dir="$(mktemp -d /tmp/receptor-build.XXXXXX)"
trap 'case "$build_dir" in /tmp/receptor-build.*) rm -rf -- "$build_dir" ;; esac' EXIT
mkdir -p "$output_dir" "$project_dir/packages"
cp "$project_dir/"*.h "$project_dir/"*.m "$project_dir/"*.x "$project_dir/"*.c \
   "$project_dir/Makefile" "$project_dir/control" "$project_dir/Receptor.plist" "$build_dir/"
cp -R "$project_dir/lib" "$build_dir/lib"
cp -R "$project_dir/App" "$project_dir/vendor" "$project_dir/Tools" "$build_dir/"
if [ -d "$project_dir/layout" ]; then
    cp -R "$project_dir/layout" "$build_dir/"
    chmod 0755 "$build_dir/layout/DEBIAN/postinst" "$build_dir/layout/DEBIAN/postrm" "$build_dir/layout/DEBIAN/prerm"
fi
if [ "${RECEPTOR_LEGACY32:-0}" = 1 ]; then
    test -f "$project_dir/vendor/tls32/lib/libcurl.a"
    cp -R "$project_dir/vendor/tls32" "$build_dir/vendor/"
    cp "$project_dir/Legacy32/control" "$build_dir/control"
    cp "$project_dir/Legacy32/Info.plist" "$build_dir/App/Info.plist"
    cp "$project_dir/Legacy32/postinst" "$build_dir/layout/DEBIAN/postinst"
    chmod 0755 "$build_dir/layout/DEBIAN/postinst"
    rm -f "$build_dir/layout/Library/LaunchDaemons/com.receptor.remote.plist"
fi
make -C "$build_dir" package FINALPACKAGE=1 "${legacy_args[@]}" "$@" 2>&1 | tee "$output_dir/wsl-build.log"
cp "$build_dir/packages/"*.deb "$project_dir/packages/"
cp "$build_dir/.theos/obj/Receptor.dylib" "$output_dir/Receptor.dylib"
cp -R "$build_dir/.theos/_/Applications/Receptor.app" "$output_dir/"
cp "$build_dir/.theos/_/usr/libexec/receptor-deb-helper" "$output_dir/receptor-deb-helper"
cp "$build_dir/.theos/_/usr/libexec/receptor-package-helper" "$output_dir/receptor-package-helper"
if [ "${RECEPTOR_LEGACY32:-0}" != 1 ]; then
    cp "$build_dir/.theos/_/usr/libexec/receptor-remote-agent" "$output_dir/receptor-remote-agent"
    cp "$build_dir/.theos/_/usr/libexec/receptor-file-helper" "$output_dir/receptor-file-helper"
fi
printf 'Artifacts copied to %s/packages and %s\n' "$project_dir" "$output_dir"
