import Foundation

/// Hand-written Swift port of `SixFour.Spec.GenomeCarrier` — the S4GN genome-in-GIF
/// codec: the 384-DOF σ-pair genome as Int32 LE Q16 behind a 24-byte versioned header
/// with a CRC32 footer, inside a standards-compliant GIF89a Application-Extension
/// block (`"SIXFOUR1" + "G10"`). Byte-exact against the generated
/// `GenomeCarrierGolden` (gated in `SwapCarrierTests`). Foundation only.
///
/// Extraction is TOTAL and mirrors the spec's outcome order exactly: absent marker →
/// `.noBlock`; short body / bad magic → `.corrupt`; CRC mismatch → `.corrupt`;
/// future MAJOR → `.versionMismatch`; else the payload.
enum GenomeCarrier {
    /// The 24-byte header fields (magic "S4GN" precedes them on the wire).
    struct Header: Equatable {
        var major: UInt8
        var minor: UInt8
        var flags: UInt16
        var dof: UInt16
        var radix: UInt8
        var deviceIdHash: UInt32
        var btCompares: UInt32
    }

    /// Header + the Int32 Q16 coefficients in flattenHaar order.
    struct Payload: Equatable {
        var header: Header
        var coeffs: [Int]
    }

    /// The EXACTLY-11-byte block identifier `"SIXFOUR1" + "G10"`.
    static let identifier: [UInt8] = Array("SIXFOUR1G10".utf8)
    /// The body magic `"S4GN"`.
    static let magic: [UInt8] = Array("S4GN".utf8)
    /// Current MAJOR schema version.
    static let currentMajor: UInt8 = 1

    private static var marker: [UInt8] { CarrierWire.appExtIntroducer + [0x0B] + identifier }
    private static let headerLen = 24

    /// Serialize a payload into the full Application-Extension byte stream.
    static func encode(_ p: Payload) -> [UInt8] {
        var body = magic
        body += [p.header.major, p.header.minor]
        body += CarrierWire.u16LE(p.header.flags)
        body += CarrierWire.u16LE(p.header.dof)
        body += [p.header.radix, 0]
        body += CarrierWire.u32LE(p.header.deviceIdHash)
        body += CarrierWire.u32LE(p.header.btCompares)
        body += [0, 0, 0, 0]
        for c in p.coeffs { body += CarrierWire.i32LE(c) }
        return CarrierWire.wrapBody(body, identifier: identifier)
    }

    /// Probe a GIF byte stream for the S4GN block (never decodes LZW frames).
    static func extract(_ stream: [UInt8]) -> Result<Payload, CarrierError> {
        guard let at = CarrierWire.findMarker(stream, marker) else { return .failure(.noBlock) }
        let whole = CarrierWire.gatherSubBlocks(stream, from: at + marker.count)
        guard whole.count >= headerLen + 4 else { return .failure(.corrupt) }
        guard Array(whole[0..<4]) == magic else { return .failure(.corrupt) }
        let preLen = whole.count - 4
        let crcGot = CarrierWire.readU32LE(whole, at: preLen)
        guard crcGot == CarrierWire.crc32(Array(whole[0..<preLen])) else { return .failure(.corrupt) }
        let header = Header(
            major: whole[4], minor: whole[5],
            flags: CarrierWire.readU16LE(whole, at: 6),
            dof: CarrierWire.readU16LE(whole, at: 8),
            radix: whole[10],
            deviceIdHash: CarrierWire.readU32LE(whole, at: 12),
            btCompares: CarrierWire.readU32LE(whole, at: 16))
        guard header.major == currentMajor else { return .failure(.versionMismatch) }
        var coeffs: [Int] = []
        coeffs.reserveCapacity((preLen - headerLen) / 4)
        var i = headerLen
        while i + 4 <= preLen {
            coeffs.append(CarrierWire.readI32LE(whole, at: i))
            i += 4
        }
        return .success(Payload(header: header, coeffs: coeffs))
    }
}
