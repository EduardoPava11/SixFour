import SwiftUI
import simd

/// THE TUNABLES for the influence field — one home, Swift-side for on-device iteration (pinned in
/// `Spec.InfluenceField` once locked). A plain (nonisolated) enum so both the `@MainActor`
/// `InfluenceField` view and the nonisolated `FieldModel` read them without an actor hop.
enum FieldTuning {
    /// Frames in the breathing noise ring (cycled by `tick % phases`). Higher = livelier shimmer.
    static let phases = 8
    /// Falloff reach (cells) of an `.arrangement` source (uniform).
    static let reachArrangement = 34.0
    /// Base falloff reach (cells) of a `.set` source, before usage scaling.
    static let reachSet = 40.0
    /// Usage→reach scaling for `.set` spokes: an unused colour still reaches `min`·reach.
    static let usageReachMin = 0.22
    /// How hard a chaos SEAM (two widgets contesting) mutes toward the neutral (0…1).
    static let seamMute = 0.85
    /// Energy multiplier while a widget is LIFTED for a move — the chaos recedes so the lifted
    /// piece of order reads as pulled out of the field (radiation + lift-drag working together).
    static let liftDim = 0.4
    /// The neutral a seam mutes toward, and the calm far-field / unlit ink.
    static let neutral = SIMD3<UInt8>(11, 11, 16)
    static let farDark = SIMD3<UInt8>(6, 6, 10)
}

/// THE UNIVERSAL GROUND — the influence field for EVERY act (`docs/SIXFOUR-INFLUENCE-FIELD-WORKFLOW.md`).
/// The rule is one line: **the widgets (whatever they are) are ORDER; every other cell is CHAOS
/// radiating out of them.** Colour emanates from each widget, dense and faithful at its edge,
/// dissolving into speckle, then into the dark void; where two widgets' influence is comparable a
/// muted seam marks the chaos boundary between them. It is as basic as the cell grid: always
/// present, always breathing, in `.live`, `.capturing`, `.rendering`, and `.review` alike.
///
/// THE LINK IS AUTHORED BY THE USER — the movable widgets (`MoveContract`) are the sources, read
/// live from `settings.widgetPlacement`; drag any of them and the field re-maps. The field
/// generalises to N sources (a Voronoi of order): add a widget in any act and it simply becomes
/// another source (pass it in `extraSources`).
///
/// THE MAP (per stage cell, workflow §3, generalised): each source `s` has a falloff weight
/// `w_s` (→0 at its reach, so the far field stays calm/dark). **energy** `E = Σ w_s` (how lit);
/// the **dominant** source colours the cell; the **runner-up** ratio `w₂/w₁` is the interplay
/// (→1 on a seam between two widgets → muted toward a dark neutral). USAGE-WEIGHTED (Decision 1):
/// a `.set` source (e.g. Palette16) radiates the palette in shutter rank order, each colour's
/// spoke reaching FARTHER the more it's used in the current frame; an `.arrangement` source (e.g.
/// Field64) bleeds its nearest edge pixel outward. HYBRID TEXTURE (Decision 2): `E` sets the
/// per-cell speckle density via an ordered-noise threshold; the noise phase advances every κ tick
/// so the field NEVER PAUSES (driven by the monotonic `tick`, not the 0/1 heartbeat).
///
/// Rendered through the shared `StageField` ⇒ masked to the canonical Stage (whole cells, rounded,
/// on black) with the bake-once / swap-per-tick perf discipline. Tier-2 pure (SwiftUI + simd).
/// Swift PROTOTYPE; formalises into `Spec.InfluenceField` (golden + codegen) once locked (§5).
struct InfluenceField: View {
    let surface: Surface
    /// The LIVE shared widget placement (identity → cell position), re-read every body.
    let placement: [ColorIdentity: (col: Int, row: Int)]
    /// κ's MONOTONIC tick counter (`SurfaceClock.tick`) — advances the breathing every frame so
    /// the look never pauses. (NOT the 0/1 heartbeat, which a static canvas would pin.)
    let tick: Int
    /// Extra order-regions for this act (future widgets: filmstrip, scrub rail, gate, lever …).
    /// Each becomes another radiating source. Empty today (only the two movables exist).
    var extraSources: [FieldSource] = []

    // Tunables live in `FieldTuning` (a nonisolated enum) so the field model can read them too.

    var body: some View {
        // Read σ on the MainActor (View.body is MainActor-isolated) and hand plain values to the
        // nonisolated FieldModel — Swift 6 strict concurrency forbids touching σ off the actor.
        let (tile, tilePalette) = Self.arrangement(of: surface)
        let model = FieldModel(sources: Self.sources(placement, extraSources),
                               palette: tilePalette.isEmpty ? surface.palette : tilePalette,
                               tile: tile, tick: tick, phaseToken: surface.phase.token,
                               lifted: surface.liftedWidget != nil)
        return StageField(phaseCount: FieldTuning.phases, phase: tick, bakeKey: model.key) { c, r, f in
            model.color(c, r, frame: f)
        }
    }

