import CoreVideo
import Metal

/// GIF89a-camera COLOR HEAD — the device circuit for the 16/32/64 ladder.
///
/// One `ingest` per 20 fps camera tick closes the loop the spec laws gate:
///
///   camera frame (32BGRA) ── center-crop + pool ──► 64-rung bin SUMS (20 Hz)
///        │  Zig floor: `s4_pool_sums_bgra8` (byte-exact, stride-aware)
///        │  GPU path:  `p16PoolSumsBGRA` (PaletteLadder.metal, parity-gated)
///        ▼
///   exact u64 adds derive the ladder (the TRANSITIVE SUMS CARRIER —
///   Spec.V21Pyramid / palette16.zig: sums compose, means don't):
///     32-rung frame = 2×2 spatial pool of two consecutive 64-rung ticks (10 Hz)
///     16-rung frame = 2×2 spatial pool of two consecutive 32-rung frames (5 Hz)
///   — the isotropic 2×2×2 ladder, GIF-exact cadences 20/10/5 fps
///   (`s4_ladder_delay_cs`: delays 5/10/20 cs).
///        ▼
///   the 16-rung stream = 256 PARTICLES (Spec.PaletteKinetics: slot = (x,y),
///   mass = L-sum); per-slot trajectories feed `s4_certified_order`
///   (Spec.KinematicHaltPrior): the certified kinematic order per slot is the
///   PonderNet halting-prior FLOOR — computed in exact integer arithmetic
///   before any learning runs. The GCT (768 bytes, `s4_sums_to_srgb8`) falls
///   out of the same 16-rung sums: color out of the way.
///
/// This type is deliberately free of AVFoundation: `CaptureSession` (or any
/// frame source) calls `poolSums64(from:)` + `ingest(_:)` per tick and reads
/// `latestGCT` / `haltFloor()` when the burst window closes. The Zig kernels
/// are the authority; `ColorHeadMetal` is throughput plumbing whose output is
/// parity-checked u64-for-u64 against the floor (ColorHeadTests).
final class ColorHead {

    /// Bins per axis at the finest rung (the 64×64 content rung).
    static let fineSide = 64
    /// The finest crop side accepted: must be a multiple of 64 so every rung's
    /// bin size is integral (and 16 | side for the GCT contract).
    let cropSide: Int

    private(set) var tick = 0
    /// Latest 64-rung frame (64·64·3 u64 sums), updated every tick (20 Hz).
    private(set) var latest64: [UInt64]?
    /// Latest 32-rung frame (32·32·3), updated every 2nd tick (10 Hz).
    private(set) var latest32: [UInt64]?
    /// Latest 16-rung frame (16·16·3), updated every 4th tick (5 Hz).
    private(set) var latest16: [UInt64]?
    /// Latest 768-byte Global Color Table realized from `latest16`.
    private(set) var latestGCT: [UInt8]?

    /// Per-slot L-trajectories (R+G+B sum per 16-rung frame): 256 histories,
    /// newest last — the particle streams `haltFloor()` certifies.
    private(set) var slotHistory: [[Int64]]

    private var pending32: [UInt64]?
    private var pending16: [UInt64]?
    private var pendingRaw64: [UInt64]?
    private var lastCropArea: Int64 = 0

    /// Accumulated S_t training pairs (the 32→64 transition's t-bands), drained
    /// by the trainer. Exact integers until the drain converts to Float.
    private var tBandFeatures: [[Int64]] = []
    private var tBandTargets: [Int64] = []
    private static let maxRetainedPairs = 8192

    /// - Parameter cropSide: center-crop side in pixels (multiple of 64).
    /// - Parameter historyTicks: 16-rung frames retained per slot (the
    ///   certification window; needs ≥ cap+2 to certify order `cap`).
    init(cropSide: Int = 1024, historyTicks: Int = 16) {
        precondition(cropSide > 0 && cropSide % ColorHead.fineSide == 0,
                     "cropSide must be a positive multiple of 64")
        self.cropSide = cropSide
        self.historyTicks = historyTicks
        self.slotHistory = Array(repeating: [], count: 256)
    }

    private let historyTicks: Int

    // MARK: - The Zig floor: camera frame → 64-rung sums

    /// Pool one 32BGRA pixel buffer into the 64-rung bin sums via the
    /// byte-exact Zig kernel (center crop computed here). Returns nil for
    /// non-BGRA buffers or frames smaller than one 64-px block.
    func poolSums64(from pixelBuffer: CVPixelBuffer) -> [UInt64]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
        else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let crop = ColorHead.cropWindow(width: w, height: h, maxSide: cropSide)
        else { return nil }

