import SwiftUI
import UIKit
import Metal
import QuartzCore
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
/// GATED behind the `-metalField` launch argument (DEBUG); the CPU `InfluenceField` stays the
/// default/fallback so the GPU path can be A/B-compared on device before it replaces the bake.
/// **On-device only** — the geometry/timing is the user's to verify; Claude compile-checks.
struct FieldMetalView: UIViewRepresentable {
    let surface: Surface
    let placement: [ColorIdentity: (col: Int, row: Int)]
    let tick: Int

    #if DEBUG
    static let enabled = ProcessInfo.processInfo.arguments.contains("-metalField")
    #else
    static let enabled = false
    #endif

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
        v.update(sources: Self.sources(placement),
                 palette: Self.packPalette(palSrc),
                 usage: Self.usage(tile),
                 tile: Self.packTile(tile),
                 tick: tick, liftAmount: liftAmount)
    }

    // MARK: input prep (mirrors InfluenceField's, but flattened for the GPU buffers)

    private static func sources(_ placement: [ColorIdentity: (col: Int, row: Int)]) -> [FieldSourceU] {
        func src(_ id: ColorIdentity, kind: Int32) -> FieldSourceU {
            let p = placement[id] ?? (MoveContract.defaultCol(id), MoveContract.defaultRow(id))
            let (w, h) = MoveContract.footprint(id)
            return FieldSourceU(minX: Float(p.col), minY: Float(p.row),
                                maxX: Float(p.col + w), maxY: Float(p.row + h), kind: kind, pad0: 0)
        }
        return [src(.field64, kind: 0), src(.palette16, kind: 1)]   // arrangement, set
    }

    private static func arrangement(of surface: Surface) -> (tile: [UInt8], palette: [SIMD3<UInt8>]) {
        let side = surface.cubeSide
        switch surface.phase {
        case .live, .locking, .capturing:
            return (surface.previewTile, surface.previewPalette)
        case .rendering, .review:
            let t = surface.cursor, base = t * side * side
            guard t >= 0, surface.indexCube.count >= base + side * side else { return ([], surface.palette) }
            let slice = Array(surface.indexCube[base ..< base + side * side])
            let pal = (t < surface.palettesPerFrame.count) ? surface.palettesPerFrame[t] : surface.palette
            return (slice, pal)
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

// MARK: - Swift mirrors of the Metal structs (same field order + padding → layout-matched)

/// Mirror of `FieldSourceU` in field.metal — 24-byte stride (4 floats + 2 int32).
struct FieldSourceU {
    var minX: Float; var minY: Float; var maxX: Float; var maxY: Float
    var kind: Int32; var pad0: Int32
}

/// Mirror of `FieldUniforms` in field.metal — 48 bytes (2 floats + 10 int32, all 4-byte).
struct FieldUniformsU {
    var cellSizePx: Float
    var liftAmount: Float
    var cols: Int32; var rows: Int32
    var minC: Int32; var maxC: Int32; var minR: Int32; var maxR: Int32
    var cornerCells: Int32
    var sourceCount: Int32
    var tick: Int32
    var pad0: Int32
}

// MARK: - The CAMetalLayer-backed view (draws once per κ tick)

final class FieldUIView: UIView {
    // UIKit requires `class var layerClass` (static does not satisfy the override).
    // swiftlint:disable:next static_over_final_class
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer {
        // swiftlint:disable:next force_cast
        layer as! CAMetalLayer
    }

    private var device: (any MTLDevice)?
    private var queue: (any MTLCommandQueue)?
    private var pipeline: (any MTLRenderPipelineState)?

    private var sources: [FieldSourceU] = []
    private var palette: [UInt8] = []
    private var usage: [Float] = []
    private var tile: [UInt8] = []
    private var tick: Int = 0
    private var liftAmount: Float = 0

    func configure() {
        isUserInteractionEnabled = false
        guard let dev = MTLCreateSystemDefaultDevice(),
              let q = dev.makeCommandQueue(),
              let lib = dev.makeDefaultLibrary(),
              let vfn = lib.makeFunction(name: "fieldVertex"),
              let ffn = lib.makeFunction(name: "fieldFragment") else { return }
        device = dev
        queue = q
        metalLayer.device = dev
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? dev.makeRenderPipelineState(descriptor: desc)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3.0
        metalLayer.contentsScale = s
        metalLayer.drawableSize = CGSize(width: bounds.width * s, height: bounds.height * s)
    }

    func update(sources: [FieldSourceU], palette: [UInt8], usage: [Float],
                tile: [UInt8], tick: Int, liftAmount: Float) {
        self.sources = sources; self.palette = palette; self.usage = usage
        self.tile = tile; self.tick = tick; self.liftAmount = liftAmount
        draw()   // one κ tick → one GPU draw (the κ tick is the only clock)
    }

    private func draw() {
        guard let queue, let pipeline,
              metalLayer.drawableSize.width > 0,
              let drawable = metalLayer.nextDrawable(),
              let cmd = queue.makeCommandBuffer() else { return }

        let scale = Float(metalLayer.contentsScale)
        var u = FieldUniformsU(
            cellSizePx: Float(SixFourLattice.gifPx) * scale,
            liftAmount: liftAmount,
            cols: Int32(SixFourLattice.cols), rows: Int32(SixFourLattice.rows),
            minC: Int32(SixFourBoundary.minC), maxC: Int32(SixFourBoundary.maxC),
            minR: Int32(SixFourBoundary.minR), maxR: Int32(SixFourBoundary.maxR),
            cornerCells: Int32(SixFourBoundary.cornerCells),
            sourceCount: Int32(sources.count), tick: Int32(truncatingIfNeeded: tick), pad0: 0)

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<FieldUniformsU>.stride, index: 0)
        palette.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        usage.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        // tile is 4096 B (the setBytes ceiling); use a buffer to stay safely under the inline limit.
        if let tbuf = device?.makeBuffer(bytes: tile, length: tile.count, options: .storageModeShared) {
            enc.setFragmentBuffer(tbuf, offset: 0, index: 3)
        }
        sources.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 4) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
