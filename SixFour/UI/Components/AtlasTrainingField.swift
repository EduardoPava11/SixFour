import SwiftUI
import simd

/// COLOR ATLAS — the on-device training instrument (the VISIBLE flywheel).
///
/// Renders `AtlasTrainingSession` in pure GRID vocabulary (`CellSprite` /
/// `CellText` / `CellActionButton` at `GlobalLattice` pitches — no glass, no AA,
/// no raw vectors), mounted inside the flag-gated atlas curation sub-state:
///
///   * LOSS SPARKLINE — a 64-column cell strip (the paletteStrip idiom), one
///     column per recorded step (latest 64, right-aligned), column height =
///     loss normalised to the window max, latest column lit white;
///   * READOUTS — monospaced step count, latest loss, ms/step, and
///     V(A) vs V(B) for the current Compare candidates, higher one marked ▲;
///   * TRAIN/PAUSE — one `CellActionButton`; plus the STRETCH saliency sweep
///     (ΔV per ToggleBin, batched forward passes) rendered as a 16×16 slice
///     following the board's L-slice scrubber (green = killing the bin RAISES
///     V, red = lowers);
///   * SIMULATOR — `AtlasTrainer.isSupported` is false there, so the widget
///     renders a clearly-labeled inert state and never calls into MPSGraph.
struct AtlasTrainingField: View {
    @Bindable var atlas: AtlasState
    @Bindable var session: AtlasTrainingSession

    /// Sparkline geometry: 64 step columns × 12 rows at the GIF atom — the same
    /// 256 pt width as the board block above it.
    private let sparkCols = 64
    private let sparkRows = 12

    private let accent = SIMD3<UInt8>(96, 165, 250)
    private let dimInk = Color(srgb8: SIMD3<UInt8>(140, 140, 140))
    private let liveInk = Color(srgb8: SIMD3<UInt8>(200, 200, 200))

    var body: some View {
        VStack(spacing: GlobalLattice.pt(2)) {
            CellText(headerLine, rows: 8, ink: liveInk)

            if AtlasTrainingSession.isSupported {
                sparkline
                CellText(stepLine, rows: 8, ink: liveInk)
                CellText(valueLine, rows: 8, ink: liveInk)
                CellText(sourceLine, rows: 6, ink: dimInk)
                controlRow
                if session.saliency != nil { saliencyRow }
            } else {
                // The simulator has no MPSGraph execution device (measured fact,
                // AtlasTrainer.isSupported) — render the labeled inert state.
                CellText("SIMULATOR · MPSGRAPH UNAVAILABLE", rows: 8, ink: dimInk)
                CellText("TRAINING RUNS ON DEVICE ONLY", rows: 6, ink: dimInk)
                CellActionButton(icon: .none, title: "TRAIN")
                    .accessibilityHidden(true)   // inert: no Button wrapper at all
            }
        }
    }

    // MARK: header + readouts (monospaced via CellText's raster)

    private var headerLine: String {
        let state = session.running ? "RUNNING"
            : (session.prepared ? "PAUSED" : "IDLE")
        return "TRAIN · VALUE NET · \(state)"
    }

    private var stepLine: String {
        let loss = session.latestLoss.map { String(format: "%.4f", $0) } ?? "—"
        let ms = session.latestMsPerStep.map { String(format: "%.1f", $0) } ?? "—"
        return String(format: "STEP %05d · LOSS %@ · %@MS", session.currentStep, loss, ms)
    }

    private var valueLine: String {
        guard let a = session.valueA, let b = session.valueB else {
            return "V·A — · V·B —"
        }
        let markA = a >= b ? "▲" : " "
        let markB = b > a ? "▲" : " "
        return String(format: "V·A %+.3f%@ · V·B %+.3f%@", a, markA, b, markB)
    }

