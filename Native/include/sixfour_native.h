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

// ─────────────────────────────────────────────────────────────────────────
// Deterministic quantized core — palette + dither + GIF89a in fixed point.
//
// Replaces the GPU/Swift palette+dither+GIF path so the 64-frame GIF is
// produced 100% deterministically (bit-exact, cross-device). Boundary: Metal
// hands back linear-sRGB Float16 halfs; Zig does linear→OKLab (fixed-point
// cbrt) + quantize + dither + significance + OKLab→sRGB8 (fixed-point gamma) +
// LZW/GIF89a. OKLab is carried in Q16 (scale 2^16); distances accumulate in
// i64; nearest-centroid argmin ties resolve to the lowest index.
//
// Memory rule (unchanged): the caller owns ALL memory. Working memory is a
// caller-provided `scratch` buffer; size it with s4_burst_scratch_bytes. Size
// the GIF output buffer with s4_gif_encode_burst_bound. All functions return
// 0 on success; see the S4_RC_* codes below.
// ─────────────────────────────────────────────────────────────────────────

// Return codes shared by the quantized-core kernels.
#define S4_RC_OK                       0
#define S4_RC_NULL_PTR                 1
#define S4_RC_BAD_SHAPE                2   /* side/k/frame_count/p out of contract */
#define S4_RC_SCRATCH_TOO_SMALL        3
#define S4_RC_OUTPUT_TOO_SMALL         4
#define S4_RC_INFEASIBLE_SIGNIFICANCE  5   /* p < min_population*k (unreachable here) */
#define S4_RC_BAD_DITHER_MODE          6
#define S4_RC_NOT_IMPLEMENTED          100 /* kernel body lands in its spec-first stage */

// Dither modes for s4_dither_frame / s4_gif_encode_burst.
#define S4_DITHER_FLOYD_STEINBERG      0
#define S4_DITHER_ATKINSON             1
#define S4_DITHER_BLUE_NOISE           2   /* spatiotemporal STBN3D */
#define S4_DITHER_BLUE_NOISE_FROZEN    3

// Input colour space the burst entrypoint expects in `in_halfs`.
#define S4_INPUT_LINEAR_SRGB_HALF      0   /* default: Metal reads back linear-sRGB */
#define S4_INPUT_OKLAB_HALF            1   /* OKLab halfs (skip Zig-side conversion) */
#define S4_INPUT_YCBCR10               2   /* fallback: raw YCbCr10 integers */

// Logging: register a sink the core PUSHES one line to per kernel call (proving
// the work ran). `msg` is NOT null-terminated — use `len`. Pass NULL to disable.
// Logs are telemetry only; they never affect the returned bytes.
typedef void (*S4LogCallback)(const uint8_t *msg, size_t len);
void s4_set_log_callback(S4LogCallback cb);

// Upper bound on the GIF89a byte length for a burst of `frame_count` frames,
// each `side`×`side`, with `k`-entry local colour tables. 0 on a bad shape.
size_t s4_gif_encode_burst_bound(int32_t frame_count, int32_t side, int32_t k);

// Working-memory bytes the burst pipeline needs in `scratch`. 0 on a bad shape.
size_t s4_burst_scratch_bytes(int32_t frame_count, int32_t side, int32_t k);

// Whole-burst entrypoint: linear-sRGB halfs → deterministic GIF89a bytes. Owns
// the entire seed→Lloyd→dither→fill→LZW reduction so determinism cannot be
// broken by an interleaved caller step. Writes the byte count to `out_len`.
int32_t s4_gif_encode_burst(const uint16_t *in_halfs,
                            int32_t frame_count, int32_t side, int32_t k,
                            int32_t input_space, int32_t lloyd_iters,
                            int32_t dither_mode, int32_t serpentine,
                            const uint8_t *stbn_mask, uint16_t frame_delay_cs,
                            const uint8_t *comment, int32_t comment_len,
                            uint8_t *out_gif, size_t out_cap, size_t *out_len,
                            void *scratch, size_t scratch_cap);

// Composable sub-kernels (also used by the cross-language golden tests + the
// staged rollout). OKLab/linear values are interleaved Q16 triplets.
int32_t s4_widen_half_to_q16(const uint16_t *halfs, int32_t n, int32_t *out_q16);

int32_t s4_linear_to_oklab_q16(const int32_t *lin_q16, int32_t p, int32_t *out_oklab_q16);

int32_t s4_quantize_frame(const int32_t *oklab_q16, int32_t p, int32_t k,
                          int32_t lloyd_iters,
                          int32_t *out_centroids_q16, uint8_t *out_indices,
                          void *scratch, size_t scratch_cap);

int32_t s4_dither_frame(const int32_t *oklab_q16, const int32_t *centroids_q16,
                        int32_t p, int32_t k, int32_t dither_mode, int32_t serpentine,
                        const uint8_t *stbn_slice, uint8_t *out_indices,
                        void *scratch, size_t scratch_cap);

// out_cell_stats: k × 7 int32 (mean[3], std[3], count); pass NULL to skip.
int32_t s4_significance_fill(const int32_t *oklab_q16, const int32_t *centroids_q16,
                             int32_t p, int32_t k, int32_t min_population,
                             uint8_t *io_indices, int32_t *out_cell_stats,
                             void *scratch, size_t scratch_cap);

int32_t s4_palette_oklab_to_srgb8(const int32_t *centroids_q16, int32_t k,
                                  uint8_t *out_rgb, void *scratch, size_t scratch_cap);

int32_t s4_gif_assemble(const uint8_t *indices, const uint8_t *palettes_rgb,
                        int32_t frame_count, int32_t side, int32_t k,
                        uint16_t frame_delay_cs,
                        const uint8_t *comment, int32_t comment_len,
                        uint8_t *out_gif, size_t out_cap, size_t *out_len);

#endif // SIXFOUR_NATIVE_H
