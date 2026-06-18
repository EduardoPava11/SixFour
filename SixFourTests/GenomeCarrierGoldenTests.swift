import Testing
@testable import SixFour

/// Byte-exact gate for the GenomeCarrier Swift port. `GenomeCarrierGolden` is GENERATED from
/// `SixFour.Spec.GenomeCarrier` (CI-proven, 6 laws). The Swift `encode` must reproduce the byte
/// stream EXACTLY and `extract` must round-trip back to the payload.
struct GenomeCarrierGoldenTests {

    private var goldenPayload: GenomeCarrier.Payload {
        let h = GenomeCarrierGolden.header
        let header = GenomeCarrier.Header(
            major: UInt8(h[0]), minor: UInt8(h[1]), flags: UInt16(h[2]),
            dof: UInt16(h[3]), radix: UInt8(h[4]), deviceIdHash: UInt32(h[5]), btCompares: UInt32(h[6]))
        return GenomeCarrier.Payload(header: header, coeffs: GenomeCarrierGolden.coeffs)
    }

    @Test func encodeMatchesGoldenBytes() {
        #expect(GenomeCarrier.encode(goldenPayload) == GenomeCarrierGolden.encoded)
    }

    @Test func extractRoundTrips() {
        let p = goldenPayload
        #expect(GenomeCarrier.extract(GenomeCarrier.encode(p)) == .success(p))
    }

    @Test func absentBlockIsNoBlock() {
        // A plain GIF header with no S4GN block.
        let plain: [UInt8] = Array("GIF89a".utf8) + [0x3B]
        #expect(GenomeCarrier.extract(plain) == .failure(.noBlock))
    }

    @Test func corruptionIsDetected() {
        var bytes = GenomeCarrier.encode(goldenPayload)
        bytes[bytes.count / 2] ^= 0x01          // flip a body byte → CRC mismatch
        let r = GenomeCarrier.extract(bytes)
        #expect(r != .success(goldenPayload))
    }
}
