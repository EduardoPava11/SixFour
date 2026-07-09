import SwiftUI
import UIKit
import simd

/// THE INSTRUMENT RAILS (THE DESIGN E5) — the two ground gestures are the user's creative
/// instruments, and a live gesture MATERIALIZES its rail (the control face of a gesture).
/// Both are DISPLAY-ONLY overlays (`allowsHitTesting(false)` at the mount): the gesture
/// itself stays on the existing clear ground layer (`lookSwipeAndExposureDrag` untouched).
/// Idle, each rail collapses to a 3-cell ghost notch spine — nearly nothing, but the
/// surface admits the instruments exist. All states are opaque ink transforms; all timing
/// derives from the ONE 20 Hz `SurfaceClock.tick`; every bake is fingerprint-cached.

// MARK: - EV RAIL (vertical drag — the exposure instrument)

/// The left-edge EV rail (`liveScene.evRail`, 2 × 26 cells): one 2×2 detent block per
/// ⅓ stop, ±2 EV ⇒ 13 detents, centre = 0 EV. The current detent is LIT (control ink);
/// the centre is ghost. Materializes outward from the centre 1 block/tick (≤6 ticks)
/// while the drag is live; dematerializes 8 ticks after release. The frame-locked
/// `.cellDetent` fires one felt tick per ⅓-stop crossing.
struct EVRail: View {
    /// The current exposure bias in EV (engine-clamped ±2).
    let bias: Float
    /// True while a vertical EV drag is in flight.
    let active: Bool
    /// The ONE clock.
    let tick: Int

    /// 0 (not Int.min) so the first body evaluation of a fresh drag can never overflow
    /// `tick - activeSince`; the worst case is an instantly-full radius for one tick.
    @State private var activeSince = 0
    @State private var releasedAt = Int.min
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    /// The current detent index −6…+6 (⅓-stop steps).
    private var detent: Int { max(-6, min(6, Int((bias * 3).rounded()))) }

    var body: some View {
        // Materialize radius: blocks within `radius` detents of centre are visible.
        let radius = active ? min(6, max(0, tick - activeSince)) : 6
        let visible = active || tick < releasedAt + 8
        let key = visible ? (radius * 64 + (detent + 6) + 4096) : Int.min + 1
        Group {
            if let img = baked.image {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: GlobalLattice.gif(2), height: GlobalLattice.gif(26))
        .onChange(of: active, initial: false) { _, on in
            if on { activeSince = tick } else { releasedAt = tick }
        }
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            baked = (k, Self.bake(visible: visible, radius: radius, detent: detent))
        }
        // One felt cellTick per ⅓-stop crossing, coalesced to the 20 fps frame.
        .cellDetent(tick: tick, every: 1,
                    position: { active ? (col: 0, row: detent) : nil })
        .accessibilityHidden(true)
    }

    /// Bake the 2×26 rail. Hidden ⇒ the 3-cell ghost notch spine (idle discoverability).
    /// Visible ⇒ one 2×2 block per detent inside the materialize radius: current = lit,
    /// centre = ghost, others = the far-dark ink (present but calm).
    private static func bake(visible: Bool, radius: Int, detent: Int) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        let calm = SIMD3<UInt8>(ghost.x / 2, ghost.y / 2, ghost.z / 2)
        return CellBitmap.image(cols: 2, rows: 26) { _, r in
            guard visible else {
                // Idle notch spine: 3 ghost cells at the rail's centre rows.
                return (r >= 12 && r <= 14) ? ghost : nil
            }
            // Row → detent: +6 EV block at rows 0–1 … −6 at rows 24–25.
            let d = 6 - (r / 2)
            guard abs(d) <= radius else { return nil }        // not yet materialized
            if d == detent { return lit }
            if d == 0 { return ghost }
            return calm
        }
    }
}

// MARK: - LOOK STRIP (horizontal swipe — the grade instrument)

/// The LOOK strip above the 64² (`liveScene.lookStrip`, 64 × 4 cells): one 4×4-cell
/// swatch per look — that look's OKLab grade applied to a fixed 4-colour probe, baked
/// once per look — with the active (or swipe-tentative) look wearing the 1-cell FRAME in
/// control ink. Materializes while a horizontal swipe is live; lingers 20 ticks after a
/// commit; idle ⇒ the 3-cell ghost notch. This carries the retired palette widget's one
/// defensible function (LOOK indicator) — the grade shown ON colours, without a
/// flickering rebake (E10).
struct LookStrip: View {
    /// The committed look (`settings.captureLook`).
    let look: LookVariant
    /// The tentative look the in-flight swipe would commit (frames it), or nil.
    let preview: LookVariant?
    /// True while a horizontal LOOK swipe is in flight.
    let dragging: Bool
    /// The ONE clock.
    let tick: Int

    @State private var committedAt = Int.min
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    /// The fixed 4-colour probe every look grades: warm skin / sky / foliage / neutral.
    /// Graded swatches are baked ONCE per look (the kernels run 5 × 4 colours, at init).
    private static let probe: [SIMD3<UInt8>] = [
        SIMD3(224, 168, 132), SIMD3(96, 144, 224), SIMD3(88, 152, 88), SIMD3(160, 160, 160),
    ]
    private static let swatches: [[SIMD3<UInt8>]] =
        LookVariant.allCases.map { $0.apply(to: probe) }

