import SwiftUI
import UIKit
import simd

/// THE GRID MIRRORS THE LADDER (Feature.rungTelemetry) — the `liveScene` instrument
/// flanks. Each of the three ladder rungs (64²@20 Hz / 32²@10 Hz / 16²@5 Hz) gets a
/// spec'd `GridLayoutContract.liveScene` region riding the right flank beside its own
/// pyramid band; the `system` region is the machine ring below the pyramid. Per rung,
/// four cell sub-blocks, all fed by the ONE `RungTelemetry` snapshot the capture
/// session publishes at the 16-rung cadence (≤ 5 Hz — never per frame):
///
///   1. ARRIVAL PULSE — a 6×6 cell block that flips full/hollow whenever the
///      rung's arrival counter MOVES between snapshots (movement, not parity —
///      derived counters land in even strides); a stalled rung simply stops
///      pulsing (the honest gap read) and any evidence-free tick
///      (`skipped > 0`) tints it.
///   2. EXPOSURE STATE — EV (one vocabulary: optical centistops when the ladder is
///      independent, pooling-equivalent +k stops when derived) + duration/ISO as
///      compact `CellText` lines ("1/20" + "800" optical, "POOL" derived).
///   3. SIGNIFICANCE — a √N fill bar (cell fill COUNT, never alpha), normalized
///      against the most-significant rung this snapshot, so the derived 1:8:64
///      sample-volume lattice reads as the √ ladder 1 : 2√2 : 8.
///   4. INDEPENDENCE HEALTH — a state glyph: filled disc (independent, ok) /
///      triangle (correlated — the ladder fell back or the streams co-move
///      everywhere, `fullyDetermined`) / hollow diamond (derived: the EXPECTED
///      maximal pole, deliberately not styled as an alarm).
///
/// GRID laws: everything is `CellBitmap`/`CellText` at the one lattice, every
/// dimension via `GlobalLattice`, no opacity-on-a-cell (state = ink change, dim =
/// the ghost ink), placement via `.place(_:in: liveScene)` only, hit-testing OFF so
/// the meters never intercept the ground LOOK-swipe/EV-drag or the 16² shutter.
///
/// PERF (the InvertedPyramidField 2026-07-08 discipline): the flanks are wrapped
/// `.equatable()` by `LivePhaseField`, so the ≤ 5 Hz telemetry cadence — not the
/// 20 fps preview publish — drives their bodies; inside, every bitmap lives in
/// `@State` keyed by a QUANTIZED fingerprint (cell fill counts, arrival counter,
/// state enums), so float-free jitter never re-bakes a CGContext.
struct RungTelemetryFlanks: View, Equatable {
    /// The latest per-rung snapshot (σ.rungTelemetry) — nil until a burst runs.
    let telemetry: RungTelemetry?
    /// The latest machine-ring snapshot (σ.systemTelemetry) — nil until published.
    let system: SystemTelemetry?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if Feature.rungTelemetry {
                if let tel = telemetry, tel.rungs.count == 3 {
                    // √N normalization reference: the most-significant rung this
                    // snapshot (fills are RELATIVE evidence across the ladder).
                    let ref = tel.rungs.map(\.sampleVolume).max() ?? 1
                    RungMeterCell(rung: tel.rungs[0], referenceVolume: ref)
                        .place("rung64", in: GridLayoutContract.liveScene)
                    RungMeterCell(rung: tel.rungs[1], referenceVolume: ref)
                        .place("rung32", in: GridLayoutContract.liveScene)
                    RungMeterCell(rung: tel.rungs[2], referenceVolume: ref)
                        .place("rung16", in: GridLayoutContract.liveScene)
                }
                if let sys = system {
                    SystemMeterCell(system: sys)
                        .place("system", in: GridLayoutContract.liveScene)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)   // meters never eat the ground gestures / shutter
    }
}

// MARK: - The meter inks (state = a different ink, never an opacity)

/// The telemetry ink palette. Degraded/unlit states are DIFFERENT OPAQUE inks
/// (Law #2: no alpha on a cell) — `ghost` is the same unlit ink the LED digits use.
enum TelemetryInk {
    static let lit = SIMD3<UInt8>(235, 235, 235)
    static let dim = SIMD3<UInt8>(90, 90, 90)
    static let ok = SIMD3<UInt8>(80, 200, 120)
    static let warn = SIMD3<UInt8>(230, 200, 60)
    static let alert = SIMD3<UInt8>(220, 60, 60)
    static let derived = SIMD3<UInt8>(140, 140, 140)
    static let ghost = SFTheme.ledGhost
}

