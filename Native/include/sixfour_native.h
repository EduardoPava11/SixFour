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

// GIFA → GIFB: collapse `t` per-frame Q16 palettes (contiguous t*k_in*3 i32) into
// ONE global palette: maximin selects k_out global leaves; every pooled colour is
// assigned to its nearest leaf (the per-frame index map, flattened to t*k_in).
// Shares s4_quantize_frame's byte-exact maximin path. Mirrors
// SixFour.Spec.Collapse.globalCollapseQ16. k_out <= 256 and <= t*k_in.
// scratch >= (t*k_in)*8 + 3*k_out*8 + k_out*4 bytes.
int32_t s4_global_collapse(const int32_t *palettes_q16, int32_t t, int32_t k_in,
                           int32_t k_out, int32_t *out_leaves_q16, uint8_t *out_indices,
                           void *scratch, size_t scratch_cap);

// Owned integer Haar (reversible lifting / S-transform) — the palette's
// dimensional space as EXACT integer math. analyze: 2^D leaves → root (3 Q16) +
// (2^D-1) detail offsets (Q16, interleaved L,a,b, coarsest-first). reconstruct is
// its exact inverse (reconstruct∘analyze = id byte-exact; a coefficient move is
// exactly reversible). Mirrors SixFour.Spec.PairTreeFixed. n must be a power of
// two. analyze scratch >= n*3*4 bytes; reconstruct needs no scratch.
int32_t s4_haar_analyze(const int32_t *leaves_q16, int32_t n,
                        int32_t *out_root_q16, int32_t *out_offsets_q16,
                        void *scratch, size_t scratch_cap);

int32_t s4_haar_reconstruct(const int32_t *root_q16, const int32_t *offsets_q16,
                            int32_t n, int32_t *out_leaves_q16);

// The node colours at Haar pairing `level` — the abstraction cascade (256 leaves →
// 16 level-4 → 4 level-2 → 1 root). Writes 2^level Q16 triples to out_nodes_q16;
// requires 0 <= level <= log2(n). Byte-exact vs PairTreeFixed.levelNodesFixed.
// SixFour surfaces level 4 (16 colours) as the capture shutter. No scratch.
int32_t s4_haar_level_nodes(int32_t level, const int32_t *root_q16,
                            const int32_t *offsets_q16, int32_t n,
                            int32_t *out_nodes_q16);

// Reversible RGBT-4D / cube-ladder lift (the spatial+temporal S-transform that
// underlies the {16³,64³,256³} cube ladder). Bijective integer lifting in Q16;
// matches Spec.RGBTLift / Spec.CubeLadder (lawLadderBijective) bit-for-bit and is
// the seam where Metal (2-D threads) and Zig (loops) must agree on tiling order.
//
// 2×2 → RGBT lift on one block: 4 ints in, 4 ints out. Bijective with s4_rgbt_unlift_quad.
int32_t s4_rgbt_lift_quad(const int32_t *in_q16, int32_t *out_q16);
// Inverse of s4_rgbt_lift_quad.
int32_t s4_rgbt_unlift_quad(const int32_t *in_q16, int32_t *out_q16);
// 2×2×2 → 1 OCTANT lift (OctreeCell.liftOct): 8 cells in (a,b,c,d near-z, e,f,g,h far-z),
// out = [coarse, g0,b0,t0, g1,b1,t1, dz]. TOTAL: refuses RC_OUT_OF_RANGE if any |in| > B.
int32_t s4_octant_lift(const int32_t *in_q16, int32_t *out_q16);
// Inverse of s4_octant_lift.
int32_t s4_octant_unlift(const int32_t *in_q16, int32_t *out_q16);
// ONE up-rung of a scalar cube in the DEVICE volume layout ((t*side + r)*side + c,
// col fastest): every coarse voxel becomes its 2x2x2 block via s4_octant_unlift;
// output cell (2t+dt, 2r+dr, 2c+dc) = octant lane dt*4+dr*2+dc (near-t face first —
// the octant z axis IS the time axis). `details` may be NULL (the zero-detail
// deterministic floor, zero-gene == floor) or [side^3 * 7] i32 voxel-major COMMITTED
// bands (the float theta layer stays OUTSIDE — a pure integer cascade stage).
// Byte-exact vs Spec.SelfSimilarReconstruct.expandRungVolume (cube_expand fixture).
// `out` is [(2*side)^3]. TOTAL: refuses rather than wrap.
int32_t s4_cube_expand_rung(const int32_t *vol, int32_t side,
                            const int32_t *details, int32_t *out);
