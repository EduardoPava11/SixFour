import Foundation
import simd
import os

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

// MARK: - Where the field came from (provenance, carried into the manifest)

/// Which probability function the AirDropped tensor actually holds. The two are semantically distinct
/// distributions, so the receiver must be told which one it got (recorded in the manifest's
/// `field_source`). Both are honest 64³-sourced fields; they pool different things.
enum V21FieldSource: String {
    /// The GPU per-frame histogram of the camera crop box, pooled over the 64-frame burst
    /// (`v21AccumulateHistKernel` -> `poolV21Counts`): the true fine-grid field (sub-pixel + temporal).
    case cameraBox = "camera_box"
    /// The index-cube histogram over the 64 frames (`fromCapture`): the temporal-only fallback used
    /// when the GPU field is unavailable (flag off, or the burst-histogram allocation failed).
    case temporalProxy = "temporal_proxy"
}

// MARK: - NumPy .npy encoder (zero-dependency, self-describing, one place to be byte-correct)

/// Encodes an `int32` array as a NumPy `.npy` v1.0 file: little-endian (`<i4`), C order, with the
/// 64-aligned ASCII header NumPy parses. `shape` is the Python tuple literal (e.g. `"(64, 64, 3, 256)"`).
/// Both the field tensor and the contestedness sidecar route through here so the byte format is defined
/// once. The Python side loads either with a single `numpy.load(path)`.
enum V21Npy {

    static func encode(_ values: [Int32], shape: String) -> Data {
        let dict = "{'descr': '<i4', 'fortran_order': False, 'shape': \(shape), }"
        // Pad the header so (magic+version+lenfield + header) is a multiple of 64, ending in '\n'.
        let preamble = 6 + 2 + 2
        let unpadded = preamble + dict.utf8.count + 1
        let pad = (64 - (unpadded % 64)) % 64
        let header = dict + String(repeating: " ", count: pad) + "\n"

        var data = Data()
        data.append(0x93)                                   // single byte 0x93, NOT UTF-8 U+0093
        data.append(contentsOf: Array("NUMPY".utf8))
        data.append(contentsOf: [0x01, 0x00])               // version 1.0
        let hlen = UInt16(header.utf8.count)
        data.append(UInt8(hlen & 0xff))                     // header length, little-endian uint16
        data.append(UInt8(hlen >> 8))
        data.append(contentsOf: Array(header.utf8))
        values.withUnsafeBytes { data.append(contentsOf: $0) }  // int32 LE on arm64
        return data
    }
}

/// The field tensor: `int32` counts, shape `[side, side, 3, nLevels]`, C order, little-endian. Axis
/// meaning `[y, x, channel(R,G,B), level]`. The energy face is `total - counts`, the mass face is
/// `counts / total`, matching `SixFour.Spec.V21Field`.
enum V21Tensor {
    static func npyData(_ field: V21FieldData) -> Data {
        V21Npy.encode(field.counts, shape: "(\(field.side), \(field.side), 3, \(field.nLevels))")
    }
}

// MARK: - The contestedness sidecar (mode margin: where the collapse is a near-tie)

/// The per-bin, per-channel **mode margin** = `peakCount - runnerUpCount` over the value levels. This is
/// the information the collapse throws away: a margin of 0 means two value levels tied for the mode, so
/// the shipped GIF byte at that bin is essentially arbitrary (a motion edge / occlusion boundary); a
/// large margin means a confident mode. Pure integer (byte-exact), so the device value matches the
/// trainer's `np.sort(field)[...,-1] - [...,-2]` exactly (the fidelity cross-check in `v21_ingest.py`).
enum V21Contested {

