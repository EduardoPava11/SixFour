import Testing
import Foundation
import simd
@testable import SixFour

/// Gate for the GIFA→GIFB render path (`DeterministicRenderer.renderGlobalPalette`):
/// the 64 per-frame palettes collapse (owned Zig `s4_global_collapse`) into ONE
/// global 256-colour palette, every frame is dithered against it, and a single
/// shared-palette GIF is assembled. Proves GIFB is actually PRODUCED (the keystone
/// gap from the architecture map) and that it rides the owned integer kernels.
struct GlobalRenderTests {

    /// A deterministic synthetic frame of OKLab pixels (side² pixels). side=16 ⇒
    /// 256 px = K, so per-frame quantize (k ≤ p) is well-posed.
    private func tile(_ seed: UInt64, side: Int) -> OKLabTile {
        var s = seed &+ 0x9E3779B97F4A7C15
        func f() -> Float {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Float(s >> 40) / Float(1 << 24)
        }
        let px = (0..<(side * side)).map { _ in SIMD3<Float>(f(), f() - 0.5, f() - 0.5) }
        return OKLabTile(side: side, pixels: px, captureNanos: 0, palette: [], finalShift: 0)
    }

    @Test func producesOneGlobalPaletteGIFB() throws {
        let side = 16
        let tiles = (0..<4).map { tile(UInt64($0 + 1), side: side) }
        let g = try DeterministicRenderer(dither: .default).renderGlobalPalette(tiles: tiles, comment: nil) { _ in }

        #expect(g.globalPalette.count == SixFourShape.K)
        #expect(g.globalLeavesQ16.count == SixFourShape.K)
        #expect(g.frameIndices.count == 4)
        for idx in g.frameIndices {
            #expect(idx.count == side * side)
            #expect(idx.allSatisfy { Int($0) < SixFourShape.K })
        }
        // Whole-GIF rescue guarantees: every global slot is used SOMEWHERE (union
        // surjective) and backed by ≥ minPopulation pooled pixels; mass conserved.
        #expect(Set(g.frameIndices.flatMap { $0 }).count == SixFourShape.K)
        #expect(g.pooledCounts.count == SixFourShape.K)
        #expect(g.pooledCounts.allSatisfy { $0 >= SixFourSignificance.minPopulation })
        #expect(g.pooledCounts.reduce(0, +) == 4 * side * side)
        // A real GIF89a was emitted.
        #expect(g.gifData.count > 0)
        #expect(String(decoding: g.gifData.prefix(6), as: UTF8.self) == "GIF89a")

        // The global palette IS the collapse leaves → sRGB (one table, consistent).
        let flat = g.globalLeavesQ16.flatMap { [$0.x, $0.y, $0.z] }
        let rgb = SixFourNative.paletteToSRGB8(centroidsQ16: flat, k: SixFourShape.K)!
        let expected = (0..<SixFourShape.K).map { SIMD3<UInt8>(rgb[$0 * 3], rgb[$0 * 3 + 1], rgb[$0 * 3 + 2]) }
        #expect(g.globalPalette == expected)
    }

    /// The render path's global leaves match a direct call to the owned Zig collapse
    /// (so GIFB genuinely rides `s4_global_collapse`, not some ad-hoc Swift path).
    @Test func ridesTheOwnedZigCollapse() throws {
        let side = 16
        let tiles = (0..<4).map { tile(UInt64($0 + 1), side: side) }

        let q16 = tiles.map { SixFourNative.oklabToQ16($0.pixels) }
        let cents = try q16.map { q -> [Int32] in
            guard let r = SixFourNative.quantizeFrame(oklabQ16: q, k: SixFourShape.K, lloydIters: 0) else {
                throw DeterministicRenderer.DetError.stageFailed("quantize")
            }
            return r.centroids
        }
        let perFrame: [[SIMD3<Int32>]] = cents.map { flat in
            (0..<SixFourShape.K).map { SIMD3<Int32>(flat[$0 * 3], flat[$0 * 3 + 1], flat[$0 * 3 + 2]) }
        }
        let collapse = SixFourNative.globalCollapse(perFramePalettes: perFrame, kOut: SixFourShape.K)!

        let g = try DeterministicRenderer(dither: .default).renderGlobalPalette(tiles: tiles, comment: nil) { _ in }
        #expect(g.globalLeavesQ16 == collapse.leaves)
    }

