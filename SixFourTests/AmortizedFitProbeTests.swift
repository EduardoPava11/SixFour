import Testing
@testable import SixFour

/// THE FLOORED-DISCHARGE PROBE (research report §5 item 1, 2026-07-05).
///
/// The claim under test: a per-capture gene, in ONE fused Metal dispatch, over the
/// octant `2×2×2 → 1 coarse + 7 residual` bands (the residual IS the encoding),
///   • MOVES ABOVE ONE Q16 LSB on a capture whose residual is structured
///     (predictable-from-coarse) — it learns where there is something to learn, and
///   • CORRECTLY NO-OPS on a flat capture whose residual is zero — it invents
///     nothing where `E[detail|coarse] ≈ 0`,
///   • and FLOORS honestly on noise whose residual is real but unpredictable —
///     work is capped at `I(coarse; detail)`, exactly the research's ceiling.
///
/// Input is 8 RAW octant voxels per block; the kernel runs `lift_oct` internally
/// to manufacture `(coarse, 7 detail)` (the same crossing the capture path uses),
/// then descends `f_θ: coarse → detail`, `φ(v)=[1, ṽ, ṽ²]`, 21 params
/// (`Spec.DetailPredictor`), from the zero floor, and Q16-commits. So this is the
/// end-to-end discharge of the "trains but doesn't learn" (FLOORED) verdict on the
/// REAL compute path (`RungDispatch.trainSimt`). The floor loss is read from the
/// kernel's OWN manufactured pairs, exactly as `CaptureGene` reports it.
///
/// A companion test pins WITHIN-DEVICE bit-reproducibility. The CROSS-GENERATION
/// leg (A-series vs M-series) is run by executing this suite on the simulator
/// (M-series host GPU) AND a physical iPhone (A-series) and diffing the printed
/// committed bytes; the determinism note records the procedure.
struct AmortizedFitProbeTests {

    private static let q16: Double = 65536

    /// N octant blocks of 8 raw voxels each (Q16). `voxels(ṽ, i)` returns the 8
    /// fine values for the octant whose coarse level is ṽ ∈ (0,1).
    private static func regime(n: Int, _ voxels: (Double, Int) -> [Double]) -> [Int32] {
        var blocks = [Int32](); blocks.reserveCapacity(n * 8)
        for i in 0..<n {
            let v = 0.1 + 0.8 * Double(i) / Double(max(1, n - 1))   // ṽ ∈ [0.1, 0.9]
            for x in voxels(v, i) { blocks.append(Int32((x * q16).rounded())) }
        }
        return blocks
    }

    /// The predict-zero-residual floor loss `½ Σ Σ (detail/Q16)²` over the kernel's
    /// OWN manufactured pairs (`out.pairs`, index 0 = coarse, 1…7 = detail) — the
    /// exact reference `CaptureGene` divides by for `lossReduction`.
    private static func floorLoss(pairs: [Int32]) -> Double {
        var sse = 0.0
        for i in stride(from: 0, to: pairs.count, by: 8) {
            for j in 1...7 { let t = Double(pairs[i + j]) / q16; sse += t * t }
        }
        return 0.5 * sse
    }

    /// A fixed 8-voxel detail pattern (mean 0.5, structured variation): scaled by a
    /// per-octant amplitude it makes the lifted detail bands LINEAR in the coarse,
    /// so the φ-linear term of a 21-param gene can fit them exactly.
    private static let pattern: [Double] = [0.50, 0.62, 0.44, 0.68, 0.40, 0.58, 0.46, 0.60]

    // MARK: - The three regimes on the real fused dispatch

    @Test func structuredResidualMovesAboveTheQ16LSB() {
        guard let rung = RungDispatch() else { return }   // no Metal ⇒ skip (floor ships)
        // Voxels = amplitude · pattern: coarse ∝ amplitude AND detail ∝ amplitude, so
        // detail is linear in coarse — learnable, and above-LSB by construction.
        let blocks = Self.regime(n: 64) { v, _ in Self.pattern.map { $0 * (0.2 + 1.6 * v) } }
        guard let out = rung.trainSimt(blocks: blocks) else { Issue.record("dispatch nil"); return }
        let floor = Self.floorLoss(pairs: out.pairs)
        let reduction = floor > 0 ? 1 - Double(out.loss) / floor : 0
        let clearedLSB = out.committed.contains { abs($0) >= 1 }   // committed ≥ 1 Q16 unit

        #expect(floor > 0)          // there IS residual energy to explain
        #expect(reduction > 0.7)    // the gene learns most of it in one dispatch
        #expect(clearedLSB)         // and it commits above the Q16 LSB
    }

