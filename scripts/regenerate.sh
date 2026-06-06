#!/bin/bash
# Regenerate SixFour.xcodeproj from project.yml, then apply post-fixes that
# xcodegen can't express directly.
#
# Post-fix: binary resource blobs (e.g. the 512-byte STBN tile stbn3d-8.bin and
# the gamma_lut.bin LUT) are plain *.bin paths, but Xcode 26 auto-classifies any
# *.bin path as `archive.macbinary`, which codesign then refuses to leave
# unsigned. Force the file type to plain `file` so codesign treats them as
# resources. (Renaming the files would touch the Haskell spec + drift gate, so
# the in-place pbxproj patch is the smaller change.) Patch EVERY archive.macbinary
# reference — a newly added *.bin resource is then covered automatically.
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate

PBX=SixFour.xcodeproj/project.pbxproj
sed -i '' \
  's|lastKnownFileType = archive.macbinary;|lastKnownFileType = file;|g' \
  "$PBX"

if grep -q "archive.macbinary" "$PBX"; then
  echo "regenerate.sh: warning — archive.macbinary still present in $PBX" >&2
  exit 1
fi

echo "regenerate.sh: project regenerated and patched."