    /// `side·side·3` margins, `[y, x, channel]` order (the field tensor with the level axis collapsed).
    static func margins(_ f: V21FieldData) -> [Int32] {
        let p = f.pixelCount, n = f.nLevels
        var out = [Int32](repeating: 0, count: p * 3)
        guard f.isValid else { return out }
        for cell in 0 ..< p {
            for ch in 0 ..< 3 {
                let base = (cell * 3 + ch) * n
                // Track the top two counts in one pass; their gap is the margin. Ties for the peak
                // collapse to a 0 margin (top2 inherits the equal peak), which is exactly the point.
                var top1 = 0, top2 = 0
                for l in 0 ..< n {
                    let c = Int(f.counts[base + l])
                    if c >= top1 { top2 = top1; top1 = c }
                    else if c > top2 { top2 = c }
                }
                out[cell * 3 + ch] = Int32(top1 - top2)
            }
        }
        return out
    }

    static func npyData(_ f: V21FieldData) -> Data {
        V21Npy.encode(margins(f), shape: "(\(f.side), \(f.side), 3)")
    }
}

// MARK: - The V2.1 transport FLOW (the recovered time axis; mirrors SixFour.Spec.V21Transport)

/// A run-length pair `(value, length)` of a transport displacement map. A rigid drift is one run.
struct V21Run: Equatable, Sendable { let value: Int32; let length: Int32 }

/// The airdrop flow: a barycenter anchor plus, per frame, the RLE-compressed transport map carrying
/// the anchor to that frame's value histogram. Reconstructs every per-frame slice byte-exact
/// (`Spec.V21Transport.lawBarycenterFlowRecovers`), and the shipped GIF is the per-frame collapse of
/// those slices (`lawGifDerivesFromFlow`) — so the model's one visible surface is a projection of the
/// stored data. This is the full `[t × value]` joint the pooled field marginalises away.
struct V21Flow: Sendable {
    let side: Int
    let nLevels: Int
    let mass: Int
    let anchor: [Int32]        // side·side·3·nLevels — the barycenter histogram
    let maps: [[V21Run]]       // per frame: RLE of the p·3·mass rank displacement
}

/// The byte-exact flow codec. All integer, dependency-free; the transport/pushforward steps route
/// through the gated Zig kernels (`transportV21`/`pushforwardV21`), so device == Zig == Haskell.
enum V21FlowCodec {

    /// The sampled inverse-CDF of one count curve (`Spec.V21Transport.quantiles`): level `l` repeated
    /// `count(l)` times, ascending. Length = the curve's mass.
    static func quantiles(_ counts: ArraySlice<Int32>) -> [Int32] {
        var out: [Int32] = []
        // `enumerated()` restarts at 0, so `level` is the value level within this curve.
        for (level, c) in counts.enumerated() where c > 0 {
            out.append(contentsOf: repeatElement(Int32(level), count: Int(c)))
        }
        return out
    }

    /// The 1-D Wasserstein-2 barycenter (`Spec.V21Transport.barycenter`): per (bin, channel) curve, the
    /// per-rank MEAN of the frames' quantiles (truncating division), rebinned. The consensus anchor.
    /// Requires every frame's per-curve mass to match. Returns nil on a shape/mass violation.
    static func barycenter(perFrame: [[Int32]], side: Int, nLevels: Int) -> [Int32]? {
        let total = side * side * 3
        let frames = perFrame.count
        guard frames > 0, perFrame.allSatisfy({ $0.count == total * nLevels }) else { return nil }
        var out = [Int32](repeating: 0, count: total * nLevels)
        for ch in 0 ..< total {
            let base = ch * nLevels
            var qsum: [Int64] = []
            var mass = -1
            for f in perFrame {
                let q = quantiles(f[base ..< base + nLevels])
                if mass < 0 { mass = q.count; qsum = [Int64](repeating: 0, count: mass) }
                guard q.count == mass else { return nil }   // equal-mass precondition
                for k in 0 ..< mass { qsum[k] += Int64(q[k]) }
            }
            for k in 0 ..< mass {
                let lvl = Int(qsum[k] / Int64(frames))
                if lvl >= 0 && lvl < nLevels { out[base + lvl] += 1 }
            }
        }
        return out
    }

