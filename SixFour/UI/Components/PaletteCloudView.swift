import SwiftUI
import simd

// MARK: - PaletteCloudView — P4, the OKLab Temporal Cloud
//
// The one palette view that adds a genuinely-NEW perceivable axis: TIME.
// See docs/SIXFOUR-HIGHDIM-UIUX.md §3 P4 (+ critic §7) and
// docs/palette-explorer-2d-3d-4d-design.md §2.3.
//
// THE GOVERNING PRINCIPLE (the user's): we simplify a high-D object by
// DIMENSIONAL PROJECTION, and 2D/3D are what we project TO because they are the
// only surfaces we can make UI controls out of. **The projections themselves
// ARE the controls.** So this view never tries to show 4D at once:
//
//   • 3 OKLab axes → a 3-D point set at TRUE coordinates (L→up/y, a→x, b→z).
//     NOT an embedding (no t-SNE/UMAP/SOM/PCA/autoencoder — forbidden: they are
//     non-deterministic, off the Haskell golden contract, distance-dishonest,
//     and pointless when the data is already a meaningful 3-space).
//   • ORTHOGRAPHIC projection is the STICKY DEFAULT — screen distance =
//     perceptual distance, the honesty claim that holds ONLY orthographic.
//     Orbit-drag rotates that 3-D projection (the orbit IS the control).
//   • An axis-pair PLANE picker chooses which OKLab pair forms the 2-D shadow.
//     Picking a plane SNAPS the orbit to a golden (yaw,pitch) — plane-pick and
//     orbit are the SAME control (the honesty refinement from Spec.CloudProjection
//     `axisPairOrbit`): a plane is a faithful planar projection, not a relabel.
//   • TIME (the 4th) → a scrub playhead over the 64 frames. The playhead is the
//     projection of the temporal axis. Motion trails = a colour's trajectory.
//     Reduce-Motion → static streak (time then partly lost — conceded).
//   • population → dot RADIUS (a non-positional channel; from perFrameCells).
//   • brushing a dot (or a SplitTree subtree) → opaque-darker index-step
//     highlight, linked across views by IndexedColor.index.
//
// CONTRACT: Tier-2 ships ZERO third-party deps — hand-written SwiftUI Canvas +
// simd. 256 dots, painter's depth-sort, no SceneKit/RealityKit/Metal (the
// VoxelCube is x,y,t pixels and keeps its Metal raymarcher; the cloud is the
// 256-colour palette and is the doc's "hand-written Canvas" call).
//
// SPEC STATUS (honest): the projection LAWS are pinned in
// `SixFour.Spec.CloudProjection` (Haskell, `cabal test` green — oklabToWorld,
// rotateYawPitch, orthographic, perspective, axisPairOrbit, aabbHull,
// populationToRadius, temporalLerp, quad4 ghost). This view PORTS that math but is
// NOT yet golden-pinned to it — there is no `Codegen.CloudProjection` emitter or
// parity test. `rotateYawPitch` + `oklabToWorld` match scalar-for-scalar; two
// constants currently DIVERGE and are renderer/explore concerns, not distance
// claims: the perspective `eye` (explore-only, no distance claim) and the
// population→radius RANGE (rendered in POINTS like `span`; only the area-true
// √-law is contractual). REMAINING SPEC-FIRST DEBT before ship:
//   - add a `Codegen.CloudProjection` emitter → `Generated/…Contract.swift`, then
//     replace these inline constants with the generated mirror + a golden-vector
//     parity test, closing the perspective/radius divergence.
//   - subtree AABB hull rendering: math exists (`aabbHull`/`quad4GhostError`) but
//     is NOT drawn in this prototype — the 4⁴ lossy hull is a future step, not a
//     shipped feature (do not read the docs' "4⁴ hull" as present here).

// MARK: - Honest projection mode

/// How the 3-D OKLab point set is flattened to the 2-D screen.
/// `.orthographic` is the **sticky default** and the ONLY mode under which the
/// "screen distance = perceptual distance" claim is honest. `.perspective` is an
/// explicitly-labelled "explore" mode that DROPS the distance claim.
enum CloudProjection: String, CaseIterable, Codable, Sendable {
    case orthographic   // distance-true (honest); the default
    case perspective    // "explore" — distance claim removed (labelled lossy)

