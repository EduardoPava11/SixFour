#!/bin/bash
# Compile the SixFour native Zig kernels into a static library for the slice
# Xcode is currently building. Invoked from the SixFour target's preBuildScript
# (see project.yml). Driven entirely by the standard Xcode build environment:
#
#   PLATFORM_NAME  iphoneos | iphonesimulator
#   ARCHS          e.g. "arm64" (we target arm64 only; SixFour is arm64-only)
#   CONFIGURATION  Debug | Release
#   SRCROOT        repo root
#
# Output: $SRCROOT/Native/lib/$PLATFORM_NAME/libsixfour_native.a, which the
# target's LIBRARY_SEARCH_PATHS ($(SRCROOT)/Native/lib/$(PLATFORM_NAME)) and
# OTHER_LDFLAGS (-lsixfour_native) pick up at link time.
set -euo pipefail

# Locate zig (Xcode's script PATH is minimal; mirror the cabal-lookup pattern
# used by the spec-codegen gate).
ZIG=""
for candidate in "/opt/homebrew/bin/zig" "/usr/local/bin/zig" "$(command -v zig 2>/dev/null || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then ZIG="$candidate"; break; fi
done
if [ -z "$ZIG" ]; then
  echo "error: zig not found; cannot build native kernels" >&2
  exit 1
fi

SRC="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PLATFORM="${PLATFORM_NAME:-iphonesimulator}"
ARCH="${ARCHS:-arm64}"
ARCH="${ARCH%% *}"  # first arch if several

# Map (platform, arch) -> zig target triple.
case "$PLATFORM" in
  iphoneos)        ZIG_TARGET="${ARCH}-ios" ;;
  iphonesimulator) ZIG_TARGET="${ARCH}-ios-simulator" ;;
  *) echo "error: unsupported PLATFORM_NAME='$PLATFORM'" >&2; exit 1 ;;
esac
# zig uses aarch64, Xcode says arm64.
ZIG_TARGET="${ZIG_TARGET/arm64/aarch64}"

# Map Xcode configuration -> zig optimize mode. ReleaseSafe in Debug keeps
# bounds/overflow checks (catches UB in the parity tests) at near-Fast speed;
# ReleaseFast for shipping Release.
case "${CONFIGURATION:-Debug}" in
  Release) OPT="ReleaseFast" ;;
  *)       OPT="ReleaseSafe" ;;
esac

OUT_DIR="$SRC/Native/lib/$PLATFORM"
mkdir -p "$OUT_DIR"

# Emit a single relocatable object, then archive it with Apple's libtool.
#
# `zig build-lib` writes its own static archive, but the archive member offsets
# are not padded to 8 bytes; once enough exported symbols grow the leading
# symbol-table member, the `.o` member lands at a non-8-aligned offset and
# Apple's ld rejects it ("64-bit mach-o member ... not 8-byte aligned"). Going
# through `zig build-obj` + `libtool -static` produces a properly-aligned
# archive regardless of object size, while keeping the -lsixfour_native link
# interface (LIBRARY_SEARCH_PATHS + OTHER_LDFLAGS) unchanged.
OBJ="$OUT_DIR/sixfour_native.o"
LIB="$OUT_DIR/libsixfour_native.a"

echo "native: zig build-obj root.zig -target $ZIG_TARGET -O$OPT -> $OBJ"
"$ZIG" build-obj "$SRC/Native/src/root.zig" \
  -target "$ZIG_TARGET" \
  -O"$OPT" \
  --cache-dir "$SRC/Native/.zig-cache" \
  -femit-bin="$OBJ"

echo "native: libtool -static -> $LIB"
rm -f "$LIB"
libtool -static -o "$LIB" "$OBJ"