    /// Run-length encode a displacement (`Spec.V21Transport.rleEncode`).
    static func rleEncode(_ d: [Int32]) -> [V21Run] {
        var runs: [V21Run] = []
        var i = 0
        while i < d.count {
            let v = d[i]
            var n = 1
            while i + n < d.count && d[i + n] == v { n += 1 }
            runs.append(V21Run(value: v, length: Int32(n)))
            i += n
        }
        return runs
    }

    /// Run-length decode (`Spec.V21Transport.rleDecode`), the exact inverse of `rleEncode`.
    static func rleDecode(_ runs: [V21Run]) -> [Int32] {
        var out: [Int32] = []
        for r in runs { out.append(contentsOf: repeatElement(r.value, count: Int(r.length))) }
        return out
    }

    /// ENCODE a burst (per-frame count fields `[frames][side·side·3·nLevels]`) as a `V21Flow`: the
    /// barycenter anchor plus, per frame, `RLE(transport(anchor → frame))`. Streams frame-by-frame, so
    /// only one frame's displacement (`p·3·mass`) is live at a time. Returns nil on any shape/mass fault.
    static func encode(perFrame: [[Int32]], side: Int, nLevels: Int) -> V21Flow? {
        let p = side * side
        let total = p * 3
        guard !perFrame.isEmpty, perFrame.allSatisfy({ $0.count == total * nLevels }),
              let anchor = barycenter(perFrame: perFrame, side: side, nLevels: nLevels) else { return nil }
        let mass = Int(anchor[0 ..< nLevels].reduce(Int32(0), +))
        guard mass > 0 else { return nil }
        var maps: [[V21Run]] = []
        maps.reserveCapacity(perFrame.count)
        for frame in perFrame {
            guard let disp = SixFourNative.transportV21(src: anchor, dst: frame, p: p, nLevels: nLevels, mass: mass)
            else { return nil }
            maps.append(rleEncode(disp))
        }
        return V21Flow(side: side, nLevels: nLevels, mass: mass, anchor: anchor, maps: maps)
    }

    /// Reconstruct every per-frame slice from a flow (the trainer's parity path; `lawBarycenterFlowRecovers`).
    static func reconstruct(_ flow: V21Flow) -> [[Int32]]? {
        let p = flow.side * flow.side
        var slices: [[Int32]] = []
        slices.reserveCapacity(flow.maps.count)
        for runs in flow.maps {
            let disp = rleDecode(runs)
            guard let slice = SixFourNative.pushforwardV21(src: flow.anchor, disp: disp, p: p,
                                                           nLevels: flow.nLevels, mass: flow.mass)
            else { return nil }
            slices.append(slice)
        }
        return slices
    }

    /// The shipped GIF frames DERIVED FROM THE FLOW (`lawGifDerivesFromFlow`): per frame, the per-channel
    /// mode of the reconstructed slice (`collapseV21` of its energy). This is the ONE image the model
    /// sees — what is shown IS what the model takes as input. Returns per-frame `p·3` sRGB bytes.
    static func gifFrames(_ flow: V21Flow) -> [[UInt8]]? {
        guard let slices = reconstruct(flow) else { return nil }
        let p = flow.side * flow.side
        var frames: [[UInt8]] = []
        frames.reserveCapacity(slices.count)
        for slice in slices {
            guard let energy = SixFourNative.countsToEnergyV21(counts: slice, p: p, nLevels: flow.nLevels),
                  let rgb = SixFourNative.collapseV21(curves: energy, p: p, nLevels: flow.nLevels)
            else { return nil }
            frames.append(rgb)
        }
        return frames
    }
}

// MARK: - The bundle manifest (self-describing, hand-written JSON, zero-dependency)

/// A single JSON file that makes the AirDropped bundle self-describing: it records which field the tensor
/// holds (`field_source`), the dtype/shape/axis order of each artifact, the artifact filenames, and the
/// relationship between the GIF and the tensor (the GIF is the field's argmin-energy collapse). A trainer
/// ingesting a folder of these reads the manifest first and never has to guess.
enum V21Manifest {