// One 2-D-Haar level over a side×side row-major grid (side even): tile into 2×2
// blocks → coarse (side/2)² plane + (side/2)² detail triples (G,B,T).
int32_t s4_cube_lift_level(int32_t side, const int32_t *grid,
                           int32_t *out_coarse, int32_t *out_details);
// Exact inverse of s4_cube_lift_level: coarse h² + details h²·3 → 2h×2h grid.
int32_t s4_cube_unlift_level(int32_t half, const int32_t *coarse,
                             const int32_t *details, int32_t *out_grid);
// One level of the temporal integer Haar split over n OKLab triples (the temporal half of
// Spec.VoxelReduce; mirrors Spec.TemporalLoop.haarSplitTime): adjacent frames → low (lifted
// parent) + high (detail) via the owned S-transform; odd tail carried into low.
// in: n·3. out_low: (n/2 + n%2)·3. out_high: (n/2)·3.
int32_t s4_haar_split_level(int32_t n, const int32_t *in_q16,
                            int32_t *out_low, int32_t *out_high);
// Exact inverse of s4_haar_split_level (Spec.TemporalLoop.haarJoinTime). out: (low_n+high_n)·3.
int32_t s4_haar_join_level(int32_t low_n, int32_t high_n, const int32_t *low,
                           const int32_t *high, int32_t *out_q16);

// Color Atlas board — deterministic Q16 mass (port of SixFour.Spec.BoardQ16).
// Integer floor-div binning + integer counts + ONE round-half-up of
// count·2^16/total per bin: the byte-exact replacement for the float histogram
// that leaked a non-dyadic 1/total into the policy/value board input.
//
// Q16 mass from precomputed integer per-bin counts (the pixel channel, whose
// counts come from a per-frame slot→bin table). bins = 16^3 = 4096; total = exact count.
int32_t s4_board_counts_to_mass_q16(const int32_t *counts, int32_t bins,
                                    int32_t total, int32_t *out_mass_q16);
// Full mass channel for n interleaved (L,a,b) Q16 colours → 4096-bin Q16 channel.
int32_t s4_board_mass_q16(const int32_t *colors_q16, int32_t n, int32_t *out_mass_q16);

// σ-pair leaf override — the user's generator-space taste tint (port of
// SixFour.Spec.LeafOverride). n generators (interleaved L,a,b Q16) + n deltas →
// 2n σ-pair leaves [g, σ(g)] where g = generator + δ and σ(l,a,b) = (l,−a,−b).
// out_leaves_q16 holds 2n triples (6n ints). deltas_q16 = NULL ⇒ zero override.
int32_t s4_leaf_override(const int32_t *generators_q16, const int32_t *deltas_q16,
                         int32_t n, int32_t *out_leaves_q16);

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

// ─────────────────────────────────────────────────────────────────────────
// Synthetic-burst generator — TRAINING data engine (Native/src/synth.zig).
//
// Mac-side training tooling, NOT shipped to device: procedurally generates an
// OKLab Q16 burst (deterministic in `seed`, integer value-noise) that the
// trainer feeds through s4_quantize_frame → s4_palette_oklab_to_srgb8 →
// s4_gif_assemble — the SAME kernels the device runs, so per-frame palettes are
// byte-identical to production. Used to bootstrap the look-NN trainer while
// trainer/data/ is empty; the loader swaps to real captures later.
//
// `out_oklab_q16` is caller-owned, frame_count·side·side·3 int32 (interleaved
// L,a,b row-major). side ≥ 2. Returns S4_RC_OK / S4_RC_NULL_PTR / S4_RC_BAD_SHAPE.
// `l_min_q16`/`l_max_q16` set the L dynamic range (Q16); `chroma_max_q16` bounds
// the a,b chroma deviation (Q16). The caller passes the canonical span
// (synth.zig L_MIN/L_MAX/CHROMA) for the default look; grain is range-proportional.
// ─────────────────────────────────────────────────────────────────────────
#define S4_SYNTH_COLOR      0   /* full OKLab burst (L,a,b vary) */
#define S4_SYNTH_GRAYSCALE  1   /* a=b=0 exactly — Milestone L training data */

int32_t s4_synth_burst(uint64_t seed, int32_t mode,
                       int32_t frame_count, int32_t side,
                       int32_t l_min_q16, int32_t l_max_q16, int32_t chroma_max_q16,
                       int32_t *out_oklab_q16);