    /// The two persistent movable widgets as sources (Field64 = arrangement, Palette16 = set),
    /// plus any act-specific extras. The minimal universal source set every phase shares.
    private static func sources(_ placement: [ColorIdentity: (col: Int, row: Int)],
                                _ extra: [FieldSource]) -> [FieldSource] {
        func rect(_ id: ColorIdentity) -> CGRect {
            let p = placement[id] ?? (MoveContract.defaultCol(id), MoveContract.defaultRow(id))
            let (w, h) = MoveContract.footprint(id)
            return CGRect(x: CGFloat(p.col), y: CGFloat(p.row), width: CGFloat(w), height: CGFloat(h))
        }
        return [FieldSource(rect: rect(.field64), kind: .arrangement),
                FieldSource(rect: rect(.palette16), kind: .set)] + extra
    }

    /// The best-available 64×64 "arrangement" (tile + its palette) for the current phase, so the
    /// edge-bleed uses each act's REAL data: the live camera in `.live`/`.capturing`, the
    /// resolving/committed GIFA frame at the cursor in `.rendering`/`.review`. Empty ⇒ arrangement
    /// sources gracefully fall back to radiating the palette (still alive, never blank).
    private static func arrangement(of surface: Surface) -> (tile: [UInt8], palette: [SIMD3<UInt8>]) {
        let side = surface.cubeSide
        switch surface.phase {
        case .live, .locking, .capturing:
            return (surface.previewTile, surface.previewPalette)
        case .rendering, .review:
            let t = surface.cursor, base = t * side * side
            guard t >= 0, surface.indexCube.count >= base + side * side else {
                return ([], surface.palette)
            }
            let slice = Array(surface.indexCube[base ..< base + side * side])
            let pal = (t < surface.palettesPerFrame.count) ? surface.palettesPerFrame[t] : surface.palette
            return (slice, pal)
        default:
            return ([], [])
        }
    }
}

/// One radiating order-region. `.arrangement` bleeds the tile's nearest edge pixel outward (the
/// preview / GIFA frame); `.set` radiates the palette in rank order with usage-scaled reach.
struct FieldSource {
    enum Kind { case arrangement, set }
    let rect: CGRect
    let kind: Kind
}

// MARK: - The field model (precomputed once per bake)

/// The pure N-source field. Precomputes the per-colour usage histogram, then answers
/// `color(c,r,frame)` for each stage cell: energy from all sources, the dominant source's colour,
/// muted on the chaos seams between widgets, dithered by an ordered-noise threshold.
private struct FieldModel {
    let sources: [FieldSource]
    let pal: [SIMD3<UInt8>]        // colours the arrangement is built from (256, padded)
    let tile: [UInt8]              // the 64×64 arrangement indices (row-major), may be empty
    let usageNorm: [Double]        // per-index usage / maxUsage ∈ [0,1] (256)
    let tick: Int
    let lifted: Bool              // a widget is being lifted → the radiation recedes (liftDim)
    let key: AnyHashable           // re-bake signature (NOT tick — breathing cycles baked frames)

    init(sources: [FieldSource], palette: [SIMD3<UInt8>], tile: [UInt8], tick: Int,
         phaseToken: String, lifted: Bool) {
        self.sources = sources
        self.tile = tile
        self.tick = tick
        self.lifted = lifted
        let ghost = SIMD3<UInt8>(20, 20, 24)
        pal = (0 ..< 256).map { $0 < palette.count ? palette[$0] : ghost }

        var counts = [Int](repeating: 0, count: 256)
        for v in tile { counts[Int(v)] += 1 }
        let maxC = max(1, counts.max() ?? 1)
        usageNorm = counts.map { Double($0) / Double(maxC) }

        // Coarse re-bake key: phase + every source rect + the 8 dominant colours. Small
        // frame-to-frame camera changes don't churn the bake; a scene/layout shift does.
        let srcKey = sources.map { "\($0.kind == .set ? "s" : "a"):\(Int($0.rect.minX)),\(Int($0.rect.minY)),\(Int($0.rect.width))x\(Int($0.rect.height))" }.joined(separator: ";")
        let topDominant = counts.enumerated().sorted { $0.element > $1.element }.prefix(8)
            .map { "\($0.offset):\($0.element * 16 / maxC)" }.joined(separator: ",")
        key = AnyHashable([phaseToken, "\(pal.count)", srcKey, topDominant, lifted ? "lift" : "-"])
    }

