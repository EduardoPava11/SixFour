import SwiftUI
import UIKit
import Metal
import QuartzCore
import os
import simd

/// THE GPU INFLUENCE FIELD (S3) — a `CAMetalLayer`-backed SwiftUI host that runs `field.metal`,
/// rendering the radiation ground on the GPU off the main thread. This replaces the CPU per-tick
/// `CellBitmap` bake (`StageField`/`InfluenceField`) — the disjointedness fix
/// (docs/SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md M1 / SIXFOUR-METAL-FIELD-SPEC-ALIGNMENT.md S3).
///
/// ONE CLOCK: there is NO `CADisplayLink` here — the κ `tick` is passed in, so SwiftUI calls
/// `updateUIView` once per 20 fps tick, which drives exactly one GPU draw. Spec-aligned: the
/// shader reads the generated `FieldTuning.metal.h` constants + the byte-exact `SixFourBoundary`
/// Stage mask (fed as uniforms) + the byte-exact dither hash.
///
/// DEFAULT cell-grid ground: the GPU field runs whenever Metal is available (every real
/// device), so the live field is smooth off the main thread. The CPU `InfluenceField` is the
/// fallback only when Metal is unavailable. In DEBUG, `-cpuField` forces the CPU path for A/B.
/// **On-device only** — the geometry/timing is the user's to verify; Claude compile-checks.
struct FieldMetalView: UIViewRepresentable {
    let surface: Surface
    let placement: [ColorIdentity: (col: Int, row: Int)]
    let tick: Int
    /// True while burst frames are landing — drives the E9 CAPTURE-ENERGY pour ramp.
    var capturing: Bool = false

    /// GPU field on iff the off-main core build has landed (`.ready`). A computed var (NOT a
    /// cached static let) so it flips true once the background build finishes — StageGround is
    /// re-evaluated every clock.tick, so the switch re-runs within one 20 fps tick (~50 ms) of
    /// readiness. The CPU bake (`InfluenceField`) is the no-Metal fallback; `-cpuField` (DEBUG)
    /// forces it so the two can still be A/B-compared.
    static var enabled: Bool {
        guard FieldMetalCore.state == .ready else { return false }
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-cpuField")
        #else
        return true
        #endif
    }

    func makeUIView(context: Context) -> FieldUIView {
        let v = FieldUIView()
        v.configure()
        return v
    }

    func updateUIView(_ v: FieldUIView, context: Context) {
        // Read σ on the MainActor; hand plain value arrays to the view (no actor hop on the GPU path).
        let (tile, tpal) = Self.arrangement(of: surface)
        let palSrc = tpal.isEmpty ? surface.palette : tpal
        let lifted = surface.liftedWidget != nil
        let ramp = CellEase.progress(tick, since: surface.liftChangedTick, ticks: FieldTuning.liftRampTicks)
        let liftAmount = Float(lifted ? ramp : (1 - ramp))
        let live: Bool = { if case .live = surface.phase { return true }; return false }()
        v.update(sources: Self.sources(placement, live: live),
                 palette: Self.packPalette(palSrc),
                 usage: Self.usage(tile),
                 tile: Self.packTile(tile),
                 tick: tick, liftAmount: liftAmount,
                 energyScale: Self.energyScale(live: live, capturing: capturing, tick: tick))
    }

    /// E9 CAPTURE ENERGY — the ground's ONE named function on Live. Idle `.live` dims to
    /// the spec-pinned near-void (`SixFourFieldTuning.liveIdleEnergy`); while burst frames
    /// land it rises to FULL energy scaled by the (tick mod 4 + 1)/4 pour ramp (peaking on
    /// each 16-rung realize — the ground glows exactly when photons are being banked).
    /// Non-live phases keep full energy (their grounds already earn or suppress it).
    static func energyScale(live: Bool, capturing: Bool, tick: Int) -> Float {
        guard live else { return 1 }
        guard capturing else { return Float(SixFourFieldTuning.liveIdleEnergy) }
        let n = max(1, SixFourFieldTuning.capturePourRampTicks)
        let phase = ((tick % n) + n) % n
        return Float(phase + 1) / Float(n)
    }

    // MARK: input prep (mirrors InfluenceField's, but flattened for the GPU buffers)

