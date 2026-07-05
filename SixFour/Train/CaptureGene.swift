import Foundation

/// The SOMATIC gene factory (V3.0, `Spec.GeneTaxonomy` class Somatic): turn the
/// burst the user just took into its own trained θ_up.
///
/// The burst's OKLab float tiles are assembled into the interleaved Q16 volume
/// (`frames × side × side × 3`, the `captureOctantsKernel` layout) through the
/// single sanctioned float→device crossing (round-half-to-even ×2¹⁶ —
/// `DeviceTrainStepCPU.quantizeQ16`), then `RungDispatch.trainOnVolume` runs
/// the whole [octant gather → deterministic-SIMT descent → Q16 commit] in one
/// command buffer. The result is a `ThetaUp` gene: born at the capture seam,
/// stored with the capture, dying with it (zero-gene == the deterministic
/// floor, so its absence is always safe).
enum CaptureGene {

    /// The per-capture somatic gene: the trained up-rung inventor + its birth
    /// telemetry. `theta` is the spec flat row-major layout (7 bands × 3).
    struct ThetaUp: Sendable, Codable, Equatable {
        let theta: [Float]
        let committed: [Int]   // f_θ at pair 0's coarse, post-Q16 (telemetry)
        let loss: Float        // final summed supervised loss
        let floorLoss: Float   // the zero-param floor loss on the SAME pairs (the reference)
        let trainMillis: Double // wall-clock of the fused GPU dispatch
        let channel: Int       // OKLab channel trained (0 = L)
        let frames: Int
        let side: Int

        /// Fraction of the floor loss the descent removed (0 = learned nothing,
        /// 1 = perfect fit). The honest one-number verdict for a capture.
        var lossReduction: Double {
            floorLoss > 0 ? 1 - Double(loss) / Double(floorLoss) : 0
        }

        /// The default fraction of the residual a capture must explain for its
        /// learning to count as WORK (research report §4 "yields work"): below this
        /// the gene is noise-floored or flat and the lossless floor ships instead.
        static let defaultWorkBar = 0.25

        /// Did this capture's learning YIELD WORK worth shipping the gene for?
        /// Two conditions, mirroring the FLOORED-discharge probe's three regimes
        /// (`AmortizedFitProbeTests`):
        ///   1. it CLEARED THE Q16 LSB — at least one committed band is non-zero
        ///      (a flat capture commits all-zero and fails here), AND
        ///   2. it EXPLAINED ENOUGH — `lossReduction ≥ bar` (a noise capture floors
        ///      below the bar, its residual being unpredictable from coarse).
        /// When false, the gene invented nothing useful; ship the byte-exact floor.
        /// This is the gated-S rule made a runtime decision — the S-map spends only
        /// where the free coarse-pool label carries above-floor, learnable detail.
        func yieldsWork(bar: Double = defaultWorkBar) -> Bool {
            committed.contains { $0 != 0 } && lossReduction >= bar
        }
    }

    /// Assemble the burst tiles into the interleaved OKLab Q16 volume
    /// (`((f·side + row)·side + col)·3 + ch` — the capture/`s4_synth_burst`
    /// layout `captureOctantsKernel` reads). Returns nil unless the burst is
    /// octant-partitionable (even frame count ≥ 2, even side, uniform tiles).
    static func volume(from tiles: [OKLabTile]) -> [Int32]? {
        guard let side = tiles.first?.side,
              tiles.count >= 2, tiles.count % 2 == 0,
              side >= 2, side % 2 == 0,
              tiles.allSatisfy({ $0.side == side && $0.pixels.count == side * side })
        else { return nil }
        var volume = [Int32](repeating: 0, count: tiles.count * side * side * 3)
        for (f, tile) in tiles.enumerated() {
            let base = f * side * side * 3
            for p in 0 ..< side * side {
                let px = tile.pixels[p]
                for ch in 0 ..< 3 {
                    volume[base + p * 3 + ch] =
                        Int32(DeviceTrainStepCPU.quantizeQ16(Double(px[ch])))
                }
            }
        }
        return volume
    }

    /// Train the somatic θ_up from the burst (L channel — the carrier). Returns
    /// nil where Metal compute is unavailable or the burst shape is untrainable;
    /// callers treat the gene as optional (its absence is the floor).
    static func train(tiles: [OKLabTile], channel: Int = 0,
                      rung: RungDispatch? = RungDispatch(),
                      w0: [Float]? = nil) -> ThetaUp? {
        guard let rung, let volume = volume(from: tiles) else { return nil }
        let t0 = DispatchTime.now().uptimeNanoseconds
        // W₀ = the meta-init the descent starts from (nil = the zero floor, today's path).
        guard let out = rung.trainOnVolume(volume: volume, frames: tiles.count,
                                           side: tiles[0].side, channel: channel, w0: w0)
        else { return nil }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        // The zero-param floor loss on the SAME manufactured pairs: ½ Σ t̃² (the
        // reference that makes `loss` readable — pure CPU pass, ~ms).
        var floorSSE = 0.0
        for i in stride(from: 0, to: out.pairs.count, by: 8) {
            for j in 1 ... 7 {
                let t = Double(out.pairs[i + j]) / 65536.0
                floorSSE += t * t
            }
        }
        return ThetaUp(theta: out.theta, committed: out.committed, loss: out.loss,
                       floorLoss: Float(0.5 * floorSSE), trainMillis: ms,
                       channel: channel, frames: tiles.count, side: tiles[0].side)
    }
}
