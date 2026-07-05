import Testing
@testable import SixFour

/// THE FULL CIRCUIT, ON THE SIMULATOR: ladder ticks → ColorHead's exact
/// integer t-band pairs (the 32→64 transition, causal features, OctantViews
/// sign) → BandHeadTrainer's plain-Metal descent. Structured motion must
/// learn to near-zero; per-tick random flicker must floor. This is the
/// yin-yang running end to end on the phone's compute path: the yin ladder
/// manufactures the labels, the yang head consumes them, arithmetic gates
/// both.
struct YinYangCircuitTests {

    /// A 64-rung tick whose bin L-sums follow `base` (per bin) plus
    /// `amp` on odd ticks — pumped straight into ColorHead.ingest (the
    /// pixel-buffer path is gated separately in ColorHeadTests).
    private func tick(base: [Int64], amp: [Int64], odd: Bool) -> [UInt64] {
        var out = [UInt64](repeating: 0, count: 64 * 64 * 3)
        for i in 0..<(64 * 64) {
            let l = base[i] + (odd ? amp[i] : 0)
            // split L across the three channels deterministically
            out[i * 3] = UInt64(l / 3)
            out[i * 3 + 1] = UInt64(l / 3)
            out[i * 3 + 2] = UInt64(l - 2 * (l / 3))
        }
        return out
    }

    private func bases() -> [Int64] {
        (0..<(64 * 64)).map { i in 300 + Int64((i * 7) % 900) }
    }

    @Test func structuredMotionLearnsOnTheDevicePath() {
        guard let trainer = BandHeadTrainer() else { return }
        let head = ColorHead(cropSide: 128)
        let base = bases()
        // STRUCTURED: the odd-tick amplitude is half the base — the t-band is
        // exactly linear in the causal features (coefficient -1/2 per bin).
        let amp = base.map { $0 / 2 }
        for t in 0..<8 {
            head.ingest(tick(base: base, amp: amp, odd: t % 2 == 1))
        }
        let (f, y, w) = head.drainTBandPairs(scale: 1.0 / 4096.0)
        #expect(y.count == 4 * 1024)   // 4 tick-pairs x 32x32 blocks
        // subsample for the single-thread kernel's budget
        var sf = [Float](); var sy = [Float]()
        for i in Swift.stride(from: 0, to: y.count, by: 16) {
            sf.append(contentsOf: f[(i * w)..<(i * w + w)])
            sy.append(y[i])
        }
        let floor = variance(sy)
        let r = trainer.train(features: sf, targets: sy, featureWidth: w,
                              steps: 2500, eta: 0.4)
        #expect(r != nil)
        if let r {
            #expect(r.finalMSE < 0.05 * floor)
        }
    }

    @Test func randomFlickerCorrectlyFloorsOnTheDevicePath() {
        guard let trainer = BandHeadTrainer() else { return }
        let head = ColorHead(cropSide: 128)
        let base = bases()
        var s: UInt64 = 20260704
        for t in 0..<8 {
            // NOISE: a fresh random amplitude field every tick — the t-band
            // is unpredictable from the causal (first-tick) features.
            let amp: [Int64] = (0..<(64 * 64)).map { _ in
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return Int64((s >> 33) % 400)
            }
            head.ingest(tick(base: base, amp: amp, odd: t % 2 == 1))
        }
        let (f, y, w) = head.drainTBandPairs(scale: 1.0 / 4096.0)
        var sf = [Float](); var sy = [Float]()
        for i in Swift.stride(from: 0, to: y.count, by: 16) {
            sf.append(contentsOf: f[(i * w)..<(i * w + w)])
            sy.append(y[i])
        }
        let floor = variance(sy)
        let r = trainer.train(features: sf, targets: sy, featureWidth: w,
                              steps: 2500, eta: 0.4)
        #expect(r != nil)
        if let r {
            #expect(r.finalMSE > 0.5 * floor)   // the honest control holds
        }
    }

    private func variance(_ ys: [Float]) -> Float {
        let m = ys.reduce(0, +) / Float(ys.count)
        return ys.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(ys.count)
    }
}