    /// On the real SixFour shape (64 frames × 64² = 262144 px), GIFB passes the
    /// whole-GIF brands: union-surjective onto all K, every global slot backed by
    /// ≥ minPopulation pooled pixels (this is the gate the capture flow will use,
    /// replacing the per-frame CompleteVoxelVolume that a global palette can't pass).
    @Test func gatesAcceptFullBurst() throws {
        let tiles = (0..<SixFourShape.T).map { tile(UInt64($0 + 1), side: 64) }
        let g = try DeterministicRenderer(dither: .default).renderGlobalPalette(tiles: tiles, comment: nil) { _ in }

        let cv = GlobalCompleteVolume(checkingFrames: g.frameIndices)
        #expect(cv != nil, "GIFB is not a complete whole-GIF volume (union not surjective onto K)")
        if let cv {
            #expect(GlobalSignificantVolume(complete: cv, pooledCounts: g.pooledCounts) != nil,
                    "GIFB is not whole-GIF significant (a global slot < minPopulation pooled, or mass mismatch)")
        }
    }

    /// The radix genome reaches the GIFB colour table: 16² = the raw maximin leaves;
    /// 4⁴ and 2⁸ are byte-exact integer projections that SHIFT the palette (the
    /// radix's inductive bias), and each is deterministic.
    @Test func radixGenomeReachesTheGlobalPalette() throws {
        let tiles = (0..<8).map { tile(UInt64($0 + 1), side: 16) }
        let r = DeterministicRenderer(dither: .default)
        let flat = try r.renderGlobalPalette(tiles: tiles, comment: nil, branching: .b16) { _ in }
        let quad4 = try r.renderGlobalPalette(tiles: tiles, comment: nil, branching: .b4) { _ in }
        let sigma = try r.renderGlobalPalette(tiles: tiles, comment: nil, branching: .b2) { _ in }

        // 16² is the identity over the collapse leaves; the others are the genome projection.
        #expect(quad4.globalLeavesQ16 != flat.globalLeavesQ16, "4⁴ genome must shift the palette")
        #expect(sigma.globalLeavesQ16 != flat.globalLeavesQ16, "2⁸ genome must shift the palette")
        // Genome projection is the exact integer one, applied to the collapse leaves.
        #expect(flat.globalLeavesQ16 == BranchedPalette.projectQ16(flat.globalLeavesQ16, branching: .b16))
        #expect(quad4.globalLeavesQ16 == BranchedPalette.projectQ16(flat.globalLeavesQ16, branching: .b4))
        #expect(sigma.globalLeavesQ16 == BranchedPalette.projectQ16(flat.globalLeavesQ16, branching: .b2))
        // Deterministic per radix.
        let sigma2 = try r.renderGlobalPalette(tiles: tiles, comment: nil, branching: .b2) { _ in }
        #expect(sigma.sha256Hex == sigma2.sha256Hex)
    }

    /// The LOSSY genomes (4⁴/2⁸) can map distinct collapse leaves to duplicate
    /// palette colours, but the WHOLE-GIF significance rescue (run after the genome
    /// projection) forces every global slot to ≥ minPopulation pooled pixels — so a
    /// 4⁴ or 2⁸ GIFB is still a complete, significant whole-GIF volume on a real burst.
    @Test func gatesAcceptLossyGenomeFullBurst() throws {
        let tiles = (0..<SixFourShape.T).map { tile(UInt64($0 + 1), side: 64) }
        let r = DeterministicRenderer(dither: .default)
        for branching in [PaletteBranching.b4, .b2] {
            let g = try r.renderGlobalPalette(tiles: tiles, comment: nil, branching: branching) { _ in }
            let cv = GlobalCompleteVolume(checkingFrames: g.frameIndices)
            #expect(cv != nil, "\(branching) GIFB not union-surjective onto K")
            if let cv {
                #expect(GlobalSignificantVolume(complete: cv, pooledCounts: g.pooledCounts) != nil,
                        "\(branching) GIFB not whole-GIF significant")
            }
        }
    }

    /// Same burst ⇒ same GIFB bytes (the determinism guarantee).
    @Test func deterministicAcrossRuns() throws {
        let tiles = (0..<4).map { tile(UInt64($0 + 1), side: 16) }
        let r = DeterministicRenderer(dither: .default)
        let a = try r.renderGlobalPalette(tiles: tiles, comment: nil) { _ in }
        let b = try r.renderGlobalPalette(tiles: tiles, comment: nil) { _ in }
        #expect(a.sha256Hex == b.sha256Hex)
    }
}
