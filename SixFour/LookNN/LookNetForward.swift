import Foundation
import simd

/// Hand-written, **zero-dependency** look-NN forward pass (Tier-2 shipped code).
///
/// Mirrors the spec oracle `SixFour.Spec.LookNetEval.forward` bit-for-bit up to
/// float summation order (gated within `1e-6` by `LookNetGoldenTests`):
///
///  - **L3 encoder** — a single σ-masked linear `phi` (10→64, no bias) applied
///    per GMM token, then **sum-pooled** over tokens (Deep-Sets, permutation
///    invariant).
///  - **L4 core** — ONE weight-shared residual block `x ↦ x + W2·tanh(W1·x)`
///    reused `coreDepth` (8) times (Mixture-of-Recursions). Produces 9 contexts.
///  - **halt head** — a σ-invariant PonderNet `λ` per step, read from
///    `(‖achroma‖², ‖chroma‖²)`. Exposed for the trainer; does NOT gate inference
///    (the unroll is static), matching the spec.
///  - **L5 decoder** — 8 per-level σ-masked heads; head `k` reads context `k`;
///    concatenated into the 384-D SigmaPairTree coefficients.
///
/// Weights are **RAW** (row-major `(out, in)`, the `nn.Linear` layout the `.s4ln`
/// blob and the golden ship); the σ-block-diagonal masks are applied here at call
/// time, exactly as the spec and the MLX/PyTorch ports apply them. No
/// `mlx-swift`, no CoreML, no Accelerate dependency — plain Swift + `Foundation`
/// `tanh`/`exp`.
enum LookNetForward {

    // Dimensional contract (mirrors NetContract / the spec).
    static let modelDim = 64
    static let gmmTokenDim = 10
    static let coreDepth = 8
    static let decoderLevelDims = [3, 3, 6, 12, 24, 48, 96, 192]
    static let decoderOutputDim = 384
    /// First `achromaticDim` hidden coordinates are σ-fixed; the rest are σ-negated.
    static let achromaticDim = 22

    /// RAW learnable weights, row-major `(out, in)`.
    struct Weights {
        var phi: [Double]       // 64 × 10
        var w1: [Double]        // 64 × 64
        var w2: [Double]        // 64 × 64
        var haltW: [Double]     // 2
        var haltB: Double
        var heads: [[Double]]   // 8 heads, each decoderLevelDims[k] × 64
    }

    /// The forward trace the golden gates: pooled context, per-step halts, output.
    struct Trace {
        let context: [Double]   // 64
        let halts: [Double]     // coreDepth (8)
        let output: [Double]    // decoderOutputDim (384)
    }

    // MARK: σ-class masks

    /// Token channel σ-classes `[μL, μa, μb, ΣLL, ΣLa, ΣLb, Σaa, Σab, Σbb, w]`.
    /// `false` = achromatic (σ-fixed), `true` = chromatic (σ-negated).
    static let gmmTokenSigmaMask: [Bool] =
        [false, true, true, false, true, true, false, false, false, false]

    /// Hidden σ-classes: 22 achromatic, then 42 chromatic (red-green ⊕ blue-yellow).
    static let sigma64Mask: [Bool] =
        Array(repeating: false, count: 22) + Array(repeating: true, count: 42)

    /// Decoder output σ-class for coefficient `j`: each OKLab triple is `[L, a, b]`
    /// = `[false, true, true]`, so the L channel (`j % 3 == 0`) is σ-fixed.
    static func decoderMaskBit(_ j: Int) -> Bool { j % 3 != 0 }

    /// Block-diagonal mask `(out × in)`: weight free iff out-class == in-class.
    private static func blockMask(out: [Bool], inn: [Bool]) -> [Double] {
        var m = [Double](repeating: 0, count: out.count * inn.count)
        for o in 0..<out.count {
            let base = o * inn.count
            for i in 0..<inn.count where out[o] == inn[i] { m[base + i] = 1 }
        }
        return m
    }

    private static let phiMask = blockMask(out: sigma64Mask, inn: gmmTokenSigmaMask)
    private static let w64Mask = blockMask(out: sigma64Mask, inn: sigma64Mask)

    private static func headMask(_ k: Int) -> [Double] {
        let dk = decoderLevelDims[k]
        let off = decoderLevelDims[0..<k].reduce(0, +)
        let outClasses = (0..<dk).map { decoderMaskBit(off + $0) }
        return blockMask(out: outClasses, inn: sigma64Mask)
    }

    // MARK: linear algebra

    /// `y[o] = Σ_i w[o·inn + i] · x[i]`, `w` flat row-major `(out × inn)`.
    private static func linear(out: Int, inn: Int, _ w: [Double], _ x: [Double]) -> [Double] {
        var y = [Double](repeating: 0, count: out)
        for o in 0..<out {
            let base = o * inn
            var acc = 0.0
            for i in 0..<inn { acc += w[base + i] * x[i] }
            y[o] = acc
        }
        return y
    }