    var body: some View {
        let framed = preview ?? look
        let visible = dragging || tick < committedAt + 20
        let framedIdx = LookVariant.allCases.firstIndex(of: framed) ?? 0
        let key = visible ? framedIdx : -1
        Group {
            if let img = baked.image {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: GlobalLattice.gif(64), height: GlobalLattice.gif(4))
        .onChange(of: look, initial: false) { _, _ in committedAt = tick }
        .onChange(of: key, initial: true) { _, k in
            guard k != baked.key else { return }
            baked = (k, Self.bake(framedIdx: visible ? framedIdx : nil))
        }
        .accessibilityHidden(true)
    }

    /// Bake the 64×4 strip: 5 swatches of 4×4 cells (a 2×2 grid of the graded probe,
    /// 2×2 cells per colour), 2-cell gaps, centred. `framedIdx == nil` ⇒ hidden (the
    /// idle 3-cell ghost notch). The framed swatch's border cells go control ink.
    private static func bake(framedIdx: Int?) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        let n = swatches.count                       // 5 looks
        let strideC = 4 + 2                          // swatch + gap
        let used = n * 4 + (n - 1) * 2               // 28 cells
        let x0 = (64 - used) / 2                     // centred
        return CellBitmap.image(cols: 64, rows: 4) { c, r in
            guard let framedIdx else {
                // Idle notch spine: 3 ghost cells centred on the bottom row.
                return (r == 3 && c >= 31 && c <= 33) ? ghost : nil
            }
            let x = c - x0
            guard x >= 0, x < used else { return nil }
            let slot = x / strideC
            let sx = x % strideC
            guard sx < 4, slot < n else { return nil }          // gap
            // The FRAME: the framed swatch's 1-cell border in control ink.
            if slot == framedIdx, sx == 0 || sx == 3 || r == 0 || r == 3 { return lit }
            // 2×2 probe grid, 2×2 cells per colour.
            let colour = swatches[slot][(r / 2) * 2 + (sx / 2)]
            return colour
        }
    }
}

// MARK: - FLUX BAR (THE DESIGN E6 — the single-number wave meter)

/// The 16×1 flux bar under the shutter (`liveScene.fluxBar`): the palette-W1 impulse
/// between CONSECUTIVE ≤ 5 Hz GCTs — `s4_v21_wdist1d`, the byte-exact 1-D Wasserstein
/// ground-distance metric (`Spec.V21Field.paletteW1`, the ColorMomentum FLUX band) —
/// quantized to lit cells by the log₂ `ColorTimeDisplayMath.fluxFillCount`
/// (`lawFluxMonotoneBounded`). Sampled ONLY at the mod-4 realize tick on the ONE
/// clock (the same 16-rung cadence the GCT lands at), and the kernel runs only when
/// a FRESH GCT arrived — never per tick, never per publish. All-ghost until two
/// distinct GCTs have landed (the instrument admits it has no signal — `latestGCT`
/// nil or single). Fingerprint-cached bake: an unchanged fill never rebakes.
struct FluxBar: View {
    /// The latest 768-byte GCT (256 slots × RGB, σ.latestGCT) — nil until a head realizes one.
    let gct: [UInt8]?
    /// THE ONE clock.
    let tick: Int

    /// The previous sampled GCT — the other end of the consecutive-pair difference.
    @State private var lastGCT: [UInt8]? = nil
    /// Lit cells 0…16; -1 = no signal yet (the all-ghost face).
    @State private var fill = -1
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    var body: some View {
        Group {
            if let img = baked.image {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: GlobalLattice.gif(16), height: GlobalLattice.gif(1))
        .onChange(of: tick) { _, t in
            guard ColorTimeDisplayMath.realizesAt(period: 4, tick: t) else { return }
            sample()
        }
        .onChange(of: fill, initial: true) { _, f in
            guard f != baked.key else { return }
            baked = (f, Self.bake(fill: f))
        }
        .accessibilityHidden(true)
    }

    /// One 5 Hz sample: difference the fresh GCT against the last one through the
    /// owned kernel. An unchanged (or absent) GCT holds the reading — no fake decay.
    private func sample() {
        guard let g = gct, g.count == 768 else { return }
        defer { lastGCT = g }
        guard let prev = lastGCT, prev != g else { return }
        guard let w1 = Self.paletteW1(prev, g) else { return }
        fill = ColorTimeDisplayMath.fluxFillCount(w1)
    }

    /// The palette-W1 impulse between two 768-byte GCTs via `s4_v21_wdist1d`
    /// (256 slots × 3 channels, 256 levels). nil on a kernel refusal — pure,
    /// unit-tested in `ColorTimeDisplayMathTests`.
    static func paletteW1(_ a: [UInt8], _ b: [UInt8]) -> Int? {
        guard a.count == 768, b.count == 768 else { return nil }
        var wd: Int32 = 0
        let rc = a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                s4_v21_wdist1d(pa.baseAddress, pb.baseAddress, 256, 256, &wd)
            }
        }
        guard rc == 0 else { return nil }
        return Int(wd)
    }

    /// Bake the 16×1 face: `fill` lit cells in control ink, the rest ghost;
    /// -1 (no signal) is the honest all-ghost rail.
    private static func bake(fill: Int) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        return CellBitmap.image(cols: 16, rows: 1) { c, _ in
            c < fill ? lit : ghost
        }
    }
}
