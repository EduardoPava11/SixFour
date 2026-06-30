import SwiftUI
import simd

/// The V2.1 two-WIDGET surface, form-follows-function over `V21FieldUI` (the cell-count layer).
///
/// One field, two widgets, one shared cell budget. The budget is split by `V21FieldUI.allocateWidgets`,
/// which forces the two widgets onto DISTINCT cell counts (the opposition law: they never take the same
/// number of cells). Each widget then subdivides its own count over the 64×64 grid with
/// `V21FieldUI.budgetCells`, a Morton quadtree weighted by per-cell uncertainty (`disagree`), so cells
/// land where the distribution is contested.
///
///   * THE MODE WIDGET is the crisp read: each plot is filled with its region's collapsed colour, zero
///     bleed (this is the GIF the user ships).
///   * THE UNCERTAINTY WIDGET is the soft read: each plot is a heat splat whose BLEED radius grows with
///     the region's spread, drawn translucently so neighbouring splats OVERLAP. Bleed interacts; counts
///     oppose. That is the whole design in one screen.
///
/// Tier-2 pure (SwiftUI + simd, zero third-party), gated behind `Feature.v21Capture`. The collapse and
/// energy math runs through the owned kernels (`SixFourNative.countsToEnergyV21` / `collapseV21`).

// MARK: - Derived per-cell field (computed once)

/// The two per-cell arrays the widgets read: the display RGB of each bin's collapsed mode, and each
/// bin's `disagree` (non-mode mass). Built once off the raw counts through the owned kernels.
private struct V21WidgetData {
    let side: Int
    let rgb: [UInt8]        // side·side·3, the collapsed mode rescaled to a display byte
    let disagree: [Int]     // side·side, per-bin non-mode observation mass
    let maxDisagree: Int    // the field's peak per-bin disagree (normaliser, >= 1)
    let modeSalience: Int   // total agreement mass (drives the Mode widget's budget share)
    let uncSalience: Int    // total disagreement mass (drives the Uncertainty widget's budget share)

    static func derive(_ f: V21FieldData) -> V21WidgetData? {
        guard f.isValid,
              let energies = SixFourNative.countsToEnergyV21(counts: f.counts, p: f.pixelCount, nLevels: f.nLevels),
              let levels = SixFourNative.collapseV21(curves: energies, p: f.pixelCount, nLevels: f.nLevels)
        else { return nil }

        let p = f.pixelCount, n = f.nLevels, denom = max(1, n - 1)

        var rgb = [UInt8](repeating: 0, count: p * 3)
        for i in 0 ..< p * 3 { rgb[i] = UInt8(min(255, Int(levels[i]) * 255 / denom)) }

        // Per-bin disagree = the max over channels of (total − peak count): the bin's worst spread.
        var dis = [Int](repeating: 0, count: p)
        var peakDis = 1, totalUnc = 0, totalAgree = 0
        for cell in 0 ..< p {
            var worst = 0, agreeHere = 0
            for ch in 0 ..< 3 {
                let base = (cell * 3 + ch) * n
                var total = 0, peak = 0
                for l in 0 ..< n {
                    let c = Int(f.counts[base + l])
                    total += c
                    if c > peak { peak = c }
                }
                let d = total - peak
                if d > worst { worst = d }
                agreeHere += peak
            }
            dis[cell] = worst
            if worst > peakDis { peakDis = worst }
            totalUnc += worst
            totalAgree += agreeHere
        }
        return V21WidgetData(side: f.side, rgb: rgb, disagree: dis, maxDisagree: peakDis,
                             modeSalience: totalAgree, uncSalience: totalUnc)
    }

    /// The full single-frame region of the field.
    var fullRegion: V21FieldUI.Region {
        V21FieldUI.Region(xLo: 0, xHi: side, yLo: 0, yHi: side, tLo: 0, tHi: 1)
    }

    /// The budget weight of a region: the total `disagree` over its bins, so the quadtree refines where
    /// the field is uncertain. The field-grounded instantiation of `V21FieldUI.regionWeight`.
    func regionWeight(_ r: V21FieldUI.Region) -> Int {
        var sum = 0
        for y in r.yLo ..< r.yHi {
            for x in r.xLo ..< r.xHi { sum += disagree[y * side + x] }
        }
        return sum
    }

    /// The average collapsed colour over a region (the Mode widget's per-plot fill).
    func meanRGB(_ r: V21FieldUI.Region) -> SIMD3<UInt8> {
        var rs = 0, gs = 0, bs = 0, count = 0
        for y in r.yLo ..< r.yHi {
            for x in r.xLo ..< r.xHi {
                let c = y * side + x
                rs += Int(rgb[c * 3 + 0]); gs += Int(rgb[c * 3 + 1]); bs += Int(rgb[c * 3 + 2])
                count += 1
            }
        }
        let d = max(1, count)
        return SIMD3(UInt8(rs / d), UInt8(gs / d), UInt8(bs / d))
    }

    /// A region's normalised spread in `[0,1]` (the Uncertainty widget's heat and bleed driver).
    func spread(_ r: V21FieldUI.Region) -> Double {
        let cells = max(1, r.volume)
        let mean = Double(regionWeight(r)) / Double(cells)
        return min(1, mean / Double(maxDisagree))
    }
}

// MARK: - The surface

struct V21WidgetSurface: View {
    let field: V21FieldData

    /// The shared screen cell budget the two widgets compete for. A few choices so the opposition is
    /// visible: the counts shift with the budget but stay distinct.
    private static let budgets = [64, 128, 192]

    @State private var budget = 128
    @State private var data: V21WidgetData?

    private var edge: CGFloat { SFTheme.gifCanvasPt }

