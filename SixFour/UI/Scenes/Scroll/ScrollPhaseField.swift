import SwiftUI
import UIKit
import simd

/// Π·live·scroll — THE SCROLL: the infinite, never-repeating tube of 64² pour
/// groups, scrolled by hand.
///
/// A `.live` SELF-EXCURSION (`Feature.scrollTube` + `surface.scrollTube`): pure
/// render state, the ABSurface FSM untouched — the documented precedent of lock +
/// burst being internal to `.live` and the Decide fold being render state. Entered
/// by a long-press on the live 64² hero; EXIT returns to the pyramid; any phase
/// edge away from `.live` clears the excursion (`SurfaceView`).
///
/// THE TUBE (`SixFour/Tube/`): slice n is 4 fine frames — ONE pour group
/// (`S4WangTiling.sliceRows`, the 4-into-1 pour of `Spec.ColorTimeDisplay`) —
/// materialized by `TubeSynth.generate`: the Jeandel–Rao aperiodic tiling is the
/// theorem-fixed op SYNTAX (random access, never repeats), the θ_up gene is the
/// ATTENTION (weights + palette warp only — `lawAttentionModulatesNotMutates`),
/// `s4_synth_burst` → octant ops → `s4_quantize_frame` is the substrate. Slices
/// are generated OFF-MAIN (the `TubeLoader` actor owns the content-addressed
/// `TubeSliceCache`), visible ± `prefetchRadius` only — we never know if/when a
/// slice is needed, and random access means a fling never blocks on neighbours.
///
/// THE VIEWPORT plays the current slice's 4 frames in a 20 Hz loop — frame =
/// `tallySlot(4, tick)`, so one loop = one pour group = 4 ticks, counted by the
/// `pour` tally rail in the exact liveScene intake16 vocabulary. COARSE-FIRST with
/// REFINE-ON-LINGER: a slice arrives as its 16² pool instantly (deterministic data
/// — the coarse floor is free), and the finer rungs MATERIALIZE on the same reveal
/// ladder the boot resolve plays (`S4WangTiling.revealTick`: 32² at 8 linger
/// ticks, 64² at 16 — decode-compute is spent where the user lingers, the
/// gene-compute-economy read). Scrolling away resets the linger; a fast scroll
/// never pays for fine bakes.
///
/// THE LATTICE: every widget rides the spec-proven `GridLayoutContract.scrollScene`
/// (hero ON the liveScene field64 band, so entering/leaving the tube never moves
/// the eye; pour tally; 2×128 position rail; EXIT/RESEED FRAME-faced verbs —
/// `Spec.CellMechanics.controlFaces`). All timing derives from the ONE 20 Hz
/// `SurfaceClock.tick`; nothing bakes per-tick (frames pre-bake at arrival /
/// reveal boundaries; the tally is a ≤64-cell fingerprinted bake; the rail rebakes
/// only when the slice/window steps).
struct ScrollPhaseField: View {
    let surface: Surface
    let clock: SurfaceClock

    @State private var model = ScrollTubeModel()
    /// The slice the in-flight vertical drag started from (nil = no drag live).
    @State private var dragBase: Int?