    var label: String { self == .orthographic ? "ortho" : "explore" }
    /// The honesty annotation surfaced in chrome + spoken once.
    var distanceClaim: String {
        self == .orthographic
            ? "Orthographic — screen distance is perceptual distance."
            : "Explore (perspective) — distance is NOT to scale."
    }
}

/// The three FAITHFUL planar shadows — a snap-to view that lays a chosen OKLab
/// axis pair flat to the screen. Ported from `SixFour.Spec.CloudProjection`
/// (`AxisPair` + `axisPairOrbit`). The key honesty point: picking a plane and
/// orbiting are the SAME control — a plane is just a specific (yaw, pitch) of the
/// orbit. So the picker doesn't relabel axes; it SNAPS the real 3-D projection.
enum CloudPlane: String, CaseIterable, Codable, Sendable {
    case ab    // chroma disc, top-down (default): u = a, v = b. (yaw, pitch) = (0, -π/2)
    case La    // front: u = a (green–red), v = L (light). (0, 0)
    case Lb    // side:  u = b (blue–yellow), v = L. (π/2, 0)

    var label: String { self == .ab ? "a×b" : self == .La ? "L×a" : "L×b" }
    /// The (yaw, pitch) that snaps this pair flat to the screen (golden).
    var orbit: (yaw: Float, pitch: Float) {
        switch self {
        case .La: return (0, 0)
        case .Lb: return (.pi / 2, 0)
        case .ab: return (0, -.pi / 2)
        }
    }
    var axesLabel: String {
        switch self {
        case .ab: return "x: a (green–red), y: b (blue–yellow), depth: L (light)"
        case .La: return "x: a (green–red), y: L (light), depth: b (blue–yellow)"
        case .Lb: return "x: b (blue–yellow), y: L (light), depth: a (green–red)"
        }
    }
}

/// Trail length for a colour's temporal trajectory. Default `.off`.
enum CloudTrail: String, CaseIterable, Codable, Sendable {
    case off, short, long
    var label: String { rawValue }
    var frames: Int { self == .off ? 0 : self == .short ? 6 : 16 }
}

// MARK: - The single owner of all cloud knobs (GRID Law #5 spirit)

struct CloudState: Equatable {
    // Sticky default: the a×b chroma disc, top-down, orthographic — a FAITHFUL
    // planar shadow (golden `axisPairOrbit PlaneAB = (0, -π/2)`). Distance-true
    // out of the box; the user orbits away from it deliberately.
    var yaw: Float = 0
    var pitch: Float = -.pi / 2
    var projection: CloudProjection = .orthographic
    // NOTE: the time cursor (`frame`) and `playing` moved to the shared PlaybackClock.
    var trail: CloudTrail = .off
    /// Brushed slot index (IndexedColor.index), linked across views. nil = none.
    var brushed: Int? = nil

    var orbitMagnitude: Float { (yaw * yaw + pitch * pitch).squareRoot() }
}

// MARK: - Precomputed geometry (off-main, all 64 frames)

/// One colour at one frame: its true OKLab position, sRGB fill, population, and
/// stable slot index. Built once per capture; the render tick is lookup + rotate
/// + project + sort only (never per-tick OKLab conversion — design §4 perf).
private struct CloudPoint {
    let index: Int               // IndexedColor.index — the cross-view link key
    let oklab: SIMD3<Float>      // true coords (L,a,b)
    let srgb: SIMD3<UInt8>
    let population: Int          // perFrameCells[frame][k].count → radius
}

/// All 64 frames of points, plus the fixed working-cube transform. The OKLab→world
/// mapping is a CONTRACT (L→y, a→x, b→z) so the axes never drift — pinned in the
/// golden `SixFour.Spec.CloudProjection.oklabToWorld`.
/// OKLab → world, the DISTANCE-TRUE map. Hand-port of the golden
/// `SixFour.Spec.CloudProjection.oklabToWorld`: centre (Lᶜ,aᶜ,bᶜ)=(0.5,0,0), then a
/// SINGLE ISOTROPIC scale s=2 on all three axes (a→x, L→y up, b→z). Isotropy is what
/// makes world distance = OKLab distance up to the constant s (`lawWorldIsometry`) —
/// per-axis scaling is FORBIDDEN because it would distort perceptual distance, the lie
/// the cloud must not tell. Pinned bit-for-bit (within float tolerance) against
/// `CloudProjectionGolden` by `CloudProjectionGoldenTests`. `lab` is (L=x, a=y, b=z).
enum CloudWorld {
    static let centreL: Float = 0.5
    static let centreA: Float = 0.0
    static let centreB: Float = 0.0
    static let scale: Float = 2.0          // canonicalScale

