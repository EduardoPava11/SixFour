import Testing
import Foundation
import simd
@testable import SixFour

/// Tests the failure-propagation path now that `forceSurjective` is gone.
/// When Sinkhorn can't produce a hard-NN-surjective remap at any θ in the
/// configured range, the merger throws `cannotAchieveSurjectiveGlobalPalette`
/// and `PaletteGenerator.generate` re-throws it instead of silently
/// substituting per-frame.
struct SurjectivityFailurePropagationTests {

    /// Adversarial fixture: every per-frame palette has K=256 identical
    /// entries and every index points at slot 0. No θ produces a
    /// surjective hard-NN remap — the merger must throw, not silently
    /// produce some palette.
    @Test func extremelyDegenerateInputThrowsCannotAchieveError() {
        let degenerateLab = SIMD3<Float>(0.5, 0.0, 0.0)
        let palettes: [[SIMD3<Float>]] = Array(
            repeating: Array(repeating: degenerateLab, count: 256),
            count: 3
        )
        let indices: [[UInt8]] = Array(repeating: [0], count: 3)

        // Global mode: adaptive θ from 15 → 0.5 floor; every θ fails.
        let merger = StageBSinkhorn(params: .global)
        do {
            _ = try merger.mergeAdaptive(
                perFramePalettes: palettes,
                perFrameIndices: indices
            )
            Issue.record("Expected mergeAdaptive to throw on degenerate input")
        } catch StageBSinkhorn.StageBError.cannotAchieveSurjectiveGlobalPalette(_, let missing, let attempts) {
            #expect(missing > 0)
            #expect(attempts >= 1)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    /// `StageBContract.merge` is the protocol-level entry. It throws the
    /// same error type — no silent nil-witness substitution.
    @Test func protocolLevelMergeThrowsOnDegenerateInput() {
        let degenerateLab = SIMD3<Float>(0.5, 0.0, 0.0)
        let palettes: [[SIMD3<Float>]] = Array(
            repeating: Array(repeating: degenerateLab, count: 256),
            count: 3
        )
        let indices: [[UInt8]] = Array(repeating: [0], count: 3)
        let merger = StageBSinkhorn(params: .global)
        do {
            _ = try merger.merge(
                perFramePalettes: palettes,
                perFrameIndices: indices
            )
            Issue.record("Expected merge to throw on degenerate input")
        } catch is StageBSinkhorn.StageBError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    /// `PaletteGenerator.generate(mode: .global)` propagates the merger's
    /// throw rather than substituting a per-frame render. Construct a
    /// fixture where Stage A's GPU-equivalent has produced degenerate
    /// per-frame palettes and check the error reaches the caller.
    @Test func paletteGeneratorPropagatesStageBFailure() async {
        let degenerateLab = SIMD3<Float>(0.5, 0.0, 0.0)
        let side = 8
        let pixelCount = side * side
        let palette: [SIMD3<Float>] = Array(repeating: degenerateLab, count: 256)
        let tile = OKLabTile(
            side: side,
            pixels: Array(repeating: degenerateLab, count: pixelCount),
            captureNanos: 0,
            palette: palette,
            finalShift: 0
        )
        let tiles = Array(repeating: tile, count: 3)

        let generator = PaletteGenerator()
        do {
            _ = try await generator.generate(tiles: tiles, mode: .global)
            Issue.record("Expected generate(.global) to throw on degenerate input")
        } catch is StageBSinkhorn.StageBError {
            // expected — no silent fallback to per-frame
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}
