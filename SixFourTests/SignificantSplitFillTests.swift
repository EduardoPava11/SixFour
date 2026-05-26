import Testing
import Foundation
import simd
@testable import SixFour

/// The per-frame palette **significance** contract: every one of the 256
/// palette slots must be backed by `≥ minPopulation` pixels (a real "range for
/// each bin"), never a donated outlier — while still using all 256 colours.
/// Mirrors the Haskell `Properties.Significance` laws (Def 21–24, Thm 6–7) on
/// the real SixFour shape (K = 256, P = 4096). See `SixFour.Spec.Significance`.
struct SignificantSplitFillTests {

    private let K = SixFourShape.K                 // 256
    private let P = SixFourShape.pixelsPerFrame     // 4096
    private var nMin: Int { SixFourSignificance.minPopulation }

    // MARK: - Def 23: every slot significant ("cannot fail")

    /// The pathological collapse: the dither put every pixel on slot 0.
    /// Split-fill must still leave all 256 slots significant (≥ n_min) and
    /// surjective — and never a count-1 outlier.
    @Test func everySlotSignificantWhenDitherCollapsedToOne() {
        let palette = distinctPalette()
        let pixels  = gradientPixels()
        let collapsed = [UInt8](repeating: 0, count: P)
        let (pal, idx) = SignificantSplitFill.rescue(palette: palette, indices: collapsed, pixels: pixels)
        let cells = SignificantSplitFill.cells(palette: pal, indices: idx, pixels: pixels)

        #expect(Set(idx).count == K, "all 256 colours must be used")
        #expect(cells.allSatisfy { $0.isSignificant }, "every slot must be significant")
        #expect(cells.map(\.count).min()! >= nMin, "no slot may be a count-<n_min outlier")
        #expect(cells.reduce(0) { $0 + $1.count } == P, "mass must be conserved")
    }