    static func json(field f: V21FieldData, source: V21FieldSource, stem: String,
                     artifacts: [String: String], flow: V21Flow?) -> Data {
        func q(_ s: String) -> String { "\"\(s)\"" }
        let arts = ["gif", "field", "contested", "anchor", "maps"].compactMap { key -> String? in
            artifacts[key].map { "    \(q(key)): \(q($0))" }
        }.joined(separator: ",\n")
        // With a flow, the bundle is a superset (schema /2) and the GIF is TRUTHFULLY the flow collapse.
        let schema = flow == nil ? "sixfour.v21.capture/1" : "sixfour.v21.capture/2"
        let collapse = flow == nil
            ? "the shipped GIF is argmin-energy = argmax-count per bin and channel of the field (s4_v21_collapse)"
            : "the shipped .gif is a per-frame k-means PREVIEW; the model's GIF is DERIVED FROM THE FLOW as the per-channel mode (collapse) of pushforward(anchor, map_t) per frame (SixFour.Spec.V21Transport.gifFromFlow), and the field is the pooled sum of those reconstructed frames"
        var flowBlock = ""
        if let fl = flow {
            flowBlock = """
            ,
              "flow": {
                "anchor_dtype": "<i4",
                "anchor_shape": [\(fl.side), \(fl.side), 3, \(fl.nLevels)],
                "frames": \(fl.maps.count),
                "mass": \(fl.mass),
                "maps_format": "little-endian i32: [frames][mass], then per frame [nRuns] then nRuns*(value,length); RLE of the p*3*mass rank displacement anchor->frame",
                "anchor": "frame 0's histogram field (the barycenter anchor is a later quality refinement)",
                "meaning": "the recovered TIME AXIS: frame-0 anchor + per-frame monotone transport maps T=Finv.F; pushforward(anchor, map_t) reconstructs frame t's [y,x,3,level] histogram, and the field is their pooled sum (SixFour.Spec.V21Transport)"
              }
            """
        }
        let json = """
        {
          "schema": "\(schema)",
          "stem": \(q(stem)),
          "side": \(f.side),
          "n_levels": \(f.nLevels),
          "field_source": \(q(source.rawValue)),
          "artifacts": {
        \(arts)
          },
          "field": {
            "dtype": "<i4",
            "shape": [\(f.side), \(f.side), 3, \(f.nLevels)],
            "axes": ["y", "x", "channel", "level"],
            "meaning": "per-bin per-channel count histogram over value levels, pooled over the burst; mass = counts / total, energy = total - counts"
          },
          "contested": {
            "dtype": "<i4",
            "shape": [\(f.side), \(f.side), 3],
            "axes": ["y", "x", "channel"],
            "meaning": "mode margin = peak count - runner-up count over levels; 0 = the collapse is a near-tie (the GIF byte is arbitrary here), large = a confident mode"
          },
          "collapse": "\(collapse)"\(flowBlock)
        }
        """
        return Data(json.utf8)
    }
}

// MARK: - The transport flow serialization (anchor .npy + RLE maps binary)

/// Serializes a `V21Flow` for the AirDrop bundle: the anchor as a standard `.npy`, the RLE maps as a
/// compact little-endian `int32` binary the trainer parses.
enum V21FlowExport {

    /// The barycenter anchor as a standard `.npy` (`int32 [side, side, 3, nLevels]`), same encoder the
    /// field uses so it loads with a single `numpy.load`.
    static func anchorData(_ flow: V21Flow) -> Data {
        V21Npy.encode(flow.anchor, shape: "(\(flow.side), \(flow.side), 3, \(flow.nLevels))")
    }

