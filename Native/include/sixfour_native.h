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

// ─────────────────────────────────────────────────────────────────────────
// Look-NN deploy blob — the MLX-trained genome, loaded for the hand-written
// on-device forward pass (NO mlx-swift / NO CoreML; CLAUDE.md Tier-2 zero-deps).
//
// Producer: trainer/export_look_net_blob.py (format documented there).
// The blob is a little-endian binary: 16-byte header ("S4LN", version=1,
// tensor_count, reserved) then one record per tensor (name_len+name, ndim,
// int32 shape, row-major float32 data). Tensors arrive in this fixed order:
//   phi (64,10), w1 (64,64), w2 (64,64), halt_w (1,2), halt_b (1),
//   head0..head7 (d_i, 64) with d_i = {3,3,6,12,24,48,96,192}.
// Weights are RAW (pre-σ-mask); the forward pass applies the σ-block-diagonal
// mask exactly as the Haskell spec / MLX / PyTorch ports do.
//
// Memory rule (unchanged): the caller (Swift) owns ALL memory. `s4_load_look_net`
// reads from the caller's `blob` buffer and writes float32 pointers into the
// caller-provided `out` struct that ALIAS into `blob` (no copy, no allocation);
// the pointers stay valid only while `blob` is alive. Returns 0 on success,
// non-zero on a malformed blob (bad magic, version, or truncation).
// ─────────────────────────────────────────────────────────────────────────

#define S4_LOOK_NET_MAGIC   0x4E4C3453u  /* "S4LN" little-endian */
#define S4_LOOK_NET_VERSION  1u
#define S4_LOOK_NET_HEAD_COUNT  8        /* 8 decoder-level heads */

typedef struct {
    // Each pointer aliases into the caller's blob buffer (row-major float32).
    const float *phi;        // (MODEL_DIM=64, GMM_TOKEN_DIM=10)
    const float *w1;         // (64, 64)
    const float *w2;         // (64, 64)
    const float *halt_w;     // (1, HALT_FEATURE_DIM=2)
    const float *halt_b;     // (1,)
    const float *heads[S4_LOOK_NET_HEAD_COUNT];  // head i: (head_dims[i], 64)
    int32_t      head_dims[S4_LOOK_NET_HEAD_COUNT]; // {3,3,6,12,24,48,96,192}
} S4LookNetWeights;

// Parse a look-NN deploy blob. `blob`/`len` describe the caller-owned buffer;
// on success `out` is populated with float32 pointers aliasing into `blob`.
// Returns 0 on success; non-zero (and `out` left unspecified) on a bad blob.
int32_t s4_load_look_net(const uint8_t *blob, size_t len, S4LookNetWeights *out);

#endif // SIXFOUR_NATIVE_H