// MARK: - The pure display math (unit-tested in TelemetryMeterTests)

/// Quantization + state mapping for the meters — PURE, integer-out, so the bake
/// fingerprints are exact and the widget never re-bakes on sub-cell float jitter.
enum TelemetryMeterMath {

    /// √N fill: how many of `width` cells light for `volume` against `reference`
    /// (the most-significant rung). `round(width·√(volume/reference))`, clamped —
    /// the √N order IS the N order (`lawSignificanceSqrtMonotone`), so the bar is
    /// monotone in the evidence. Degenerate inputs (no reference / no volume) → 0.
    static func sqrtFillCells(volume: Int64, reference: Int64, width: Int) -> Int {
        guard width > 0, reference > 0, volume > 0 else { return 0 }
        guard volume < reference else { return width }
        let f = (Double(volume) / Double(reference)).squareRoot()
        return max(0, min(width, Int((Double(width) * f).rounded())))
    }

    /// Arrival-pulse beat: the bit that drives the pulse block's full/hollow
    /// flip. Toggles whenever the arrival counter MOVED between snapshots
    /// (a new-burst reset counts as movement); an unchanged counter keeps the
    /// beat, so a stalled rung stops pulsing — the honest gap read. Raw
    /// arrival PARITY cannot drive this: derived snapshots publish at the
    /// 16-rung cadence (`ch.tick % 4 == 0`) with `arrivals = ticks >> k`, so
    /// rung64 lands 4, 8, …, 64 and rung32 lands 2, 4, …, 32 — always even,
    /// a permanently frozen pulse. `last == nil` (first snapshot after mount)
    /// reads already-landed arrivals as the first beat.
    static func pulseBeat(arrivals: Int, last: Int?, beat: Bool) -> Bool {
        guard let last else { return arrivals > 0 }
        return arrivals != last ? !beat : beat
    }

    /// The independence-health state cell's three values.
    enum Health: Int, Equatable {
        /// Independent exposure and the decorrelation statistic is below the
        /// fully-determined pole — genuinely separate evidence.
        case independent = 0
        /// Independent by schedule but the streams co-move everywhere
        /// (`fullyDetermined`, 1000‰) — the ladder fell back / the warning light.
        case correlated = 1
        /// Derived by exact pooling — the EXPECTED maximal pole, not an alarm.
        case derived = 2
    }

    /// Map a rung's provenance bit + comovement permille to the health cell.
    /// Derived mode is always `.derived` (honest, never a false alarm); an
    /// independent rung warns ONLY at the fully-determined pole (≥ 1000‰);
    /// -1 (no coarser rung / no data yet) stays `.independent`.
    static func health(independent: Bool, comovementPermille: Int) -> Health {
        guard independent else { return .derived }
        return comovementPermille >= 1000 ? .correlated : .independent
    }

    /// Signed EV centistops → the compact stop label ("+1.0", "-0.5", "+0.0").
    static func evLabel(centistops: Int) -> String {
        String(format: "%+.1f", Double(centistops) / 100)
    }

    /// The shutter-time line: "1/20" from the optical duration (µs); "POOL" in
    /// derived mode (no per-rung shutter exists — the stops are pooling); "-"
    /// when independent but unmetered.
    static func durationLabel(independent: Bool, durationUs: Int64) -> String {
        guard independent else { return "POOL" }
        guard durationUs > 0 else { return "-" }
        return "1/\(Int((1_000_000.0 / Double(durationUs)).rounded()))"
    }

    /// The gain line: ISO from milli-units ("800"); empty in derived mode (the
    /// EV line already carries the pooling-equivalent stops).
    static func isoLabel(independent: Bool, isoMilli: Int64) -> String {
        guard independent else { return "" }
        guard isoMilli > 0 else { return "-" }
        return "\(Int((Double(isoMilli) / 1000).rounded()))"
    }

    /// Budget fill: cells lit for `us` against `budgetUs` over `width` cells,
    /// clamped to the bar — the tick-CPU meter's quantizer.
    static func budgetFillCells(us: Int, budgetUs: Int, width: Int) -> Int {
        guard width > 0, budgetUs > 0, us > 0 else { return 0 }
        return min(width, max(0, Int((Double(width) * Double(us) / Double(budgetUs)).rounded())))
    }

