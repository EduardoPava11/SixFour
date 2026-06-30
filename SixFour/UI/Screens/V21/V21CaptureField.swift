import Foundation
import simd

/// Build the V2.1 probability field from a committed capture, and export it (with the GIF) as tensors
/// the user can AirDrop.
///
/// The shipped GIF is the COLLAPSE (one byte per bin, the mode). The thing the model trains on is the
/// FIELD: per 64×64 spatial bin, a probability function per colour channel. We have the data to build
/// that field already, the committed 64-frame burst: each spatial bin saw 64 temporal samples (one per
/// frame, read through that frame's palette), so its per-channel histogram over the value levels IS its
/// probability function. That is the honest 64³-sourced field, no synthetic stand-in.
///
/// Two artifacts leave the phone:
///   * the GIF (the collapse), already on disk at `surface.gifURL`;
///   * the field tensor as a NumPy `.npy` (`int32` counts, shape `[y, x, 3, level]`), self-describing
///     so it loads with a single `numpy.load` on the training side.

// MARK: - Capture -> probability field

extension V21FieldData {

    /// Build the per-bin temporal probability field from a committed burst. For each spatial bin and
    /// channel, count the value seen at that bin across all frames (the value = the frame palette's
    /// colour at the bin's index). The result is layout-identical to what the V2.1 kernels consume:
    /// `((cell·3 + channel)·nLevels + level)`, `cell = y·side + x`. `nLevels == 256` keeps the full
    /// byte alphabet; a smaller `nLevels` rescales the 0..255 value. Returns nil on a malformed cube.
    static func fromCapture(indexCube: [UInt8],
                            palettesPerFrame: [[SIMD3<UInt8>]],
                            side: Int,
                            nLevels: Int = 256) -> V21FieldData? {
        let frames = palettesPerFrame.count
        let p = side * side
        guard side > 0, nLevels > 0, frames > 0, indexCube.count >= frames * p else { return nil }

        var counts = [Int32](repeating: 0, count: p * 3 * nLevels)
        let hi = nLevels - 1
        for t in 0 ..< frames {
            let pal = palettesPerFrame[t]
            let fbase = t * p
            for cell in 0 ..< p {
                let idx = Int(indexCube[fbase + cell])
                guard idx >= 0, idx < pal.count else { continue }
                let rgb = pal[idx]
                let chans = (Int(rgb.x), Int(rgb.y), Int(rgb.z))
                for ch in 0 ..< 3 {
                    let v = ch == 0 ? chans.0 : (ch == 1 ? chans.1 : chans.2)
                    let level = nLevels == 256 ? v : min(hi, v * hi / 255)
                    counts[(cell * 3 + ch) * nLevels + level] += 1
                }
            }
        }
        return V21FieldData(side: side, nLevels: nLevels, counts: counts)
    }
}

// MARK: - NumPy .npy tensor writer (zero-dependency, self-describing)

/// Writes a `V21FieldData` count tensor as a NumPy `.npy` v1.0 file: an `int32` array of shape
/// `[side, side, 3, nLevels]` in C order, little-endian. Axis meaning: `[y, x, channel(R,G,B), level]`.
/// The Python side loads it with `numpy.load(path)`; the energy face is `total - counts`, the mass face
/// is `counts / total`, matching `SixFour.Spec.V21Field`.
enum V21Tensor {

    static func npyData(_ field: V21FieldData) -> Data {
        let shape = "(\(field.side), \(field.side), 3, \(field.nLevels))"
        let dict = "{'descr': '<i4', 'fortran_order': False, 'shape': \(shape), }"
        // Pad the header so (magic+version+lenfield + header) is a multiple of 64, ending in '\n'.
        let preamble = 6 + 2 + 2
        let unpadded = preamble + dict.utf8.count + 1
        let pad = (64 - (unpadded % 64)) % 64
        let header = dict + String(repeating: " ", count: pad) + "\n"

        var data = Data()
        data.append(0x93)
        data.append(contentsOf: Array("NUMPY".utf8))
        data.append(contentsOf: [0x01, 0x00])               // version 1.0
        let hlen = UInt16(header.utf8.count)
        data.append(UInt8(hlen & 0xff))                     // header length, little-endian uint16
        data.append(UInt8(hlen >> 8))
        data.append(contentsOf: Array(header.utf8))
        field.counts.withUnsafeBytes { data.append(contentsOf: $0) }  // int32 LE on arm64
        return data
    }
}

// MARK: - The AirDrop bundle

/// Assembles the share items for AirDrop: the GIF (the collapse) and the field tensor (the probability
/// functions). The tensor is written to a temp `.npy`; the GIF is already on disk.
enum V21Export {

    /// `[gifURL?, tensorURL]`, suitable for `ActivityView(items:)`. The tensor filename carries the
    /// shape so it is self-describing in the receiver's file list.
    static func shareItems(field: V21FieldData, gifURL: URL?) -> [Any] {
        var items: [Any] = []
        if let gif = gifURL { items.append(gif) }
        let name = "sixfour_field_\(field.side)x\(field.side)x3x\(field.nLevels).npy"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try V21Tensor.npyData(field).write(to: url)
            items.append(url)
        } catch {
            // A failed tensor write still lets the GIF share; the caller surfaces an empty-tensor case.
        }
        return items
    }
}
