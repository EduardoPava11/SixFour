import SwiftUI
import simd

/// On-device **palette globe**: the 256-colour per-frame palette rendered as a
/// rotatable sphere that steps through the 64 frames and loops. Each colour
/// occupies a fixed slot on an icosahedral (Fibonacci) sphere lattice, so the
/// loop reads as the surface RECOLOURING and BREATHING in place: a slot pushes
/// outward (a peak) where its colour is concentrated, sinks (a valley) where it
/// is rare.
///
/// It is the 3-D sibling of `PaletteStripView` — same data
/// (`palettesForDisplay`, `[frame][colour]` sRGB), same `TimelineView`
/// 20 fps loop clock — with a Canvas 3-D projection instead of a linear strip.
///
/// Interaction (a tool, not a decoration):
///   * **drag** to rotate (orbit),
///   * **scrub** the slider to hold a single one of the 64 steps,
///   * **play/pause** the loop,
///   * **tap a colour** to query it — slot, hex, concentration — with a haptic.
///
/// Concentration is computed in-view as colour-space density (a Gaussian KDE
/// over the 256 colours), so the view depends only on the palette stack. Real
/// pixel-population counts (`ClusterStatistics.Cluster.count`) can replace it
/// later without changing this interface.
struct PaletteSphereView: View {
    let palettes: [[SIMD3<UInt8>]]      // [frame][colour] sRGB; expect 64 × 256
    let frameRate: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var yaw: Double = 0.6
    @State private var pitch: Double = -0.35
    @State private var baseYaw: Double = 0.6
    @State private var basePitch: Double = -0.35
    @State private var scrubFrame: Double? = nil      // non-nil = paused on this step
    @State private var selected: Int? = nil
    @State private var lattice: [SIMD3<Double>] = []
    @State private var conc: [[Double]] = []          // [frame][colour] in 0...1
    @State private var ready = false

    init(palettes: [[SIMD3<UInt8>]], frameRate: Int = 20) {
        self.palettes = palettes
        self.frameRate = frameRate
    }