        var sums = [UInt64](repeating: 0, count: 64 * 64 * 3)
        let rc = sums.withUnsafeMutableBufferPointer { out in
            s4_pool_sums_bgra8(
                base.assumingMemoryBound(to: UInt8.self),
                Int32(stride), Int32(crop.x0), Int32(crop.y0),
                Int32(crop.side), 64, out.baseAddress)
        }
        guard rc == 0 else { return nil }
        lastCropArea = Int64(crop.side / 16) * Int64(crop.side / 16)
        return sums
    }

    /// The shared center-crop contract: the largest multiple-of-64 square that
    /// fits, capped at `maxSide`, centered. Both the Zig and Metal paths use
    /// this exact window so parity is well-defined.
    static func cropWindow(width: Int, height: Int, maxSide: Int)
        -> (x0: Int, y0: Int, side: Int)? {
        let fit = (min(width, height) / fineSide) * fineSide
        let side = min(fit, maxSide)
        guard side >= fineSide else { return nil }
        return ((width - side) / 2, (height - side) / 2, side)
    }

    // MARK: - The ladder: exact u64 adds at GIF-exact cadences

    /// Ingest one 64-rung frame (one 20 Hz tick). Derives the 32- and 16-rung
    /// frames by exact addition on the sums carrier, updates the GCT, and
    /// appends to the particle histories at the 5 Hz cadence.
    func ingest(_ sums64: [UInt64]) {
        precondition(sums64.count == 64 * 64 * 3)
        latest64 = sums64
        tick += 1

        let spatial32 = ColorHead.poolSpatial2(sums64, side: 64)
        if let held = pending32 {
            let frame32 = zip(held, spatial32).map(+)
            latest32 = frame32
            if let rawPrev = pendingRaw64 {
                emitTBandPairs(prevTick: rawPrev, currentTick: sums64)
            }
            pending32 = nil
            pendingRaw64 = nil

            let spatial16 = ColorHead.poolSpatial2(frame32, side: 32)
            if let held16 = pending16 {
                let frame16 = zip(held16, spatial16).map(+)
                latest16 = frame16
                pending16 = nil
                emit16(frame16)
            } else {
                pending16 = spatial16
            }
        } else {
            pending32 = spatial32
            pendingRaw64 = sums64
        }
    }

    // MARK: - The S_t training pairs (the 32→64 transition's t-bands)

    /// Per 2×2×2 spacetime block (2×2 fine bins × the tick pair): CAUSAL
    /// features from the FIRST tick's four L-sums (+ bias), target = the
    /// block's t-band, band_T = Σ(t=0) − Σ(t=1) (the OctantViews sign — the
    /// reversal-ODD label S_t owes, Spec.AxisSKI). Exact integers here;
    /// floats only at 'drainTBandPairs'.
    private func emitTBandPairs(prevTick: [UInt64], currentTick: [UInt64]) {
        let lum: ([UInt64], Int, Int) -> Int64 = { sums, bx, by in
            let i = (by * 64 + bx) * 3
            return Int64(sums[i]) + Int64(sums[i + 1]) + Int64(sums[i + 2])
        }
        for by in stride(from: 0, to: 64, by: 2) {
            for bx in stride(from: 0, to: 64, by: 2) {
                let p00 = lum(prevTick, bx, by)
                let p01 = lum(prevTick, bx + 1, by)
                let p10 = lum(prevTick, bx, by + 1)
                let p11 = lum(prevTick, bx + 1, by + 1)
                let cSum = lum(currentTick, bx, by) + lum(currentTick, bx + 1, by)
                    + lum(currentTick, bx, by + 1) + lum(currentTick, bx + 1, by + 1)
                let tBand = (p00 + p01 + p10 + p11) - cSum
                tBandFeatures.append([1, p00, p01, p10, p11])
                tBandTargets.append(tBand)
            }
        }
        if tBandTargets.count > ColorHead.maxRetainedPairs {
            let drop = tBandTargets.count - ColorHead.maxRetainedPairs
            tBandFeatures.removeFirst(drop)
            tBandTargets.removeFirst(drop)
        }
    }

    /// Drain the accumulated S_t pairs as Float rows for 'BandHeadTrainer'
    /// (row-major, width 5: bias + the four causal fine L-sums), scaled by
    /// `scale` (callers pass ~1/binMass so features sit near O(1)). Clears
    /// the accumulator. The single exact→float boundary of the circuit.
    func drainTBandPairs(scale: Float) -> (features: [Float], targets: [Float], width: Int) {
        var f = [Float]()
        f.reserveCapacity(tBandFeatures.count * 5)
        for row in tBandFeatures {
            f.append(1)
            for v in row.dropFirst() { f.append(Float(v) * scale) }
        }
        let t = tBandTargets.map { Float($0) * scale }
        tBandFeatures.removeAll(keepingCapacity: true)
        tBandTargets.removeAll(keepingCapacity: true)
        return (f, t, 5)
    }

    private func emit16(_ frame16: [UInt64]) {
        // The 16-rung frame is 8 fine pixels deep per bin axis step:
        // area per bin = (cropSide/16)² pixels × 4 ticks of temporal pooling.
        if lastCropArea > 0 {
            var gct = [UInt8](repeating: 0, count: 768)
            let rc = frame16.withUnsafeBufferPointer { sums in
                gct.withUnsafeMutableBufferPointer { out in
                    s4_sums_to_srgb8(sums.baseAddress, 16, lastCropArea * 4, out.baseAddress)
                }
            }
            if rc == 0 { latestGCT = gct }
        }
        // Particle mass per slot: the L-sum (R+G+B) — Spec.PaletteKinetics.
        for slot in 0..<256 {
            let l = Int64(frame16[slot * 3]) + Int64(frame16[slot * 3 + 1])
                  + Int64(frame16[slot * 3 + 2])
            slotHistory[slot].append(l)
            if slotHistory[slot].count > historyTicks {
                slotHistory[slot].removeFirst()
            }
        }
    }

    /// 2×2 spatial block-sum: side×side×3 sums → (side/2)×(side/2)×3.
    static func poolSpatial2(_ sums: [UInt64], side: Int) -> [UInt64] {
        let half = side / 2
        var out = [UInt64](repeating: 0, count: half * half * 3)
        for by in 0..<half {
            for bx in 0..<half {
                for c in 0..<3 {
                    let a = sums[((2 * by) * side + 2 * bx) * 3 + c]
                    let b = sums[((2 * by) * side + 2 * bx + 1) * 3 + c]
                    let d = sums[((2 * by + 1) * side + 2 * bx) * 3 + c]
                    let e = sums[((2 * by + 1) * side + 2 * bx + 1) * 3 + c]
                    out[(by * half + bx) * 3 + c] = a + b + d + e
                }
            }
        }
        return out
    }

    // MARK: - The halting-prior floor

    /// The certified kinematic order per palette slot over the retained
    /// 16-rung window — the PonderNet halting-prior FLOOR, exact integers,
    /// no learning involved (Spec.KinematicHaltPrior). Slots whose window is
    /// still too short to falsify (n < cap+2) report -1 (not yet certifiable).
    func haltFloor(cap: Int32 = 4) -> [Int32] {
        slotHistory.map { history in
            guard history.count >= Int(cap) + 2 else { return -1 }
            return history.withUnsafeBufferPointer { buf in
                s4_certified_order(buf.baseAddress, Int32(history.count), cap)
            }
        }
    }
}

