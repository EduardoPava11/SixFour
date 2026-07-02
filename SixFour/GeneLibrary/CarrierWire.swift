import Foundation

/// Shared GIF89a Application-Extension wire helpers for the two gene carriers —
/// the S4GN look-genome block (`GenomeCarrier`) and the S4GX swap block
/// (`SwapCarrier`). Hand-written Tier-2 port of the framing half of
/// `SixFour.Spec.GenomeCarrier` / `SixFour.Spec.SwapCarrier`, byte-exact against
/// the generated goldens (`GenomeCarrierGolden` / `SwapCarrierGolden`,
/// gated in `SwapCarrierTests`). Foundation only.

/// Total-and-distinct extraction outcomes, mirroring the spec's `CarrierError`:
/// `noBlock` (absent — a plain GIF, or a transcode dropped the block) is distinct
/// from `corrupt` (present but bad magic/CRC/structure) and `versionMismatch`
/// (a future MAJOR; never a partial parse).
enum CarrierError: Error, Equatable {
    case noBlock
    case corrupt
    case versionMismatch
}

enum CarrierWire {
    /// The `[0x21, 0xFF]` Application-Extension introducer.
    static let appExtIntroducer: [UInt8] = [0x21, 0xFF]

    /// Standard CRC32 (ISO-HDLC, polynomial 0xEDB88320), table-free — mirrors the
    /// spec's `crc32` bit-for-bit (one definition per language, shared by both blocks).
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return ~crc
    }

    /// Split a body into ≤255-byte GIF data sub-blocks, each prefixed by its length byte.
    static func subBlockify(_ body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(body.count + body.count / 255 + 1)
        var i = 0
        while i < body.count {
            let n = min(255, body.count - i)
            out.append(UInt8(n))
            out.append(contentsOf: body[i ..< i + n])
            i += n
        }
        return out
    }

    /// Concatenate data sub-blocks until the 0x00 terminator — the inverse of `subBlockify`.
    static func gatherSubBlocks(_ stream: [UInt8], from start: Int) -> [UInt8] {
        var out: [UInt8] = []
        var i = start
        while i < stream.count {
            let n = Int(stream[i])
            if n == 0 { break }
            let end = min(i + 1 + n, stream.count)
            out.append(contentsOf: stream[(i + 1) ..< end])
            i += 1 + n
        }
        return out
    }

    /// The index of the first occurrence of `marker` in `stream`, or nil.
    static func findMarker(_ stream: [UInt8], _ marker: [UInt8]) -> Int? {
        guard !marker.isEmpty, stream.count >= marker.count else { return nil }
        for i in 0 ... (stream.count - marker.count) {
            if Array(stream[i ..< i + marker.count]) == marker { return i }
        }
        return nil
    }

    /// Wrap a CRC-footed body in the Application-Extension framing:
    /// introducer + 0x0B + the 11-byte identifier + sub-blocks(body ‖ crc32) + 0x00.
    static func wrapBody(_ body: [UInt8], identifier: [UInt8]) -> [UInt8] {
        let crc = crc32(body)
        let footer: [UInt8] = u32LE(crc)
        return appExtIntroducer + [0x0B] + identifier + subBlockify(body + footer) + [0x00]
    }

    // MARK: little-endian helpers (Int32-width two's complement, matching the spec)

    static func i32LE(_ v: Int) -> [UInt8] {
        let w = UInt32(bitPattern: Int32(truncatingIfNeeded: v))
        return u32LE(w)
    }

    static func u32LE(_ w: UInt32) -> [UInt8] {
        [UInt8(w & 0xFF), UInt8((w >> 8) & 0xFF), UInt8((w >> 16) & 0xFF), UInt8((w >> 24) & 0xFF)]
    }

    static func u16LE(_ w: UInt16) -> [UInt8] {
        [UInt8(w & 0xFF), UInt8(w >> 8)]
    }

    /// Sign-extending read of 4 LE bytes (total: missing bytes read as 0).
    static func readI32LE(_ bytes: [UInt8], at i: Int) -> Int {
        Int(Int32(bitPattern: readU32LE(bytes, at: i)))
    }

    static func readU32LE(_ bytes: [UInt8], at i: Int) -> UInt32 {
        func b(_ k: Int) -> UInt32 { k < bytes.count ? UInt32(bytes[k]) : 0 }
        return b(i) | (b(i + 1) << 8) | (b(i + 2) << 16) | (b(i + 3) << 24)
    }

    static func readU16LE(_ bytes: [UInt8], at i: Int) -> UInt16 {
        func b(_ k: Int) -> UInt16 { k < bytes.count ? UInt16(bytes[k]) : 0 }
        return b(i) | (b(i + 1) << 8)
    }
}