    /// The RLE maps as little-endian `int32`: `[frames][mass]`, then per frame `[nRuns]` followed by
    /// `nRuns × (value, length)`. `rleDecode` of a frame's runs is its `p·3·mass` rank displacement.
    static func mapsData(_ flow: V21Flow) -> Data {
        var d = Data()
        func put(_ v: Int32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        put(Int32(flow.maps.count)); put(Int32(flow.mass))
        for runs in flow.maps {
            put(Int32(runs.count))
            for r in runs { put(r.value); put(r.length) }
        }
        return d
    }
}

// MARK: - The AirDrop bundle

/// Assembles the share items for AirDrop into one self-describing bundle that shares a filename stem, so
/// the GIF, the field tensor, the contestedness sidecar, and the manifest group together in the
/// receiver's folder and never overwrite a previous capture:
///
///   * `<stem>.gif`                          the collapse (the shipped GIF);
///   * `<stem>_field_SxSx3xN.npy`            the probability functions (int32 counts);
///   * `<stem>_contested_SxSx3.npy`          the mode-margin sidecar;
///   * `<stem>_manifest.json`                describes all of the above, incl. `field_source`.
enum V21Export {

    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "v21export")

    /// `[gifURL?, fieldURL, contestedURL, manifestURL]`, suitable for `ActivityView(items:)`. Each
    /// artifact is written independently and best-effort: a failed write drops only that one item, and
    /// the manifest (written last) lists exactly the artifacts that actually shipped.
    static func shareItems(field: V21FieldData, source: V21FieldSource, gifURL: URL?, flow: V21Flow?) -> [Any] {
        let stem = "sixfour_\(UUID().uuidString.prefix(8).lowercased())"
        let tmp = FileManager.default.temporaryDirectory
        var items: [Any] = []
        var artifacts: [String: String] = [:]

        // The GIF (the collapse): copy to the shared stem so the bundle groups. On a copy failure, fall
        // back to sharing the original URL (still correct, just not stem-named).
        if let gif = gifURL {
            let name = "\(stem).gif"
            let dst = tmp.appendingPathComponent(name)
            do {
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: gif, to: dst)
                items.append(dst); artifacts["gif"] = name
            } catch {
                items.append(gif); artifacts["gif"] = gif.lastPathComponent
            }
        }

        // The field tensor (the probability functions).
        let fieldName = "\(stem)_field_\(field.side)x\(field.side)x3x\(field.nLevels).npy"
        if let url = write(V21Tensor.npyData(field), to: tmp.appendingPathComponent(fieldName)) {
            items.append(url); artifacts["field"] = fieldName
        }

        // The contestedness sidecar (mode margin).
        let contName = "\(stem)_contested_\(field.side)x\(field.side)x3.npy"
        if let url = write(V21Contested.npyData(field), to: tmp.appendingPathComponent(contName)) {
            items.append(url); artifacts["contested"] = contName
        }

        // The transport FLOW (the recovered time axis): barycenter anchor .npy + RLE maps binary. This
        // is the artifact that keeps a MOVING capture trainable; the field/GIF derive from it.
        if let fl = flow {
            let anchorName = "\(stem)_anchor_\(fl.side)x\(fl.side)x3x\(fl.nLevels).npy"
            if let url = write(V21FlowExport.anchorData(fl), to: tmp.appendingPathComponent(anchorName)) {
                items.append(url); artifacts["anchor"] = anchorName
            }
            let mapsName = "\(stem)_maps.bin"
            let mapsData = V21FlowExport.mapsData(fl)
            if let url = write(mapsData, to: tmp.appendingPathComponent(mapsName)) {
                items.append(url); artifacts["maps"] = mapsName
            }
            logger.log("export: stem=\(stem) FLOW shipped — anchor + maps.bin (\(mapsData.count/1024) KiB, \(fl.maps.count) frames, mass \(fl.mass))")
        } else {
            logger.log("export: stem=\(stem) NO flow (nil) — shipping pooled field only")
        }

        // The manifest LAST: it names exactly what shipped above.
        let manName = "\(stem)_manifest.json"
        let manData = V21Manifest.json(field: field, source: source, stem: stem, artifacts: artifacts, flow: flow)
        if let url = write(manData, to: tmp.appendingPathComponent(manName)) {
            items.append(url)
        }
        return items
    }

    /// Write `data` to `url`, returning the URL on success and `nil` (silently) on failure.
    private static func write(_ data: Data, to url: URL) -> URL? {
        do { try data.write(to: url); return url } catch { return nil }
    }
}