    /// Thermal steps lit for a pressure level -1…4 (unknown → 0, nominal → 1,
    /// … shutdown → 5), clamped to the 5-block strip.
    static func thermalLit(level: Int) -> Int { max(0, min(5, level + 1)) }
}

// MARK: - One rung's instrument (a 14-atom-wide flank cell block)

/// One rung's four sub-blocks, top-aligned in its flank region (the region's
/// height mirrors the rung side — 64/32/16 atoms — so the coarsest rung gets the
/// tightest fit: 62 pt of cells in 64 pt). All bitmaps are baked in `@State` and
/// re-baked ONLY when the quantized meter key changes (`meterKey`); the text
/// lines ride `CellText`'s NSCache. σ-agnostic: plain values in, cells out.
struct RungMeterCell: View {
    let rung: RungTelemetry.RungState
    /// The √N normalization reference — the max sample volume across the three
    /// rungs in this snapshot (the flanks compare RELATIVE evidence).
    let referenceVolume: Int64

    @State private var baked = Baked()

    private struct Baked {
        var pulse: UIImage?
        var health: UIImage?
        var bar: UIImage?
        /// The arrival counter at the last bake — the beat's movement reference.
        var lastArrivals: Int?
        /// The pulse's beat bit (`TelemetryMeterMath.pulseBeat`), toggled per
        /// counter movement — NOT arrival parity, which freezes on the derived
        /// rungs' even-stride counters (rung64 publishes 4, 8, …, 64).
        var beat = false
    }

    /// The full flank width in sub-cells: 14 atoms = 28 sub-cells = 56 pt.
    private static let barSub = 28
    /// Pulse + health glyph side in sub-cells (12 pt blocks).
    private static let glyphSub = 6

    private var healthState: TelemetryMeterMath.Health {
        TelemetryMeterMath.health(independent: rung.independent,
                                  comovementPermille: rung.comovementPermilleVsCoarser)
    }

    private var fillCells: Int {
        TelemetryMeterMath.sqrtFillCells(volume: rung.sampleVolume,
                                         reference: referenceVolume,
                                         width: Self.barSub)
    }

    /// The QUANTIZED bake fingerprint — every value is already a cell step
    /// (arrival counter, boolean gap, state enum, fill count), so a snapshot
    /// that changes nothing visible re-bakes nothing. The pulse's beat bit is
    /// a pure function of the arrival-counter HISTORY, and the counter is
    /// combined here — so every beat flip is a key change and the fingerprint
    /// stays exact without hashing the beat itself.
    private var meterKey: Int {
        var h = Hasher()
        h.combine(rung.arrivals)
        h.combine(rung.skipped > 0)
        h.combine(healthState)
        h.combine(fillCells)
        return h.finalize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(1)) {
            HStack(spacing: GlobalLattice.pt(2)) {
                Self.image(baked.pulse, cols: Self.glyphSub, rows: Self.glyphSub)
                Self.image(baked.health, cols: Self.glyphSub, rows: Self.glyphSub)
            }
            CellText(TelemetryMeterMath.evLabel(centistops: rung.evCentistops))
            CellText(TelemetryMeterMath.durationLabel(independent: rung.independent,
                                                      durationUs: rung.exposureDurationUs),
                     rows: 5)
            if rung.independent {
                CellText(TelemetryMeterMath.isoLabel(independent: rung.independent,
                                                     isoMilli: rung.isoMilli),
                         rows: 5)
            }
            Self.image(baked.bar, cols: Self.barSub, rows: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: meterKey, initial: true) { _, _ in rebake() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let mode = rung.independent ? "independent" : "derived"
        let health: String
        switch healthState {
        case .independent: health = "healthy"
        case .correlated: health = "correlated"
        case .derived: health = "derived pooling"
        }
        return "Rung \(rung.side): \(mode), EV \(TelemetryMeterMath.evLabel(centistops: rung.evCentistops)), "
            + "\(rung.arrivals) of \(rung.expectedArrivals) arrivals, \(health)"
    }

    /// Render a cached bitmap at the sub-cell pitch (nearest-neighbour, no AA —
    /// the `CellSprite` contract minus the per-evaluation bake).
    @ViewBuilder
    private static func image(_ img: UIImage?, cols: Int, rows: Int) -> some View {
        if let img {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: GlobalLattice.pt(cols), height: GlobalLattice.pt(rows))
        }
    }