// As s4_synth_burst, with an explicit DETAIL scale (Q16). detail_q16 > 65536 adds
// high-frequency detail above the significance floor — spans the perceptual/detail
// entropy axis at real scale. 65536 (= S4_SYNTH_DETAIL_Q16) reproduces s4_synth_burst.
#define S4_SYNTH_DETAIL_Q16  65536   /* the canonical (1.0) detail level */
int32_t s4_synth_burst_detail(uint64_t seed, int32_t mode,
                              int32_t frame_count, int32_t side,
                              int32_t l_min_q16, int32_t l_max_q16, int32_t chroma_max_q16,
                              int32_t detail_q16, int32_t *out_oklab_q16);

// ─────────────────────────────────────────────────────────────────────────
// Look transfer / LUT extraction (R3D .cube). The on-screen "look" and the
// exported 3D LUT are two projections of ONE OKLab palette→palette transform
// derived from the captured palette's luminance-zone chroma profile. Mirrors
// SixFour.Spec.{ZoneProfile,LookTransfer,CubeLut}. Caller owns all memory.
// ─────────────────────────────────────────────────────────────────────────

// Analyse a `p`-entry OKLab Q16 palette into a luminance-zone chroma profile:
// per-zone mean a/b/chroma (sum-then-divide; empty zones fall back to the global
// mean) + the global means. `num_zones` ∈ [1,64]. `out_mean_*` each hold
// `num_zones` int32; `out_global` holds 3 int32. Returns S4_RC_*.
int32_t s4_zone_profile_q16(const int32_t *palette_oklab_q16, int32_t p, int32_t num_zones,
                           int32_t *out_mean_a, int32_t *out_mean_b, int32_t *out_mean_c,
                           int32_t *out_global);

// Map `k` OKLab Q16 colours through the look transform (the live PREVIEW look):
// keep L, blend a/b toward the zone target by `strength_q16`, scale chroma
// (clamped [chroma_min_q16, chroma_max_q16]); `polarity_q16` = ±65536 flips the
// target hue; below `chroma_eps_q16` blended chroma it snaps to the target
// direction. `out_oklab_q16` may alias `in_oklab_q16`. Returns S4_RC_*.
int32_t s4_look_transfer_q16(const int32_t *in_oklab_q16, int32_t k,
                            const int32_t *mean_a, const int32_t *mean_b, const int32_t *mean_c,
                            int32_t num_zones, int32_t strength_q16,
                            int32_t chroma_min_q16, int32_t chroma_max_q16,
                            int32_t polarity_q16, int32_t chroma_eps_q16,
                            int32_t *out_oklab_q16);

// Build the `cube_size`³ .cube as Q16 sRGB-encoded triples in .cube order (R
// fastest, then G, then B): per voxel Log3G10/RWG grid coord → tonemapped linear
// Rec.709 → OKLab → look transfer → linear sRGB → black lift → gamut compress →
// sRGB gamma (Q16). `out_q16` holds `out_cap` int32 (needs cube_size³·3).
// cube_size ∈ [2,65]. Returns S4_RC_* (S4_RC_OUTPUT_TOO_SMALL if out_cap short).
int32_t s4_build_cube_q16(int32_t cube_size,
                         const int32_t *mean_a, const int32_t *mean_b, const int32_t *mean_c,
                         int32_t num_zones, int32_t strength_q16,
                         int32_t chroma_min_q16, int32_t chroma_max_q16,
                         int32_t polarity_q16, int32_t chroma_eps_q16,
                         int32_t *out_q16, size_t out_cap);

// ─────────────────────────────────────────────────────────────────────────
// Host-side decode + inverse colour — TOOLING / TEST ONLY (not shipped path).
//
// These three are exported by the Zig core (Native/src/kernels.zig) for host-side
// round-trip verification and the cross-language golden tests; they are NOT called
// by the iOS app. Declared here so header-based callers get correct prototypes and
// the contract surface is unambiguous (Zig exports 31 symbols total: 28 shipped +
// these 3 tooling). Memory rule unchanged: caller owns all memory.
// ─────────────────────────────────────────────────────────────────────────

// Inverse of s4_palette_oklab_to_srgb8: k packed sRGB8 triplets → interleaved
// OKLab Q16 (fixed-point). Used by golden round-trip tests.
int32_t s4_srgb8_to_oklab_q16(const uint8_t *rgb, int32_t k, int32_t *out_oklab_q16);