/// GPU throughput path for the 64-rung pooling — `p16PoolSumsBGRA`
/// (PaletteLadder.metal). One thread per bin, sequential integer accumulation,
/// byte-identical to the Zig floor by construction; ColorHeadTests gates the
/// parity. Falls back to nil (caller uses the Zig path) when Metal is absent.
final class ColorHeadMetal {
    private let context: GPUContext
    private let pso: any MTLComputePipelineState

    private struct P16Params {
        var stride: UInt32
        var x0: UInt32
        var y0: UInt32
        var side: UInt32
        var outSide: UInt32
    }

    init?() {
        guard let ctx = try? GPUContext(queueLabel: "palette-ladder"),
              let pipeline = try? ctx.pso("p16PoolSumsBGRA") else { return nil }
        self.context = ctx
        self.pso = pipeline
    }

    /// Pool one 32BGRA buffer to 64-rung sums on the GPU, using the SAME
    /// center-crop contract as the Zig floor. Returns u64-widened sums.
    func poolSums64(from pixelBuffer: CVPixelBuffer, maxSide: Int) -> [UInt64]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
        else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let crop = ColorHead.cropWindow(width: w, height: h, maxSide: maxSide)
        else { return nil }

        guard let inBuf = context.device.makeBuffer(
                bytes: base, length: stride * h, options: .storageModeShared),
              let outBuf = context.device.makeBuffer(
                length: 64 * 64 * 3 * MemoryLayout<UInt32>.stride,
                options: .storageModeShared)
        else { return nil }

        var params = P16Params(
            stride: UInt32(stride), x0: UInt32(crop.x0), y0: UInt32(crop.y0),
            side: UInt32(crop.side), outSide: 64)

        guard let cmd = context.queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return nil }
        enc.setComputePipelineState(pso)
        enc.setBuffer(inBuf, offset: 0, index: 0)
        enc.setBytes(&params, length: MemoryLayout<P16Params>.stride, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        let bins = 64 * 64
        let tg = min(pso.maxTotalThreadsPerThreadgroup, 256)
        enc.dispatchThreads(MTLSize(width: bins, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let raw = outBuf.contents().assumingMemoryBound(to: UInt32.self)
        return (0..<(bins * 3)).map { UInt64(raw[$0]) }
    }
}