    /// Bake the three sub-block bitmaps — runs once per QUANTIZED value change,
    /// never per body evaluation. Tiny bitmaps (≤ 112 cells) at ≤ 5 Hz.
    private func rebake() {
        let n = Self.glyphSub
        // Advance the beat on counter MOVEMENT (never parity — the derived
        // rung64/rung32 counters land in even strides at the 5 Hz publish, so
        // `arrivals % 2` froze those pulses for the whole burst).
        baked.beat = TelemetryMeterMath.pulseBeat(arrivals: rung.arrivals,
                                                  last: baked.lastArrivals,
                                                  beat: baked.beat)
        baked.lastArrivals = rung.arrivals
        let on = baked.beat
        let ink: SIMD3<UInt8> = rung.skipped > 0 ? TelemetryInk.warn : TelemetryInk.lit

        // 1. ARRIVAL PULSE: full block on the beat, hollow outline off it —
        //    the flip IS the pulse; no arrivals ⇒ no flips ⇒ the gap.
        baked.pulse = CellBitmap.image(cols: n, rows: n) { c, r in
            if on { return ink }
            let border = c == 0 || r == 0 || c == n - 1 || r == n - 1
            return border ? ink : TelemetryInk.ghost
        }

        // 4. INDEPENDENCE HEALTH: disc / triangle / hollow diamond, by state.
        let state = healthState
        baked.health = CellBitmap.image(cols: n, rows: n) { c, r in
            let cx = Double(n) / 2, cy = Double(n) / 2
            switch state {
            case .independent:   // filled disc — the seal
                return CellGeom.dist(c, r, cx, cy) <= cx - 0.6 ? TelemetryInk.ok : nil
            case .correlated:    // filled triangle — the warning
                guard r >= 1 && r <= n - 2 else { return nil }
                let t = Double(r - 1) / Double(n - 3)
                return abs(Double(c) + 0.5 - cx) <= t * (cx - 1) ? TelemetryInk.warn : nil
            case .derived:       // hollow diamond — expected-maximal, NOT an alarm
                let m = abs(Double(c) + 0.5 - cx) + abs(Double(r) + 0.5 - cy)
                return (m >= cx - 1 && m <= cx) ? TelemetryInk.derived : nil
            }
        }

        // 3. SIGNIFICANCE: the √N fill bar — lit count is the quantized value.
        let lit = fillCells
        baked.bar = CellBitmap.image(cols: Self.barSub, rows: 4) { c, _ in
            c < lit ? TelemetryInk.lit : TelemetryInk.ghost
        }
    }
}

// MARK: - The machine ring (the ONE system region, 64×24 atoms)

/// Tick CPU vs the 50 ms budget (mean fill + worst-tick marker), the v21 hist
/// buffer's ~384 MiB lifecycle as a state cell, and thermal/system pressure as a
/// stepped strip. Same bake-cache discipline as `RungMeterCell`; published data
/// only changes on lifecycle/pressure edges + burst seams, so this is near-static.
struct SystemMeterCell: View {
    let system: SystemTelemetry

    @State private var baked = Baked()

    private struct Baked {
        var cpuBar: UIImage?
        var v21: UIImage?
        var thermal: UIImage?
    }

    /// CPU bar width in sub-cells (64 sub = 128 pt).
    private static let cpuBarSub = 64

    private var cpuMeanMs: Int { (system.tickCpuMeanUs + 500) / 1000 }
    private var cpuFill: Int {
        TelemetryMeterMath.budgetFillCells(us: system.tickCpuMeanUs,
                                           budgetUs: system.tickBudgetUs,
                                           width: Self.cpuBarSub)
    }
    private var cpuMaxCell: Int {
        TelemetryMeterMath.budgetFillCells(us: system.tickCpuMaxUs,
                                           budgetUs: system.tickBudgetUs,
                                           width: Self.cpuBarSub)
    }
    private var thermalSteps: Int { TelemetryMeterMath.thermalLit(level: system.pressureLevel) }

    /// Quantized bake fingerprint — cell counts + state enums only.
    private var meterKey: Int {
        var h = Hasher()
        h.combine(cpuFill)
        h.combine(cpuMaxCell)
        h.combine(system.tickCpuMeanUs > system.tickBudgetUs)
        h.combine(system.v21Buffer)
        h.combine(thermalSteps)
        return h.finalize()
    }