    @Test func flatResidualCorrectlyNoOps() {
        guard let rung = RungDispatch() else { return }
        // 8 EQUAL voxels per octant ⇒ lift gives coarse = value, all 7 detail = 0:
        // nothing to invent. Coarse still varies across octants.
        let blocks = Self.regime(n: 64) { v, _ in [Double](repeating: v, count: 8) }
        guard let out = rung.trainSimt(blocks: blocks) else { Issue.record("dispatch nil"); return }

        #expect(Self.floorLoss(pairs: out.pairs) == 0)        // zero residual — the flat capture
        #expect(out.loss == 0)                                // nothing learned, nothing lost
        #expect(out.committed.allSatisfy { $0 == 0 })         // THE no-op: invented nothing
    }

    @Test func noiseResidualFloorsHonestly() {
        guard let rung = RungDispatch() else { return }
        // Voxels = base + per-voxel hash noise, uncorrelated with the coarse level ⇒
        // lifted detail is real (large floor) but unpredictable from coarse. Work is
        // capped at I(coarse; detail) ≈ 0: the loss cannot fall much below the floor.
        var s: UInt64 = 0x9E3779B97F4A7C15
        let blocks = Self.regime(n: 64) { v, _ in
            (0..<8).map { _ in
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return v + (Double((s >> 40) % 2000) / Self.q16 - 1000 / Self.q16)   // ±~0.015
            }
        }
        guard let out = rung.trainSimt(blocks: blocks) else { Issue.record("dispatch nil"); return }
        let floor = Self.floorLoss(pairs: out.pairs)
        let reduction = floor > 0 ? 1 - Double(out.loss) / floor : 0

        #expect(floor > 0.0005)    // real residual energy…
        #expect(reduction < 0.35)  // …but the gene can't invent it from coarse — the honest cap
    }

    // MARK: - The gated-S ship decision (report §4 "yields work")

    /// Wrap a real dispatch's output as the gene the app would carry, so the runtime
    /// `yieldsWork` ship-gate is tested on ACTUAL kernel results, not synthetic numbers.
    private static func gene(_ out: (pairs: [Int32], theta: [Float], committed: [Int], loss: Float))
        -> CaptureGene.ThetaUp {
        CaptureGene.ThetaUp(theta: out.theta, committed: out.committed, loss: out.loss,
                            floorLoss: Float(floorLoss(pairs: out.pairs)),
                            trainMillis: 0, channel: 0, frames: 2, side: 2)
    }

    @Test func yieldsWorkGatesTheThreeRegimes() {
        guard let rung = RungDispatch() else { return }
        let structured = Self.regime(n: 64) { v, _ in Self.pattern.map { $0 * (0.2 + 1.6 * v) } }
        let flat = Self.regime(n: 64) { v, _ in [Double](repeating: v, count: 8) }
        var s: UInt64 = 0x9E3779B97F4A7C15
        let noise = Self.regime(n: 64) { v, _ in
            (0..<8).map { _ in
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return v + (Double((s >> 40) % 2000) / Self.q16 - 1000 / Self.q16)
            }
        }
        guard let sOut = rung.trainSimt(blocks: structured),
              let fOut = rung.trainSimt(blocks: flat),
              let nOut = rung.trainSimt(blocks: noise) else { Issue.record("dispatch nil"); return }

        #expect(Self.gene(sOut).yieldsWork() == true)    // structured → SHIP the gene
        #expect(Self.gene(fOut).yieldsWork() == false)   // flat → floor (committed all 0)
        #expect(Self.gene(nOut).yieldsWork() == false)   // noise → floor (below the work bar)
    }

    // MARK: - Bit-reproducibility (the determinism-floor audit, within-device leg)

    @Test func fusedDispatchIsBitReproducibleAcrossRuns() {
        guard let rung = RungDispatch() else { return }
        let blocks = Self.regime(n: 64) { v, _ in Self.pattern.map { $0 * (0.2 + 1.6 * v) } }
        guard let a = rung.trainSimt(blocks: blocks),
              let b = rung.trainSimt(blocks: blocks) else { Issue.record("dispatch nil"); return }
        // The FP32-accumulate → pinned-round → Q16 path must be byte-identical run to run.
        #expect(a.committed == b.committed)
        #expect(a.loss.bitPattern == b.loss.bitPattern)
        #expect(a.theta == b.theta)
        // Printed so a physical-device run of this suite can be diffed against the sim
        // (M-series host) run — the cross-generation reproducibility audit.
        print("AMORTIZED-FIT committed=\(a.committed) loss=\(a.loss.bitPattern) theta0=\(a.theta.first ?? 0)")
    }
}
