import Foundation
import Testing
@testable import SixFour

/// `Spec.DetailEntropy`'s laws on the Swift twin (2026-07-11 link-ledger
/// wave 2): the bit-budget estimator behaves like Shannon entropy must.
struct DetailEntropyTests {

    @Test func entropyLaws() {
        // Non-negative, zero iff single symbol.
        #expect(DetailEntropy.shannonBits([]) == 0)
        #expect(DetailEntropy.shannonBits([7, 7, 7, 7]) == 0)
        #expect(DetailEntropy.shannonBits([1, 2]) > 0)
        // Max at uniform: H(uniform over 4) = 2 bits exactly.
        let uniform = [0, 1, 2, 3, 0, 1, 2, 3]
        #expect(abs(DetailEntropy.shannonBits(uniform) - 2.0) < 1e-12)
        // Upper bound log2(alphabet); skewed strictly below uniform.
        let skewed = [0, 0, 0, 0, 0, 1, 2, 3]
        #expect(DetailEntropy.shannonBits(skewed) < 2.0)
        #expect(DetailEntropy.shannonBits(skewed)
                <= log2(Double(DetailEntropy.alphabetSize(skewed))) + 1e-12)
        // codedBits = n · H.
        #expect(abs(DetailEntropy.codedBits(uniform) - 16.0) < 1e-12)
    }

    @Test func constantDetailCostsZeroBits() {
        // A flat (perfectly predicted) octant set: every band constant ⇒ the
        // whole detail set codes to zero bits — the compressible-surplus
        // reading of "flat costs nothing".
        let flat = Array(repeating: Array(repeating: 0, count: 7), count: 16)
        #expect(DetailEntropy.detailEntropyBits(flat) == 0)
    }

    @Test func perBandDiffersFromPooled() {
        // Two bands, each constant (0 bits per band) but with DIFFERENT
        // constants: pooled they look like a 2-symbol source (positive bits).
        // Per-band coding is the strictly better reading — the law that keeps
        // bands separate.
        let details = (0..<8).map { _ in [0, 5, 0, 0, 0, 0, 0] }
        #expect(DetailEntropy.detailEntropyBits(details) == 0)
        #expect(DetailEntropy.shannonBits(DetailEntropy.pooledCoeffs(details)) > 0)
    }
}