    /// LIVE act: anchor to the spec-proven liveScene pyramid bands (the same
    /// re-anchor as InfluenceField.sources — glow tracks the REAL pyramid);
    /// other acts keep the movable-widget anchors.
    private static func sources(_ placement: [ColorIdentity: (col: Int, row: Int)],
                                live: Bool) -> [FieldSourceU] {
        if live,
           let f64 = GridLayoutContract.region("field64", in: GridLayoutContract.liveScene),
           let f16 = GridLayoutContract.region("field16", in: GridLayoutContract.liveScene) {
            func src(_ r: GridRegion, kind: Int32) -> FieldSourceU {
                FieldSourceU(minX: Float(r.col), minY: Float(r.row),
                             maxX: Float(r.col + r.w), maxY: Float(r.row + r.h), kind: kind, pad0: 0)
            }
            return [src(f64, kind: 0), src(f16, kind: 1)]   // arrangement, set
        }
        func src(_ id: ColorIdentity, kind: Int32) -> FieldSourceU {
            let p = placement[id] ?? (MoveContract.defaultCol(id), MoveContract.defaultRow(id))
            let (w, h) = MoveContract.footprint(id)
            return FieldSourceU(minX: Float(p.col), minY: Float(p.row),
                                maxX: Float(p.col + w), maxY: Float(p.row + h), kind: kind, pad0: 0)
        }
        return [src(.field64, kind: 0), src(.palette16, kind: 1)]   // arrangement, set
    }

    private static func arrangement(of surface: Surface) -> (tile: [UInt8], palette: [SIMD3<UInt8>]) {
        switch surface.phase {
        case .live:
            return (surface.previewTile, surface.previewPalette)
        // The post-capture phases (`.captured`/`.picked`) SUPPRESS the full-screen ground:
        // they are inert placeholders pending the new review surface, so the ground must NOT
        // paint the captured scene behind them (it would overlap the forthcoming review tiles).
        default:
            return ([], [])
        }
    }

    /// 256 colours → 768 packed bytes (r,g,b), ghost-padded.
    private static func packPalette(_ pal: [SIMD3<UInt8>]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 256 * 3)
        let ghost = SIMD3<UInt8>(20, 20, 24)
        for i in 0 ..< 256 {
            let c = i < pal.count ? pal[i] : ghost
            out[i * 3] = c.x; out[i * 3 + 1] = c.y; out[i * 3 + 2] = c.z
        }
        return out
    }

    /// 64×64 indices, zero-padded if absent (the arrangement source then reads palette[0]).
    private static func packTile(_ tile: [UInt8]) -> [UInt8] {
        if tile.count == 64 * 64 { return tile }
        var out = [UInt8](repeating: 0, count: 64 * 64)
        for i in 0 ..< min(tile.count, out.count) { out[i] = tile[i] }
        return out
    }

    /// Per-index usage normalised to the max (the spoke-reach weight).
    private static func usage(_ tile: [UInt8]) -> [Float] {
        var counts = [Int](repeating: 0, count: 256)
        for v in tile { counts[Int(v)] += 1 }
        let maxC = max(1, counts.max() ?? 1)
        return counts.map { Float($0) / Float(maxC) }
    }
}

/// THE ONE GROUND for every act — the GPU field by default (`FieldMetalView.enabled`), with the
/// CPU `InfluenceField` as the no-Metal fallback. Used by all act phase fields so the smooth GPU
/// field persists across the act1→act2 transition (no reverting to the main-thread CPU bake during
/// the burst). Same field, same κ tick.
struct StageGround: View {
    let surface: Surface
    let placement: [ColorIdentity: (col: Int, row: Int)]
    let tick: Int
    /// True while burst frames land (E9): the field's named function is CAPTURE ENERGY —
    /// dim idle near-void on Live, full energy on the pour ramp while banking photons.
    var capturing: Bool = false
    var body: some View {
        // Tri-state on the off-main build so the FIRST-PAINT window paints nothing (the Color.black
        // base in SurfaceView shows through as the intended black) instead of running the InfluenceField
        // CPU StageField bake on the main thread. InfluenceField is reserved strictly for the genuine
        // no-Metal device, reached only after the off-main build DEFINITIVELY resolves to `.failed`.
        switch FieldMetalCore.state {
        case .ready:
            if FieldMetalView.enabled {
                FieldMetalView(surface: surface, placement: placement, tick: tick,
                               capturing: capturing)
                    .ignoresSafeArea()
            } else {
                InfluenceField(surface: surface, placement: placement, tick: tick,
                               capturing: capturing)
            }
        case .failed:
            InfluenceField(surface: surface, placement: placement, tick: tick,
                           capturing: capturing)
        case .pending:
            Color.clear
        }
    }
}

// MARK: - Swift mirrors of the Metal structs (same field order + padding → layout-matched)

/// Mirror of `FieldSourceU` in field.metal — 24-byte stride (4 floats + 2 int32).
struct FieldSourceU {
    var minX: Float; var minY: Float; var maxX: Float; var maxY: Float
    var kind: Int32; var pad0: Int32
}

