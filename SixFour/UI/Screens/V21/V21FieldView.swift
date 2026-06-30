import SwiftUI
import UIKit
import simd

/// The **V2.1 pre-collapse field** surface, form-follows-function: the data structure
/// IS the design, so this view shows nothing decorative, only the three things the
/// V2.1 capture actually is.
///
/// V2.1 captures, per 64x64 bin, a PROBABILITY CURVE per colour channel (the histogram
/// of that bin's camera box). The shipped GIF is the COLLAPSE (the mode of each curve,
/// argmin energy via `s4_v21_collapse`); the model trains on the full curves. So three
/// reads sit on one field:
///   1. THE COLLAPSE (what ships): each bin painted its mode colour.
///   2. THE UNCERTAINTY: each bin shaded by its curve entropy. A spread (high-entropy)
///      box reads bright, a sharp (flat) box reads dark, so you SEE which bins the
///      camera was unsure about.
///   3. THE DISTRIBUTION: tap a bin to read its three per-channel curves, with the
///      collapsed mode level marked on each.
///
/// Tier-2 pure (SwiftUI + UIKit + simd, zero third-party). Additive and gated: the whole
/// surface is behind `Feature.v21Capture`, so with the flag off (MVP1) it renders nothing
/// and no MVP1 path reaches it. The runtime math runs through the owned Zig kernels via
/// `SixFourNative.countsToEnergyV21` and `SixFourNative.collapseV21`.

// MARK: - The captured field (per-bin probability curves)

/// One V2.1 capture as a field of per-bin histograms. `counts` is `side·side·3·nLevels`,
/// pixel-major then channel R,G,B then value level, matching the layout the Zig kernels
/// (`s4_v21_accumulate_hist` out, `s4_v21_counts_to_energy` / `s4_v21_collapse` in) expect:
/// `((cell·3 + channel)·nLevels + level)`.
struct V21FieldData {
    let side: Int
    let nLevels: Int
    let counts: [Int32]

    var pixelCount: Int { side * side }

    var isValid: Bool {
        side > 0 && nLevels > 0 && counts.count == side * side * 3 * nLevels
    }

    /// The `nLevels` counts of one bin's one channel (0=R, 1=G, 2=B), as a 0-based slice.
    func curve(cell: Int, channel: Int) -> ArraySlice<Int32> {
        let base = (cell * 3 + channel) * nLevels
        return counts[base ..< base + nLevels]
    }
}

// MARK: - The derived reads (collapse, uncertainty)

/// Everything the field collapses to, computed once off the raw `counts`: the per-bin
/// mode levels (through the Zig collapse), a display image of the collapsed result, a
/// grayscale image of per-bin entropy, and the per-bin normalised entropy itself.
private struct V21Derived {
    let collapseLevels: [UInt8]      // side·side·3, the raw argmin level per bin/channel
    let collapseImage: UIImage?      // the shipped look, level rescaled to a display byte
    let uncertaintyImage: UIImage?   // per-bin entropy as grayscale
    let entropy: [Float]             // per bin, max-channel, normalised to [0,1]

    /// Run `counts -> energies -> collapse` through the owned kernels, then build the two
    /// field images. Returns nil if the field is malformed or a kernel declines.
    static func derive(_ f: V21FieldData) -> V21Derived? {
        guard f.isValid,
              let energies = SixFourNative.countsToEnergyV21(counts: f.counts, p: f.pixelCount, nLevels: f.nLevels),
              let levels = SixFourNative.collapseV21(curves: energies, p: f.pixelCount, nLevels: f.nLevels)
        else { return nil }

        let p = f.pixelCount
        let n = f.nLevels
        let denom = max(1, n - 1)

        // The collapse level IS the byte (0..nLevels-1); rescale to 0..255 for display so a
        // small nLevels does not read as a near-black field. (Mode index, not the colour byte.)
        var rgb = [UInt8](repeating: 0, count: p * 3)
        for i in 0 ..< p * 3 {
            rgb[i] = UInt8(min(255, Int(levels[i]) * 255 / denom))
        }
        let collapseImage = image(rgb: rgb, side: f.side)

        // Per-bin Shannon entropy of the curve, taken over the channel of widest spread and
        // normalised by log(nLevels) so it lands in [0,1]. This is the uncertainty read.
        var entropy = [Float](repeating: 0, count: p)
        var grey = [UInt8](repeating: 0, count: p * 3)
        let logN = Float(log(Double(max(2, n))))
        for cell in 0 ..< p {
            var maxH: Float = 0
            for ch in 0 ..< 3 {
                let base = (cell * 3 + ch) * n
                var total: Float = 0
                for l in 0 ..< n { total += Float(f.counts[base + l]) }
                guard total > 0 else { continue }
                var h: Float = 0
                for l in 0 ..< n {
                    let c = Float(f.counts[base + l])
                    if c > 0 {
                        let pr = c / total
                        h -= pr * log(pr)
                    }
                }
                if h > maxH { maxH = h }
            }
            let nh = logN > 0 ? min(1, maxH / logN) : 0
            entropy[cell] = nh
            let g = UInt8(nh * 255)
            grey[cell * 3 + 0] = g
            grey[cell * 3 + 1] = g
            grey[cell * 3 + 2] = g
        }
        let uncertaintyImage = image(rgb: grey, side: f.side)

        return V21Derived(collapseLevels: levels, collapseImage: collapseImage,
                          uncertaintyImage: uncertaintyImage, entropy: entropy)
    }