    private var sourceLine: String {
        switch session.dataSource {
        case .none:
            let n = atlas.log.compareCount
            return n >= AtlasTrainingSession.minimumLogPairs
                ? "DATA · LOG \(n) PAIRS READY"
                : "DATA · \(n)/\(AtlasTrainingSession.minimumLogPairs) PAIRS — SYNTH FALLBACK"
        case .decisionLog(let pairs):
            return "DATA · DECISION LOG · \(pairs) PAIRS"
        case .synthetic(let pairs):
            return "DATA · SYNTHETIC · \(pairs) PAIRS (LOG < \(AtlasTrainingSession.minimumLogPairs))"
        case .blockedByKillSwitch(let pairs):
            return "DATA · KILL-SWITCH · \(pairs) LOG PAIRS REJECTED (NO SIGNAL) → SYNTH"
        }
    }

    // MARK: the loss sparkline (one cell column per step, right-aligned)

    private var sparkline: some View {
        let window = Array(session.telemetry.chronological.suffix(sparkCols))
        let maxLoss = max(window.map(\.loss).max() ?? 0, 0.0001)
        let offset = sparkCols - window.count
        let ghost = SFTheme.ledGhost
        let rows = sparkRows
        return CellSprite(cols: sparkCols, rows: rows, cellPt: GlobalLattice.gifPx) { c, r in
            guard c >= offset else {
                // No step recorded for this column yet: baseline ghost only.
                return r == rows - 1 ? ghost : nil
            }
            let step = window[c - offset]
            let frac = max(0, min(1, step.loss / maxLoss))
            let height = max(1, Int((CGFloat(frac) * CGFloat(rows)).rounded(.up)))
            guard r >= rows - height else { return nil }
            let isLatest = c - offset == window.count - 1
            return isLatest ? SIMD3<UInt8>(255, 255, 255) : accent
        }
        .accessibilityLabel("Loss sparkline, latest \(window.count) steps")
    }

    // MARK: controls

    private var controlRow: some View {
        HStack(spacing: GlobalLattice.pt(2)) {
            Button { session.toggle(with: atlas) } label: {
                CellActionButton(icon: .none,
                                 title: session.running ? "PAUSE" : "TRAIN",
                                 prominent: session.running)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.running ? "Pause training" : "Start training")

            // STRETCH — the ΔV sweep (enabled once the graph is live; the busy
            // state is a cell transform of the label, never opacity).
            Button { session.sweep(with: atlas) } label: {
                CellActionButton(icon: .none,
                                 title: session.sweeping ? "SWEEP…" : "SWEEP ΔV")
            }
            .buttonStyle(.plain)
            .disabled(!session.prepared || session.sweeping)
            .accessibilityLabel("Sweep value sensitivity")
        }
    }

    // MARK: saliency overlay (16×16 slice at the board's L scrubber)

    private var saliencyRow: some View {
        HStack(spacing: GlobalLattice.pt(3)) {
            saliencySlice
            CellText(String(format: "ΔV · L %02d", atlas.slice), rows: 6, ink: dimInk)
        }
    }

    /// The current L-slice of the ΔV field: green = killing the bin raises
    /// V(picked candidate), red = lowers it; intensity ∝ |ΔV| / max|ΔV|.
    private var saliencySlice: some View {
        let field = session.saliency ?? []
        let n = AtlasBinIdx.perAxis
        let slice = atlas.slice
        let maxAbs = max(field.map { abs($0) }.max() ?? 0, Float.ulpOfOne)
        return CellSprite(cols: n, rows: n, cellPt: GlobalLattice.gifPx) { c, r in
            let bin = AtlasBinIdx(l: slice, a: c, b: r)
            guard bin.flat < field.count else { return SIMD3<UInt8>(14, 14, 16) }
            let dv = field[bin.flat]
            let t = abs(dv) / maxAbs
            let lum = UInt8(24 + min(231, Int((t * 231).rounded())))
            if dv > 0 { return SIMD3<UInt8>(12, lum, 40) }    // kill raises V
            if dv < 0 { return SIMD3<UInt8>(lum, 24, 24) }    // kill lowers V
            return SIMD3<UInt8>(14, 14, 16)
        }
        .accessibilityLabel("Value sensitivity slice \(slice)")
    }
}
