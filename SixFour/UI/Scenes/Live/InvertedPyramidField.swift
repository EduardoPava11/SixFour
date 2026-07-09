import SwiftUI
import Foundation
import UIKit
import simd

/// THE LIVE CAPTURE FACE — the inverted-pyramid three-view, at HONEST CADENCE.
///
/// The user opens the phone and sees the world at all THREE granularities of the isotropic
/// 2×2×2 ladder at once: 64² (top, widest), 32² (middle), 16² (the point). The 16² vertex
/// IS the shutter — tapping it fires the 64-frame burst. Tapping the 64² meters that point.
///
/// THE PROPOSITION (docs/UI-FORM-FOLLOWS-FUNCTION.md D0/E1/E2/E7): the coarse rungs are TRUE
/// TEMPORAL INTEGRALS refreshing at the ladder's real cadences — one 16² frame integrates
/// the ENTIRE light of FOUR consecutive 64² frames (same total photons, coarser space, 4×
/// the time; `Spec.ColorTimeDisplay`, cadences 64@20 Hz / 32@10 Hz / 16@5 Hz):
///   * every publish pools the 64² into u64 SUM accumulators (sums are the transitive
///     carrier; means never compose — ONE divide at the display boundary);
///   * the 32² realizes (whole-tile swap) on tick ≡ 0 (mod 2), the 16² on tick ≡ 0 (mod 4)
///     — crisp swaps at the rung's native cadence; motion smear in the 16² is the LESSON;
///   * INTAKE TALLIES in the pyramid's own gutters make the pour COUNTABLE — 2 slots over
///     the 32², 4 over the 16² (`lawTallyEqualsUnits`), each tick inks one slot with that
///     frame's DC (the ColorMomentum MASS band); on the realize tick the filled slots flash
///     and pour into the coarse swap, at 5 Hz, forever;
///   * during the burst the 16² becomes the BANKED LEDGER — landed frame n permanently owns
///     raster cells 4(n−1)…4n−1 (64 × 4 = 256, `lawLedgerConserves`), so the finished tile
///     is a genuine time-woven image, each 4-cell strip sampled 5 cs apart.
///
/// THE CONTROL LANGUAGE (D1/E3): the shutter wears BRACKETS (`ControlBrackets`) in the
/// gutter outside the tile — idle beats lit for 1 tick on every 16-rung realize (the
/// affordance and the cadence teacher are one element), pressed inverts, busy is red,
/// disabled is the checker. The bracket rect is the hit rect (20 cells = 80 pt).
///
/// All timing derives from the ONE 20 Hz `SurfaceClock.tick` (`ColorTimeDisplayMath`, the
/// Swift twin of `Spec.ColorTimeDisplay`). All bakes are @State-cached and keyed by content;
/// a tick where nothing steps rebakes nothing.
struct InvertedPyramidField: View {
    /// The live 64×64 index tile (`surface.previewTile`): one palette index per GIF pixel.
    let tile64: [UInt8]
    /// The 256-colour palette those indices resolve through (`surface.previewPalette`).
    let palette: [SIMD3<UInt8>]

    /// LIVE-LADDER (Feature.liveLadder): the REAL device ladder rungs realized to sRGB8 by
    /// the preview `ColorHead`. When present they are ADOPTED at the same mod-2 / mod-4
    /// realize gating as the in-view accumulators (E1) — the cadence law holds either way.
    /// IDLE-ONLY: the preview head does not run during a burst, so while a stage is
    /// active the banked accumulators own the realize (the tiles would be stale).
    var tile32: [SIMD3<UInt8>] = []
    var tile16: [SIMD3<UInt8>] = []
    var useLiveLadder: Bool = false

    /// OPTICAL-EV (Feature.opticalEV): three REAL exposures, one per tile, already realized
    /// to sRGB8. Takes precedence over live-ladder / in-view when all three are present —
    /// WHILE IDLE only (the exposure driver pauses during a burst; E7 streams instead),
    /// and rebaked only when the optical content itself changes (fingerprinted).
    var opticalTile64: [SIMD3<UInt8>] = []
    var opticalTile32: [SIMD3<UInt8>] = []
    var opticalTile16: [SIMD3<UInt8>] = []
    var useOptical: Bool = false