    /// Build an opaque sRGB `side×side` `UIImage` from packed RGB bytes, interpolation off
    /// (the 64×64 stays hard under upscale). Mirrors `CaptureViewModel.image(fromRGBA:)`.
    private static func image(rgb: [UInt8], side: Int) -> UIImage? {
        let pixelCount = side * side
        guard rgb.count == pixelCount * 3 else { return nil }
        var bytes = [UInt8](repeating: 255, count: pixelCount * 4)
        for i in 0 ..< pixelCount {
            bytes[i * 4 + 0] = rgb[i * 3 + 0]
            bytes[i * 4 + 1] = rgb[i * 3 + 1]
            bytes[i * 4 + 2] = rgb[i * 3 + 2]
        }
        let bytesPerRow = side * 4
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            .byteOrder32Big
        ]
        guard let cg = CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - The surface

/// Which read of the field the hero shows.
private enum V21FieldMode: Hashable {
    case ships          // the collapsed result (the GIF)
    case uncertainty    // per-bin entropy

    var label: String {
        switch self {
        case .ships: return "SHIPS"
        case .uncertainty: return "SPREAD"
        }
    }
}

struct V21FieldView: View {
    let field: V21FieldData

    var body: some View {
        // The entire surface is gated: off in MVP1, this renders nothing and is unreachable.
        Group {
            if Feature.v21Capture {
                content
            } else {
                Color.clear
            }
        }
    }

    @State private var mode: V21FieldMode = .ships
    @State private var derived: V21Derived?
    @State private var selected: Int?

