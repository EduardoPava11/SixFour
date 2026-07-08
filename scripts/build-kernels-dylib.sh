#!/bin/bash
# Build the owned Swift kernel core as a macOS dylib for the trainer.
#
# The SAME sources the iPhone app compiles (SixFour/Kernels/*.swift) are built
# here as libsixfour_kernels.dylib and loaded by trainer/native_kernels.py via
# ctypes — the @_cdecl exports keep the exact C ABI the Zig core had, so the
# trainer's synthetic data engine runs the identical code path as the device:
# no train/deploy skew. (Successor to `cd Native && zig build`, 2026-07-06.)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/trainer/lib"
OUT="$OUT_DIR/libsixfour_kernels.dylib"

mkdir -p "$OUT_DIR"

swiftc -O -parse-as-library -emit-library \
  "$ROOT"/SixFour/Kernels/*.swift \
  -o "$OUT"

echo "built $OUT"