    private var v21Label: String {
        switch system.v21Buffer {
        case .none: return "OFF"
        case .allocated: return "ALLOC"
        case .held: return "HELD"
        case .freed: return "FREED"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GlobalLattice.pt(2)) {
            // Tick CPU: mean fill vs the 50 ms budget; the worst tick is the
            // single bright marker cell; over-budget flips the fill to alert ink.
            HStack(spacing: GlobalLattice.pt(2)) {
                CellText("CPU \(cpuMeanMs)")
                Self.image(baked.cpuBar, cols: Self.cpuBarSub, rows: 4)
            }
            // v21 hist buffer (the ~384 MiB the memory audit watches): state cell
            // + word — allocated (solid) / held (checker) / freed (outline) / off.
            HStack(spacing: GlobalLattice.pt(2)) {
                CellText("V21")
                Self.image(baked.v21, cols: 8, rows: 8)
                CellText(v21Label, rows: 5)
            }
            // Thermal/system pressure: a 5-step strip, green → yellow → red.
            HStack(spacing: GlobalLattice.pt(2)) {
                CellText("HEAT")
                Self.image(baked.thermal, cols: 38, rows: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: meterKey, initial: true) { _, _ in rebake() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "System: tick CPU \(cpuMeanMs) of \(system.tickBudgetUs / 1000) milliseconds, "
            + "buffer \(v21Label), pressure level \(max(0, system.pressureLevel))")
    }

    @ViewBuilder
    private static func image(_ img: UIImage?, cols: Int, rows: Int) -> some View {
        if let img {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: GlobalLattice.pt(cols), height: GlobalLattice.pt(rows))
        }
    }

    private func rebake() {
        // CPU: mean fill (ok ink; alert once the MEAN busts the budget) + the
        // worst-tick marker cell (bright; alert when the worst tick busts it).
        let fill = cpuFill
        let maxCell = cpuMaxCell
        let meanOver = system.tickCpuMeanUs > system.tickBudgetUs
        let maxOver = system.tickCpuMaxUs > system.tickBudgetUs
        baked.cpuBar = CellBitmap.image(cols: Self.cpuBarSub, rows: 4) { c, _ in
            if maxCell > 0 && c == maxCell - 1 {
                return maxOver ? TelemetryInk.alert : TelemetryInk.lit
            }
            return c < fill ? (meanOver ? TelemetryInk.alert : TelemetryInk.ok)
                            : TelemetryInk.ghost
        }

        // v21 lifecycle state cell: solid = accumulating, 2×2 checker = held by
        // the detached flow job (the no-opacity dim idiom), outline = freed.
        let state = system.v21Buffer
        baked.v21 = CellBitmap.image(cols: 8, rows: 8) { c, r in
            switch state {
            case .none:
                return TelemetryInk.ghost
            case .allocated:
                return TelemetryInk.lit
            case .held:
                return ((c / 2) + (r / 2)) % 2 == 0 ? TelemetryInk.lit : TelemetryInk.ghost
            case .freed:
                let border = c == 0 || r == 0 || c == 7 || r == 7
                return border ? TelemetryInk.dim : nil
            }
        }

        // Thermal strip: 5 blocks of 6 sub-cells with 2-sub gaps (38 total).
        let lit = thermalSteps
        baked.thermal = CellBitmap.image(cols: 38, rows: 6) { c, _ in
            let block = c / 8
            guard block < 5, c % 8 < 6 else { return nil }   // the gaps
            guard block < lit else { return TelemetryInk.ghost }
            if block <= 1 { return TelemetryInk.ok }
            return block == 2 ? TelemetryInk.warn : TelemetryInk.alert
        }
    }
}

#if DEBUG
/// Canvas check with no camera — a synthetic derived-mode snapshot + machine ring.
#Preview("Rung telemetry flanks (derived mode)") {
    ZStack(alignment: .topLeading) {
        Color.black.ignoresSafeArea()
        RungTelemetryFlanks(
            telemetry: RungTelemetry.derived(ticks: 37, fineBinArea: 3000, generation: 1),
            system: SystemTelemetry(tickCpuMeanUs: 9000, tickCpuMaxUs: 31000, tickCount: 37,
                                    tickBudgetUs: 50000, v21Buffer: .allocated, pressureLevel: 1))
    }
    .frame(width: 400, height: 872)
}
#endif