    /// Per-tile DIGITAL exposure in STOPS (display gain). Coarse rungs lift a touch,
    /// matching "more colour-time ⇒ can carry the brighter exposure".
    var ev64: Float = 0
    var ev32: Float = 0.5
    var ev16: Float = 1.0

    /// Whether an engine stage is running (lock/burst/refine/encode) — the 16² then shows
    /// the banked ledger and the brackets go BUSY.
    var stageActive: Bool = false
    /// EXACT banked frames (never float progress): 0…64 landed burst frames; render
    /// stages pass 64 (the whole window is banked). `Spec.ColorTimeDisplay.ledgerFillCount`.
    var landedFrames: Int = 0
    /// Whether a tap on the 16² should fire (`phase == .live && !stage.active`).
    var shutterEnabled: Bool = true
    /// THE ONE CLOCK — `SurfaceClock.tick` (20 Hz). Drives the realize gating, the intake
    /// tallies, the bracket BEAT, and the meter-crosshair linger. No second timer exists.
    var tick: Int = 0
    /// Reduce-motion (`SurfaceClock.reduceMotion`): pins the shutter brackets' idle
    /// BEAT off (D1 — no 5 Hz strobe for reduce-motion users). The realize cadence
    /// itself is content, not decoration, and keeps running.
    var reduceMotion: Bool = false

    /// Fired by a tap on the 16² vertex — the shutter kick (`engine.capture()`).
    var onShutter: () -> Void = {}
    /// Fired by a tap on the 64² — one-shot meter that point (normalized 0..1 over the tile).
    var onMeter64: (CGPoint) -> Void = { _ in }

    /// Every bake lives in @State keyed by the actual inputs (the PERF discipline,
    /// docs/PERF-MAP.md): a publish accumulates + rebakes ONLY the 64²; a realize tick
    /// swaps ONLY the rung whose cadence fired; the tallies are one ≤64-cell bake per
    /// tick; the brackets rebake once per treatment change.
    @State private var baked = Baked()

    private struct Baked {
        var img64: UIImage?
        var img32: UIImage?
        var img16: UIImage?
        /// The 16²'s gain-applied base colours at its LAST REALIZE — the ledger and the
        /// shutter bake read these without re-pooling the pyramid.
        var base16: [SIMD3<UInt8>] = []

        // E1 — the temporal-integral accumulators (u64 sums; ONE divide at realize).
        var acc32 = [UInt64](repeating: 0, count: 32 * 32 * 3)
        var acc16 = [UInt64](repeating: 0, count: 16 * 16 * 3)
        var frames32 = 0
        var frames16 = 0

        /// The last published 64² sums — kept so the meter crosshair / its expiry can
        /// rebake the 64² without waiting for the next publish.
        var lastS64: [UInt64] = []

        // E2 — the intake tallies (slot colours = each tick's frame DC / mass band).
        var tallyDC = SIMD3<UInt8>(0, 0, 0)
        var slots32: [SIMD3<UInt8>?] = [nil, nil]
        var slots16: [SIMD3<UInt8>?] = [nil, nil, nil, nil]
        var intake32Img: UIImage?
        var intake16Img: UIImage?
        var intake32Key = 0
        var intake16Key = 0

        // E7 — the banked capture ledger (permanent per-frame 4-cell strips).
        var ledger = [SIMD3<UInt8>](repeating: .init(0, 0, 0), count: 256)
        var ledgerFilled = 0

        // OPTICAL-EV — the fingerprint of the last optical bake (0 = none) and whether
        // the 64² currently shows the optical base exposure (drives `rebake64`'s source).
        var opticalKey = 0
        var opticalDisplay = false

        // E4 — the meter crosshair (inverted 3×3 cross, 20-tick linger).
        var meterCell: (col: Int, row: Int)?
        var meterSince = Int.min

        // E3 — pressed state (brackets + tile invert for 2 ticks).
        var pressedUntil = Int.min
    }

    /// One fingerprint over every input that changes the PIXELS. Hashing ~20 KB per body
    /// evaluation is microseconds; it is what lets a tick-only evaluation skip the pyramid.
    private var pixelKey: Int {
        var h = Hasher()
        h.combine(tile64); h.combine(palette)
        h.combine(tile32); h.combine(tile16); h.combine(useLiveLadder)
        h.combine(opticalTile64); h.combine(opticalTile32); h.combine(opticalTile16)
        h.combine(useOptical)
        h.combine(ev64); h.combine(ev32); h.combine(ev16)
        return h.finalize()
    }

