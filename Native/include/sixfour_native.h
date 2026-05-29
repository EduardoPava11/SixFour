// SixFour native kernels — C ABI contract.
//
// Implemented in Zig (Native/src/*.zig), compiled to libsixfour_native.a by
// Native/build-ios.sh and linked into the SixFour app target. The Swift side
// imports these declarations through SixFour-Bridging-Header.h.
//
// Memory rule: the caller (Swift) owns ALL memory. No allocator crosses this
// boundary. Functions read from `const` input pointers and write into
// caller-provided output buffers, returning the element/byte count written.

#ifndef SIXFOUR_NATIVE_H
#define SIXFOUR_NATIVE_H

#include <stddef.h>
#include <stdint.h>

// Toolchain probe — returns x + 1. Used by the build/link smoke test only.
uint32_t s4_probe(uint32_t x);

#endif // SIXFOUR_NATIVE_H
