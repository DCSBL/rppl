#!/usr/bin/env bash
# Unpacks the `test-products` artifact of the macOS CI build job and prints the .xctestrun file for
# one platform, so a test job can run `xcodebuild test-without-building` instead of compiling again.
#
# Usage: unpack_test_products.sh TARBALL DEST_DIR iphonesimulator|watchsimulator
#
# The tarball is the Build/Products directory of `xcodebuild build-for-testing` (packed with tar so
# the executable bits and symlinks inside the .app bundles survive the artifact upload). An
# .xctestrun refers to its products through __TESTROOT__, the directory it sits in, so the file
# only works next to the unpacked Debug-<platform> folder.
set -euo pipefail
tarball="$1" dest="$2" platform="$3"

case "$platform" in
  iphonesimulator) prefix="Rppl_" ;;
  watchsimulator) prefix="RpplWatch_" ;;
  *) echo "unknown platform ${platform} (iphonesimulator|watchsimulator)" >&2; exit 2 ;;
esac

mkdir -p "$dest"
tar -C "$dest" -xf "$tarball"

shopt -s nullglob
runs=("$dest"/${prefix}*"${platform}"*.xctestrun)
if [ "${#runs[@]}" -ne 1 ]; then
  echo "expected one ${prefix}*${platform}*.xctestrun in ${dest}, found ${#runs[@]}:" >&2
  ls "$dest" >&2
  exit 1
fi
echo "${runs[0]}"