    private static func masked(_ w: [Double], _ mask: [Double]) -> [Double] {
        var out = w
        for i in 0..<out.count { out[i] *= mask[i] }
        return out
    }

    private static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-z)) }

    // MARK: forward

    /// Run the forward pass. `tokens` is a list of `gmmTokenDim`-length vectors.
    static func forward(_ w: Weights, tokens: [[Double]]) -> Trace {
        let phiM = masked(w.phi, phiMask)
        let w1M = masked(w.w1, w64Mask)
        let w2M = masked(w.w2, w64Mask)

        // L3: per-token phi (10→64), then sum-pool over tokens.
        var context = [Double](repeating: 0, count: modelDim)
        for t in tokens {
            let placed = linear(out: modelDim, inn: gmmTokenDim, phiM, t)
            for i in 0..<modelDim { context[i] += placed[i] }
        }

        // L4: refine x ↦ x + W2·tanh(W1·x); collect coreDepth+1 contexts.
        func refine(_ x: [Double]) -> [Double] {
            let pre = linear(out: modelDim, inn: modelDim, w1M, x).map(tanh)
            let dx = linear(out: modelDim, inn: modelDim, w2M, pre)
            return zip(x, dx).map(+)
        }
        var contexts = [context]
        for _ in 0..<coreDepth { contexts.append(refine(contexts[contexts.count - 1])) }

        // σ-invariant halt λ per step (read from contexts[0..<coreDepth]).
        func halt(_ x: [Double]) -> Double {
            var a = 0.0, c = 0.0
            for i in 0..<achromaticDim { a += x[i] * x[i] }
            for i in achromaticDim..<modelDim { c += x[i] * x[i] }
            return sigmoid(w.haltW[0] * a + w.haltW[1] * c + w.haltB)
        }
        let halts = (0..<coreDepth).map { halt(contexts[$0]) }

        // L5: head k reads contexts[k]; concat per-level outputs into 384 coeffs.
        var output = [Double]()
        output.reserveCapacity(decoderOutputDim)
        for k in 0..<decoderLevelDims.count {
            let dk = decoderLevelDims[k]
            let wm = masked(w.heads[k], headMask(k))
            output.append(contentsOf: linear(out: dk, inn: modelDim, wm, contexts[k]))
        }

        return Trace(context: context, halts: halts, output: output)
    }
}

// MARK: - σ-pair palette reconstruction (the canonical "look" output)

extension LookNetForward {
    /// Depth of the generator Haar pyramid (128 = 2^7 generators).
    static let paletteDepth = 7
    /// Reconstructed palette size (128 generators × σ-pair = 256 OKLab colours).
    static let paletteLeaves = 256

    /// σ(L, a, b) = (L, −a, −b) — the OKLab chroma complement.
    static func sigmaReflect(_ c: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(c.x, -c.y, -c.z)
    }

    /// Reconstruct the **256-colour σ-pair OKLab palette** from the 384 decoder
    /// coefficients — the canonical look output, mirroring
    /// `SixFour.Spec.SigmaPairHead.reconstructPaired`:
    ///
    ///  - a depth-7 inverse Haar pyramid: each node splits into mirror children
    ///    `node ± offset`, top-down, level `i` consuming `2^i` offsets → 128
    ///    OKLab generators `c_i`;
    ///  - then the σ-pair interleave `[c_0, σ(c_0), c_1, σ(c_1), …]`, so every
    ///    odd leaf is the exact chroma complement of its even predecessor — the
    ///    palette is σ-symmetric by construction, for any coefficients.
    ///
    /// Purely algebraic (no weights). Grayscale is the special case where the
    /// chroma channels of every generator are 0.
    static func reconstructPalette(_ coeffs: [Double]) -> [SIMD3<Double>] {
        precondition(coeffs.count == decoderOutputDim, "expected \(decoderOutputDim) coefficients")
        var nodes = [SIMD3<Double>(coeffs[0], coeffs[1], coeffs[2])]   // root (DC colour)
        var idx = 3
        for level in 0..<paletteDepth {
            let n = 1 << level                                        // 2^level nodes / offsets
            var next = [SIMD3<Double>]()
            next.reserveCapacity(n * 2)
            for k in 0..<n {
                let off = SIMD3<Double>(coeffs[idx], coeffs[idx + 1], coeffs[idx + 2])
                idx += 3
                let p = nodes[k]
                next.append(p + off)                                  // child 0 = parent + δ
                next.append(p - off)                                  // child 1 = parent − δ
            }
            nodes = next
        }
        // 128 generators → interleave each with its σ-reflection → 256 leaves.
        var palette = [SIMD3<Double>]()
        palette.reserveCapacity(nodes.count * 2)
        for c in nodes {
            palette.append(c)
            palette.append(sigmaReflect(c))
        }
        return palette
    }
}
