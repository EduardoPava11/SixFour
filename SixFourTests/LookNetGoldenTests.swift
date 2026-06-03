import Testing
@testable import SixFour

/// Gate for the hand-written Swift look-NN forward (`LookNetForward`) against the
/// spec oracle (`SixFour.Spec.LookNetEval.forward`, transported as
/// `LookNetGolden`). Weights and inputs arrive bit-exact (IEEE-754 hex); the
/// float matmul order diverges across languages, so the pooled context, per-step
/// halts, and 384-D output are gated within `LookNetGolden.tolerance` (1e-6) —
/// the same tolerance the Python MLX/PyTorch ports use.
struct LookNetGoldenTests {

    /// Decode a string of concatenated 16-hex-digit IEEE-754 doubles.
    private static func decode(_ s: String) -> [Double] {
        let chars = Array(s)
        var out = [Double]()
        out.reserveCapacity(chars.count / 16)
        var i = 0
        while i < chars.count {
            let bits = UInt64(String(chars[i..<i + 16]), radix: 16)!
            out.append(Double(bitPattern: bits))
            i += 16
        }
        return out
    }

    private static func decode1(_ s: String) -> Double {
        Double(bitPattern: UInt64(s, radix: 16)!)
    }

    private func goldenWeights() -> LookNetForward.Weights {
        LookNetForward.Weights(
            phi: Self.decode(LookNetGolden.phiHex),
            w1: Self.decode(LookNetGolden.w1Hex),
            w2: Self.decode(LookNetGolden.w2Hex),
            haltW: Self.decode(LookNetGolden.haltWHex),
            haltB: Self.decode1(LookNetGolden.haltBHex),
            heads: LookNetGolden.headHex.map(Self.decode)
        )
    }

    private func tokens(_ c: LookNetGolden.Case) -> [[Double]] {
        let flat = Self.decode(c.tokensHex)
        let dim = LookNetForward.gmmTokenDim
        return (0..<c.tokenCount).map { Array(flat[$0 * dim ..< ($0 + 1) * dim]) }
    }

    private func maxAbsDiff(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0.0) { max($0, abs($1.0 - $1.1)) }
    }

    /// Swift `forward` reproduces the spec oracle's context, halts, and output
    /// for every golden case, within tolerance.
    @Test func forwardMatchesGolden() {
        let w = goldenWeights()
        let tol = LookNetGolden.tolerance
        for c in LookNetGolden.cases {
            let tr = LookNetForward.forward(w, tokens: tokens(c))

            #expect(tr.context.count == LookNetForward.modelDim)
            #expect(tr.halts.count == LookNetForward.coreDepth)
            #expect(tr.output.count == LookNetForward.decoderOutputDim)

            let dCtx = maxAbsDiff(tr.context, Self.decode(c.contextHex))
            let dHalt = maxAbsDiff(tr.halts, Self.decode(c.haltsHex))
            let dOut = maxAbsDiff(tr.output, Self.decode(c.outputHex))
            #expect(dCtx <= tol, "[\(c.name)] context drift \(dCtx)")
            #expect(dHalt <= tol, "[\(c.name)] halt drift \(dHalt)")
            #expect(dOut <= tol, "[\(c.name)] output drift \(dOut)")
        }
    }

    /// The Deep-Sets sum-pool is permutation-invariant: reordering tokens leaves
    /// the pooled context unchanged (up to float reassociation).
    @Test func poolIsPermutationInvariant() {
        let w = goldenWeights()
        let c = LookNetGolden.cases.first { $0.name == "octet" }!
        let toks = tokens(c)
        let a = LookNetForward.forward(w, tokens: toks).context
        let b = LookNetForward.forward(w, tokens: toks.reversed()).context
        #expect(maxAbsDiff(a, b) <= 1e-9, "pool not permutation-invariant")
    }
}