/// Mirror of `FieldUniforms` in field.metal — 48 bytes (3 floats + 9 int32, all 4-byte).
struct FieldUniformsU {
    var cellSizePx: Float
    var liftAmount: Float
    var cols: Int32; var rows: Int32
    var minC: Int32; var maxC: Int32; var minR: Int32; var maxR: Int32
    var cornerCells: Int32
    var sourceCount: Int32
    var tick: Int32
    /// E9 CAPTURE-ENERGY multiplier (idle-live near-void / capture pour ramp / 1 elsewhere).
    var energyScale: Float
}

// MARK: - The CAMetalLayer-backed view (draws once per κ tick)

/// The shared Metal device/queue/render-pipeline, built ONCE and reused by every `FieldUIView`
/// across phase transitions — so tapping into capture doesn't rebuild the pipeline (an expensive
/// `makeRenderPipelineState`) on the main thread at the transition. `@unchecked Sendable`: Metal
/// device/queue/PSO are safe to share (same discipline as the app's other pipelines).
final class FieldMetalCore: @unchecked Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: any MTLRenderPipelineState

    static let log = Logger(subsystem: "com.sixfour.SixFour", category: "metal.ground")

    /// Build lifecycle for the off-main PSO compile. `.pending` while the background build runs
    /// (StageGround paints nothing → the Color.black base shows as the intended black), `.ready`
    /// once the core lands, `.failed` only when Metal is genuinely unavailable (→ CPU fallback).
    enum BuildState { case pending, ready, failed }

    /// nonisolated(unsafe) statics guarded by an NSLock — satisfies SWIFT_STRICT_CONCURRENCY=complete.
    /// FieldMetalCore is @unchecked Sendable, so handing the built instance across the queue boundary
    /// is data-race-safe. The core is built OFF the main thread (the makeRenderPipelineState compile is
    /// the device first-paint stall) and published once ready.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _shared: FieldMetalCore?
    nonisolated(unsafe) private static var _state: BuildState = .pending
    nonisolated(unsafe) private static var primed = false

    /// The built core, or nil until the background build lands (`configure`/`draw` already
    /// `guard let core = FieldMetalCore.shared else { return }`, so they no-op-to-black meanwhile).
    static var shared: FieldMetalCore? {
        lock.lock(); defer { lock.unlock() }; return _shared
    }

    /// The current build state (StageGround/`enabled` branch on this; it flips within one κ tick of
    /// readiness because StageGround is re-evaluated every clock.tick).
    static var state: BuildState {
        lock.lock(); defer { lock.unlock() }; return _state
    }

    /// Kick the off-main PSO compile exactly once. Called from `SixFourApp.init` so the heavy
    /// makeDefaultLibrary + makeFunction + makeRenderPipelineState run in parallel with the rest of
    /// launch instead of stalling the first CATransaction on the main thread.
    static func prime() {
        lock.lock()
        if primed { lock.unlock(); return }
        primed = true
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            let core = FieldMetalCore()
            lock.lock()
            _shared = core
            _state = core != nil ? .ready : .failed
            lock.unlock()
        }
    }

    // Each failure is logged individually: this is the persistent StageGround. If it returns nil the
    // app has no opaque Metal background and the window shows white, so on a white-screen launch the
    // device console (subsystem com.sixfour.SixFour, category metal.ground) names the exact failing step.
    private init?() {
        NSLog("SF-mg0: StageGround FieldMetalCore init")
        guard let dev = MTLCreateSystemDefaultDevice() else {
            Self.log.error("StageGround OFF: MTLCreateSystemDefaultDevice nil (no GPU)")
            return nil
        }
        guard let q = dev.makeCommandQueue() else {
            Self.log.error("StageGround OFF: makeCommandQueue nil (device=\(dev.name, privacy: .public))")
            return nil
        }
        guard let lib = dev.makeDefaultLibrary() else {
            Self.log.error("StageGround OFF: makeDefaultLibrary nil (default.metallib missing or unsigned on device?)")
            return nil
        }
        guard let vfn = lib.makeFunction(name: "fieldVertex") else {
            Self.log.error("StageGround OFF: makeFunction(fieldVertex) nil (metallib stale?)")
            return nil
        }
        guard let ffn = lib.makeFunction(name: "fieldFragment") else {
            Self.log.error("StageGround OFF: makeFunction(fieldFragment) nil (metallib stale?)")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pso: any MTLRenderPipelineState
        do {
            pso = try dev.makeRenderPipelineState(descriptor: desc)
        } catch {
            Self.log.error("StageGround OFF: makeRenderPipelineState failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        device = dev; queue = q; pipeline = pso
        NSLog("SF-mg-ready: StageGround ready device=\(dev.name)")
        Self.log.log("StageGround ready: device=\(dev.name, privacy: .public)")
    }
}

final class FieldUIView: UIView {
    // UIKit requires `class var layerClass` (static does not satisfy the override).
    // swiftlint:disable:next static_over_final_class
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer {
        // swiftlint:disable:next force_cast
        layer as! CAMetalLayer
    }

    private var sources: [FieldSourceU] = []
    private var palette: [UInt8] = []
    private var usage: [Float] = []
    private var tile: [UInt8] = []
    private var tick: Int = 0
    private var liftAmount: Float = 0
    private var energyScale: Float = 1

    /// κ-gate: the last tick we actually drew on, so multiple `updateUIView` calls within one 20 fps
    /// tick (σ mutates several times — palette, captured frames, cursor) collapse to ONE draw.
    private var lastDrawnTick: Int = -1
    /// Pooled tile buffer (allocated once, re-filled) — no per-draw MTLBuffer allocation.
    private var tileBuffer: (any MTLBuffer)?

    func configure() {
        isUserInteractionEnabled = false
        // GUARDRAIL (first-frame black): set the view + layer to a NON-opaque BLACK base BEFORE the
        // `guard` below. If `FieldMetalCore.shared` is nil (default.metallib missing/unsigned on a
        // device) — or a future path ever mounts this view before `.ready` — an opaque, never-presented
        // CAMetalLayer paints undefined/WHITE over the Color.black base. Doing this before the guard
        // makes a nil core degrade to the app's intended black instead of a bare white window, so a
        // launch/Metal fault is never masked as "white screen". Zero behavioural change on the live path.
        isOpaque = false
        backgroundColor = .black
        metalLayer.isOpaque = false
        metalLayer.backgroundColor = UIColor.black.cgColor
        guard let core = FieldMetalCore.shared else { return }
        metalLayer.device = core.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        // NOT opaque: until the first GPU present, an opaque CAMetalLayer shows undefined/white over
        // the Color.black base. Transparent lets the black base show through, so a launch fault reads
        // as the app's intended black, not a bare white window (keeps "white" from masking the cause).
        metalLayer.isOpaque = false
        metalLayer.maximumDrawableCount = 3   // triple-buffer so a draw never starves on the pool
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3.0
        let newSize = CGSize(width: bounds.width * s, height: bounds.height * s)
        metalLayer.contentsScale = s
        guard newSize != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = newSize
        // Re-fill the resized drawable now (rotation / safe-area / first non-zero layout) so the
        // field never shows a stale or blank frame until the next κ tick. Guarded on `sources` so
        // we never draw before the first `update()` (the draw path indexes the source buffers).
        if !sources.isEmpty { draw() }
    }

    func update(sources: [FieldSourceU], palette: [UInt8], usage: [Float],
                tile: [UInt8], tick: Int, liftAmount: Float, energyScale: Float) {
        self.sources = sources; self.palette = palette; self.usage = usage
        self.tile = tile; self.tick = tick; self.liftAmount = liftAmount
        self.energyScale = energyScale
        // κ-gate: exactly ONE draw per tick. σ mutates several times per tick (palette, captured
        // frames, cursor), each re-firing updateUIView; collapse them so nextDrawable is called once.
        guard tick != lastDrawnTick else { return }
        lastDrawnTick = tick
        draw()
    }

    private func draw() {
        guard let core = FieldMetalCore.shared,
              metalLayer.drawableSize.width > 0,
              let drawable = metalLayer.nextDrawable(),
              let cmd = core.queue.makeCommandBuffer() else { return }

        let scale = Float(metalLayer.contentsScale)
        var u = FieldUniformsU(
            cellSizePx: Float(SixFourLattice.gifPx) * scale,
            liftAmount: liftAmount,
            cols: Int32(SixFourLattice.cols), rows: Int32(SixFourLattice.rows),
            minC: Int32(SixFourBoundary.minC), maxC: Int32(SixFourBoundary.maxC),
            minR: Int32(SixFourBoundary.minR), maxR: Int32(SixFourBoundary.maxR),
            cornerCells: Int32(SixFourBoundary.cornerCells),
            sourceCount: Int32(sources.count), tick: Int32(truncatingIfNeeded: tick),
            energyScale: energyScale)

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(core.pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<FieldUniformsU>.stride, index: 0)
        palette.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        usage.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        // tile (4096 B) via a POOLED buffer (allocated once, memcpy'd) — no per-draw allocation.
        if tile.count > 0 {
            if tileBuffer == nil || tileBuffer!.length < tile.count {
                tileBuffer = core.device.makeBuffer(length: tile.count, options: .storageModeShared)
            }
            if let tbuf = tileBuffer {
                memcpy(tbuf.contents(), tile, tile.count)
                enc.setFragmentBuffer(tbuf, offset: 0, index: 3)
            }
        }
        sources.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 4) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