// Scratch bytes s4_gif_decode needs for a `gif_len`-byte GIF89a. 0 if gif_len==0.
size_t s4_gif_decode_scratch_bytes(size_t gif_len);

// Decode a GIF89a (the inverse of s4_gif_assemble) back to per-frame indices +
// local palettes. Pass out_indices/out_palettes_rgb = NULL to PROBE shape only
// (writes out_frame_count/out_side/out_k). Returns S4_RC_*.
int32_t s4_gif_decode(const uint8_t *gif, size_t gif_len,
                      uint8_t *out_indices, uint8_t *out_palettes_rgb,
                      int32_t *out_frame_count, int32_t *out_side, int32_t *out_k,
                      void *scratch, size_t scratch_cap);

// ─────────────────────────────────────────────────────────────────────────
// V2.1 (pre-collapse field)
//
// The V2.1 pre-collapse field kernels (Native/src/kernels.zig, ports of
// SixFour.Spec.V21Field). A "curve" carries one channel's per-level energy or
// count; collapse of a curve is the sRGB byte the V2 boundary consumes. These
// are ADDITIVE: no MVP1 path calls them. Memory rule unchanged: caller owns all
// memory. All return S4_RC_* (S4_RC_OUT_OF_RANGE on a domain/envelope refusal).
// ─────────────────────────────────────────────────────────────────────────

// Per channel-curve, the energy-MINIMISING level (argmin, lowest index wins
// ties) written as an sRGB byte. `curves` is [p*3*n_levels] Q16 energies
// (pixel-major: pixel, channel R,G,B, then level); writes p*3 bytes to
// out_rgb. n_levels <= 256 (the level is the byte).
int32_t s4_v21_collapse(const int32_t *curves, int32_t p, int32_t n_levels,
                        uint8_t *out_rgb);

// Per-level octant-lift driver: drives the gated byte-exact s4_octant_lift over
// each of n_levels curve levels. `octant_curves` is [8*n_levels] (cell-major,
// level-contiguous); writes the coarse curve [n_levels] and 7 residual curves
// [7*n_levels] (residual-major).
int32_t s4_v21_octant_lift_curve(const int32_t *octant_curves, int32_t n_levels,
                                 int32_t *out_coarse, int32_t *out_residuals);

// Per-level integer opponent transform of the neighbour delta. `bin1`/`bin2`
// are [3*n_levels] (R,G,B curves, level-contiguous) Q16; writes [3*n_levels]
// (L,a,b) delta curves. Computed in i64; refuses on i32-envelope overflow.
int32_t s4_v21_opponent_delta(const int32_t *bin1, const int32_t *bin2,
                              int32_t n_levels, int32_t *out_lab);

// Captured-bin energy curve: E(level) = total - count(level), total = sum of a
// curve's counts (argmin E = the mode). `counts` is [p*3*n_levels] (pixel-major,
// R,G,B, then level), non-negative; writes [p*3*n_levels] energies. Per-curve
// total in i64; refuses on i32-envelope overflow.
int32_t s4_v21_counts_to_energy(const int32_t *counts, int32_t p, int32_t n_levels,
                                int32_t *out_energy);

// The monotone 1-D optimal-transport map T = F^-1 . F between two EQUAL-MASS count
// histograms, as a per-RANK integer displacement d[k] = q_dst[k] - q_src[k] on the
// sorted-quantile mass line. `src`/`dst` are [p*3*n_levels] counts (pixel-major:
// pixel, channel R,G,B, then level), each per-(cell,channel) curve summing to `mass`;
// writes [p*3*mass] displacements (same cell/channel major order, rank-contiguous).
// Restores the V2.1 time axis: anchor curve + this map reconstructs a frame's curve
// (s4_v21_pushforward). Refuses (RC_OUT_OF_RANGE) n_levels>256, mass<=0, a negative
// count, or a curve not summing to `mass`.
int32_t s4_v21_transport(const int32_t *src, const int32_t *dst, int32_t p,
                         int32_t n_levels, int32_t mass, int32_t *out_disp);

// Apply a per-rank displacement to a source curve and re-bin, reproducing the
// transported curve. `src` is [p*3*n_levels] counts (each curve summing to `mass`);
// `disp` is [p*3*mass] rank displacements; writes [p*3*n_levels] counts to `out`.
// With disp = s4_v21_transport(src,dst) yields dst byte-exact; with the negated disp
// it inverts back to src. Refuses (RC_OUT_OF_RANGE) n_levels>256, mass<=0, a curve not
// summing to `mass`, or a landing level src_level+disp outside [0, n_levels).
int32_t s4_v21_pushforward(const int32_t *src, const int32_t *disp, int32_t p,
                           int32_t n_levels, int32_t mass, int32_t *out);

