#!/usr/bin/env bash
# Build on a native Linux filesystem so DrvFS permissions cannot break dpkg-deb.
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos installation}"
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build_dir="$(mktemp -d /tmp/receptor-build.XXXXXX)"
trap 'case "$build_dir" in /tmp/receptor-build.*) rm -rf -- "$build_dir" ;; esac' EXIT
mkdir -p "$project_dir/build" "$project_dir/packages"
cp "$project_dir/"*.h "$project_dir/"*.m "$project_dir/"*.x "$project_dir/"*.c \
   "$project_dir/Makefile" "$project_dir/control" "$project_dir/Receptor.plist" "$build_dir/"
cp -R "$project_dir/lib" "$build_dir/lib"
cp -R "$project_dir/App" "$project_dir/vendor" "$project_dir/Tools" "$build_dir/"
if [ -d "$project_dir/layout" ]; then
    cp -R "$project_dir/layout" "$build_dir/"
    chmod 0755 "$build_dir/layout/DEBIAN/postinst" "$build_dir/layout/DEBIAN/postrm"
fi
make -C "$build_dir" package FINALPACKAGE=1 "$@" 2>&1 | tee "$project_dir/build/wsl-build.log"
cp "$build_dir/packages/"*.deb "$project_dir/packages/"
cp "$build_dir/.theos/obj/Receptor.dylib" "$project_dir/build/Receptor.dylib"
cp -R "$build_dir/.theos/_/Applications/Receptor.app" "$project_dir/build/"
cp "$build_dir/.theos/_/usr/libexec/receptor-deb-helper" "$project_dir/build/receptor-deb-helper"
printf 'Artifacts copied to %s/packages and %s/build\n' "$project_dir" "$project_dir"
