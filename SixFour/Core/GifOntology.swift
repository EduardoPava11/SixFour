import Foundation
import simd

/// THE ONTOLOGY — the GIF's own concepts as the app's core value types
/// (docs/REBUILD-2026-07-10-PLAN.md §2b; Stage 1, approved 2026-07-11).
///
/// Daniel's brief: "GIFs are self-contained stop motion. The app needs to take
/// the concepts like color palette and index mapping and abstract it." The
/// 2026-07-11 ontology audit found that abstraction stated exactly once — in
/// the spec (`Spec.Palette` / `Spec.ModelIO` / `Spec.WeaveOrder` /
/// `Spec.Gif89aDecode`) — while the app restated color in 7+ shapes, indices
/// in 3 widths, and time in 4 encodings. These four types are the PROMOTION of
/// the spec's ontology to the app surface; every other representation is a
/// view of them, produced by the same golden-gated kernels as before.
///
/// The types are deliberately PURE VALUES over the bit-exact integer substrate
/// (OKLab Q16 = `SIMD3<Int32>`, indices = `UInt8`, time = `WeaveRung`): no
/// Metal, no AVFoundation, no floats. Unit 1 is additive — nothing in the live
/// path constructs these yet; Unit 2 swaps the renderer/surface onto them
/// behind a byte-parity gate.
///
/// SELF-CONTAINED STOP MOTION, as laws (gated in GifOntologyTests):
///  * delay is a THEOREM of the rung (`s4_ladder_delay_cs`), never stored;
///  * the sRGB8 palette wire round-trips (`s4_palette_oklab_to_srgb8` ∘
///    `s4_srgb8_to_oklab_q16` = id on the sRGB8-canonical subset — the
///    capture-format contract's "sRGB8-canonical" rule as a type invariant);
///  * `Loop(gifBytes: loop.gifBytes()) == loop` — the artifact IS the value
///    (`s4_gif_assemble` / `s4_gif_decode`, the Spec.Gif89aDecode round-trip).

// MARK: - Palette (the VALUE space)

/// THE COLOR TABLE: K OKLab-Q16 leaves in slot order (slot order == GIF color
/// table order). Mirrors `Spec.Palette`; promoted from `CollapsedPalette`'s
/// leaves. The sRGB8 GCT/LCT bytes are a VIEW (`srgb8()`), not a second
/// representation — both directions run through the golden color kernels.
struct Palette: Equatable, Hashable, Sendable {
    /// OKLab Q16 leaves in slot order.
    var leavesQ16: [SIMD3<Int32>]

    /// The palette size K (the GIF color-table entry count).
    var k: Int { leavesQ16.count }

    init(leavesQ16: [SIMD3<Int32>]) {
        self.leavesQ16 = leavesQ16
    }

    /// Construct from the sRGB8 wire view (k packed RGB triples — a 768-byte
    /// GCT at k=256), CANONICALIZED. The inverse/realize kernel pair
    /// (`s4_srgb8_to_oklab_q16` / `s4_palette_oklab_to_srgb8`) is idempotent
    /// but not the identity on every raw byte triple — a few edge codes shift
    /// once through the OKLab round trip, then stabilize. A `Palette`
    /// therefore always holds a FIXED POINT of the pair: `srgb8()` is exact,
    /// and GIF encode→decode is value-exact (the round-trip law). Production
    /// palettes arrive already stabilized (every GCT/LCT byte in the app is
    /// kernel-realized); canonicalization only ever moves hand-fed bytes.
    init?(srgb8: [UInt8]) {
        guard !srgb8.isEmpty, srgb8.count % 3 == 0 else { return nil }
        var bytes = srgb8
        for _ in 0..<4 {
            guard let q16 = Palette.inverse(bytes),
                  let realized = Palette.realize(q16) else { return nil }
            if realized == bytes {
                leavesQ16 = q16
                return
            }
            bytes = realized
        }
        return nil // the pair failed to stabilize — should be unreachable
    }

    /// The sRGB8 wire VIEW (k packed RGB triples) via the golden kernel
    /// `s4_palette_oklab_to_srgb8` — the same realization every GCT/LCT byte
    /// in the app already goes through. Exact (returns the canonical bytes)
    /// whenever the leaves are canonical, which `init?(srgb8:)` guarantees.
    func srgb8() -> [UInt8]? {
        Palette.realize(leavesQ16)
    }

