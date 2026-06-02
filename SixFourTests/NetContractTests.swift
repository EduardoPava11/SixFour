import Testing
@testable import SixFour

/// Locks the look-NN FORM seam (`Generated/NetContract.swift`, source
/// `SixFour.Spec.Net.slotLookDims`). The on-device forward pass loads weights of
/// exactly this shape, so any drift between the spec, the MLX trainer, and Swift
/// must fail here. Also pins the 384-vs-768 distinction the docs used to conflate.
struct NetContractTests {

    @Test func lookNetFormIsPinned() {
        // GMM_TOKEN_DIM tokens → SIGMA_PAIR_DOF coefficients.
        #expect(SixFourNetIO.look.inputDim == 10)
        #expect(SixFourNetIO.look.outputDim == 384)
        #expect(SixFourNetIO.lookSigmaPairDOF == 384)

        let aux = SixFourNetIO.lookAuxDims
        #expect(aux["MODEL_DIM"] == 64)
        #expect(aux["CORE_DEPTH"] == 8)
        #expect(aux["SIGMA_PAIR_LEAVES"] == 256)
        #expect(aux["MAX_TOKENS"] == 16384)
    }

    /// The σ-pair structural identities — the FORM the UI/UX follows.
    @Test func sigmaPairFormIdentities() {
        let dof = SixFourNetIO.lookSigmaPairDOF
        let leaves = SixFourNetIO.lookAuxDims["SIGMA_PAIR_LEAVES"]!

        // 384 = 3 · 128 σ-pair generators (root + 1+2+…+64 inner = 128).
        #expect(dof == 3 * 128)
        // The genome reconstructs 256 leaves = 2 · (384/3) generators.
        #expect(leaves == 2 * (dof / 3))
        // Leaves are the K-colour palette; the FLAT leaf space is 256·3 = 768 reals
        // (NOT the genome DOF — that is the conflation the contract now forbids).
        #expect(leaves == SixFourShape.K)
        #expect(leaves * 3 == 768)
        #expect(dof != leaves * 3, "genome DOF (384) must NOT equal the flat leaf space (768)")

        // MAX_TOKENS = T·K (the pooled GMM token budget).
        #expect(SixFourNetIO.lookAuxDims["MAX_TOKENS"]! == SixFourShape.T * SixFourShape.K)
    }
}
