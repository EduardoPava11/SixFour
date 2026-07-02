//! Test aggregation root for `zig build test`.
//!
//! Pulls in the module unit tests AND the cross-language fixture tests. It is
//! kept SEPARATE from root.zig because build-ios.sh compiles root.zig directly
//! with `zig build-lib` (no build system, hence no `build_options` module) — so
//! the fixture machinery, which depends on the build-option-provided fixture
//! path, must not live in root.zig's top level.

test {
    _ = @import("root.zig"); // C-ABI surface (smoke test)
    _ = @import("kernels.zig"); // quantized-core ABI: size helpers + color kernel + stubs
    _ = @import("synth.zig"); // synthetic-burst training-data generator + end-to-end chain
    _ = @import("color_fixture_test.zig"); // cross-language color golden (skip-if-absent)
    _ = @import("gif_assemble_fixture_test.zig"); // cross-language GIF-assembler golden
    _ = @import("significance_fixture_test.zig"); // cross-language significance golden
    _ = @import("dither_fixture_test.zig"); // cross-language spatial-dither golden
    _ = @import("quant_fixture_test.zig"); // cross-language quantizer golden
    _ = @import("collapse_fixture_test.zig"); // cross-language global-collapse golden (GIFA→GIFB)
    _ = @import("v21_collapse_fixture_test.zig"); // cross-language V2.1 collapse golden (curve argmin → byte)
    _ = @import("v21_octant_fixture_test.zig"); // cross-language V2.1 per-level octant-lift driver golden
    _ = @import("v21_opponent_fixture_test.zig"); // cross-language V2.1 opponent-delta golden (encode target)
    _ = @import("v21_counts_fixture_test.zig"); // cross-language V2.1 captured-bin energy golden (make_bins core + duality)
    _ = @import("v21_hist_fixture_test.zig"); // cross-language V2.1 histogram accumulation golden (make_bins half 1)
    _ = @import("v21_mode_relative_fixture_test.zig"); // cross-language V2.1 encoder-input golden (centered/mode-relative/anchor reconstruction)
    _ = @import("v21_palette_delta_fixture_test.zig"); // cross-language V2.1 palette-delta golden (temporal metric weight + symmetry + gauge invariance)
    _ = @import("v21_soft_hist_fixture_test.zig"); // cross-language V2.1 soft-splat golden (sub-LSB construction + mass + exact centroid)
    _ = @import("v21_wdist1d_fixture_test.zig"); // cross-language V2.1 Wasserstein-1 palette metric golden (L1 of CDFs + charges distance)
    _ = @import("haar_fixture_test.zig"); // cross-language integer-Haar golden (reversible lifting)
    _ = @import("haar_barrier_hazard_test.zig"); // adversarial: dropped inter-level barrier (untracked hazard mode) breaks reconstruct∘analyze
    _ = @import("haar_barrier_race_test.zig"); // adversarial: level-sequential stale-read race (missing global barrier) breaks reconstruct∘analyze
    _ = @import("haar_inplace_intralevel_race_test.zig"); // adversarial: INTRA-level write-before-read alias (naive ascending/parallel map) breaks reconstruct∘analyze
    _ = @import("haar_tensor_float_test.zig"); // adversarial: fp16/bf16 Metal-4 tensor/cooperative-matrix lift drops low Q16 bits → breaks reconstruct∘analyze
    _ = @import("haar_coherency_premature_read_test.zig"); // adversarial: CPU reads GPU shared (unified-memory) Haar buffer before command-buffer completion (no waitUntilCompleted) breaks reconstruct∘analyze
    _ = @import("invertibility_break_test.zig"); // adversarial break-hunt: i32 overflow, leaf-override unclamped, divfloor-vs-trunc, in-place race, fp16 tensor, unified-memory, Core-AI ULP bypass, widen golden
    _ = @import("totality_test.zig"); // total-function redesign: T1 totality (all 10 refuse OOR), T3 intermediate-truth via i64, T5 ship-mode parity, T6 domain-boundary knife-edge
    _ = @import("temporal_fixture_test.zig"); // cross-language temporal one-level Haar split golden (VoxelReduce temporal half)
    _ = @import("rgbt4d_fixture_test.zig"); // cross-language RGBT-4D lift + cube-ladder golden (Metal/Zig alignment)
    _ = @import("cube_expand_fixture_test.zig"); // cross-language device-layout volume up-rung golden (floor + gene arms)
    _ = @import("gif_fixture_test.zig"); // cross-language full-burst GIF golden (Stage 6)
    _ = @import("lut_fixture_test.zig"); // cross-language look transfer + LUT-extraction golden
}