    private var frameCount: Int { max(1, palettes.count) }
    private var paused: Bool { scrubFrame != nil || reduceMotion }

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / Double(frameRate), paused: paused)) { ctx in
                let frame = displayFrame(date: ctx.date)
                ZStack {
                    Canvas { gc, size in render(into: gc, size: size, frame: frame) }
                        .gesture(rotateGesture)
                        .gesture(tapGesture(frame: frame))
                    readout(frame: frame)
                }
            }
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 0.5))

            controls
        }
        .task { await prepare() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Palette globe: 256 colours on a rotatable sphere, advancing through 64 frames; drag to rotate, tap a colour to inspect.")
    }

    // MARK: controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if scrubFrame == nil { scrubFrame = Double(liveFrame()) } else { scrubFrame = nil }
            } label: {
                Image(systemName: scrubFrame == nil ? "pause.fill" : "play.fill")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
            .tint(.white)

            Slider(
                value: Binding(
                    get: { scrubFrame ?? Double(liveFrame()) },
                    set: { scrubFrame = $0.rounded() }
                ),
                in: 0...Double(frameCount - 1),
                step: 1
            )
            .tint(.white)

            Text("t \(Int(scrubFrame ?? Double(liveFrame())))/\(frameCount - 1)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func readout(frame: Int) -> some View {
        if let k = selected, k < palettes[frame].count {
            let c = palettes[frame][k]
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: Double(c.x)/255, green: Double(c.y)/255, blue: Double(c.z)/255))
                        .frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.4), lineWidth: 0.5))
                    Text(hex(c)).font(.system(.caption2, design: .monospaced))
                }
                Text("slot \(k) · \(Int((conc[safe: frame]?[safe: k] ?? 0) * 100))% conc")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(8)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    // MARK: gestures

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                yaw = baseYaw + Double(v.translation.width) * 0.01
                pitch = max(-1.5, min(1.5, basePitch + Double(v.translation.height) * 0.01))
            }
            .onEnded { _ in baseYaw = yaw; basePitch = pitch }
    }

    private func tapGesture(frame: Int) -> some Gesture {
        SpatialTapGesture()
            .onEnded { v in query(at: v.location, frame: frame) }
    }

    // MARK: rendering

    private func render(into gc: GraphicsContext, size: CGSize, frame: Int) {
        guard ready, frame < palettes.count, !lattice.isEmpty else { return }
        let pal = palettes[frame], cc = conc[safe: frame] ?? []
        let cx = size.width / 2, cy = size.height / 2
        let R = min(size.width, size.height) * 0.40
        let f = 4 * R

        struct Dot { let z: Double; let x: CGFloat; let y: CGFloat; let r: CGFloat; let col: Color; let k: Int }
        var dots: [Dot] = []
        dots.reserveCapacity(min(256, pal.count))
        let n = min(min(256, pal.count), lattice.count)
        for k in 0..<n {
            let w = cc[safe: k] ?? 0
            let radius = R * (0.80 + 0.55 * w)
            let p = rotate(lattice[k] * radius)
            let s = f / (f - p.z)
            let sc = SIMD3<UInt8>(pal[k].x, pal[k].y, pal[k].z)
            dots.append(Dot(
                z: p.z,
                x: cx + CGFloat(p.x * s),
                y: cy - CGFloat(p.y * s),
                r: CGFloat((2.5 + 6 * w) * s),
                col: Color(red: Double(sc.x)/255, green: Double(sc.y)/255, blue: Double(sc.z)/255),
                k: k
            ))
        }
        dots.sort { $0.z < $1.z }
        for d in dots {
            let rect = CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2)
            gc.fill(Path(ellipseIn: rect), with: .color(d.col))
            if d.k == selected {
                gc.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                          with: .color(.white), lineWidth: 1.5)
            }
        }
    }

    private func rotate(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let cy = cos(yaw), sy = sin(yaw), cx = cos(pitch), sx = sin(pitch)
        let x = p.x * cy + p.z * sy
        let z = -p.x * sy + p.z * cy
        let y = p.y
        return SIMD3(x, y * cx - z * sx, y * sx + z * cx)
    }

    private func query(at loc: CGPoint, frame: Int) {
        guard ready, frame < palettes.count, !lattice.isEmpty else { return }
        // Reproject at a nominal size; the Canvas is square-ish so use a stored guess.
        // We reproject relative to the view by re-deriving R from the rendered frame:
        // SpatialTapGesture gives points in the Canvas's local space.
        let cx = lastSize.width / 2, cy = lastSize.height / 2
        let R = min(lastSize.width, lastSize.height) * 0.40
        let f = 4 * R
        let cc = conc[safe: frame] ?? []
        var best = -1; var bestD = 28.0 * 28.0
        let n = min(min(256, palettes[frame].count), lattice.count)
        for k in 0..<n {
            let w = cc[safe: k] ?? 0
            let p = rotate(lattice[k] * R * (0.80 + 0.55 * w))
            let s = f / (f - p.z)
            let px = cx + CGFloat(p.x * s), py = cy - CGFloat(p.y * s)
            let dx = Double(px - loc.x), dy = Double(py - loc.y)
            let d = dx*dx + dy*dy
            if d < bestD { bestD = d; best = k }
        }
        if best >= 0 { selected = best; Haptics.selection() }
    }

    // Canvas size is needed for hit-testing; capture it via a background reader.
    @State private var lastSize: CGSize = CGSize(width: 300, height: 260)

    // MARK: frame clock

    private func liveFrame() -> Int { displayFrame(date: Date()) }

    private func displayFrame(date: Date) -> Int {
        if let s = scrubFrame { return min(frameCount - 1, max(0, Int(s))) }
        if reduceMotion { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        return Int((t * Double(frameRate)).rounded(.down)) % frameCount
    }

    // MARK: data prep

    private func prepare() async {
        let lat = Self.fibonacciLattice(256)
        let pal = palettes
        let dens = await Task.detached(priority: .userInitiated) {
            Self.concentration(pal)
        }.value
        await MainActor.run {
            self.lattice = lat
            self.conc = dens
            self.ready = true
        }
    }

    /// Fibonacci sphere: 256 near-uniform directions (a stable colour-slot lattice).
    nonisolated static func fibonacciLattice(_ k: Int) -> [SIMD3<Double>] {
        let ga = Double.pi * (3 - (5.0).squareRoot())
        return (0..<k).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(k)
            let r = (max(0, 1 - y * y)).squareRoot()
            let th = ga * Double(i)
            return SIMD3(cos(th) * r, y, sin(th) * r)
        }
    }

    /// Per-frame colour-space density (Gaussian KDE), normalised to 0...1.
    nonisolated static func concentration(_ palettes: [[SIMD3<UInt8>]]) -> [[Double]] {
        let h2 = 0.045
        return palettes.map { pal -> [Double] in
            let pts = pal.map { SIMD3<Double>(Double($0.x)/255, Double($0.y)/255, Double($0.z)/255) }
            var out = [Double](repeating: 0, count: pts.count)
            for i in 0..<pts.count {
                var s = 0.0
                for j in 0..<pts.count {
                    let d = pts[i] - pts[j]
                    s += exp(-(d.x*d.x + d.y*d.y + d.z*d.z) / h2)
                }
                out[i] = s
            }
            let mx = out.max() ?? 1
            return mx > 0 ? out.map { $0 / mx } : out
        }
    }

    private func hex(_ c: SIMD3<UInt8>) -> String {
        String(format: "#%02X%02X%02X", c.x, c.y, c.z)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

#if DEBUG
#Preview("Palette Globe") {
    // Synthetic 64×256 drifting palette so the tool is demonstrable without a capture.
    let frames = 64, k = 256
    let palettes: [[SIMD3<UInt8>]] = (0..<frames).map { t in
        let u = Double(t) / Double(frames) * 2 * .pi
        return (0..<k).map { i in
            let cl = Double(i % 6)
            let r = 0.5 + 0.4 * sin(u + cl)
            let g = 0.5 + 0.4 * sin(u * 2 + cl * 1.7)
            let b = 0.5 + 0.4 * cos(u + cl * 0.5 + Double(i) * 0.01)
            return SIMD3<UInt8>(UInt8(max(0, min(255, r*255))),
                                UInt8(max(0, min(255, g*255))),
                                UInt8(max(0, min(255, b*255))))
        }
    }
    return PaletteSphereView(palettes: palettes)
        .frame(width: 320)
        .padding()
        .background(.black)
}
#endif
