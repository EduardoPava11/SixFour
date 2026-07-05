import Foundation

/// META-INITIALISATION prototype (research report §5 item 4 / §3 "meta-learned
/// init"): the offline outer loop that BUYS the on-device few-step fit.
///
/// The naive per-capture overfit is brutal (COIN: 15k–50k steps); the escape the
/// literature names is a meta-learned starting point `W₀` from which a NEW capture
/// converges in a handful of steps (functa: 3 steps). The on-device kernel today
/// descends from the ZERO floor (`deviceTrainSimtKernel` sets `th = 0`), so it must
/// travel the full distance every capture. This is the Mac-side (Tier-1) reference
/// that PROVES the value before the kernel is taught to start from `W₀`: a Reptile
/// outer loop over a family of captures, then a measurement that few-step-from-`W₀`
/// beats few-step-from-zero on held-out captures.
///
/// Reuses the exact `DeviceTrainStepCPU` math (`f_θ: coarse → 7 bands`,
/// `φ(v)=[1,ṽ,ṽ²]`, mean-gradient GD) so the prototype and the shipped head agree.
/// Deterministic (no RNG in the optimiser); the capture family is caller-supplied.
enum MetaInit {

    typealias Pair = DeviceTrainStepCPU.Pair

    /// The supervised loss `½ Σᵢ Σⱼ (θ·φ(vᵢ) − dᵢⱼ)²` over one capture's pairs, in
    /// Q16-normalised units — the objective both the inner loop and the eval report.
    static func loss(_ theta: [Double], _ pairs: [Pair]) -> Double {
        var sse = 0.0
        for p in pairs {
            let raw = DeviceTrainStepCPU.rawBands(theta: theta, coarse: p.coarse)
            for j in 0..<DeviceTrainStepCPU.bands {
                let d = raw[j] - Double(p.detail[j]) / 65536
                sse += d * d
            }
        }
        return 0.5 * sse
    }

    /// One mean-gradient GD step from `theta` over `pairs` (the `trainDevice` step,
    /// exposed so the inner loop can start from an arbitrary `W₀`).
    static func step(_ theta: [Double], _ pairs: [Pair], eta: Double) -> [Double] {
        guard !pairs.isEmpty else { return theta }
        let fc = DeviceTrainStepCPU.featureCount
        var grad = [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount)
        for p in pairs {
            let phi = DeviceTrainStepCPU.features(p.coarse)
            let raw = DeviceTrainStepCPU.rawBands(theta: theta, coarse: p.coarse)
            for j in 0..<DeviceTrainStepCPU.bands {
                let err = raw[j] - Double(p.detail[j]) / 65536
                for k in 0..<fc { grad[j * fc + k] += err * phi[k] }
            }
        }
        let scale = eta / Double(pairs.count)
        return zip(theta, grad).map { $0 - scale * $1 }
    }

    /// `steps` GD steps over `pairs`, starting from `w0` (the inner adaptation loop).
    static func trainFrom(_ w0: [Double], steps: Int, eta: Double, pairs: [Pair]) -> [Double] {
        var theta = w0
        for _ in 0..<max(0, steps) { theta = step(theta, pairs, eta: eta) }
        return theta
    }

    /// REPTILE outer loop: adapt `innerSteps` from the current `W₀` on each capture,
    /// then nudge `W₀` a fraction `epsilon` toward the mean adapted point. Starts at
    /// the zero floor; returns the meta-initialisation. First-order (no second-order
    /// backprop), so it maps to a cheap offline pass.
    static func reptile(captures: [[Pair]], outerSteps: Int, innerSteps: Int,
                        eta: Double, epsilon: Double) -> [Double] {
        var w0 = [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount)
        guard !captures.isEmpty else { return w0 }
        for _ in 0..<max(0, outerSteps) {
            var meanAdapted = [Double](repeating: 0, count: w0.count)
            for pairs in captures {
                let adapted = trainFrom(w0, steps: innerSteps, eta: eta, pairs: pairs)
                for i in 0..<w0.count { meanAdapted[i] += adapted[i] }
            }
            let n = Double(captures.count)
            for i in 0..<w0.count { w0[i] += epsilon * (meanAdapted[i] / n - w0[i]) }
        }
        return w0
    }
}