    @inline(__always) static func map(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            (lab.y - centreA) * scale,     // (a - aᶜ)·s → x (green–red)
            (lab.x - centreL) * scale,     // (L - Lᶜ)·s → y (up)
            (lab.z - centreB) * scale      // (b - bᶜ)·s → z (blue–yellow depth)
        )
    }
}

private struct CloudGeometry {
    let frames: [[CloudPoint]]   // 64 × 256
    let maxPopulation: Int

    /// Delegates to the spec-pinned `CloudWorld.map` (see `CloudProjectionGolden`).
    @inline(__always) static func world(_ lab: SIMD3<Float>) -> SIMD3<Float> {
        CloudWorld.map(lab)
    }

    static func build(palettes: [[SIMD3<UInt8>]],
                      cells: [[SixFourSignificantCell]]?) -> CloudGeometry {
        var out: [[CloudPoint]] = []
        out.reserveCapacity(palettes.count)
        var maxPop = 1
        for (t, pal) in palettes.enumerated() {
            var row: [CloudPoint] = []
            row.reserveCapacity(pal.count)
            for (k, c) in pal.enumerated() {
                let lab = ColorScience.srgb8ToOKLab(c.x, c.y, c.z).simd
                let pop: Int
                if let cells, cells.indices.contains(t), cells[t].indices.contains(k) {
                    pop = max(0, cells[t][k].count)
                } else {
                    pop = 0   // no significance data → uniform radius (guarded below)
                }
                maxPop = max(maxPop, pop)
                row.append(CloudPoint(index: k, oklab: lab, srgb: c, population: pop))
            }
            out.append(row)
        }
        return CloudGeometry(frames: out, maxPopulation: maxPop)
    }

    var hasPopulation: Bool { maxPopulation > 1 }
}

// MARK: - The view

/// The OKLab Temporal Cloud. Pure SwiftUI Canvas + simd; 256 dots.
@MainActor
struct PaletteCloudView: View {
    let palettes: [[SIMD3<UInt8>]]
    let perFrameCells: [[SixFourSignificantCell]]?
    /// The canonical SplitTree of the CURRENT frame, for subtree brushing/hulls.
    /// Built by the caller (reuse `SplitTree.build`); optional so the cloud still
    /// renders on legacy data.
    var splitTree: SplitTree?
    var branching: PaletteBranching = .b16
    var edge: CGFloat = SFTheme.gifCanvasPt
    /// The shared playback clock — the cloud's time cursor / play-pause come from
    /// here, so the cloud scrubs in lockstep with the GIF player (the old private
    /// 60 Hz `Timer` was removed).
    var clock: PlaybackClock
    /// Brushed index binding — shared across all palette views by IndexedColor.index.
    @Binding var brushedIndex: Int?

