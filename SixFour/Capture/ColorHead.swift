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
///   before any learning runs. The GCT (768 bytes) falls out of the same
///   16-rung sums: color out of the way — realized by `s4_sums_to_srgb8` on the
///   gamma-byte (32BGRA) feed, or `s4_sums_bt2020_to_srgb8` (BT.2020 gamut hop +
///   inverse-EOTF, Spec.RadiometricRealize) on the linear16 x420 feed.
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
    /// Whether the current sums are LINEAR16 BT.2020 (x420 measurement path) vs
    /// gamma sRGB8 bytes (32BGRA path). Selects the emit16 GCT realization:
    /// linear → `s4_sums_bt2020_to_srgb8` (gamut hop + inverse-EOTF), byte →
    /// `s4_sums_to_srgb8`. Set by whichever `poolSums64` produced the tick.
    private var sumsAreLinear = false

    /// Accumulated S_t training pairs (the 32→64 transition's t-bands), drained
    /// by the trainer. Exact integers until the drain converts to Float.
    /// PERF 2026-07-08: FLAT storage, stride 4 (p00,p01,p10,p11; the bias is
    /// synthesized at drain) — the old `[[Int64]]` allocated 1024 small heap
    /// arrays per pair-tick and paid an O(rows) array-of-arrays removeFirst at
    /// the cap; flat arrays append in place and the cap drop is one memmove.
    private var tBandFeatures: [Int64] = []
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
        tBandFeatures.reserveCapacity(ColorHead.maxRetainedPairs * 4)
        tBandTargets.reserveCapacity(ColorHead.maxRetainedPairs)
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
        sumsAreLinear = false // gamma sRGB8 bytes → s4_sums_to_srgb8 in emit16
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

    // MARK: - The measurement path: x420 → full-range R'G'B'10 → linear pool

    /// The luma half of the capture contract (`palette16.zig` header): video-range
    /// 10-bit Y' (64…940) → full-range (0…1023), held at ×4096 fixed point so the
    /// per-pixel step is one table read plus adds. Codes above 940 clamp to 1023,
    /// below 64 to 0 (range expansion is a clamp by definition, not absorption).
    static let x420LumaLUT4096: [Int32] = (0..<1024).map { y in
        let n = Int64(max(0, y - 64)) * 1023 * 4096 + 438
        return Int32(min(Int64(1023) * 4096, n / 876))
    }

    /// The chroma half: BT.2020 NCL coefficients folded into ×4096 fixed point in
    /// 10-bit full-range units per video-range chroma code (C'−512, span ±448 ⇒
    /// normalized C = (C'−512)/896): R += 1.4746·C_r, G −= 0.16455·C_b + 0.57135·C_r,
    /// B += 1.8814·C_b, each ×1023/896×4096.
    static func x420ChromaOffsets4096(cb: Int32, cr: Int32) -> (r: Int32, g: Int32, b: Int32) {
        let cbs = cb - 512, crs = cr - 512
        return (r: 6896 * crs, g: -770 * cbs - 2672 * crs, b: 8799 * cbs)
    }

    /// One pixel of the conversion — the pure twin the pixel loop must equal
    /// (tested against the float BT.2020 reference in X420MeasurementPathTests).
    static func x420RGB10(y: Int, cb: Int, cr: Int) -> (r: Int, g: Int, b: Int) {
        let lum = x420LumaLUT4096[y]
        let off = x420ChromaOffsets4096(cb: Int32(cb), cr: Int32(cr))
        let clamp: (Int32) -> Int = { v in Int(min(1023, max(0, (v + 2048) >> 12))) }
        return (clamp(lum + off.r), clamp(lum + off.g), clamp(lum + off.b))
    }

    /// Reused per-tick conversion target (side²·3 u16) — one allocation per crop
    /// geometry, not per frame.
    private var rgb10Scratch: [UInt16] = []

    /// THE MEASUREMENT PATH (the capture contract recorded in `palette16.zig`):
    /// pool one x420 (10-bit YCbCr 4:2:0 video-range, BT.2020/HLG) buffer into
    /// the 64-rung bin sums. Swift owns the colorimetry — integer BT.2020
    /// Y'CbCr→R'G'B' with video→full range expansion (nearest chroma, exact
    /// fixed point) — then the Zig floor owns the radiometry:
    /// `s4_pool_sums_linear_hlg10` linearizes through the HLG golden LUT and
    /// block-sums, so bin sums are ∝ scene light in linear16 units.
    ///
    /// NOTE: on this path the sums are LINEAR16 in BT.2020 primaries, so `emit16`
    /// realizes the GCT via `s4_sums_bt2020_to_srgb8` (the inverse-EOTF kernel,
    /// Spec.RadiometricRealize): area-mean the linear16 sums, apply the golden
    /// BT.2020→sRGB linear matrix + clamp, then the sRGB OETF. `lastCropArea` is
    /// the per-tick spatial area (side/16)²; `emit16` uses `lastCropArea*4` (×4
    /// temporal ticks) as the exact pixel `count`. `sumsAreLinear = true` selects
    /// that path over the gamma-byte `s4_sums_to_srgb8`.
    func poolSums64(fromX420 pixelBuffer: CVPixelBuffer) -> [UInt64]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer)
                == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { return nil }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard let crop = ColorHead.cropWindow(width: w, height: h, maxSide: cropSide)
        else { return nil }
        let side = crop.side

        // x420 samples are the top 10 bits of 16-bit little-endian words.
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) / 2
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1) / 2
        let yPtr = yBase.assumingMemoryBound(to: UInt16.self)
        let cPtr = cBase.assumingMemoryBound(to: UInt16.self)

        if rgb10Scratch.count != side * side * 3 {
            rgb10Scratch = [UInt16](repeating: 0, count: side * side * 3)
        }
        ColorHead.x420LumaLUT4096.withUnsafeBufferPointer { lut in
            rgb10Scratch.withUnsafeMutableBufferPointer { rgb in
                for row in 0..<side {
                    let py = crop.y0 + row
                    let yRow = yPtr + py * yStride
                    let cRow = cPtr + (py >> 1) * cStride
                    var o = row * side * 3
                    // 4:2:0 shares one chroma sample per horizontal pixel pair:
                    // recompute the offsets only when the pair index advances
                    // (crop.x0 may be odd, so track ci rather than col parity).
                    // Values are identical to the per-pixel form; cRow changes
                    // per row, so the cache resets with each row.
                    var lastCi = -1
                    var off: (r: Int32, g: Int32, b: Int32) = (0, 0, 0)
                    for col in 0..<side {
                        let px = crop.x0 + col
                        let lum = lut[Int(yRow[px] >> 6)]
                        let ci = (px >> 1) * 2
                        if ci != lastCi {
                            off = ColorHead.x420ChromaOffsets4096(
                                cb: Int32(cRow[ci] >> 6), cr: Int32(cRow[ci + 1] >> 6))
                            lastCi = ci
                        }
                        rgb[o] = UInt16(min(1023, max(0, (lum + off.r + 2048) >> 12)))
                        rgb[o + 1] = UInt16(min(1023, max(0, (lum + off.g + 2048) >> 12)))
                        rgb[o + 2] = UInt16(min(1023, max(0, (lum + off.b + 2048) >> 12)))
                        o += 3
                    }
                }
            }
        }

        var sums = [UInt64](repeating: 0, count: 64 * 64 * 3)
        let rc = rgb10Scratch.withUnsafeBufferPointer { rgb in
            sums.withUnsafeMutableBufferPointer { out in
                s4_pool_sums_linear_hlg10(rgb.baseAddress, Int32(side), 64, out.baseAddress)
            }
        }
        guard rc == 0 else { return nil }
        lastCropArea = Int64(side / 16) * Int64(side / 16)
        sumsAreLinear = true // linear16 BT.2020 → s4_sums_bt2020_to_srgb8 in emit16
        return sums
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
                tBandFeatures.append(p00)
                tBandFeatures.append(p01)
                tBandFeatures.append(p10)
                tBandFeatures.append(p11)
                tBandTargets.append(tBand)
            }
        }
        if tBandTargets.count > ColorHead.maxRetainedPairs {
            let drop = tBandTargets.count - ColorHead.maxRetainedPairs
            tBandFeatures.removeFirst(drop * 4)
            tBandTargets.removeFirst(drop)
        }
    }

    /// Drain the accumulated S_t pairs as Float rows for 'BandHeadTrainer'
    /// (row-major, width 5: bias + the four causal fine L-sums), scaled by
    /// `scale` (callers pass ~1/binMass so features sit near O(1)). Clears
    /// the accumulator. The single exact→float boundary of the circuit.
    func drainTBandPairs(scale: Float) -> (features: [Float], targets: [Float], width: Int) {
        var f = [Float]()
        f.reserveCapacity(tBandTargets.count * 5)
        for i in 0 ..< tBandTargets.count {
            f.append(1)
            for j in 0 ..< 4 { f.append(Float(tBandFeatures[i * 4 + j]) * scale) }
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
            let count = lastCropArea * 4 // spatial area × 4 temporal ticks = pixels/bin
            let rc = frame16.withUnsafeBufferPointer { sums in
                gct.withUnsafeMutableBufferPointer { out in
                    sumsAreLinear
                        // linear16 BT.2020 measurement sums → gamut hop + inverse-EOTF
                        ? s4_sums_bt2020_to_srgb8(sums.baseAddress, 16, count, out.baseAddress)
                        // gamma sRGB8 byte sums → round-half-up mean
                        : s4_sums_to_srgb8(sums.baseAddress, 16, count, out.baseAddress)
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

    // MARK: - The display realization (LIVE-LADDER preview, Feature.liveLadder)

    /// Realize the current 32-rung and 16-rung sums into direct sRGB8 RGB tiles for
    /// the live inverted-pyramid preview — the inverse-EOTF kernel the header names
    /// (`s4_sums_bt2020_to_srgb8` / `s4_sums_to_srgb8`, `Spec.RadiometricRealize`)
    /// applied at the 32² and 16² rungs (not just the 16² GCT `emit16` already does).
    ///
    /// Each rung is area-meaned over its exact pixel `count`, matching `emit16`'s
    /// `lastCropArea*4` for the 16-rung: the 16-bin pools (side/16)² spatial pixels ×
    /// 4 temporal ticks = `lastCropArea*4`; the 32-bin pools (side/32)² × 2 ticks =
    /// `lastCropArea/2`. Linear x420 sums realize via the BT.2020 gamut-hop kernel;
    /// gamma-byte sums (32BGRA feed) via `s4_sums_to_srgb8`. Nil until both rungs
    /// exist. Display-only — no GIF byte depends on it (the burst path is untouched).
    func realizeLadderSrgb8() -> (rgb32: [SIMD3<UInt8>], rgb16: [SIMD3<UInt8>])? {
        guard lastCropArea > 0, let l32 = latest32, let l16 = latest16 else { return nil }
        // INVARIANT: lastCropArea == (crop.side/16)² — the 16-RUNG per-bin spatial area (set in
        // poolSums64). The rung counts below depend on it; re-basing lastCropArea would silently
        // mis-scale both by a constant factor (×4 / ×256). Balance = spatial pixels × temporal ticks:
        let count32 = lastCropArea / 2   // (crop.side/32)² spatial × 2 temporal ticks = S²/512
        let count16 = lastCropArea * 4   // (crop.side/16)² spatial × 4 temporal ticks = S²/64
        guard count32 > 0 else { return nil }
        guard let rgb32 = realizeRung(l32, side: 32, count: count32),
              let rgb16 = realizeRung(l16, side: 16, count: count16) else { return nil }
        return (rgb32, rgb16)
    }

    /// One rung of `realizeLadderSrgb8`: sums → sRGB8 via the inverse-EOTF kernel
    /// (selected by `sumsAreLinear`, exactly as `emit16`), packed to SIMD3<UInt8>.
    private func realizeRung(_ sums: [UInt64], side: Int, count: Int64) -> [SIMD3<UInt8>]? {
        var out = [UInt8](repeating: 0, count: side * side * 3)
        let rc = sums.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { o in
                sumsAreLinear
                    ? s4_sums_bt2020_to_srgb8(s.baseAddress, Int32(side), count, o.baseAddress)
                    : s4_sums_to_srgb8(s.baseAddress, Int32(side), count, o.baseAddress)
            }
        }
        guard rc == 0 else { return nil }
        return (0..<(side * side)).map {
            SIMD3<UInt8>(out[$0 * 3], out[$0 * 3 + 1], out[$0 * 3 + 2])
        }
    }

    /// OPTICAL-EV single-frame realize (NO temporal pooling): pool ONE frame's 64² linear
    /// sums spatially down to `side` (64/32/16) and realize to sRGB8. Unlike
    /// `realizeLadderSrgb8`, each optical exposure is a DISTINCT frame, so there is no temporal
    /// mixing — the per-bin count is purely spatial, `(crop.side/side)²`. Same inverse-EOTF
    /// kernel selection (`sumsAreLinear`) as `emit16`. Display-only; the burst path is untouched.
    func realizeSingleFrame(sums64: [UInt64], side: Int) -> [SIMD3<UInt8>]? {
        guard side == 64 || side == 32 || side == 16 else { return nil }
        guard lastCropArea > 0 else { return nil }
        var sums = sums64
        var s = 64
        while s > side { sums = ColorHead.poolSpatial2(sums, side: s); s /= 2 }
        // Per-bin spatial pixel count = (crop.side/side)², derived from the ACTUAL crop the sums
        // were pooled over (`lastCropArea == (crop.side/16)²`, set in poolSums64), NOT the instance
        // `cropSide` — so a `crop.side < cropSide` (camera min-dim below cropSide) stays balanced:
        // (crop.side/side)² = lastCropArea·(16/side)² = lastCropArea·256/side², exact for 16/32/64.
        let count = lastCropArea * 256 / Int64(side * side)
        return realizeRung(sums, side: side, count: count)
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

    // MARK: - The halting-depth budget (KinematicHaltPrior KEYSTONE)

    /// The halting depth the certified-order floor licenses — the max certified
    /// kinematic order across slots whose window is long enough to certify, or
    /// -1 if none certify yet. This is `lawCheapestZeroLossHaltIsCertifiedOrder`
    /// made into a runtime budget: Newton prediction of order k is EXACT, so the
    /// per-slot order is exactly how deep learning can help.
    ///
    /// Pure + static so `KinematicHaltPriorBudgetTests` can exercise the gate on
    /// synthetic order vectors with no camera.
    static func haltingDepthBudget(_ orders: [Int32]) -> Int {
        Int(orders.filter { $0 >= 0 }.max() ?? -1)
    }

    /// Whether the S_t yang head has residual worth fitting, given the floor.
    /// The head is a first-order (bias + causal-L) predictor, so a scene whose
    /// motion certifies at order ≤ 1 everywhere (static or constant-velocity) is
    /// already shipped EXACTLY by the kinematic floor + bias — training it there
    /// is the wasted S-packets ARM 3 of the training-occurs proof punishes. Real
    /// spatially-conditional t-band structure only appears at order ≥ 2
    /// (acceleration and up). `orders` = `haltFloor()`.
    static func residualNeedsLearning(_ orders: [Int32]) -> Bool {
        haltingDepthBudget(orders) >= 2
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
