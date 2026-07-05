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

    // MARK: - The shipped W₀ blob (offline producer → device loader)

    /// Serialise a meta-init to the on-disk blob: `paramCount` little-endian Float32
    /// (84 bytes for the 21-param head) — a plain binary Resource, the house pattern
    /// (`stbn3d-8.bin`). Float32, not Double, because the device consumes `[Float]`.
    static func serialize(_ w0: [Double]) -> Data {
        var data = Data(capacity: w0.count * 4)
        for x in w0 {
            var le = Float(x).bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// The exact inverse of `serialize` — nil unless the blob is a whole number of
    /// Float32 of the expected length.
    static func deserialize(_ data: Data, count: Int = DeviceTrainStepCPU.paramCount) -> [Double]? {
        guard data.count == count * 4 else { return nil }
        var out = [Double](); out.reserveCapacity(count)
        var i = data.startIndex
        for _ in 0..<count {
            let bits = data[i..<(i + 4)].reduce(into: UInt32(0)) { acc, byte in acc = (acc >> 8) | (UInt32(byte) << 24) }
            out.append(Double(Float(bitPattern: bits)))
            i += 4
        }
        return out
    }

    /// THE OFFLINE PRODUCER (deterministic, no RNG): the Reptile meta-init over a
    /// SYNTHETIC capture family — the documented STAND-IN until real AirDropped bursts
    /// (`docs/PER-CAPTURE-LEARNING-RESEARCH.md` §5.1) supply the corpus. Kept explicit
    /// and seeded so the blob it emits is reproducible byte-for-byte across builds.
    /// NOT validated on real scenes, which is exactly why the deployed path is gated
    /// OFF (`Feature.metaInitW0`) until a real-corpus W₀ replaces it.
    static func syntheticCorpusW0() -> [Double] {
        let c = [0.10, -0.08, 0.06, 0.12, -0.05, 0.09, -0.07]
        let family = [0.6, 0.8, 1.0, 1.2, 1.4].map { amp -> [Pair] in
            (0..<16).map { i in
                let vt = 0.1 + 0.8 * Double(i) / 15
                let detail = c.map { DeviceTrainStepCPU.quantizeQ16(amp * $0 * vt) }
                return Pair(coarse: Int((vt * 65536).rounded()), detail: detail)
            }
        }
        return reptile(captures: family, outerSteps: 300, innerSteps: 5, eta: 0.5, epsilon: 0.2)
    }

    /// The W₀ the device descends from when `Feature.metaInitW0` is on: a shipped
    /// `metainit-w0.bin` Resource (a real-corpus blob) if present, else the synthetic
    /// stand-in. Computed once. `[Float]` for the kernel's `w0:` parameter.
    static let deployedW0: [Float] = {
        if let url = Bundle.main.url(forResource: "metainit-w0", withExtension: "bin"),
           let data = try? Data(contentsOf: url),
           let w = deserialize(data), w.count == DeviceTrainStepCPU.paramCount {
            return w.map(Float.init)
        }
        return syntheticCorpusW0().map(Float.init)
    }()

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