// Histogram accumulation: box-decimate a FINE grid into coarse voxels and, per
// voxel per channel, count fine samples at each value level. `fine` is
// [ft*fy*fx*3] u8, layout (((ft*fy + y)*fx + x)*3 + ch); `out_counts` (zeroed
// here) is [ct*cy*cx*3*n_levels], layout ((coarseVoxel*3 + ch)*n_levels + value).
// Dimensions must be divisible by the decimation factors; refuses a value >= n_levels.
int32_t s4_v21_accumulate_hist(const uint8_t *fine, int32_t fx, int32_t fy, int32_t ft,
                               int32_t dx, int32_t dy, int32_t dt, int32_t n_levels,
                               int32_t *out_counts);

// Soft-splat histogram accumulation (the sub-LSB sibling of accumulate_hist):
// each `fine` sample is a high-precision position hi in 0..(n_levels-1)*w
// (hi = level*w + subfraction); a unit of integer mass w splats across the two
// adjacent levels ((w - hi%w) at hi/w, hi%w at hi/w + 1), so the discarded
// sub-LSB fraction survives as the histogram's first moment. `fine` is
// [ft*fy*fx*3] i32, layouts as accumulate_hist; each (voxel,channel) cell totals
// box*w. Refuses w<=0, n_levels>256, or hi out of range.
int32_t s4_v21_accumulate_hist_soft(const int32_t *fine, int32_t fx, int32_t fy, int32_t ft,
                                    int32_t dx, int32_t dy, int32_t dt, int32_t n_levels,
                                    int32_t w, int32_t *out_counts);

// Ground-state centering: subtract each curve's minimum, so the GIF byte (argmin)
// sits at energy 0. `curves` is [p*3*n_levels]; writes [p*3*n_levels] centered
// energies. Centering in i64; refuses on i32-envelope overflow.
int32_t s4_v21_centered_energy(const int32_t *curves, int32_t p, int32_t n_levels,
                               int32_t *out_centered);

// Mode-relative ENCODER INPUT: the centered curve reindexed about its own mode
// (left-rotated by the argmin), so the argmin is pinned to relative-0 and the
// absolute mode is WITHHELD. `curves` is [p*3*n_levels]; writes [p*3*n_levels].
int32_t s4_v21_mode_relative(const int32_t *curves, int32_t p, int32_t n_levels,
                             int32_t *out_rel);

// Anchor (the left inverse of mode_relative GIVEN the GIF byte): out[l] =
// rel[(l - mode) mod n], so anchor(mode, mode_relative(e)) == centered(e). `rel`
// is [p*3*n_levels], `modes` is [p*3] (the per-curve GIF level); writes [p*3*n_levels].
int32_t s4_v21_anchor_at(const int32_t *rel, const int32_t *modes, int32_t p,
                         int32_t n_levels, int32_t *out_centered);

// Palette delta (the temporal metric weight): the L1 / total-variation distance
// between two palettes' per-channel value histograms, sum |hist1 - hist2|.
// Permutation-invariant (slot order is the index gauge) and byte-exact.
// `pal1`/`pal2` are [k*3] u8 SLOT-MAJOR (slot*3 + channel), values in
// 0..n_levels-1; writes the scalar to out_pd[0]. Refuses n_levels>256 or a
// value >= n_levels.
int32_t s4_v21_palette_delta(const uint8_t *pal1, const uint8_t *pal2, int32_t k,
                             int32_t n_levels, int32_t *out_pd);

// 1-D Wasserstein-1 palette metric: the L1 distance between the two palettes'
// per-channel value CDFs (palette_delta with a per-channel cumsum inserted
// before the abs-sum), so it charges the GROUND DISTANCE mass must travel.
// Byte-exact integer, permutation-invariant; same [k*3] slot-major layout;
// writes the scalar to out_wd[0]. Refuses n_levels>256 or a value >= n_levels.
int32_t s4_v21_wdist1d(const uint8_t *pal1, const uint8_t *pal2, int32_t k,
                       int32_t n_levels, int32_t *out_wd);

#endif // SIXFOUR_NATIVE_H
