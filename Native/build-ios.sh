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

echo "native: zig build-lib root.zig -target $ZIG_TARGET -O$OPT -> $OUT_DIR"
"$ZIG" build-lib "$SRC/Native/src/root.zig" \
  -target "$ZIG_TARGET" \
  -O"$OPT" \
  --cache-dir "$SRC/Native/.zig-cache" \
  -femit-bin="$OUT_DIR/libsixfour_native.a"