    var body: some View {
        Group {
            if Feature.v21Capture { content } else { Color.clear }
        }
    }

    /// `[modeCells, uncCells]` from the opposition allocator: distinct by construction.
    private var split: [Int] {
        guard let d = data else { return [0, 0] }
        return V21FieldUI.allocateWidgets(budget, [(d.modeSalience, 0), (d.uncSalience, 1)])
    }

    @ViewBuilder private var content: some View {
        let s = split
        VStack(alignment: .leading, spacing: GlobalLattice.pt(6)) {
            CellText("V2.1 WIDGETS", rows: 9, ink: .white)

            CellSelector(options: Self.budgets.map { ($0, "\($0)") }, selection: $budget)

            // The opposition, made legible: two widgets, two DISTINCT counts.
            HStack(spacing: GlobalLattice.pt(6)) {
                CellText("MODE \(s[0])", rows: 8, ink: Color(srgb8: SIMD3(150, 150, 150)))
                CellText("SPREAD \(s[1])", rows: 8, ink: Color(srgb8: SIMD3(150, 150, 150)))
                Spacer(minLength: 0)
                CellText(s[0] != s[1] ? "OPPOSED" : "TIE", rows: 8,
                         ink: Color(srgb8: s[0] != s[1] ? SIMD3(120, 210, 130) : SIMD3(210, 120, 120)))
            }

            if let d = data {
                CellText("MODE WIDGET (crisp)", rows: 7, ink: Color(srgb8: SIMD3(120, 120, 120)))
                ModeWidget(data: d, cells: s[0], edge: edge)

                CellText("UNCERTAINTY WIDGET (bleed interacts)", rows: 7,
                         ink: Color(srgb8: SIMD3(120, 120, 120)))
                UncertaintyWidget(data: d, cells: s[1], edge: edge)
            } else {
                Rectangle().fill(Color(srgb8: SFTheme.ledGhost)).frame(width: edge, height: edge)
            }
        }
        .padding(GlobalLattice.pt(6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .task(id: field.counts.count) { data = V21WidgetData.derive(field) }
    }
}

// MARK: - The Mode widget (crisp, zero bleed)

/// The crisp read: each budgeted plot is filled opaque with its region's collapsed colour. Zero bleed,
/// hard edges, the GIF the user ships. More cells (a bigger budget share) means finer plots.
private struct ModeWidget: View {
    let data: V21WidgetData
    let cells: Int
    let edge: CGFloat

    var body: some View {
        let plots = V21FieldUI.budgetCells(data.regionWeight, data.fullRegion, cells)
        Canvas { ctx, size in
            let cw = size.width / CGFloat(max(1, data.side))
            for p in plots {
                let r = p.region
                let rect = CGRect(x: CGFloat(r.xLo) * cw, y: CGFloat(r.yLo) * cw,
                                  width: CGFloat(r.xHi - r.xLo) * cw,
                                  height: CGFloat(r.yHi - r.yLo) * cw)
                ctx.fill(Path(rect), with: .color(Color(srgb8: data.meanRGB(r))))
            }
        }
        .frame(width: edge, height: edge)
        .background(Color(srgb8: SFTheme.ledGhost))
        .pixelFrame()
    }
}

// MARK: - The Uncertainty widget (heat, bleed interacts)

/// The soft read: each budgeted plot is a heat splat whose BLEED radius grows with the region's spread.
/// The bleed is drawn translucently and OVERSIZED, so adjacent splats overlap and blend, the bleed
/// interacting across widget cells. A crisp core marks the plot itself.
private struct UncertaintyWidget: View {
    let data: V21WidgetData
    let cells: Int
    let edge: CGFloat

    var body: some View {
        let plots = V21FieldUI.budgetCells(data.regionWeight, data.fullRegion, cells)
        Canvas { ctx, size in
            let cw = size.width / CGFloat(max(1, data.side))
            // Bleed pass first (translucent, oversized, additive overlap), then the crisp cores.
            for p in plots {
                let r = p.region
                let nh = data.spread(r)
                let bleed = CGFloat(nh) * cw * 2.0     // up to two cells of spill at full uncertainty
                let rect = CGRect(x: CGFloat(r.xLo) * cw, y: CGFloat(r.yLo) * cw,
                                  width: CGFloat(r.xHi - r.xLo) * cw,
                                  height: CGFloat(r.yHi - r.yLo) * cw).insetBy(dx: -bleed, dy: -bleed)
                ctx.fill(Path(roundedRect: rect, cornerRadius: bleed),
                         with: .color(heat(nh).opacity(0.30)))
            }
            for p in plots {
                let r = p.region
                let nh = data.spread(r)
                let rect = CGRect(x: CGFloat(r.xLo) * cw, y: CGFloat(r.yLo) * cw,
                                  width: CGFloat(r.xHi - r.xLo) * cw,
                                  height: CGFloat(r.yHi - r.yLo) * cw)
                ctx.fill(Path(rect), with: .color(heat(nh)))
            }
        }
        .frame(width: edge, height: edge)
        .background(Color(srgb8: SIMD3(8, 8, 12)))
        .pixelFrame()
    }

    /// Cool-to-hot ramp: low spread reads dark blue, high spread reads bright orange.
    private func heat(_ nh: Double) -> Color {
        let r = UInt8(min(255, nh * 255))
        let g = UInt8(min(255, nh * nh * 150))
        let b = UInt8(min(255, (1 - nh) * 150 + 20))
        return Color(srgb8: SIMD3(r, g, b))
    }
}

#if DEBUG
#Preview {
    V21WidgetSurface(field: .demo())
}
#endif