    /// k sRGB8 triples → OKLab-Q16 leaves (`s4_srgb8_to_oklab_q16`).
    private static func inverse(_ rgb: [UInt8]) -> [SIMD3<Int32>]? {
        let count = rgb.count / 3
        var flat = [Int32](repeating: 0, count: count * 3)
        let rc = rgb.withUnsafeBufferPointer { r in
            flat.withUnsafeMutableBufferPointer { out in
                s4_srgb8_to_oklab_q16(r.baseAddress, Int32(count), out.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { return nil }
        return (0..<count).map {
            SIMD3<Int32>(flat[$0 * 3], flat[$0 * 3 + 1], flat[$0 * 3 + 2])
        }
    }

    /// OKLab-Q16 leaves → k sRGB8 triples (`s4_palette_oklab_to_srgb8`).
    /// SIMD3<Int32> strides at 16 bytes, so flatten explicitly rather than
    /// reinterpreting memory.
    private static func realize(_ leaves: [SIMD3<Int32>]) -> [UInt8]? {
        guard !leaves.isEmpty else { return nil }
        let flat: [Int32] = leaves.flatMap { [$0.x, $0.y, $0.z] }
        var rgb = [UInt8](repeating: 0, count: leaves.count * 3)
        let rc = flat.withUnsafeBufferPointer { c in
            rgb.withUnsafeMutableBufferPointer { out in
                s4_palette_oklab_to_srgb8(c.baseAddress, Int32(leaves.count), out.baseAddress, nil, 0)
            }
        }
        return rc == S4_RC_OK ? rgb : nil
    }
}

// MARK: - IndexPlane (the CONTENT)

/// THE INDEX MAP: side² palette indices, row-major, kernel-native `UInt8`
/// (the one width — the `[UInt16]`/`[Int]` shapes retire with Unit 2).
/// Mirrors `Spec.Gif89aDecode.IndexMap`.
struct IndexPlane: Equatable, Hashable, Sendable {
    /// The square side in pixels.
    let side: Int
    /// side² indices into a `Palette`, row-major.
    var indices: [UInt8]

    init?(side: Int, indices: [UInt8]) {
        guard side > 0, indices.count == side * side else { return nil }
        self.side = side
        self.indices = indices
    }
}

// MARK: - WeaveRung (TIME)

/// THE TIME UNIT (mirrors `Spec.WeaveOrder.WeaveRung`): which rung of the
/// isotropic ladder a frame belongs to. The GCE delay is a THEOREM of the
/// rung (`s4_ladder_delay_cs`: 64→5 cs, 32→10, 16→20 — the GIF89a time law),
/// so it is derived here and stored nowhere.
enum WeaveRung: UInt8, Equatable, Hashable, Sendable, CaseIterable {
    case w64 = 0
    case w32 = 1
    case w16 = 2

    /// The rung's native content side.
    var side: Int {
        switch self {
        case .w64: return 64
        case .w32: return 32
        case .w16: return 16
        }
    }

    /// The rung whose native side is `side`, if it is a ladder side.
    init?(side: Int) {
        switch side {
        case 64: self = .w64
        case 32: self = .w32
        case 16: self = .w16
        default: return nil
        }
    }

    /// THE TIME LAW: the GCE delay in integer centiseconds, derived from the
    /// side by the golden kernel — never a stored constant.
    var delayCs: UInt16 {
        let cs = s4_ladder_delay_cs(Int32(side))
        precondition(cs > 0, "ladder delay law refused side \(side)")
        return UInt16(cs)
    }
}

// MARK: - Cel (one stop-motion frame)

/// ONE FRAME of the stop motion: an index plane on a time rung. The plane's
/// side may be an integer REPLICATION of the rung's side (the 64→256 export,
/// `replicate2D` — replication adds pixels, never information or time), so
/// the delay always comes from the RUNG, not the raster.
struct Cel: Equatable, Hashable, Sendable {
    var plane: IndexPlane
    var rung: WeaveRung

    init?(plane: IndexPlane, rung: WeaveRung) {
        guard plane.side % rung.side == 0 else { return nil }
        self.plane = plane
        self.rung = rung
    }

    /// The frame's GCE delay — the rung's theorem, unconditionally.
    var delayCs: UInt16 { rung.delayCs }
}

// MARK: - Loop (the self-contained stop motion)

/// THE IN-MEMORY GIF: cels + per-frame palettes. Promoted from
/// `SixFourModelOutput` + `ModelRender` — per-frame palette is the VALUE,
/// index plane is the CONTENT, and the render is nothing but
/// `palette[index]` (mirrors `Spec.ModelIO.renderFrame`). The GIF89a file is
/// ONE codec of this value (`gifBytes()` / `init(gifBytes:)`); `.s4cr` stays
/// the pre-collapse measurement sidecar. A model that "makes the GIF better"
/// is exactly a better `record → Loop` function.
struct Loop: Equatable, Hashable, Sendable {
    /// The stop-motion frames, in play order.
    var cels: [Cel]
    /// Per-frame palettes (MVP1 is per-frame; a global palette is the special
    /// case of all entries equal). Count == cels.count.
    var palettes: [Palette]

    init?(cels: [Cel], palettes: [Palette]) {
        guard !cels.isEmpty, cels.count == palettes.count else { return nil }
        self.cels = cels
        self.palettes = palettes
    }

    var frameCount: Int { cels.count }

    /// THE RENDER: `palette[index]`, frame `t` realized to OKLab-Q16 pixels.
    /// One line, because the ontology is the render — anything more is a view.
    func renderFrameQ16(_ t: Int) -> [SIMD3<Int32>]? {
        guard cels.indices.contains(t) else { return nil }
        let leaves = palettes[t].leavesQ16
        guard let maxIndex = cels[t].plane.indices.max(), Int(maxIndex) < leaves.count
        else { return nil }
        return cels[t].plane.indices.map { leaves[Int($0)] }
    }

    /// THE EXPORT VIEW (the capture-format contract, `replicate2D ≠ upscale256`):
    /// every cel's plane replicated `factor`× per axis in the INDEX domain via
    /// the generated contract (`SixFourExport.replicate`, whose exact left
    /// inverse is `decimate`). Palettes and TIME are untouched — replication
    /// adds pixels, never information. The wire loop whose `gifBytes()` is the
    /// shipped 256-side file.
    func replicated(by factor: Int) -> Loop? {
        guard factor >= 1 else { return nil }
        if factor == 1 { return self }
        var wireCels = [Cel]()
        wireCels.reserveCapacity(cels.count)
        for cel in cels {
            let big = SixFourExport.replicate(cel.plane.indices, side: cel.plane.side, factor: factor)
            guard let plane = IndexPlane(side: cel.plane.side * factor, indices: big),
                  let wireCel = Cel(plane: plane, rung: cel.rung) else { return nil }
            wireCels.append(wireCel)
        }
        return Loop(cels: wireCels, palettes: palettes)
    }

    /// THE IMPORT VIEW (Spec.CaptureFormat's other half — promoted by the
    /// 2026-07-11 link ledger, wave 1): decimate every cel's plane by `factor`
    /// via the generated contract (`SixFourCaptureFormat.decimate`, the exact
    /// left inverse of `replicated(by:)` on its range). Palettes and TIME
    /// untouched, mirroring the export view.
    func decimated(by factor: Int) -> Loop? {
        guard factor >= 1 else { return nil }
        if factor == 1 { return self }
        var smallCels = [Cel]()
        smallCels.reserveCapacity(cels.count)
        for cel in cels {
            guard cel.plane.side % factor == 0 else { return nil }
            let small = SixFourCaptureFormat.decimate(
                cel.plane.indices, bigSide: cel.plane.side, factor: factor)
            guard let plane = IndexPlane(side: cel.plane.side / factor, indices: small),
                  let smallCel = Cel(plane: plane, rung: cel.rung) else { return nil }
            smallCels.append(smallCel)
        }
        return Loop(cels: smallCels, palettes: palettes)
    }

    /// THE INGEST — self-containment's missing direction closed: shipped wire
    /// bytes (the 256-side replicated export) back to the CANONICAL
    /// capture-side Loop. Decode, then undo the wire replication when the
    /// raster is the wire side; native ladder-side GIFs pass through
    /// unchanged. This is what re-editing and training on an already-exported
    /// GIF stand on: `ingest(loop.replicated.gifBytes()) == loop`.
    static func ingest(wireGif: Data) -> Loop? {
        guard let wire = Loop(gifBytes: wireGif),
              let side = wire.cels.first?.plane.side else { return nil }
        if side == SixFourCaptureFormat.wireSide {
            return wire.decimated(by: SixFourCaptureFormat.upscaleFactor)
        }
        return wire
    }

    /// UI VIEW: the per-frame palettes as sRGB8 triples — the shape the
    /// observable surface paints with (`σ.palettesPerFrame`). Same realization
    /// kernel as the wire, so display and file can never disagree.
    func srgb8Palettes() -> [[SIMD3<UInt8>]]? {
        var out = [[SIMD3<UInt8>]]()
        out.reserveCapacity(palettes.count)
        for palette in palettes {
            guard let rgb = palette.srgb8() else { return nil }
            out.append((0..<palette.k).map {
                SIMD3(rgb[$0 * 3], rgb[$0 * 3 + 1], rgb[$0 * 3 + 2])
            })
        }
        return out
    }

    /// SELF-CONTAINMENT, encode half: the GIF89a bytes, via the same golden
    /// assembler the shipped path uses (`SixFourNative.gifAssemble` →
    /// `s4_gif_assemble`). Requires the uniformity GIF89a itself requires
    /// (one side, one K, one delay ⇒ one rung); returns nil otherwise —
    /// refusal, never silent coercion.
    func gifBytes(comment: String? = nil) -> Data? {
        guard let first = cels.first else { return nil }
        let side = first.plane.side
        let rung = first.rung
        let k = palettes[0].k
        guard cels.allSatisfy({ $0.plane.side == side && $0.rung == rung }),
              palettes.allSatisfy({ $0.k == k }),
              // THE ≤K BRAND at the wire (`Spec.SuperResPalette`, promoted by
              // the 2026-07-11 link ledger): invented detail is free only as
              // INDEX detail inside each frame's ≤256 table — never a 257th
              // colour. GIF89a physically caps the table; refuse, never clamp.
              k <= 256
        else { return nil }
        var indices = [UInt8]()
        indices.reserveCapacity(frameCount * side * side)
        for cel in cels { indices.append(contentsOf: cel.plane.indices) }
        var palettesRGB = [UInt8]()
        palettesRGB.reserveCapacity(frameCount * k * 3)
        for palette in palettes {
            guard let rgb = palette.srgb8() else { return nil }
            palettesRGB.append(contentsOf: rgb)
        }
        return SixFourNative.gifAssemble(
            indices: indices, palettesRGB: palettesRGB,
            frameCount: frameCount, side: side, k: k,
            delayCs: rung.delayCs, comment: comment)
    }

    /// SELF-CONTAINMENT, decode half: parse GIF89a bytes back into the value
    /// (`s4_gif_decode`, the golden inverse of the assembler). `rung` names
    /// the time rung when the raster side is a replication (e.g. the 256-side
    /// export); for native ladder sides it is inferred. Palettes come back
    /// sRGB8-canonical, so `decode(encode(loop)) == loop` for loops whose
    /// palettes are sRGB8-canonical — the round-trip law the tests gate.
    init?(gifBytes: Data, rung: WeaveRung? = nil) {
        let bytes = [UInt8](gifBytes)
        var frameCount: Int32 = 0
        var side: Int32 = 0
        var k: Int32 = 0
        // Probe pass sizes the buffers; decode pass fills them.
        var rc = bytes.withUnsafeBufferPointer { gif in
            s4_gif_decode(gif.baseAddress, bytes.count, nil, nil,
                          &frameCount, &side, &k, nil, 0)
        }
        guard rc == S4_RC_OK, frameCount > 0, side > 0, k > 0 else { return nil }
        var indices = [UInt8](repeating: 0, count: Int(frameCount) * Int(side) * Int(side))
        var palettesRGB = [UInt8](repeating: 0, count: Int(frameCount) * Int(k) * 3)
        let scratchBytes = s4_gif_decode_scratch_bytes(bytes.count)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: max(scratchBytes, 1), alignment: 16)
        defer { scratch.deallocate() }
        rc = bytes.withUnsafeBufferPointer { gif in
            indices.withUnsafeMutableBufferPointer { idx in
                palettesRGB.withUnsafeMutableBufferPointer { pal in
                    s4_gif_decode(gif.baseAddress, bytes.count,
                                  idx.baseAddress, pal.baseAddress,
                                  &frameCount, &side, &k, scratch, scratchBytes)
                }
            }
        }
        guard rc == S4_RC_OK else { return nil }
        let resolvedRung = rung ?? WeaveRung(side: Int(side)) ?? .w64
        let pixelsPerFrame = Int(side) * Int(side)
        let bytesPerPalette = Int(k) * 3
        var cels = [Cel]()
        var palettes = [Palette]()
        for t in 0..<Int(frameCount) {
            let frame = Array(indices[t * pixelsPerFrame ..< (t + 1) * pixelsPerFrame])
            guard let plane = IndexPlane(side: Int(side), indices: frame),
                  let cel = Cel(plane: plane, rung: resolvedRung),
                  let palette = Palette(srgb8: Array(
                    palettesRGB[t * bytesPerPalette ..< (t + 1) * bytesPerPalette]))
            else { return nil }
            cels.append(cel)
            palettes.append(palette)
        }
        self.init(cels: cels, palettes: palettes)
    }
}
