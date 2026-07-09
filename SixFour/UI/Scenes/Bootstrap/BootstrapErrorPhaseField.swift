import SwiftUI
import UIKit
import simd

/// Π — the per-phase cell-field renderers for the *non-instrument* lifecycle phases:
/// `bootstrap`, `unauthorized`, and `error`. These are the phases where there is no
/// live camera / GIF surface to paint, only a status field. Each is a CELL REGION on
/// the one surface (`SixFour.Spec.Display.lawPhaseIsCellGrid`), NOT a screen — they are
/// reached by `surfaceStep` flipping σ.phase, and `PhaseField.field(for:_:_:)` routes
/// to them. A phase change is a cell update, never a view swap.
///
/// Ported from `Screens/State/StateScreens.swift` (BootstrapSkeleton / UnauthorizedView
/// / FailureView), with the GRID cell-only law applied: every glyph is a `CellSymbol`,
/// every word is `CellText`, the buttons are `CellActionButton`-style flat cell grounds,
/// and the bootstrap pulse is driven by the ONE κ clock's `tick` (no private
/// `withAnimation`/`Timer`). No `Text`, no glass, no SF-Symbol-as-chrome, no UIKit
/// `Slider`/`Picker`.
///
/// Tier-2: SwiftUI + UIKit + simd only.

// MARK: - bootstrap

/// `bootstrap` — the pre-session skeleton. A single square cell region at screen centre
/// breathes between two ink levels, paced by κ (`clock.tick`) so it shares the one 20 fps
/// heartbeat instead of spawning its own animation. A status word sits below it.
struct BootstrapPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    /// A slow triangle wave 0…1 over the κ tick (period ≈ 2 s at 20 fps), so the pulse
    /// reads as a calm breath, not a strobe. Pinned to mid when reduce-motion holds the
    /// heartbeat (the field still draws, just static).
    private var breath: Double {
        if clock.reduceMotion { return 0.5 }
        let period = 40                                  // 2 s at logicRateHz = 20
        let p = clock.tick % period
        let up = Double(p) / Double(period / 2)
        return p < period / 2 ? up : 2 - up              // 0→1→0 triangle
    }

    var body: some View {
        // Floor/ceiling raised so the breathing square is a clearly-visible mid-gray the moment the
        // bootstrap field paints (at tick 0 breath=0, so lo IS the launch value) — an unmistakable
        // non-white "alive launch" indicator on the black ground, not the near-black 10..26 it was.
        let lo = 40.0, hi = 64.0
        let v = UInt8(lo + (hi - lo) * breath)
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: GlobalLattice.pt(6)) {
                // The breathing square — a flat cell ground, square corners (GRID Law #2).
                Color(srgb8: SIMD3(v, v, v))
                    .frame(width: GlobalLattice.gif(GlobalLattice.previewCells),
                           height: GlobalLattice.gif(GlobalLattice.previewCells))
                CellText("CONFIGURING CAMERA", rows: 8, ink: Color(srgb8: SIMD3(150, 150, 150)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Configuring the camera")
    }
}

// MARK: - unauthorized

/// `unauthorized` — camera access denied. A cell-rendered camera-deny glyph, the title +
/// prose (as `CellText`, not `Text`), and an Open-Settings cell button that deep-links to
/// iOS Settings so the user can grant access. This is a terminal field in the FSM (no
/// recovery event); the deep link is the only action.
struct UnauthorizedPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: GlobalLattice.pt(9)) {
                CellSymbol(systemName: "camera.metering.unknown",
                           box: 28, ink: Color(srgb8: SIMD3(180, 180, 180)))
                CellText("CAMERA ACCESS DENIED", rows: 11, ink: .white)

                // Prose as CELLS (GRID §6.8 cell-only law) — fixed short lines, not wrapped.
                VStack(spacing: GlobalLattice.pt(2)) {
                    CellText("SIXFOUR NEEDS THE CAMERA", rows: 8,
                             ink: Color(srgb8: SIMD3(170, 170, 170)))
                    CellText("TO CAPTURE 64 FRAMES INTO", rows: 8,
                             ink: Color(srgb8: SIMD3(170, 170, 170)))
                    CellText("A 64x64 GIF. ENABLE IT IN", rows: 8,
                             ink: Color(srgb8: SIMD3(170, 170, 170)))
                    CellText("SETTINGS TO CONTINUE.", rows: 8,
                             ink: Color(srgb8: SIMD3(170, 170, 170)))
                }

                Button { openSettings() } label: {
                    CellActionButton(icon: .none, title: "OPEN SETTINGS",
                                     prominent: false, fillWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Settings")
            }
            .padding(.horizontal, GlobalLattice.pt(8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - error

/// `error` — a fault dropped the surface here (`surfaceStep`: `.fault` from any phase →
/// `.error`). A warning glyph + the fault token (read from σ) + a Try-Again cell button.
/// Recovery is the MODELLED `.retake` edge (Spec.ABSurface: Error joins the Retake bail
/// list → `.live`); the `.live` phase change also fires `engine.reset()` in SurfaceView,
/// so the capture engine restarts with the surface. The button only emits an event; it
/// never reaches around σ.
struct ErrorPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: GlobalLattice.pt(9)) {
                CellSymbol(systemName: "exclamationmark.triangle",
                           box: 24, ink: Color(srgb8: SIMD3(225, 200, 70)))
                CellText("SOMETHING WENT WRONG", rows: 11, ink: .white)
                // Show WHICH step faulted (σ.faultMessage, set by SurfaceView from the engine's
                // .failed(reason)) as fixed-width cell lines — a readable on-screen diagnostic
                // instead of a blind fault. Falls back to the generic line when no token is set.
                VStack(spacing: GlobalLattice.pt(2)) {
                    ForEach(Array(Self.faultLines(surface.faultMessage).enumerated()), id: \.offset) { _, line in
                        CellText(line, rows: 8, ink: Color(srgb8: SIMD3(190, 190, 190)))
                    }
                }

                Button { surface.step(.retake) } label: {
                    CellActionButton(icon: .none, title: "TRY AGAIN",
                                     prominent: true, fillWidth: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Try again")
            }
            .padding(.horizontal, GlobalLattice.pt(8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Turn the raw fault token (σ.faultMessage) into fixed-width UPPERCASE cell lines the
    /// CellText raster can draw without overflowing the screen. Collapses whitespace, caps the
    /// total length, and hard-wraps at `width` chars into at most `maxLines`. Falls back to the
    /// generic line when there is no token. Pure — a function of the message only.
    static func faultLines(_ message: String?, width: Int = 22, maxLines: Int = 3) -> [String] {
        let raw = (message ?? "").uppercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let collapsed = raw.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        guard !collapsed.isEmpty else { return ["THE SURFACE HIT A FAULT."] }
        let capped = String(collapsed.prefix(width * maxLines))
        var lines: [String] = []
        var i = capped.startIndex
        while i < capped.endIndex && lines.count < maxLines {
            let j = capped.index(i, offsetBy: width, limitedBy: capped.endIndex) ?? capped.endIndex
            lines.append(String(capped[i..<j]))
            i = j
        }
        return lines
    }
}