    /// Field hero edge = the canonical 256 pt GIF canvas (64 cells × 4 pt), so one bin is
    /// one 4 pt cell and the field sits crisp at the device width.
    private var edge: CGFloat { SFTheme.gifCanvasPt }
    private var cellW: CGFloat { edge / CGFloat(max(1, field.side)) }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(6)) {
            CellText("V2.1 FIELD", rows: 9, ink: .white)

            CellSelector(options: [(V21FieldMode.ships, V21FieldMode.ships.label),
                                   (V21FieldMode.uncertainty, V21FieldMode.uncertainty.label)],
                         selection: $mode)

            heroField

            distribution
        }
        .padding(GlobalLattice.pt(6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .task(id: field.counts.count) { derived = V21Derived.derive(field) }
    }

    /// The 64×64 field: collapsed result or entropy, with a 1-cell selection cursor and a
    /// tap-to-select gesture. One bitmap (`PixelImage`), never 4096 Canvas fills.
    @ViewBuilder private var heroField: some View {
        let img = (mode == .ships) ? derived?.collapseImage : derived?.uncertaintyImage
        ZStack(alignment: .topLeading) {
            if let img {
                PixelImage(image: img, edge: edge)
            } else {
                // No derived field yet (computing, or a kernel declined): a flat ground.
                Rectangle().fill(Color(srgb8: SFTheme.ledGhost)).frame(width: edge, height: edge)
            }
        }
        .frame(width: edge, height: edge)
        // The selection cursor is drawn (a flat opaque 1 pt border, no AA stroke), not
        // composed, so it stays on the rasteriser side of the grid placement law.
        .overlay {
            Canvas { ctx, size in
                guard let s = selected, field.side > 0 else { return }
                let cw = size.width / CGFloat(field.side)
                let cx = s % field.side, cy = s / field.side
                let rect = CGRect(x: CGFloat(cx) * cw, y: CGFloat(cy) * cw, width: cw, height: cw)
                ctx.fillBorder(rect, width: 1, color: .white)
            }
            .allowsHitTesting(false)
        }
        .pixelFrame()
        // minimumDistance 0 so a plain tap selects the bin under the finger.
        .gesture(DragGesture(minimumDistance: 0).onEnded { v in select(at: v.location) })
        .accessibilityLabel("V2.1 field, \(mode.label) read. Tap a bin to read its curves.")
    }

    /// The selected bin's three per-channel probability curves, the mode marked on each, plus
    /// the bin's collapsed swatch and its entropy. The reason the field exists: the model
    /// trains on these curves, the GIF ships only their modes.
    @ViewBuilder private var distribution: some View {
        if let s = selected, let d = derived {
            let cx = s % field.side, cy = s / field.side
            VStack(alignment: .leading, spacing: GlobalLattice.pt(4)) {
                HStack(spacing: GlobalLattice.pt(4)) {
                    CellText("BIN \(cx),\(cy)", rows: 8, ink: Color(srgb8: SIMD3(150, 150, 150)))
                    Spacer(minLength: GlobalLattice.pt(4))
                    CellText("SPREAD \(Int(d.entropy[s] * 100))", rows: 8,
                             ink: Color(srgb8: SIMD3(150, 150, 150)))
                }
                ForEach(0 ..< 3, id: \.self) { ch in
                    HStack(spacing: GlobalLattice.pt(3)) {
                        CellText(["R", "G", "B"][ch], rows: 8, ink: Color(srgb8: channelInk(ch)))
                        ChannelCurve(counts: field.curve(cell: s, channel: ch),
                                     nLevels: field.nLevels,
                                     modeLevel: Int(d.collapseLevels[s * 3 + ch]),
                                     ink: channelInk(ch))
                            .frame(height: GlobalLattice.pt(14))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        } else {
            CellText("TAP A BIN", rows: 8, ink: Color(srgb8: SIMD3(110, 110, 110)))
        }
    }

    private func channelInk(_ ch: Int) -> SIMD3<UInt8> {
        switch ch {
        case 0: return SIMD3(230, 90, 90)
        case 1: return SIMD3(90, 200, 110)
        default: return SIMD3(100, 140, 235)
        }
    }

    /// Map a tap point inside the field to a bin index, clamped to the grid.
    private func select(at p: CGPoint) {
        guard cellW > 0 else { return }
        let cx = min(field.side - 1, max(0, Int(p.x / cellW)))
        let cy = min(field.side - 1, max(0, Int(p.y / cellW)))
        selected = cy * field.side + cx
    }
}

// MARK: - One channel's probability curve

/// A single channel's histogram drawn as flat bars across the value levels, with the
/// collapsed mode level lit white. Bar height is the count relative to the curve's own
/// peak (the shape, not the absolute population). Canvas (not 4096 cells) is fine here:
/// it is one bin's `nLevels` bars, well under the palette-scale ceiling.
private struct ChannelCurve: View {
    let counts: ArraySlice<Int32>
    let nLevels: Int
    let modeLevel: Int
    let ink: SIMD3<UInt8>

    var body: some View {
        Canvas { ctx, size in
            guard nLevels > 0 else { return }
            let arr = Array(counts)
            let peak = max(1, Int(arr.max() ?? 1))
            let bw = size.width / CGFloat(nLevels)
            for l in 0 ..< min(nLevels, arr.count) {
                let frac = CGFloat(max(0, Int(arr[l]))) / CGFloat(peak)
                let h = frac * size.height
                let rect = CGRect(x: CGFloat(l) * bw, y: size.height - h,
                                  width: max(1, bw), height: h)
                let c = (l == modeLevel) ? SIMD3<UInt8>(255, 255, 255) : ink
                ctx.fillCell(rect, srgb8: c)
            }
        }
        .background(Color(srgb8: SFTheme.ledGhost))
    }
}

#if DEBUG
extension V21FieldData {
    /// A synthetic field for previews only (pure Swift, no kernels): a colour gradient whose
    /// per-bin curve spread grows left to right, so the SPREAD read visibly brightens rightward.
    static func demo(side: Int = 64, nLevels: Int = 32) -> V21FieldData {
        var counts = [Int32](repeating: 0, count: side * side * 3 * nLevels)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let cell = y * side + x
                let spread = 1 + (nLevels - 1) * x / max(1, side - 1)   // sharp left, wide right
                for ch in 0 ..< 3 {
                    let axis = ch == 0 ? x : (ch == 1 ? y : (x + y) / 2)
                    let center = (nLevels - 1) * axis / max(1, side - 1)
                    let lo = max(0, center - spread / 2)
                    let hi = min(nLevels - 1, center + spread / 2)
                    let base = (cell * 3 + ch) * nLevels
                    for l in lo ... hi { counts[base + l] += Int32(1 + (l == center ? 4 : 0)) }
                }
            }
        }
        return V21FieldData(side: side, nLevels: nLevels, counts: counts)
    }
}

#Preview {
    V21FieldView(field: .demo())
}
#endif