    private let scene = GridLayoutContract.scrollScene

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The persistent influence ground stays hoisted in SurfaceView; the tube
            // rides it exactly as the live pyramid does.
            hero.place("hero", in: scene)
            pourRail.place("pour", in: scene)
            rail.place("rail", in: scene)
            ScrollVerb(title: "EXIT", clock: clock) {
                surface.scrollTube = false
            }
            .accessibilityLabel("Exit the tube")
            .accessibilityHint("Back to the live pyramid")
            .place("exit", in: scene)
            ScrollVerb(title: "RESEED", clock: clock) {
                model.reseed()
            }
            .accessibilityLabel("Reseed the tube")
            .accessibilityHint("Jump to a fresh infinite tube")
            .place("reseed", in: scene)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onAppear {
            // The gene reaches the generator as the committed θ_up words through the
            // ONE sanctioned float→Q16 crossing; no gene ⇒ [] ⇒ the deterministic
            // floor (zero-gene == floor). Captured once per entry — a mid-scroll gene
            // landing must not silently rewrite the tube under the user.
            let words = (surface.thetaUp?.theta ?? []).map {
                DeviceTrainStepCPU.quantizeQ16(Double($0))
            }
            model.enter(gene: words, tick: clock.tick)
        }
        .onChange(of: clock.tick) { _, t in
            model.onTick(t)
        }
        // The slice index readout — the transient-CellText idiom (the EV-overlay
        // vocabulary): always meaningful here, so always on, top-centred.
        .overlay(alignment: .top) {
            CellText("SLICE \(model.slice)", cell: GlobalLattice.gif(1))
                .padding(.top, GlobalLattice.gif(4))
                .allowsHitTesting(false)
                .accessibilityLabel("Tube slice \(model.slice)")
        }
    }

    // ── the viewport (the D1 BRACKETS image-content control) ─────────────────

    private var hero: some View {
        ZStack {
            // The hero is an image-content control (`controlFaces["hero"]` =
            // brackets): ghost brackets + BEAT idle, PRESSED ink while the drag is
            // live. Reduce-motion pins the beat off (tick 1 is provably beat-free).
            ControlBrackets(side: 64, state: dragBase != nil ? 1 : 0,
                            tick: clock.tick, reduceMotion: clock.reduceMotion)
            Group {
                if let img = model.heroImage(tick: clock.tick) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Color.black   // slice not materialized yet — an honest void
                }
            }
            .frame(width: GlobalLattice.gif(64), height: GlobalLattice.gif(64))
        }
        .contentShape(Rectangle())   // the bracket rect IS the hit rect (D1)
        .gesture(scrollDrag)
        .accessibilityLabel("Tube viewport, slice \(model.slice)")
        .accessibilityHint("Drag vertically to scroll the infinite tube")
    }

    /// The ONE tube gesture: vertical drag scrolls the tube — 16 cells (64 pt) of
    /// travel = one slice, drag up = deeper (the next slice), absolute from the
    /// drag's base slice so a slow drag never accumulates rounding drift.
    private var scrollDrag: some Gesture {
        DragGesture(minimumDistance: GlobalLattice.gif(2))
            .onChanged { value in
                if dragBase == nil { dragBase = model.slice }
                let step = Int((-value.translation.height / GlobalLattice.gif(16)).rounded())
                model.setSlice((dragBase ?? model.slice) + step, tick: clock.tick)
            }
            .onEnded { _ in dragBase = nil }
    }

    // ── the pour tally (the intake16 idiom — one loop = one pour group) ───────

    private var pourRail: some View {
        Group {
            if let img = model.pourImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: GlobalLattice.gif(16), height: GlobalLattice.gif(2))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // ── the tube-position rail (a ±32-slice ruler under a fixed cursor) ───────

    private var rail: some View {
        Group {
            if let img = model.railImage {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: GlobalLattice.gif(2), height: GlobalLattice.gif(128))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// ── the model (σ-independent tube state, MainActor; generation off-main) ─────

/// THE SCROLL's state: the tube seed, the current slice, the materialized window,
/// and the baked display artifacts. All mutation is MainActor; the heavy slice
/// generation runs in the `TubeLoader` actor (off-main), folded back here.
@MainActor @Observable
final class ScrollTubeModel {

    /// The default tube seed — an arbitrary pinned constant ("THETUBE1"); RESEED
    /// mixes it forward through the same pinned SplitMix64 derivation the slices
    /// use, so every tube is reachable deterministically.
    static let defaultTubeSeed: UInt64 = 0x5448_4554_5542_4531

    /// Slices requested around the current one (visible ± prefetch — lazy by
    /// design: the tube is infinite, we materialize only what a linger can reach).
    static let prefetchRadius = 1
    /// Materialized slices kept around the cursor before eviction (± this).
    static let keepRadius = 2

    private(set) var tubeSeed = ScrollTubeModel.defaultTubeSeed
    private(set) var slice = 0
    private(set) var gene: [Int] = []

    /// One materialized slice's display artifacts. The 16² pool is baked AT ARRIVAL
    /// (the coarse floor is free); the finer rungs bake lazily at their reveal
    /// boundaries — compute spent only where the user lingers.
    private struct SliceBakes {
        let frames: [TubeFrame]
        /// Per-frame global mean colour (the ColorMomentum MASS band) — tally ink.
        let dc: [SIMD3<UInt8>]
        let img16: [UIImage?]
        var img32: [UIImage?]?
        var img64: [UIImage?]?
    }

    private var window: [Int: SliceBakes] = [:]
    private var inFlight: Set<Int> = []
    private let loader = TubeLoader()

    /// The tick the CURRENT slice became displayable (data on screen) — the linger
    /// clock the refine ladder runs on. nil while the slice is still materializing.
    private var revealStart: Int?
    /// The last κ tick seen (folds stamp arrival against this).
    private var lastTick = 0

    // The pour tally (the intake16 idiom): slot = the frame of the pour group
    // showing this tick; ink = that frame's DC; flash on the mod-4 realize.
    private var pourSlots: [SIMD3<UInt8>?] = [nil, nil, nil, nil]
    private var pourKey = Int.min
    private(set) var pourImage: UIImage?

    private var railKey = Int.min
    private(set) var railImage: UIImage?

    // ── lifecycle ─────────────────────────────────────────────────────────────

    /// Enter the tube: adopt the gene (content-addresses every slice) and prefetch
    /// the opening window. Idempotent for the same gene.
    func enter(gene: [Int], tick: Int) {
        lastTick = tick
        if gene != self.gene {
            self.gene = gene
            window.removeAll()
            revealStart = nil
        }
        prefetch()
        rebakeRail()
    }

    /// Jump to a fresh tube: mix the seed forward (the pinned SplitMix64 slice
    /// derivation reused as the reseed mixer), drop the window, restart at slice 0.
    func reseed() {
        tubeSeed = TubeSynth.sliceSeed(tubeSeed: tubeSeed, slice: 1)
        slice = 0
        window.removeAll()
        inFlight.removeAll()   // stale folds are discarded by the seed guard below
        revealStart = nil
        prefetch()
        rebakeRail()
    }

    /// Move the cursor to slice `n` (the drag's absolute target). A cached slice
    /// starts its linger clock immediately; a missing one starts when its fold
    /// lands. Prefetches the new window and evicts outside ± `keepRadius`.
    func setSlice(_ n: Int, tick: Int) {
        guard n != slice else { return }
        lastTick = tick
        slice = n
        revealStart = window[n] != nil ? tick : nil
        Haptics.selection()   // discrete slice-change confirmation (not a cell detent)
        prefetch()
        evict()
        rebakeRail()
    }

    /// One κ tick: run the refine-on-linger ladder (bake the 32²/64² at their
    /// reveal boundaries) and advance the pour tally. Nothing here bakes unless a
    /// boundary or a fingerprint stepped.
    func onTick(_ t: Int) {
        lastTick = t
        refineOnLinger(t)
        advancePour(t)
    }

    // ── display ───────────────────────────────────────────────────────────────

    /// The viewport image for `tick`: frame = the pour-group slot (4-tick loop),
    /// rung = the finest the linger has EARNED (coarse-first; `revealTick` 8/16 for
    /// the 32²/64² — the same ladder the boot resolve plays, in the same order).
    func heroImage(tick: Int) -> UIImage? {
        guard let b = window[slice], let start = revealStart else { return nil }
        let f = ColorTimeDisplayMath.tallySlot(slots: 4, tick: tick)
        let linger = tick - start
        if linger >= S4WangTiling.revealTick(.r64), let imgs = b.img64 { return imgs[f] }
        if linger >= S4WangTiling.revealTick(.r32), let imgs = b.img32 { return imgs[f] }
        return b.img16[f]
    }

    // ── the lazy window (generated off-main, visible ± prefetch only) ─────────

    /// Request every missing slice in the prefetch window from the loader actor.
    /// Requests are content-addressed in the loader's cache, so a duplicate
    /// request after an eviction is a dictionary hit, not a regeneration. Each
    /// request carries the `stillWanted` probe, so a request the scroll has
    /// already left behind is skipped BEFORE its generation cost is paid.
    private func prefetch() {
        for s in (slice - Self.prefetchRadius) ... (slice + Self.prefetchRadius) {
            guard window[s] == nil, !inFlight.contains(s) else { continue }
            inFlight.insert(s)
            let seed = tubeSeed
            let g = gene
            Task { [weak self] in
                let frames = await self?.loader.frames(tubeSeed: seed, gene: g, slice: s,
                                                       wanted: { [weak self] in
                    await self?.stillWanted(slice: s, seed: seed) ?? false
                })
                self?.fold(slice: s, seed: seed, frames: frames)
            }
        }
    }

    /// TRUE while `(seed, s)` is still worth materializing — the loader's
    /// PRE-GENERATION staleness probe (it reads fresh MainActor state at the
    /// moment the loader is about to generate, never a launch-time snapshot):
    /// the seed must not have been RESEEDed away and the slice must still sit
    /// in the keep window — exactly the admit rule `fold` enforces after the
    /// fact, applied before the cost instead.
    private func stillWanted(slice s: Int, seed: UInt64) -> Bool {
        seed == tubeSeed && abs(s - slice) <= Self.keepRadius
    }

    /// Fold one materialized slice back on the MainActor: bake its coarse floor,
    /// admit it to the window, and start the linger clock if it is the one on
    /// screen. A fold from a superseded seed (RESEED raced it) is discarded;
    /// nil frames (the loader's pre-generation staleness probe skipped it, or
    /// a kernel refused) just clears the in-flight mark so a later prefetch
    /// can re-request.
    private func fold(slice s: Int, seed: UInt64, frames: [TubeFrame]?) {
        inFlight.remove(s)
        guard seed == tubeSeed, let frames, window[s] == nil else { return }
        guard abs(s - slice) <= Self.keepRadius else { return }   // scrolled far away
        var dc: [SIMD3<UInt8>] = []
        var img16: [UIImage?] = []
        for f in frames {
            let s16 = Self.sums16(of: f)
            dc.append(InvertedPyramidField.frameDC(fromSums16: s16))
            img16.append(InvertedPyramidField.pooledImage(sums: s16, side: 16,
                                                          count: 16, gainStops: 0))
        }
        window[s] = SliceBakes(frames: frames, dc: dc, img16: img16)
        if s == slice, revealStart == nil { revealStart = lastTick }
        rebakeRail()
    }

    /// Drop materialized slices outside the keep window (the loader's LRU still
    /// holds their frames, so scrolling back is a cache hit).
    private func evict() {
        for k in window.keys where abs(k - slice) > Self.keepRadius {
            window.removeValue(forKey: k)
        }
    }

    // ── refine-on-linger (the reveal ladder as a compute schedule) ────────────

    /// Bake the current slice's finer rungs when its linger crosses their reveal
    /// ticks (32² at 8, 64² at 16 — `S4WangTiling.revealTick`, the boot-resolve
    /// ladder). Each rung bakes exactly once per slice arrival.
    private func refineOnLinger(_ t: Int) {
        guard let start = revealStart, var b = window[slice] else { return }
        let linger = t - start
        var changed = false
        if linger >= S4WangTiling.revealTick(.r32), b.img32 == nil {
            b.img32 = b.frames.map { f in
                InvertedPyramidField.pooledImage(sums: ColorHead.poolSpatial2(Self.sums64(of: f), side: 64),
                                                 side: 32, count: 4, gainStops: 0)
            }
            changed = true
        }
        if linger >= S4WangTiling.revealTick(.r64), b.img64 == nil {
            b.img64 = b.frames.map { f in
                InvertedPyramidField.pooledImage(sums: Self.sums64(of: f),
                                                 side: 64, count: 1, gainStops: 0)
            }
            changed = true
        }
        if changed { window[slice] = b }
    }

    // ── the pour tally ────────────────────────────────────────────────────────

    /// Advance the 4-slot rail: the tick's slot inks with the SHOWING frame's DC
    /// (slot index == frame index — the loop IS the pour group), the window
    /// restarts at slot 1's tick, the realize tick flashes (the pour). Fingerprint-
    /// gated: an unchanged rail never rebakes.
    private func advancePour(_ t: Int) {
        let slot = ColorTimeDisplayMath.tallySlot(slots: 4, tick: t)
        if slot == 1 {
            let keep = pourSlots[1]
            pourSlots = [nil, keep, nil, nil]
        }
        if let b = window[slice], revealStart != nil, slot < b.dc.count {
            pourSlots[slot] = b.dc[slot]
        }
        let flash = ColorTimeDisplayMath.realizesAt(period: 4, tick: t)
        var h = Hasher()
        for s in pourSlots { h.combine(s?.x); h.combine(s?.y); h.combine(s?.z) }
        h.combine(flash)
        let key = h.finalize()
        guard key != pourKey else { return }
        pourKey = key
        pourImage = InvertedPyramidField.tallyImage(slots: pourSlots, width: 16,
                                                    slotCells: 3, gapCells: 1, flash: flash)
    }

    // ── the position rail ─────────────────────────────────────────────────────

    /// Bake the 2×128 rail: a ±32-slice ruler scrolling under a fixed centre
    /// cursor — cursor lit, materialized slices marked, pour-group-pitch ruler
    /// ticks ghost. Rebakes only when the slice/window/seed steps (never per tick).
    private func rebakeRail() {
        var h = Hasher()
        h.combine(slice); h.combine(tubeSeed)
        for k in window.keys.sorted() { h.combine(k) }
        let key = h.finalize()
        guard key != railKey else { return }
        railKey = key
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let held = SFTheme.ledGhost &* 2   // materialized marker: doubled ghost ink
        let ghost = SFTheme.ledGhost
        let cursor = slice
        let cached = Set(window.keys)
        railImage = CellBitmap.image(cols: 2, rows: 128) { _, r in
            let s = cursor + (r / 2) - 32
            if s == cursor { return lit }
            if cached.contains(s) { return held }
            let m = ((s % 4) + 4) % 4
            return m == 0 ? ghost : nil
        }
    }

    // ── the pooling twins (the sums carrier, exactly the pyramid's math) ──────

    /// A tube frame resolved to the 64²·3 u64 sums carrier (1 px per cell).
    private static func sums64(of f: TubeFrame) -> [UInt64] {
        var pal = [SIMD3<UInt8>](repeating: .init(0, 0, 0), count: 256)
        for i in 0 ..< min(256, f.paletteRGB.count / 3) {
            pal[i] = SIMD3<UInt8>(f.paletteRGB[i * 3], f.paletteRGB[i * 3 + 1],
                                  f.paletteRGB[i * 3 + 2])
        }
        return InvertedPyramidField.sums64(from: f.indices, palette: pal)
    }

    /// The frame's 16² sums (16 fine px per bin — divisor 16 at realize).
    private static func sums16(of f: TubeFrame) -> [UInt64] {
        ColorHead.poolSpatial2(ColorHead.poolSpatial2(sums64(of: f), side: 64), side: 32)
    }
}

// ── the loader actor (generation OFF-MAIN, content-addressed) ────────────────

/// The single owner of the tube's `TubeSliceCache` (non-Sendable by design):
/// every materialization runs on this actor's executor — never the MainActor —
/// and repeated reads (scroll back, re-entry, duplicate prefetch) are dictionary
/// hits on the `(tubeSeed, geneHash, slice)` content address.
actor TubeLoader {
    private let cache = TubeSliceCache(capacity: 16)

    /// The slice's 4 preview frames (cache hit or generate). `wanted` is
    /// consulted ON THIS EXECUTOR immediately before the generation cost is
    /// paid: a fling through N slices queues every intermediate slice here
    /// serially, and without the check the LANDING slice would wait behind the
    /// full materialization of every stale one (the model's fold guard
    /// discards them only after the cost is spent). A stale request now costs
    /// one probe and returns nil; scrolling back simply re-requests it (and
    /// usually cache-hits). The `await` is a suspension point — the actor is
    /// reentrant there, but the non-Sendable cache is only ever touched
    /// between suspension points, so its single-owner confinement holds.
    /// Otherwise nil iff a kernel refused — propagated, never wrapped.
    func frames(tubeSeed: UInt64, gene: [Int], slice: Int,
                wanted: @Sendable () async -> Bool) async -> [TubeFrame]? {
        guard await wanted() else { return nil }
        return cache.frames(tubeSeed: tubeSeed, gene: gene, slice: slice)
    }
}

// ── the verb face (FRAME, the D1 control language) ───────────────────────────

/// A 20×12 FRAME-faced verb (`controlFaces` "exit"/"reseed"): a 1-cell control-ink
/// ring beating lit for 1 tick on every 16-rung realize (reduce-motion pins the
/// beat off — tick 1 is provably beat-free), the label in cell text. Baked once
/// per treatment change; the whole face is the hit rect (80×48 pt ≥ touch floor).
private struct ScrollVerb: View {
    let title: String
    let clock: SurfaceClock
    let action: () -> Void
    @State private var baked: (key: Int, image: UIImage?) = (.min, nil)

    var body: some View {
        let treatment = SixFourCellMechanics.faceTreatment(
            state: 0, tick: clock.reduceMotion ? 1 : clock.tick)
        Button {
            Haptics.selection()
            action()
        } label: {
            ZStack {
                Group {
                    if let img = baked.image {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                    } else {
                        Color.clear
                    }
                }
                CellText(title, rows: 7, cell: GlobalLattice.pt(1))
            }
            .frame(width: GlobalLattice.gif(20), height: GlobalLattice.gif(12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: treatment, initial: true) { _, tr in
            guard tr != baked.key else { return }
            baked = (tr, Self.bake(treatment: tr))
        }
    }

    private static func bake(treatment: Int) -> UIImage? {
        let lit = SIMD3<UInt8>(UInt8(SixFourCellMechanics.faceControlInk.r),
                               UInt8(SixFourCellMechanics.faceControlInk.g),
                               UInt8(SixFourCellMechanics.faceControlInk.b))
        let ring = treatment == 1 ? lit : SFTheme.ledGhost   // the BEAT lights the ring
        return CellBitmap.image(cols: 20, rows: 12) { c, r in
            (c == 0 || c == 19 || r == 0 || r == 11) ? ring : nil
        }
    }
}