    /// The ledger key: −1 when idle, else the EXACT landed-frame count (never a float).
    private var shutterKey: Int { stageActive ? min(64, max(0, landedFrames)) : -1 }

    /// The shutter's control-state ordinal (`SixFourCellMechanics.controlStates`):
    /// busy while a stage runs; pressed for 2 ticks after the tap; disabled when the
    /// surface won't fire; else idle (whose face carries the BEAT).
    private var controlState: Int {
        if stageActive { return 2 }                      // busy
        if tick < baked.pressedUntil { return 1 }        // pressed
        if !shutterEnabled { return 3 }                  // disabled
        return 0                                         // idle (BEAT)
    }

    /// THE STACK'S STRUCTURAL ROW OFFSETS from its top — these MUST mirror the body's
    /// VStack (64² + 1-row gutter + intake32 + 1-row gutter + 32² + intake16 + the
    /// 2-row bracket gutter + 16²). `ColorTimeDisplayMathTests` pins `contractTopRow`
    /// + these offsets to the spec-proven `liveScene` field64/intake32/field32/
    /// intake16/field16 regions, so any stack growth that would drift the render off
    /// the proven rows fails loudly instead of silently (the 2026-07-08 regression:
    /// center-derived placement drifted ONE row when the stack grew 120 → 122 rows).
    enum StackRows {
        /// The 1-row gutters above/below the intake32 rail.
        static let gutter = 1
        /// The bracket footprint inset: `gutterCells + 1` bracket ring rows above the 16².
        static let bracketInset = 2
        static let field64 = 0
        static let intake32 = field64 + 64 + gutter
        static let field32 = intake32 + 2 + gutter
        static let intake16 = field32 + 32
        static let field16 = intake16 + 2 + bracketInset
        /// Total height including the bracket ring below the 16².
        static let total = field16 + 16 + bracketInset
    }

    /// The pyramid's pinned top row — the spec-proven `field64` region row (49). The
    /// stack is TOP-PINNED here, never center-derived: centering re-derives the top
    /// from the stack height, so any growth silently drifts every band off the
    /// contract rows the flanks/rails/influence anchors are proven against.
    static let contractTopRow: Int =
        GridLayoutContract.region("field64", in: GridLayoutContract.liveScene)?.row ?? 49

    var body: some View {
        let atom = GlobalLattice.gif(1)   // the ONE 4 pt cell atom (cube law: 1 GIF px/cell)

        // Wide top → point bottom; the funnel is the pooling factor drawn to scale. The
        // gutters carry the intake tallies, so alignment is structural (the spec-proven
        // liveScene bands — field64 49–112, intake32 114–115, field32 117–148,
        // intake16 149–150, field16 153–168 — ARE this stack at the pinned top row).
        VStack(spacing: 0) {
            // 64² — the finest view, repainting every tick (20 Hz); tap to meter (E4).
            Self.spriteImage(baked.img64, side: 64, cellPt: atom)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    let side = atom * 64
                    let nx = min(max(value.location.x / side, 0), 1)
                    let ny = min(max(value.location.y / side, 0), 1)
                    baked.meterCell = (col: min(63, Int(nx * 64)), row: min(63, Int(ny * 64)))
                    baked.meterSince = tick
                    rebake64()
                    onMeter64(CGPoint(x: nx, y: ny))
                    Haptics.selection()
                })

            Color.clear.frame(width: atom, height: GlobalLattice.gif(1))

            // INTAKE 32 (E2): 2 slots × 15 cells — two fine ticks pour into one 32² swap.
            Self.spriteImage(baked.intake32Img, cols: 32, rows: 2, cellPt: atom)
                .allowsHitTesting(false)

            Color.clear.frame(width: atom, height: GlobalLattice.gif(1))

            // 32² — a TRUE 2-frame integral, realized at 10 Hz (tick ≡ 0 mod 2).
            Self.spriteImage(baked.img32, side: 32, cellPt: atom)
                .allowsHitTesting(false)

