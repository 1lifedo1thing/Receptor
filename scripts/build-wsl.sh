#!/usr/bin/env bash
# Build on a native Linux filesystem so DrvFS permissions cannot break dpkg-deb.
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos installation}"
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build_dir="$(mktemp -d /tmp/receptor-build.XXXXXX)"
trap 'case "$build_dir" in /tmp/receptor-build.*) rm -rf -- "$build_dir" ;; esac' EXIT
mkdir -p "$project_dir/build" "$project_dir/packages"
cp "$project_dir/"*.h "$project_dir/"*.m "$project_dir/"*.x \
   "$project_dir/Makefile" "$project_dir/control" "$project_dir/Receptor.plist" "$build_dir/"
cp -R "$project_dir/lib" "$build_dir/lib"
make -C "$build_dir" package FINALPACKAGE=1 "$@" 2>&1 | tee "$project_dir/build/wsl-build.log"
cp "$build_dir/packages/"*.deb "$project_dir/packages/"
cp "$build_dir/.theos/obj/Receptor.dylib" "$project_dir/build/Receptor.dylib"
printf 'Artifacts copied to %s/packages and %s/build\n' "$project_dir" "$project_dir"