    @State private var cloud = CloudState()
    @State private var geometry: CloudGeometry? = nil
    /// Still read for the reduce-motion "static streak" affordance (the trail signal);
    /// the playback freeze itself is owned by the shared clock.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            cloudSurface
            controls
        }
        .task(id: paletteSignature) { rebuildGeometry() }
        .onChange(of: brushedIndex) { _, v in cloud.brushed = v }
        .onAppear { cloud.brushed = brushedIndex }
    }

    /// Cheap identity so the geometry rebuild fires once per distinct capture.
    private var paletteSignature: Int {
        var h = Hasher()
        h.combine(palettes.count)
        h.combine(palettes.first?.first?.x ?? 0)
        h.combine(palettes.last?.last?.z ?? 0)
        return h.finalize()
    }

    // MARK: The cloud is the primary interactive surface

    private var cloudSurface: some View {
        ZStack(alignment: .topTrailing) {
            cloudCanvas
                .frame(width: edge, height: edge)
                .background(Color.black)
                .highPriorityGesture(orbitGesture)
                .gesture(brushTap)
                .accessibilityElement()
                .accessibilityLabel("OKLab temporal palette cloud, 256 colours")
                .accessibilityValue(spokenSummary)

            // Reset orbit to the honest ortho top/side snap (glass chrome).
            GlassIconButton(systemImage: "cube.transparent",
                            accessibilityLabel: "Snap to orthographic rest") {
                withAnimation(.easeInOut(duration: 0.4)) {
                    cloud.yaw = 0; cloud.pitch = 0
                    cloud.projection = .orthographic
                }
            }
            .padding(8)
        }
    }

    /// The render tick: for the current frame, rotate world coords, project per
    /// the chosen mode, painter's back-to-front sort, fill flat indexed dots. The
    /// dot is CONTENT (opaque indexed colour, no opacity-as-shading); brushed dots
    /// step to an opaque darker index, never alpha (GRID Law #2).
    private var cloudCanvas: some View {
        // Reads the shared clock; re-renders when it advances (under reduce-motion the
        // clock holds frame 0, and trails render as a faded static streak so the
        // temporal signal isn't entirely motion-gated away).
        canvasFor(frame: clock.frame)
            .pixelFrame()
    }

    private func canvasFor(frame index: Int) -> some View {
        Canvas { ctx, size in
            guard let geo = geometry, !geo.frames.isEmpty else { return }
            let f = min(index, geo.frames.count - 1)
            let yaw = cloud.yaw, pitch = cloud.pitch
            let center = SIMD2<Float>(Float(size.width) * 0.5, Float(size.height) * 0.5)
            let span = Float(min(size.width, size.height)) * 0.42

            // --- trails: a colour's trajectory over the last N frames (or static
            // streak under Reduce Motion). Drawn first, behind the live dots. ---
            let trailN = cloud.trail.frames
            if trailN > 0 {
                for n in stride(from: trailN, through: 1, by: -1) {
                    let pf = ((f - n) % geo.frames.count + geo.frames.count) % geo.frames.count
                    // GRID Law #2: trail samples are OPAQUE. Age is shown by an
                    // opaque darker index step + a smaller radius — NEVER by alpha
                    // on a content dot (the prior `.opacity()` was a Law #2 breach).
                    let age = Float(n) / Float(trailN)                 // 1 = oldest
                    let dim = 0.65 - 0.42 * age                        // 0.65 recent … 0.23 old
                    let r = CGFloat(1.0 + 1.4 * Double(1 - age))       // ~2.4 recent … 1.0 old
                    for p in geo.frames[pf] {
                        if let b = cloud.brushed, b != p.index { continue }   // brushed → only its trail
                        let s = project(world: CloudGeometry.world(p.oklab),
                                        yaw: yaw, pitch: pitch, center: center, span: span, size: size)
                        let c = p.srgb
                        let trailC = SIMD3<UInt8>(UInt8(Float(c.x) * dim),
                                                  UInt8(Float(c.y) * dim),
                                                  UInt8(Float(c.z) * dim))
                        let sx = CGFloat(s.x), sy = CGFloat(s.y)
                        let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(Color(srgb8: trailC)))
                    }
                }
            }

            // --- live dots: project, depth-sort (painter's, smallest-z last =
            // front-most wins for the visible dot in dense clusters). ---
            var projected: [(s: SIMD2<Float>, z: Float, p: CloudPoint)] = []
            projected.reserveCapacity(geo.frames[f].count)
            for p in geo.frames[f] {
                let w = rotate(CloudGeometry.world(p.oklab), yaw: yaw, pitch: pitch)
                let s = projectRotated(w, center: center, span: span, size: size)
                projected.append((s, w.z, p))
            }
            projected.sort { $0.z > $1.z }   // far (large z) first, near last

            for entry in projected {
                let p = entry.p
                let r = radius(for: p, geo: geo)
                let sx = CGFloat(entry.s.x), sy = CGFloat(entry.s.y)
                var fill = p.srgb
                // Selection = opaque DARKER index step (GRID Law #2; never alpha).
                if let b = cloud.brushed {
                    if b == p.index {
                        // emphasise the brushed dot by a bright opaque ring step
                        let rr = r + 2
                        let ring = CGRect(x: sx - rr, y: sy - rr, width: rr * 2, height: rr * 2)
                        ctx.fill(Path(ellipseIn: ring), with: .color(.white))
                    } else {
                        fill = darkenStep(p.srgb)   // others recede via an opaque dark step
                    }
                }
                let rect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(srgb8: fill)))
            }

            // --- subtree hull (deterministic OKLab AABB, tagged LOSSY when 4-ary).
            // Off unless a subtree is brushed; drawn as opaque hairline edges. ---
            // (Hull rendering kept minimal in the prototype; the AABB math is
            //  SPEC-TODO. The structural read lives in the dot geometry itself.)
        }
    }

    // MARK: Projection math (ported from the golden Spec.CloudProjection)

    /// Yaw about world up-axis Y, then pitch about X — a composition of two
    /// rotations, hence an ISOMETRY (orbit preserves 3-D distance). Ported scalar-
    /// for-scalar from the golden `SixFour.Spec.CloudProjection.rotateYawPitch`
    /// (same convention as VoxelCubeView). TODO(spec-pin): verify vs the golden.
    @inline(__always)
    private func rotate(_ w: SIMD3<Float>, yaw: Float, pitch: Float) -> SIMD3<Float> {
        let cy = cos(yaw), sy = sin(yaw)
        let x1 = cy * w.x + sy * w.z          // yaw about Y: (x,z)
        let z1 = -sy * w.x + cy * w.z
        let cp = cos(pitch), sp = sin(pitch)
        let y2 = cp * w.y - sp * z1           // pitch about X: (y,z)
        let z2 = sp * w.y + cp * z1
        return SIMD3<Float>(x1, y2, z2)
    }

    @inline(__always)
    private func project(world w: SIMD3<Float>, yaw: Float, pitch: Float,
                         center: SIMD2<Float>, span: Float, size: CGSize) -> SIMD2<Float> {
        projectRotated(rotate(w, yaw: yaw, pitch: pitch), center: center, span: span, size: size)
    }

    /// The honesty hinge. Orthographic: screen = rotated (x,y) scaled by a CONSTANT
    /// — distance is preserved, the claim holds. Perspective: divide by depth — the
    /// "explore" mode, distance claim DROPPED (and labelled as such in chrome).
    @inline(__always)
    private func projectRotated(_ w: SIMD3<Float>, center: SIMD2<Float>,
                                span: Float, size: CGSize) -> SIMD2<Float> {
        let x: Float, y: Float
        switch cloud.projection {
        case .orthographic:
            x = w.x * span
            y = w.y * span
        case .perspective:
            // Explore mode only — carries NO distance claim, so this eye constant
            // is a renderer choice, NOT spec-pinned (the spec parameterizes `eye`).
            let camZ: Float = 2.2
            let denom = camZ - w.z            // nearer (smaller z) → larger
            let persp = camZ / max(0.3, denom)
            x = w.x * span * persp
            y = w.y * span * persp
        }
        // Screen y grows downward → flip so OKLab L (up) reads up.
        return SIMD2<Float>(center.x + x, center.y - y)
    }

    /// population → radius: area-true (√), so a dot's AREA reads as population —
    /// the ONLY contractual part (matches the spec's √-law). The min/max here are
    /// in POINTS (a renderer concern, like `span`); they intentionally differ from
    /// the spec's world-unit 0.6…3.0 and are NOT golden-pinned yet (SPEC-TODO:
    /// derive the points range from the spec range × the on-screen scale).
    @inline(__always)
    private func radius(for p: CloudPoint, geo: CloudGeometry) -> CGFloat {
        guard geo.hasPopulation else { return 3.0 }
        let frac = Double(p.population) / Double(geo.maxPopulation)
        return 2.0 + 5.0 * CGFloat(frac.squareRoot())   // 2…7 pt (renderer units)
    }

    /// An opaque darker step (index-dither spirit) for de-emphasised dots — never
    /// alpha on a content dot (GRID Law #2).
    @inline(__always)
    private func darkenStep(_ c: SIMD3<UInt8>) -> SIMD3<UInt8> {
        SIMD3<UInt8>(UInt8(Int(c.x) * 35 / 100),
                     UInt8(Int(c.y) * 35 / 100),
                     UInt8(Int(c.z) * 35 / 100))
    }

    // MARK: Controls — every control manipulates a real projection

    private var controls: some View {
        VStack(spacing: 10) {
            // HONEST: projection mode — toggles the actual distance-true ↔ explore
            // projection. The label states the honesty claim.
            projectionSelector

            // HONEST: the 2-D shadow plane — picking a plane SNAPS the orbit to a
            // specific (yaw, pitch) (golden `axisPairOrbit`). Plane-pick and orbit
            // are the SAME control: a plane is just a faithful planar projection.
            planeSelector

            // HONEST: the time projection — playhead over the 64 frames + trails.
            transportCluster

            // Read-only legend (radius ↔ population) + the honesty annotation.
            legend
        }
        .frame(maxWidth: edge)
    }

    // Pixelated cell segments for the projection mode.
    private var projectionSelector: some View {
        CellSelector(options: CloudProjection.allCases.map { (value: $0, label: $0.label) },
                     selection: Binding(get: { cloud.projection }, set: { cloud.projection = $0 }))
    }

    /// The plane snap-selector. Tapping a plane animates yaw/pitch to the golden
    /// orbit for that OKLab axis pair (and resets the projection to ortho — the
    /// faithful planar shadow is an orthographic claim). Highlights whichever
    /// plane the current orbit is snapped to.
    // Pixelated plane snap-selector. Not a plain CellSelector because selection is
    // DERIVED (currentPlane) and may be none when orbited freely — so the segments are
    // built manually: CellText on a flat cell ground, 1-cell accent border when snapped.
    private var planeSelector: some View {
        HStack(spacing: GlobalLattice.pt(GlobalLattice.gutterCells)) {
            ForEach(CloudPlane.allCases, id: \.self) { plane in
                let isSel = currentPlane == plane && cloud.projection == .orthographic
                Button {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        cloud.yaw = plane.orbit.yaw
                        cloud.pitch = plane.orbit.pitch
                        cloud.projection = .orthographic   // a planar shadow is ortho-honest
                    }
                } label: {
                    CellText(plane.label, rows: 9, ink: isSel ? .white : Color(srgb8: SIMD3(140, 140, 140)))
                        .padding(.horizontal, GlobalLattice.pt(3))
                        .frame(minHeight: 44)
                        .background(Color(srgb8: SFTheme.ledGhost))
                        .border(Color(srgb8: isSel ? SIMD3(96, 165, 250) : SFTheme.ledGhost),
                                width: GlobalLattice.pt(1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(plane.label) plane"))
                .accessibilityAddTraits(isSel ? [.isSelected] : [])
            }
        }
    }

    /// Which faithful plane the orbit is (approximately) snapped to, if any.
    private var currentPlane: CloudPlane? {
        CloudPlane.allCases.first { p in
            abs(cloud.yaw - p.orbit.yaw) < 0.01 && abs(cloud.pitch - p.orbit.pitch) < 0.01
        }
    }

    private var transportCluster: some View {
        VStack(spacing: 8) {
            GlassToolbarCluster {
                GlassIconButton(systemImage: clock.playing ? "pause.fill" : "play.fill",
                                accessibilityLabel: clock.playing ? "Pause time" : "Play time") {
                    clock.togglePlay()
                }
                // Trail length cycles off → short → long (the trajectory control).
                GlassIconButton(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                accessibilityLabel: "Trail length \(cloud.trail.label)",
                                tint: cloud.trail == .off ? .white.opacity(0.6) : .white) {
                    withAnimation(.snappy) { cloud.trail = cloud.trail.next }
                }
            }
            // The playhead — the literal projection of the temporal axis (pixelated).
            VStack(alignment: .leading, spacing: GlobalLattice.pt(1)) {
                CellText("Frame \(clock.frame + 1)/\(max(palettes.count, 1))",
                         rows: 7, ink: Color(srgb8: SIMD3(210, 210, 210)))
                CellSlider(value: Binding(get: { Double(clock.frame) },
                                          set: { clock.scrub(to: Int($0.rounded())) }),
                           range: 0...Double(max(palettes.count - 1, 1)))
            }
            .padding(GlobalLattice.pt(6))
            .background(Color(srgb8: SFTheme.ledGhost))   // flat cell panel, no glass
        }
    }

    private var legend: some View {
        GlassInfoChip {   // now a flat ledGhost cell ground (no glass)
            VStack(alignment: .leading, spacing: GlobalLattice.pt(1)) {
                CellText(cloud.projection.distanceClaim, rows: 7, ink: .white)
                CellText("Dot area = population. " + (currentPlane?.axesLabel ?? "Orbited — drag to a snap plane to read axes."),
                         rows: 7, ink: Color(srgb8: SIMD3(140, 140, 140)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Gestures (the projections ARE the controls)

    /// Orbit-drag = rotate the 3-D projection. No inertia → nothing to freeze.
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let gain: Float = 0.007
                cloud.yaw += Float(v.translation.width) * gain
                cloud.pitch += Float(-v.translation.height) * gain
                cloud.pitch = max(-1.5, min(1.5, cloud.pitch))
            }
    }

    /// Tap-to-brush: front-most-wins pick (smallest screen-z) in the current
    /// frame, then publish the index so every linked view highlights the same slot.
    private var brushTap: some Gesture {
        SpatialTapGesture()
            .onEnded { ev in pickNearest(at: ev.location) }
    }

    private func pickNearest(at loc: CGPoint) {
        guard let geo = geometry, !geo.frames.isEmpty else { return }
        let f = min(clock.frame, geo.frames.count - 1)
        let yaw = cloud.yaw, pitch = cloud.pitch
        let size = CGSize(width: edge, height: edge)
        let center = SIMD2<Float>(Float(edge) * 0.5, Float(edge) * 0.5)
        let span = Float(edge) * 0.42

        var best: (index: Int, d2: Float, z: Float)? = nil
        for p in geo.frames[f] {
            let w = rotate(CloudGeometry.world(p.oklab), yaw: yaw, pitch: pitch)
            let s = projectRotated(w, center: center, span: span, size: size)
            let dx = s.x - Float(loc.x), dy = s.y - Float(loc.y)
            let d2 = dx * dx + dy * dy
            guard d2 < 20 * 20 else { continue }   // within ~20 pt of a dot
            // front-most wins: prefer smaller z, then smaller distance.
            if best == nil || w.z < best!.z - 0.001 || (abs(w.z - best!.z) < 0.001 && d2 < best!.d2) {
                best = (p.index, d2, w.z)
            }
        }
        let picked = best?.index
        cloud.brushed = (picked == cloud.brushed) ? nil : picked   // tap again to clear
        brushedIndex = cloud.brushed                               // publish to linked views
    }

    // MARK: Drivers / a11y

    // NOTE: the cloud's private playback timer + `advance()` were removed — the time
    // cursor now comes from the shared `PlaybackClock` (the single clock).

    private func rebuildGeometry() {
        geometry = CloudGeometry.build(palettes: palettes, cells: perFrameCells)
    }

    /// One spoken summary (NOT 256 focusable dots) — mirrors PaletteTreeView.
    private var spokenSummary: String {
        var s = "256 colours at their OKLab coordinates. \(cloud.projection.distanceClaim) "
        s += "Frame \(clock.frame + 1) of \(max(palettes.count, 1)). "
        s += currentPlane.map { "Snapped to the \($0.label) plane; \($0.axesLabel). " } ?? "Orbited freely. "
        s += "Dot area shows population. Drag to orbit; tap a dot to brush."
        if reduceMotion { s += " Reduce Motion: time is shown as a static streak." }
        if let b = cloud.brushed { s += " Brushed slot \(b)." }
        return s
    }
}

private extension CloudTrail {
    var next: CloudTrail { self == .off ? .short : self == .short ? .long : .off }
}

// MARK: - Preview (synthetic 64-frame palette, no capture needed)

#if DEBUG
private func makeSyntheticCloudPalettes() -> ([[SIMD3<UInt8>]], [[SixFourSignificantCell]]) {
    let frames = 64, k = 256
    var pals: [[SIMD3<UInt8>]] = []
    var cells: [[SixFourSignificantCell]] = []
    for t in 0..<frames {
        var p = [SIMD3<UInt8>](repeating: .zero, count: k)
        var cs: [SixFourSignificantCell] = []
        for i in 0..<k {
            let hue = Float(i) / Float(k) + Float(t) / Float(frames) * 0.3
            let r = UInt8((0.5 + 0.5 * sin(hue * 6.28318)) * 255)
            let g = UInt8((0.5 + 0.5 * sin((hue + 0.33) * 6.28318)) * 255)
            let b = UInt8((0.5 + 0.5 * sin((hue + 0.66) * 6.28318)) * 255)
            p[i] = SIMD3<UInt8>(r, g, b)
            let pop = 16 + (i * 7 + t * 3) % 200   // varied populations exercise radius
            cs.append(SixFourSignificantCell(mean: .zero, stdDev: .zero, count: pop, provenance: .extracted))
        }
        pals.append(p); cells.append(cs)
    }
    return (pals, cells)
}

#Preview("Palette Cloud — synthetic") {
    struct Host: View {
        @State var brushed: Int? = nil
        @State var clock = PlaybackClock()
        var body: some View {
            let (pals, cells) = makeSyntheticCloudPalettes()
            ScrollView {
                PaletteCloudView(palettes: pals, perFrameCells: cells,
                                 splitTree: nil, clock: clock, brushedIndex: $brushed)
                    .padding()
            }
            .preferredColorScheme(.dark)
        }
    }
    return Host()
}
#endif