            // INTAKE 16 (E2): 4 slots × 3 cells — FOUR fine ticks pour into one 16² swap.
            Self.spriteImage(baked.intake16Img, cols: 16, rows: 2, cellPt: atom)
                .allowsHitTesting(false)

            // 16² — the vertex = the shutter, wearing the D1 BRACKETS (E3). A TRUE 4-frame
            // integral at 5 Hz; during the burst it is the banked weave ledger (E7). The
            // whole 20×20-cell bracket rect is the hit rect (80 pt ≥ the touch floor).
            ZStack {
                ControlBrackets(side: 16, state: controlState, tick: tick,
                                reduceMotion: reduceMotion)
                Self.spriteImage(baked.img16, side: 16, cellPt: atom)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard shutterEnabled else { return }
                baked.pressedUntil = tick + 2
                rebakeShutter()
                onShutter()
            }
            // E7 haptic: ONE frame-locked detent per completed pour group (every 4 landed
            // frames = 16 detents across the burst) — the 4:1 banking rhythm, felt.
            .cellDetent(tick: tick, every: 1,
                        position: { stageActive ? (col: 0, row: landedFrames / 4) : nil })
            .accessibilityLabel(stageActive ? "Working" : "Capture 64-frame burst")
            .accessibilityHint("Tap the coarse view to capture sixty-four frames")
        }
        // TOP-PINNED at the contract row (horizontal centering still matches the
        // proven cols — the 64-wide stack centres to col 18 = field64.col). Padding
        // OUTSIDE the flexible frame insets the canvas by exactly `contractTopRow`
        // rows, so the stack's row 0 IS the field64 region row.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, GlobalLattice.gif(Self.contractTopRow))
        .onChange(of: pixelKey, initial: true) { _, _ in
            ingestPublish()
        }
        .onChange(of: tick) { _, t in
            onTick(t)
        }
        .onChange(of: shutterKey) { _, _ in
            updateLedger()
        }
    }

    /// The cached bitmap at the cell pitch — square tiles.
    @ViewBuilder
    private static func spriteImage(_ img: UIImage?, side: Int, cellPt: CGFloat) -> some View {
        spriteImage(img, cols: side, rows: side, cellPt: cellPt)
    }

    /// The cached bitmap at the cell pitch (nearest-neighbour, no AA, self-framed) —
    /// the `CellSprite` render contract minus the per-evaluation bake. The frame is
    /// reserved even while `img` is nil so the stack never reflows.
    @ViewBuilder
    private static func spriteImage(_ img: UIImage?, cols: Int, rows: Int,
                                    cellPt: CGFloat) -> some View {
        Group {
            if let img {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: cellPt * CGFloat(cols), height: cellPt * CGFloat(rows))
    }

    // MARK: - the publish path (every camera frame: accumulate + repaint the 64²)

    /// One σ publish: repaint the 64² (its cadence is every tick), ADD the frame into the
    /// 32²/16² sum accumulators (E1 — the banking), and ink the current intake-tally slot
    /// with this frame's DC. The coarse tiles are NOT touched here — they swap only on
    /// their realize ticks (`onTick`), which is the whole lesson.
    private func ingestPublish() {
        // OPTICAL-EV takes precedence WHILE IDLE ONLY: three REAL exposures, rendered
        // with NO digital gain. NEVER during a stage — the exposure driver runs only
        // while `collecting == false` (`CaptureSession`), so during lock/burst/render
        // the optical tiles are a pre-burst freeze; the streaming publish path below
        // is the show (E7: "the burst is the show, never a freeze").
        let optical = useOptical && !stageActive
            && opticalTile64.count == 64 * 64
            && opticalTile32.count == 32 * 32
            && opticalTile16.count == 16 * 16
        if optical {
            // Fingerprint the OPTICAL inputs themselves: `pixelKey` churns per publish
            // (the streaming tile64 rides the same hash), so without this the branch
            // would rebake three identical bitmaps at 20 Hz from unchanged exposures.
            var h = Hasher()
            h.combine(opticalTile64); h.combine(opticalTile32); h.combine(opticalTile16)
            let key = h.finalize()
            guard key != baked.opticalKey else { return }
            baked.opticalKey = key
            baked.opticalDisplay = true
            rebake64()   // optical-aware: bakes from opticalTile64 (+ any live crosshair)
            baked.img32 = Self.rgbImage(tile: opticalTile32, side: 32, gainStops: 0)
            baked.base16 = Self.rgbBase(tile: opticalTile16, side: 16, gainStops: 0)
            rebakeShutter()
            return
        }
        baked.opticalDisplay = false

        let s64 = Self.sums64(from: tile64, palette: palette)    // 64×64×3, 1 px/cell
        baked.lastS64 = s64
        rebake64()

        // E1 — bank the frame: u64 SUMS are the transitive carrier (means never compose).
        let s32p = ColorHead.poolSpatial2(s64, side: 64)         // 32×32×3, 4 px/cell
        for i in 0 ..< baked.acc32.count { baked.acc32[i] &+= s32p[i] }
        baked.frames32 += 1
        let s16p = ColorHead.poolSpatial2(s32p, side: 32)        // 16×16×3, 16 px/cell
        for i in 0 ..< baked.acc16.count { baked.acc16[i] &+= s16p[i] }
        baked.frames16 += 1

        // E2 — this frame's DC (the ColorMomentum MASS band): one reduction over the
        // already-computed 16² sums (768 adds — microseconds).
        baked.tallyDC = Self.frameDC(fromSums16: s16p)
        fillTallySlot()

        // Seed: the very first publish realizes both coarse rungs immediately so the
        // pyramid never opens blank; from then on the cadence gating owns the swaps.
        if baked.img32 == nil { realize32() }
        if baked.base16.isEmpty { realize16() }
    }

    // MARK: - the one clock (realize gating + beat-driven rebakes)

    /// One 20 Hz tick: realize the 32² on mod-2, the 16² on mod-4 (`Spec.ColorTimeDisplay
    /// .realizesAt` — `lawDisplayCadenceIsPoolDepth`), advance the tally rails, expire the
    /// pressed inversion and the meter crosshair. Anything whose key did not step bakes
    /// nothing.
    private func onTick(_ t: Int) {
        if ColorTimeDisplayMath.realizesAt(period: 2, tick: t), baked.frames32 > 0 {
            realize32()
        }
        if ColorTimeDisplayMath.realizesAt(period: 4, tick: t), baked.frames16 > 0 {
            realize16()
        }
        rebakeTallies(tick: t)
        if t == baked.pressedUntil { rebakeShutter() }               // pressed inversion ends
        if baked.meterCell != nil, t == baked.meterSince + 20 {      // crosshair linger ends
            baked.meterCell = nil
            rebake64()
        }
    }

    /// Realize the 32²: divide the accumulator ONCE by its true sample count
    /// (4 px × banked frames — 8 on the ideal schedule, `lawRealizeSamplesLadder`),
    /// swap the whole tile, clear the bank. Live-ladder tiles are adopted at this
    /// same cadence when present — but ONLY while idle: the preview ColorHead runs
    /// only while `collecting == false`, so during a stage the ladder tiles are a
    /// pre-burst freeze and the honest banked accumulators own the realize (E7).
    private func realize32() {
        if useLiveLadder && !stageActive && tile32.count == 32 * 32 {
            baked.img32 = Self.rgbImage(tile: tile32, side: 32, gainStops: ev32)
        } else {
            let count = UInt64(max(1, 4 * baked.frames32))
            baked.img32 = Self.pooledImage(sums: baked.acc32, side: 32, count: count,
                                           gainStops: ev32)
        }
        baked.acc32 = [UInt64](repeating: 0, count: 32 * 32 * 3)
        baked.frames32 = 0
    }

    /// Realize the 16² (divisor 16 px × banked frames — 64 on the ideal schedule) and
    /// rebake the shutter face from the fresh base colours. Live-ladder adoption is
    /// idle-only, exactly like `realize32` — during a stage the E7 ledger must bank
    /// each frame's OWN realize, never a stale pre-burst ladder tile.
    private func realize16() {
        if useLiveLadder && !stageActive && tile16.count == 16 * 16 {
            baked.base16 = Self.rgbBase(tile: tile16, side: 16, gainStops: ev16)
        } else {
            let count = UInt64(max(1, 16 * baked.frames16))
            baked.base16 = Self.pooledBase(sums: baked.acc16, side: 16, count: count,
                                           gainStops: ev16)
        }
        baked.acc16 = [UInt64](repeating: 0, count: 16 * 16 * 3)
        baked.frames16 = 0
        rebakeShutter()
    }

    // MARK: - the 64² bake (with the E4 meter crosshair)

    /// The meter crosshair cell while its 20-tick linger is running, else nil.
    private var activeMeterCell: (col: Int, row: Int)? {
        guard let cell = baked.meterCell, tick < baked.meterSince + 20 else { return nil }
        return cell
    }

    /// Repaint the 64² — from the optical base exposure while the optical display is
    /// active (so the E4 crosshair works there too), else from the last published sums
    /// (count 1/cell) — inverting the 3×3 crosshair at the metered point while it lingers.
    private func rebake64() {
        if baked.opticalDisplay, opticalTile64.count == 64 * 64 {
            baked.img64 = Self.rgbImage(tile: opticalTile64, side: 64, gainStops: 0,
                                        invertCross: activeMeterCell)
            return
        }
        guard !baked.lastS64.isEmpty else { baked.img64 = nil; return }
        baked.img64 = Self.pooledImage(sums: baked.lastS64, side: 64, count: 1,
                                       gainStops: ev64, invertCross: activeMeterCell)
    }

    // MARK: - the intake tallies (E2)

    /// Ink the CURRENT tick's slot on both rails with the fresh frame DC (called on
    /// publish, so a dropped frame leaves its slot hollow — the tally is honest).
    private func fillTallySlot() {
        baked.slots32[ColorTimeDisplayMath.tallySlot(slots: 2, tick: tick)] = baked.tallyDC
        baked.slots16[ColorTimeDisplayMath.tallySlot(slots: 4, tick: tick)] = baked.tallyDC
    }

    /// Advance both rails for tick `t`: the tick AFTER a realize opens a fresh window
    /// (slots clear to ghost — `lawPourWindowExact`'s [1…n−1, 0] walk), the realize tick
    /// itself flashes the filled slots lit for exactly 1 tick (the pour). Bakes are
    /// fingerprinted so an unchanged rail never rebakes.
    private func rebakeTallies(tick t: Int) {
        // Fresh window: slot walk restarts at 1 on the tick after each realize.
        if ColorTimeDisplayMath.tallySlot(slots: 2, tick: t) == 1 {
            let keep = baked.slots32[1]
            baked.slots32 = [nil, keep]
        }
        if ColorTimeDisplayMath.tallySlot(slots: 4, tick: t) == 1 {
            let keep = baked.slots16[1]
            baked.slots16 = [nil, keep, nil, nil]
        }
        let flash32 = ColorTimeDisplayMath.realizesAt(period: 2, tick: t)
        let flash16 = ColorTimeDisplayMath.realizesAt(period: 4, tick: t)

        var h32 = Hasher()
        for s in baked.slots32 { h32.combine(s?.x); h32.combine(s?.y); h32.combine(s?.z) }
        h32.combine(flash32)
        let k32 = h32.finalize()
        if k32 != baked.intake32Key {
            baked.intake32Key = k32
            baked.intake32Img = Self.tallyImage(slots: baked.slots32, width: 32,
                                                slotCells: 15, gapCells: 2, flash: flash32)
        }

        var h16 = Hasher()
        for s in baked.slots16 { h16.combine(s?.x); h16.combine(s?.y); h16.combine(s?.z) }
        h16.combine(flash16)
        let k16 = h16.finalize()
        if k16 != baked.intake16Key {
            baked.intake16Key = k16
            baked.intake16Img = Self.tallyImage(slots: baked.slots16, width: 16,
                                                slotCells: 3, gapCells: 1, flash: flash16)
        }
    }

    /// Bake one tally rail (width × 2 cells): filled slots carry their frame's DC — lit
    /// control ink for the 1-tick pour flash — pending slots are ghost ink; gaps are
    /// transparent. Ink transforms only, never alpha.
    static func tallyImage(slots: [SIMD3<UInt8>?], width: Int,
                           slotCells: Int, gapCells: Int, flash: Bool) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ghost = SFTheme.ledGhost
        let stride = slotCells + gapCells
        return CellBitmap.image(cols: width, rows: 2) { c, _ in
            let slot = c / stride
            guard slot < slots.count, c % stride < slotCells else { return nil }   // gap
            guard let dc = slots[slot] else { return ghost }                        // pending
            return flash ? lit : dc                                                 // poured
        }
    }

    /// The frame's global mean colour from the 16² sums (16²·16 px = 4096 fine pixels):
    /// the MASS band of `Spec.ColorMomentum`, shown by the tallies.
    static func frameDC(fromSums16 sums: [UInt64]) -> SIMD3<UInt8> {
        guard sums.count == 16 * 16 * 3 else { return .init(0, 0, 0) }
        var tot = SIMD3<UInt64>(0, 0, 0)
        for cell in 0 ..< 256 {
            tot.x &+= sums[cell * 3]
            tot.y &+= sums[cell * 3 + 1]
            tot.z &+= sums[cell * 3 + 2]
        }
        let k: UInt64 = 64 * 64   // one divide, at the display boundary
        return SIMD3<UInt8>(UInt8(min(255, tot.x / k)),
                            UInt8(min(255, tot.y / k)),
                            UInt8(min(255, tot.z / k)))
    }

    // MARK: - the banked ledger + shutter bake (E7)

    /// Fold newly landed frames into the PERMANENT ledger: frame n takes raster cells
    /// 4(n−1)…4n−1 from the CURRENT base16 (that frame's own 5 Hz realize), exactly once
    /// (`lawLedgerStepExact` — a re-entrant callback can never overfill the tile).
    private func updateLedger() {
        guard stageActive else {
            baked.ledgerFilled = 0
            rebakeShutter()
            return
        }
        let landed = min(64, max(0, landedFrames))
        if landed < baked.ledgerFilled { baked.ledgerFilled = 0 }    // a new stage epoch
        if baked.base16.count == 16 * 16, landed > baked.ledgerFilled {
            for f in (baked.ledgerFilled + 1) ... landed {
                for cell in ColorTimeDisplayMath.ledgerCells(f) {
                    baked.ledger[cell] = baked.base16[cell]
                }
            }
        }
        baked.ledgerFilled = landed
        rebakeShutter()
    }

    /// Bake ONLY the 16² face. Idle: the realized coarse tile (inverted while pressed —
    /// the D1 PRESSED treatment). During a stage: the banked ledger — landed cells keep
    /// the colours they banked, PERMANENTLY; unbanked cells are the quarter-ink ghost of
    /// the live base (the existing b/4 idiom).
    private func rebakeShutter() {
        guard baked.base16.count == 16 * 16 else { baked.img16 = nil; return }
        let base = baked.base16
        if stageActive {
            let filled = ColorTimeDisplayMath.ledgerFillCount(baked.ledgerFilled)
            let ledger = baked.ledger
            baked.img16 = CellBitmap.image(cols: 16, rows: 16) { c, r in
                let cell = r * 16 + c
                if cell < filled { return ledger[cell] }
                let b = base[cell]
                return SIMD3<UInt8>(b.x / 4, b.y / 4, b.z / 4)
            }
        } else {
            let inverted = tick < baked.pressedUntil
            baked.img16 = CellBitmap.image(cols: 16, rows: 16) { c, r in
                let b = base[r * 16 + c]
                return inverted ? SIMD3<UInt8>(255 &- b.x, 255 &- b.y, 255 &- b.z) : b
            }
        }
    }

    // MARK: - The pooling (reuses the shipped exact kernel)

    /// Resolve the 64×64 index tile into the sums carrier (`side²·3` u64, one pixel per cell
    /// so `count == 1`) that `ColorHead.poolSpatial2` consumes. Off-palette indices resolve to
    /// black. The display twin of the camera's `poolSums64`.
    static func sums64(from tile: [UInt8], palette: [SIMD3<UInt8>]) -> [UInt64] {
        var s = [UInt64](repeating: 0, count: 64 * 64 * 3)
        let n = min(tile.count, 64 * 64)
        for i in 0 ..< n {
            let idx = Int(tile[i])
            let c = idx < palette.count ? palette[idx] : SIMD3<UInt8>(0, 0, 0)
            s[i * 3] = UInt64(c.x)
            s[i * 3 + 1] = UInt64(c.y)
            s[i * 3 + 2] = UInt64(c.z)
        }
        return s
    }

    /// Realize one rung's sums into a baked bitmap: divide each bin by its sample `count`
    /// (means don't compose, so divide only at the display boundary), apply digital EV
    /// gain (2^stops), clamp to sRGB8. `invertCross` draws the E4 meter crosshair — a 3×3
    /// cross of INVERTED cells (an ink transform, never an overlay).
    static func pooledImage(sums: [UInt64], side: Int, count: UInt64, gainStops: Float,
                            invertCross: (col: Int, row: Int)? = nil) -> UIImage? {
        let gain = pow(2.0, Double(gainStops))
        let k = Double(count)
        return CellBitmap.image(cols: side, rows: side) { c, r in
            let i = (r * side + c) * 3
            let ch: (Int) -> UInt8 = { o in
                let v = (Double(sums[i + o]) / k) * gain
                return UInt8(max(0, min(255, v.rounded())))
            }
            var px = SIMD3<UInt8>(ch(0), ch(1), ch(2))
            if let x = invertCross, onCross(c, r, x.col, x.row) {
                px = SIMD3<UInt8>(255 &- px.x, 255 &- px.y, 255 &- px.z)
            }
            return px
        }
    }

    /// The 3×3 meter crosshair mask: the centre cell plus one cell along each axis.
    @inline(__always)
    static func onCross(_ c: Int, _ r: Int, _ mc: Int, _ mr: Int) -> Bool {
        (r == mr && abs(c - mc) <= 1) || (c == mc && abs(r - mr) <= 1)
    }

    /// The 16²'s gain-applied base colours from pooled sums — the shutter fill dims
    /// THESE, so they cache across fill steps.
    static func pooledBase(sums: [UInt64], side: Int, count: UInt64,
                           gainStops: Float) -> [SIMD3<UInt8>] {
        let gain = pow(2.0, Double(gainStops))
        let k = Double(count)
        return (0 ..< side * side).map { cell in
            let i = cell * 3
            let ch: (Int) -> UInt8 = { o in
                let v = (Double(sums[i + o]) / k) * gain
                return UInt8(max(0, min(255, v.rounded())))
            }
            return SIMD3<UInt8>(ch(0), ch(1), ch(2))
        }
    }

    // MARK: - The live-ladder realization (Feature.liveLadder)

    /// Realize one PRE-MEANED rung tile (already area-meaned + inverse-EOTF'd by the owned
    /// kernel) into a baked bitmap: digital EV gain + clamp. The `rgbImage` twin of
    /// `pooledImage` — no `/count` divide, since the means are already realized.
    static func rgbImage(tile: [SIMD3<UInt8>], side: Int, gainStops: Float,
                         invertCross: (col: Int, row: Int)? = nil) -> UIImage? {
        let gain = pow(2.0, Double(gainStops))
        return CellBitmap.image(cols: side, rows: side) { c, r in
            let px = tile[r * side + c]
            let ch: (UInt8) -> UInt8 = { v in
                UInt8(max(0, min(255, (Double(v) * gain).rounded())))
            }
            var out = SIMD3<UInt8>(ch(px.x), ch(px.y), ch(px.z))
            if let x = invertCross, onCross(c, r, x.col, x.row) {
                out = SIMD3<UInt8>(255 &- out.x, 255 &- out.y, 255 &- out.z)
            }
            return out
        }
    }

    /// The 16²'s gain-applied base colours from a pre-realized tile — the live-ladder /
    /// optical twin of `pooledBase`.
    static func rgbBase(tile: [SIMD3<UInt8>], side: Int, gainStops: Float) -> [SIMD3<UInt8>] {
        let gain = pow(2.0, Double(gainStops))
        return tile.map { px in
            let ch: (UInt8) -> UInt8 = { v in
                UInt8(max(0, min(255, (Double(v) * gain).rounded())))
            }
            return SIMD3<UInt8>(ch(px.x), ch(px.y), ch(px.z))
        }
    }
}

#if DEBUG
/// Canvas check with no camera — the synthetic `DemoScene` tile pooled to the three rungs.
#Preview("Inverted pyramid — three views (demo scene)") {
    InvertedPyramidField(tile64: DemoScene.tile(tick: 0),
                         palette: DemoScene.palette)
        .ignoresSafeArea()
}
#endif