    /// The flat scene (d = 1): all pixels identical. This is the case that used
    /// to force the rescue to donate outliers. With population-significance and
    /// P = 16·K, all 256 slots are still significant (≈16 pixels each).
    @Test func everySlotSignificantOnFlatScene() {
        let palette = distinctPalette()
        let flat = [SIMD3<Float>](repeating: SIMD3<Float>(0.5, 0.1, -0.2), count: P)
        let collapsed = [UInt8](repeating: 0, count: P)
        let (pal, idx) = SignificantSplitFill.rescue(palette: palette, indices: collapsed, pixels: flat)
        let cells = SignificantSplitFill.cells(palette: pal, indices: idx, pixels: flat)

        #expect(Set(idx).count == K)
        #expect(cells.allSatisfy { $0.count >= nMin },
                "even a totally flat frame must yield 256 significant slots")
    }

    /// A two-colour frame — still no outliers.
    @Test func everySlotSignificantOnTwoColorScene() {
        let palette = distinctPalette()
        let cA = SIMD3<Float>(0.2, -0.1, 0.1)
        let cB = SIMD3<Float>(0.8, 0.1, -0.1)
        let pixels = (0..<P).map { $0 % 2 == 0 ? cA : cB }
        // Start from a (rich-looking) nearest-centroid dither so most slots are empty.
        let dithered = pixels.map { p -> UInt8 in
            UInt8(palette.firstIndex { simd_length_squared($0 - p) < 1e-6 } ?? 0)
        }
        let (pal, idx) = SignificantSplitFill.rescue(palette: palette, indices: dithered, pixels: pixels)
        let cells = SignificantSplitFill.cells(palette: pal, indices: idx, pixels: pixels)
        #expect(Set(idx).count == K)
        #expect(cells.allSatisfy { $0.count >= nMin })
        #expect(cells.reduce(0) { $0 + $1.count } == P)
    }

    /// On a frame that is already well-populated (16 per slot), split-fill is a
    /// no-op — it does not perturb a healthy assignment.
    @Test func noOpWhenAlreadySignificant() {
        let palette = distinctPalette()
        let pixels  = gradientPixels()
        let healthy = (0..<P).map { UInt8($0 % K) }   // 16 per slot
        let (_, idx) = SignificantSplitFill.rescue(palette: palette, indices: healthy, pixels: pixels)
        #expect(idx == healthy, "an already-significant frame must be returned unchanged")
    }

    // MARK: - Def 21: range box well-formed

    @Test func rangeBoxContainsMeanAndStdIsNonNegative() {
        let palette = distinctPalette()
        let pixels  = gradientPixels()
        let dithered = (0..<P).map { UInt8($0 % K) }
        let (pal, idx) = SignificantSplitFill.rescue(palette: palette, indices: dithered, pixels: pixels)
        let cells = SignificantSplitFill.cells(palette: pal, indices: idx, pixels: pixels)
        for c in cells {
            #expect(c.stdDev.x >= 0 && c.stdDev.y >= 0 && c.stdDev.z >= 0)
            let lo = c.rangeLo, hi = c.rangeHi
            #expect(lo.x <= c.mean.x && c.mean.x <= hi.x)
            #expect(lo.y <= c.mean.y && c.mean.y <= hi.y)
            #expect(lo.z <= c.mean.z && c.mean.z <= hi.z)
        }
    }

    // MARK: - The SignificantVoxelVolume brand (the encoder's gate)

    @Test func brandAcceptsAnAllSignificantVolume() throws {
        let frame = (0..<P).map { UInt8($0 % K) }              // surjective, 16/slot
        let cvv = try #require(CompleteVoxelVolume(checkingFrames:
            Array(repeating: frame, count: SixFourShape.T)))
        let cells = cellsFromCounts([Int](repeating: P / K, count: K))   // 16 each
        let svv = SignificantVoxelVolume(complete: cvv,
            cells: Array(repeating: cells, count: SixFourShape.T))
        #expect(svv != nil, "all-significant, mass-conserving cells must build the brand")
    }

    @Test func brandRejectsACountOneOutlierSlot() throws {
        let frame = (0..<P).map { UInt8($0 % K) }
        let cvv = try #require(CompleteVoxelVolume(checkingFrames:
            Array(repeating: frame, count: SixFourShape.T)))
        // Mass still 4096, but slot 0 is a lone outlier (count 1).
        var counts = [Int](repeating: P / K, count: K)         // 16 each, sum 4096
        counts[0] = 1; counts[1] = P / K + (P / K - 1)         // move 15 to slot 1
        let bad = cellsFromCounts(counts)
        let svv = SignificantVoxelVolume(complete: cvv,
            cells: Array(repeating: bad, count: SixFourShape.T))
        #expect(svv == nil, "a count-1 outlier slot must be rejected by the brand")
    }

    @Test func brandRejectsMassMismatch() throws {
        let frame = (0..<P).map { UInt8($0 % K) }
        let cvv = try #require(CompleteVoxelVolume(checkingFrames:
            Array(repeating: frame, count: SixFourShape.T)))
        var counts = [Int](repeating: P / K, count: K)
        counts[0] -= 1                                          // sum 4095 ≠ 4096
        let bad = cellsFromCounts(counts)
        let svv = SignificantVoxelVolume(complete: cvv,
            cells: Array(repeating: bad, count: SixFourShape.T))
        #expect(svv == nil, "non-mass-conserving cells must be rejected")
    }

    // MARK: - Constants single-sourced from the spec

    @Test func feasibilityMatchesSixFourShape() {
        #expect(SixFourSignificance.feasible(pixels: P, k: K),
                "4096 ≥ 2·256 — the all-significant guarantee is feasible")
        #expect(!SixFourSignificance.feasible(pixels: nMin * K - 1, k: K))
    }

    @Test func chiSquareTableIsSingleSourced() {
        // ClusterStatisticsOps must defer to the generated SixFourSignificance.
        #expect(ClusterStatisticsOps.ChiSquare3.critical(alpha: 0.05) == 7.815)
        #expect(Float(SixFourSignificance.chiSquare3Critical(alpha: 0.05)) == 7.815)
        #expect(Float(SixFourSignificance.chiSquare3Critical(alpha: 0.001)) == 16.266)
    }

    // MARK: - Fixtures

    private func cellsFromCounts(_ counts: [Int]) -> [SixFourSignificantCell] {
        counts.enumerated().map { i, n in
            SixFourSignificantCell(mean: SIMD3<Float>(Float(i) / 255, 0, 0),
                                   stdDev: .zero, count: n,
                                   provenance: n >= nMin ? .extracted : .degenerate)
        }
    }

    private func distinctPalette() -> [SIMD3<Float>] {
        (0..<K).map { SIMD3<Float>(Float($0) / Float(K - 1), 0, 0) }
    }

    /// 4096 OKLab pixels spanning the L axis (rich, all distinct-ish).
    private func gradientPixels() -> [SIMD3<Float>] {
        (0..<P).map { i in
            let l: Float = Float(i) / Float(P - 1)
            let a: Float = Float((i * 7) % 256) / 255.0 - 0.5
            let b: Float = Float((i * 13) % 256) / 255.0 - 0.5
            return SIMD3<Float>(l, a, b)
        }
    }
}
