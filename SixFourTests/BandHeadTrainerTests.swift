import Testing
@testable import SixFour

/// THE TRAINING-OCCURS PROOF, ON THE PHONE'S OWN COMPUTE PATH — the three-arm
/// experiment (prove_training_occurs.py) replicated through the plain-Metal
/// fused trainer (`BandHeadTrainer`), running in the iPhone simulator:
/// structured targets must learn to ~zero, noise targets must FLOOR (the
/// honest control), and the sequential kernel must be bit-deterministic.
/// No Mac, no MLX, no MPSGraph — Apple Metal only. Skips where Metal is
/// absent (floor-only environments).
struct BandHeadTrainerTests {

    /// One-hot phase features over t: (t mod 8) x ((t/8) mod 3) — the same
    /// observable features as the numpy proof, 24-wide.
    private func phaseFeatures(ticks: Int) -> [Float] {
        var out = [Float](repeating: 0, count: ticks * 24)
        for t in 0..<ticks {
            out[t * 24 + (t % 8) * 3 + (t / 8) % 3] = 1
        }
        return out
    }

    private func variance(_ ys: [Float]) -> Float {
        let m = ys.reduce(0, +) / Float(ys.count)
        return ys.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(ys.count)
    }

    @Test func structuredTargetsLearnToNearZero() {
        guard let trainer = BandHeadTrainer() else { return }
        let ticks = 64
        // Deterministic 'gene': pattern over phase, scaled by block — exactly
        // realizable in the features, so the optimum is zero loss.
        let pattern: [Float] = [3, -7, 1, 8, -2, 5, -4, 6]
        var targets = [Float]()
        for t in 0..<ticks {
            let scale: Int = 1 + (t / 8) % 3
            targets.append(pattern[t % 8] * Float(scale))
        }
        let floor = variance(targets)
        let r = trainer.train(
            features: phaseFeatures(ticks: ticks), targets: targets,
            featureWidth: 24, steps: 1500, eta: 0.05)
        #expect(r != nil)
        if let r {
            #expect(r.finalMSE < 0.05 * floor)   // TRAINING OCCURS, on-device path
            #expect(r.initialMSE > 0.5 * floor)  // and it started from far away
        }
    }

    @Test func noiseTargetsCorrectlyFloor() {
        guard let trainer = BandHeadTrainer() else { return }
        let ticks = 64
        // LCG noise, same scale family as the structured arm — the honest
        // control: if this "learns", the structured descent proves nothing.
        var s: UInt64 = 20260704
        var targets = [Float]()
        for t in 0..<ticks {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let raw: Int64 = Int64((s >> 33) & 0xf)
            let v: Float = Float(raw) - 8
            let scale: Int = 1 + (t / 8) % 3
            targets.append(v * Float(scale))
        }
        let floor = variance(targets)
        let r = trainer.train(
            features: phaseFeatures(ticks: ticks), targets: targets,
            featureWidth: 24, steps: 1500, eta: 0.05)
        #expect(r != nil)
        if let r {
            // 24 one-hot phase cells CAN memorize some of 64 noise points
            // (24/64 of the variance is reachable), so the floor bound is the
            // unreachable remainder, with margin: no better than 45% of var.
            #expect(r.finalMSE > 0.45 * floor)
        }
    }

    @Test func sequentialKernelIsBitDeterministic() {
        guard let trainer = BandHeadTrainer() else { return }
        let ticks = 48
        var targets = [Float]()
        for t in 0..<ticks {
            let m: Int = (t * 37) % 23
            targets.append(Float(m) - 11)
        }
        let run = {
            trainer.train(
                features: self.phaseFeatures(ticks: ticks), targets: targets,
                featureWidth: 24, steps: 400, eta: 0.03)
        }
        let a = run()
        let b = run()
        #expect(a != nil && b != nil)
        if let a, let b {
            #expect(a.weights == b.weights)       // bit-identical
            #expect(a.finalMSE == b.finalMSE)
        }
    }
}
