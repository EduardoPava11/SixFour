#!/bin/bash
# Regenerate SixFour.xcodeproj from project.yml, then apply post-fixes that
# xcodegen can't express directly.
#
# Post-fix: stbn3d-8.bin is a 512-byte STBN tile, but Xcode 26 auto-classifies
# any *.bin path as `archive.macbinary`, which codesign then refuses to leave
# unsigned. Force the file type to plain `file` so codesign treats it as a
# resource. (Renaming the file would touch the Haskell spec + drift gate,
# so the in-place pbxproj patch is the smaller change.)
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate

PBX=SixFour.xcodeproj/project.pbxproj
sed -i '' \
  's|/\* stbn3d-8.bin \*/ = {isa = PBXFileReference; lastKnownFileType = archive.macbinary;|/* stbn3d-8.bin */ = {isa = PBXFileReference; lastKnownFileType = file;|' \
  "$PBX"

if grep -q "archive.macbinary" "$PBX"; then
  echo "regenerate.sh: warning — archive.macbinary still present in $PBX" >&2
  exit 1
fi

echo "regenerate.sh: project regenerated and patched."