    /// The sRGB8 a stage cell shows on breathing `frame`. `nil` → transparent (a widget owns its
    /// own cells — it draws opaque on top — so the field never bleeds over a widget's edge).
    func color(_ c: Int, _ r: Int, frame f: Int) -> SIMD3<UInt8>? {
        let px = Double(c) + 0.5, py = Double(r) + 0.5

        // Energy from every source; track the top two and the dominant's colour.
        var w1 = 0.0, w2 = 0.0, sum = 0.0
        var domColor = FieldTuning.neutral
        for s in sources {
            if s.rect.contains(CGPoint(x: px, y: py)) { return nil }   // occlusion (order owns it)
            let w = weight(px, py, s)
            sum += w
            if w > w1 { w2 = w1; w1 = w; domColor = sourceColor(px, py, s) }
            else if w > w2 { w2 = w }
        }
        if sum <= 0.001 { return FieldTuning.farDark }              // far calm: a near-black cell
        // While a widget is lifted, the chaos recedes (radiation + lift-drag working together).
        let E = min(1.0, sum) * (lifted ? FieldTuning.liftDim : 1.0)

        // Chaos SEAM: where the runner-up rivals the dominant, mute toward the neutral.
        let interplay = w1 > 0 ? w2 / w1 : 0
        let lit = FieldModel.lerp(domColor, FieldTuning.neutral, FieldTuning.seamMute * interplay)

        // Hybrid texture: energy sets the speckle density via the breathing noise ring.
        let n = FieldModel.noise(c, r, ((f % FieldTuning.phases) + FieldTuning.phases) % FieldTuning.phases)
        return n < E ? lit : FieldTuning.farDark
    }

    /// Falloff weight of source `s` at `(px,py)`: linear ramp to 0 at the source's reach. A `.set`
    /// source's reach is scaled by the usage of the colour it radiates in this direction (dominant
    /// colours reach farther); an `.arrangement` source uses a uniform reach.
    private func weight(_ px: Double, _ py: Double, _ s: FieldSource) -> Double {
        let d = FieldModel.distToRect(px, py, s.rect)
        let reach: Double
        switch s.kind {
        case .set:
            let rank = setRank(px, py, s)
            reach = FieldTuning.reachSet
                * (FieldTuning.usageReachMin + (1 - FieldTuning.usageReachMin) * usageNorm[rank])
        case .arrangement:
            reach = FieldTuning.reachArrangement
        }
        return max(0.0, 1.0 - d / max(1.0, reach))
    }

    /// The colour source `s` radiates at `(px,py)`.
    private func sourceColor(_ px: Double, _ py: Double, _ s: FieldSource) -> SIMD3<UInt8> {
        switch s.kind {
        case .set:
            return pal[setRank(px, py, s)]
        case .arrangement:
            return tile.isEmpty ? pal[setRank(px, py, s)] : bleedColor(px, py, s)
        }
    }

    /// Palette rank for a `.set` source at `(px,py)`: the shutter-order index for the angle of the
    /// cell about the source centre (`GridScript.capture` is identity ⇒ rank == palette index).
    private func setRank(_ px: Double, _ py: Double, _ s: FieldSource) -> Int {
        let theta = FieldModel.turn(px, py, Double(s.rect.midX), Double(s.rect.midY))
        return min(255, max(0, Int(theta * 256.0)))
    }

    /// The arrangement's edge colour in `(px,py)`'s direction: clamp the cell onto the tile and
    /// read that index (an outside cell continues the nearest edge pixel = a bleed).
    private func bleedColor(_ px: Double, _ py: Double, _ s: FieldSource) -> SIMD3<UInt8> {
        let lc = min(63, max(0, Int(px - Double(s.rect.minX))))
        let lr = min(63, max(0, Int(py - Double(s.rect.minY))))
        let i = Int(tile[lr * 64 + lc])
        return i < pal.count ? pal[i] : FieldTuning.neutral
    }

    // MARK: pure helpers

    /// Euclidean distance (cells) from point `(px,py)` to the rectangle `R` (0 inside).
    static func distToRect(_ px: Double, _ py: Double, _ R: CGRect) -> Double {
        let dx = max(Double(R.minX) - px, 0, px - Double(R.maxX))
        let dy = max(Double(R.minY) - py, 0, py - Double(R.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Angle of `(px,py)` about `(cx,cy)`: 0 at top, clockwise, normalised to [0,1).
    static func turn(_ px: Double, _ py: Double, _ cx: Double, _ cy: Double) -> Double {
        var a = atan2(px - cx, -(py - cy))
        if a < 0 { a += 2 * Double.pi }
        return a / (2 * Double.pi)
    }

    static func lerp(_ a: SIMD3<UInt8>, _ b: SIMD3<UInt8>, _ t: Double) -> SIMD3<UInt8> {
        let tt = min(1, max(0, t))
        @inline(__always) func mix(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8(min(255, max(0, (Double(x) + (Double(y) - Double(x)) * tt).rounded())))
        }
        return SIMD3(mix(a.x, b.x), mix(a.y, b.y), mix(a.z, b.z))
    }

    /// Cheap per-cell ordered noise in [0,1), phase-shifted by `f` so the speckle breathes. A hash
    /// stand-in for the blue-noise field the formalization (`Spec.InfluenceField`) pins.
    static func noise(_ c: Int, _ r: Int, _ f: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: (c &* 73856093) ^ (r &* 19349663) ^ (f &* 83492791) ^ 0x9e3779b9)
        h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
        return Double(h) / Double(UInt32.max)
    }
}
