import Foundation
import os

/// Sink for the log lines the Zig core pushes (one per kernel call). Global so
/// the `@convention(c)` callback can reference it without capturing.
private let zigLogger = Logger(subsystem: "com.sixfour.SixFour", category: "native.zig")

/// Thread-dictionary key that suppresses Zig log forwarding on the current thread
/// (set by the live preview). File-scope so the non-capturing C callback can read it.
private let zigLogSuppressKey = "com.sixfour.suppressZigLog"

/// Swift surface over the native Zig kernels.
///
/// The implementations live in `Native/src/*.zig` (C ABI declared in
/// `Native/include/sixfour_native.h`, bridged via `SixFour-Bridging-Header.h`)
/// and are compiled to `libsixfour_native.a` by `Native/build-ios.sh` during
/// the build. Each entry point mirrors a Swift reference implementation that
/// stays in the tree as the parity oracle.
enum SixFourNative {
    private static let log = Logger(subsystem: "com.sixfour", category: "native")

    /// Toolchain/link smoke test — returns `x + 1` from the Zig static lib.
    /// Proves the FFI is wired end-to-end; remove once a real kernel ships.
    static func probe(_ x: UInt32) -> UInt32 {
        s4_probe(x)
    }

    /// Route the Zig core's pushed log lines into `os.Logger` (category
    /// `native.zig`, debug level). Call once at startup. After this, every
    /// kernel call emits one line — visible proof in Console that the
    /// deterministic work ran, stage by stage. The closure is non-capturing
    /// (references the global `zigLogger`), so it converts to a C function pointer.
    static func installLogging() {
        s4_set_log_callback { (msg: UnsafePointer<UInt8>?, len: Int) in
            guard let msg, len > 0 else { return }
            // The callback fires synchronously on the calling kernel's thread, so
            // a thread-local set by the live preview suppresses ONLY the preview's
            // lines (it calls the kernels ~10×/s); the capture render, on another
            // thread, still logs every stage.
            if Thread.current.threadDictionary[zigLogSuppressKey] != nil { return }
            let text = String(decoding: UnsafeBufferPointer(start: msg, count: len), as: UTF8.self)
            zigLogger.debug("zig: \(text, privacy: .public)")
        }
    }

    /// Run `body` with this thread's Zig log lines suppressed. Used by the live
    /// 64×64 preview so its per-frame kernel logs don't flood the log stream;
    /// the deterministic capture render (a different thread) is unaffected.
    static func withZigLogsSuppressed<R>(_ body: () -> R) -> R {
        let td = Thread.current.threadDictionary
        td[zigLogSuppressKey] = true
        defer { td.removeObject(forKey: zigLogSuppressKey) }
        return body()
    }

    // MARK: - Deterministic quantized core (palette + dither + GIF89a)

    /// Parameters for the deterministic GIF burst encoder. Defaults match the
    /// SixFour shape (64 frames, 64×64, 256-colour local palettes, 20 fps).
    struct GifEncodeParams {
        var frameCount: Int32 = 64
        var side: Int32 = 64
        var k: Int32 = 256
        var inputSpace: Int32 = 0       // S4_INPUT_LINEAR_SRGB_HALF
        var lloydIters: Int32 = 15
        var ditherMode: Int32 = 2       // S4_DITHER_BLUE_NOISE
        var serpentine: Int32 = 0
        var frameDelayCentiseconds: UInt16 = 5
        init() {}
    }

    /// Encode a 64-frame burst into a deterministic GIF89a via the Zig core.
    ///
    /// `linearHalfs` is the linear-sRGB Float16 tile read back from Metal
    /// (T·H·W·3 IEEE-half bit patterns). `stbnMask` is the toroidally-tiled
    /// STBN3D mask bytes for the blue-noise dither modes (pass `nil` for the
    /// error-diffusion modes). Returns the GIF bytes, or `nil` on failure.
    ///
    /// The underlying `s4_gif_encode_burst` is IMPLEMENTED (the deterministic fold
    /// widen->oklab->quantize->dither->palette->assemble) and is byte-exact against
    /// the Haskell golden `golden.gif` (pinned by `Native/src/gif_fixture_test.zig`).
    /// `DeviceGifParityTests` re-asserts that byte-exactness ON the device.
    static func encodeBurst(
        linearHalfs: [UInt16],
        stbnMask: [UInt8]?,
        comment: String?,
        params: GifEncodeParams = GifEncodeParams()
    ) -> Data? {
        let bound = s4_gif_encode_burst_bound(params.frameCount, params.side, params.k)
        let scratchBytes = s4_burst_scratch_bytes(params.frameCount, params.side, params.k)
        guard bound > 0, scratchBytes > 0 else {
            log.error("encodeBurst: bad shape \(params.frameCount)×\(params.side)²×\(params.k)")
            return nil
        }

        var out = [UInt8](repeating: 0, count: bound)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: scratchBytes, alignment: 16)
        defer { scratch.deallocate() }
        var outLen: Int = 0
        let commentBytes: [UInt8] = comment.map { Array($0.utf8) } ?? []

        let rc: Int32 = linearHalfs.withUnsafeBufferPointer { halfsPtr in
            out.withUnsafeMutableBufferPointer { outPtr in
                commentBytes.withUnsafeBufferPointer { cPtr in
                    withMaskPointer(stbnMask) { maskPtr in
                        s4_gif_encode_burst(
                            halfsPtr.baseAddress,
                            params.frameCount, params.side, params.k,
                            params.inputSpace, params.lloydIters,
                            params.ditherMode, params.serpentine,
                            maskPtr, params.frameDelayCentiseconds,
                            cPtr.baseAddress, Int32(commentBytes.count),
                            outPtr.baseAddress, bound, &outLen,
                            scratch, scratchBytes
                        )
                    }
                }
            }
        }

        guard rc == S4_RC_OK else {
            log.error("s4_gif_encode_burst failed: rc=\(rc)")
            return nil
        }
        return Data(out[0..<outLen])
    }

    /// Call `body` with a pointer to `mask`'s bytes, or NULL when `mask` is nil.
    private static func withMaskPointer<R>(
        _ mask: [UInt8]?,
        _ body: (UnsafePointer<UInt8>?) -> R
    ) -> R {
        if let mask {
            return mask.withUnsafeBufferPointer { body($0.baseAddress) }
        }
        return body(nil)
    }

    // MARK: - Per-stage deterministic kernels (the visible pipeline)
    //
    // Thin Swift surfaces over the verified Zig kernels, called stage-by-stage by
    // DeterministicRenderer so each progress banner maps to one real kernel. Each
    // is byte-exact against a Haskell golden (Native/src/*_fixture_test.zig).

    /// OKLab `Float` pixels → Q16 `Int32` (×65536, round-half-to-even). ×2^16 is
    /// exact in `Float`; only the final round chooses an integer — deterministic.
    static func oklabToQ16(_ pixels: [SIMD3<Float>]) -> [Int32] {
        var out = [Int32]()
        out.reserveCapacity(pixels.count * 3)
        for p in pixels {
            out.append(Int32((p.x * 65536).rounded(.toNearestOrEven)))
            out.append(Int32((p.y * 65536).rounded(.toNearestOrEven)))
            out.append(Int32((p.z * 65536).rounded(.toNearestOrEven)))
        }
        return out
    }

    struct QuantResult { let centroids: [Int32]; let indices: [UInt8] }

    /// Maximin seed + optional Lloyd → k Q16 centroids + assignment.
    static func quantizeFrame(oklabQ16: [Int32], k: Int, lloydIters: Int) -> QuantResult? {
        let p = Int32(oklabQ16.count / 3)
        var centroids = [Int32](repeating: 0, count: k * 3)
        var indices = [UInt8](repeating: 0, count: Int(p))
        let scratchBytes = Int(p) * 8 + 3 * k * 8 + k * 4
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: scratchBytes, alignment: 16)
        defer { scratch.deallocate() }
        let rc = oklabQ16.withUnsafeBufferPointer { px in
            centroids.withUnsafeMutableBufferPointer { c in
                indices.withUnsafeMutableBufferPointer { idx in
                    s4_quantize_frame(px.baseAddress, p, Int32(k), Int32(lloydIters),
                                      c.baseAddress, idx.baseAddress, scratch, scratchBytes)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_quantize_frame rc=\(rc)"); return nil }
        return QuantResult(centroids: centroids, indices: indices)
    }

    /// Deterministic synthetic OKLab Q16 burst (`s4_synth_burst`) — the CAMERA-FREE
    /// input generator. Returns `frameCount*side*side*3` interleaved Int32 OKLab Q16,
    /// reproducible from `seed` (mode 0 = colour, 1 = grayscale). This is the
    /// synthetic-data harness that lets a device test exercise the make/encode path
    /// with no AVFoundation capture; the SAME generator the Mac trainer
    /// (`trainer/zig_native.py`) uses, so device and Mac agree byte-for-byte per seed.
    static func synthBurst(seed: UInt64, mode: Int32, frameCount: Int32, side: Int32,
                           lMinQ16: Int32 = 5243, lMaxQ16: Int32 = 60293,
                           chromaMaxQ16: Int32 = 18350) -> [Int32]? {
        let count = Int(frameCount) * Int(side) * Int(side) * 3
        guard count > 0 else { return nil }
        var out = [Int32](repeating: 0, count: count)
        let rc = out.withUnsafeMutableBufferPointer { o in
            s4_synth_burst(seed, mode, frameCount, side, lMinQ16, lMaxQ16, chromaMaxQ16, o.baseAddress)
        }
        guard rc == S4_RC_OK else { log.error("s4_synth_burst rc=\(rc)"); return nil }
        return out
    }

    /// Dither one frame against fixed centroids → indices. mode 0=FS 1=Atkinson
    /// 2=blueNoise 3=frozen; `stbnSlice` is the per-frame STBN3D mask for 2/3.
    static func ditherFrame(oklabQ16: [Int32], centroids: [Int32], k: Int,
                            mode: Int, serpentine: Bool, stbnSlice: [UInt8]?) -> [UInt8]? {
        let p = Int32(oklabQ16.count / 3)
        var indices = [UInt8](repeating: 0, count: Int(p))
        let scratchBytes = Int(p) * 3 * 4
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: scratchBytes, alignment: 16)
        defer { scratch.deallocate() }
        let rc = oklabQ16.withUnsafeBufferPointer { px in
            centroids.withUnsafeBufferPointer { c in
                indices.withUnsafeMutableBufferPointer { idx in
                    withMaskPointer(stbnSlice) { mask in
                        s4_dither_frame(px.baseAddress, c.baseAddress, p, Int32(k),
                                        Int32(mode), serpentine ? 1 : 0, mask,
                                        idx.baseAddress, scratch, scratchBytes)
                    }
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_dither_frame rc=\(rc)"); return nil }
        return indices
    }

    struct GlobalCollapseResult { let leaves: [SIMD3<Int32>]; let indices: [Int] }

    /// GIFA → GIFB: collapse the per-frame Q16 OKLab palettes into ONE global palette
    /// via the Zig `s4_global_collapse` (maximin `kOut` leaves + per-colour nearest-leaf
    /// re-index). The byte-exact on-device home of the collapse; mirrors the pure-Swift
    /// `FarthestPointCollapse` and the Haskell `globalCollapseQ16`, all gated to the same
    /// spec golden. Requires uniform per-frame palette length. `indices` is the flattened
    /// `t·kIn` index map (frame `f`, slot `s` → `indices[f·kIn + s]`).
    ///
    /// ⚠️ V2-DEFERRED-GLOBAL-PALETTE — global (GIFB) collapse, deferred to V2 behind
    /// Feature.globalPaletteV2 (false in MVP1). Kept, compiled, and golden-gated for V2; not a live
    /// MVP1 path. See docs/SIXFOUR-GLOBAL-PALETTE-RETIREMENT-WORKFLOW.md. Do not add new callers.
    static func globalCollapse(perFramePalettes: [[SIMD3<Int32>]], kOut: Int) -> GlobalCollapseResult? {
        let t = perFramePalettes.count
        guard t > 0, let kIn = perFramePalettes.first?.count, kIn > 0,
              perFramePalettes.allSatisfy({ $0.count == kIn }) else { return nil }
        var flat = [Int32](); flat.reserveCapacity(t * kIn * 3)
        for frame in perFramePalettes { for c in frame { flat.append(c.x); flat.append(c.y); flat.append(c.z) } }
        let p = t * kIn
        var leaves = [Int32](repeating: 0, count: kOut * 3)
        var indices = [UInt8](repeating: 0, count: p)
        let scratchBytes = p * 8 + 3 * kOut * 8 + kOut * 4
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: scratchBytes, alignment: 16)
        defer { scratch.deallocate() }
        let rc = flat.withUnsafeBufferPointer { fp in
            leaves.withUnsafeMutableBufferPointer { lp in
                indices.withUnsafeMutableBufferPointer { ip in
                    s4_global_collapse(fp.baseAddress, Int32(t), Int32(kIn), Int32(kOut),
                                       lp.baseAddress, ip.baseAddress, scratch, scratchBytes)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_global_collapse rc=\(rc)"); return nil }
        let leafVecs = (0 ..< kOut).map { SIMD3<Int32>(leaves[$0 * 3], leaves[$0 * 3 + 1], leaves[$0 * 3 + 2]) }
        return GlobalCollapseResult(leaves: leafVecs, indices: indices.map { Int($0) })
    }

    // MARK: - Owned integer Haar (reversible lifting)

    /// Forward integer Haar over Q16 OKLab leaves (`s4_haar_analyze`): the palette's
    /// dimensional space as exact integer math. `leaves.count` must be a power of two.
    /// Returns the root + `n-1` detail offsets (coarsest-first). Mirrors
    /// `SixFour.Spec.PairTreeFixed.analyzeFixed`; `reconstruct∘analyze = id` exactly.
    static func haarAnalyze(leaves: [SIMD3<Int32>]) -> (root: SIMD3<Int32>, offsets: [SIMD3<Int32>])? {
        let n = leaves.count
        guard n > 0, (n & (n - 1)) == 0 else { return nil }
        var flat = [Int32](); flat.reserveCapacity(n * 3)
        for c in leaves { flat.append(c.x); flat.append(c.y); flat.append(c.z) }
        var root = [Int32](repeating: 0, count: 3)
        var offs = [Int32](repeating: 0, count: (n - 1) * 3)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: n * 3 * 4, alignment: 16)
        defer { scratch.deallocate() }
        let rc = flat.withUnsafeBufferPointer { lp in
            root.withUnsafeMutableBufferPointer { rp in
                offs.withUnsafeMutableBufferPointer { op in
                    s4_haar_analyze(lp.baseAddress, Int32(n), rp.baseAddress, op.baseAddress, scratch, n * 3 * 4)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_haar_analyze rc=\(rc)"); return nil }
        let rootVec = SIMD3<Int32>(root[0], root[1], root[2])
        let offVecs = (0 ..< (n - 1)).map { SIMD3<Int32>(offs[$0 * 3], offs[$0 * 3 + 1], offs[$0 * 3 + 2]) }
        return (rootVec, offVecs)
    }

    /// Inverse integer Haar (`s4_haar_reconstruct`): root + `n-1` offsets → `n` leaves.
    /// Exact inverse of `haarAnalyze`.
    static func haarReconstruct(root: SIMD3<Int32>, offsets: [SIMD3<Int32>]) -> [SIMD3<Int32>]? {
        let n = offsets.count + 1
        guard n > 0, (n & (n - 1)) == 0 else { return nil }
        var rootFlat = [root.x, root.y, root.z]
        var offFlat = [Int32](); offFlat.reserveCapacity(offsets.count * 3)
        for o in offsets { offFlat.append(o.x); offFlat.append(o.y); offFlat.append(o.z) }
        var leaves = [Int32](repeating: 0, count: n * 3)
        let rc = rootFlat.withUnsafeBufferPointer { rp in
            offFlat.withUnsafeBufferPointer { op in
                leaves.withUnsafeMutableBufferPointer { lp in
                    s4_haar_reconstruct(rp.baseAddress, op.baseAddress, Int32(n), lp.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_haar_reconstruct rc=\(rc)"); return nil }
        return (0 ..< n).map { SIMD3<Int32>(leaves[$0 * 3], leaves[$0 * 3 + 1], leaves[$0 * 3 + 2]) }
    }

    /// The node colours at Haar pairing `level` (`s4_haar_level_nodes`) — the
    /// abstraction cascade. `level 0` = `[root]`; `level i` = `2^i` nodes; `level
    /// log2(n)` = the full leaf palette. SixFour surfaces `level 4` (16 colours) as
    /// the capture shutter. `n` = total leaves (a power of two), `0 <= level <=
    /// log2(n)`. Byte-exact vs `SixFour.Spec.PairTreeFixed.levelNodesFixed`.
    static func haarLevelNodes(level: Int, root: SIMD3<Int32>, offsets: [SIMD3<Int32>]) -> [SIMD3<Int32>]? {
        let n = offsets.count + 1
        guard n > 0, (n & (n - 1)) == 0, level >= 0, (1 << level) <= n else { return nil }
        let count = 1 << level
        var rootFlat = [root.x, root.y, root.z]
        var offFlat = [Int32](); offFlat.reserveCapacity(offsets.count * 3)
        for o in offsets { offFlat.append(o.x); offFlat.append(o.y); offFlat.append(o.z) }
        var nodes = [Int32](repeating: 0, count: count * 3)
        let rc = rootFlat.withUnsafeBufferPointer { rp in
            offFlat.withUnsafeBufferPointer { op in
                nodes.withUnsafeMutableBufferPointer { np in
                    s4_haar_level_nodes(Int32(level), rp.baseAddress, op.baseAddress, Int32(n), np.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_haar_level_nodes rc=\(rc)"); return nil }
        return (0 ..< count).map { SIMD3<Int32>(nodes[$0 * 3], nodes[$0 * 3 + 1], nodes[$0 * 3 + 2]) }
    }

    // MARK: - σ-pair leaf override (the n=0 taste tint)

    /// Apply the user's generator-space taste tint (`s4_leaf_override`, the owned
    /// port of `SixFour.Spec.LeafOverride.applySigmaOverride`).
    /// ⚠️ OWNED-BUT-UNWIRED: zero production callers — the σ-pair tint for step 3+
    /// (learned genomes), NOT the live n=0 loop (that uses `PersonalTaste.leafTint`).
    /// For each generator
    /// `gᵢ`, add `δᵢ` and emit the σ-pair `[g, σ(g)]` with `σ(l,a,b) = (l,−a,−b)`.
    /// Returns `2·generators.count` σ-pair leaves. `deltas` is zero-padded /
    /// truncated to the generator count; `nil` (or empty) ⇒ the no-op override.
    /// Byte-exact across Haskell/Zig/Swift — the σ-symmetry is preserved by
    /// construction (the odd leaf is σ of the *nudged* generator).
    static func leafOverride(generators: [SIMD3<Int32>], deltas: [SIMD3<Int32>]? = nil) -> [SIMD3<Int32>]? {
        let n = generators.count
        guard n > 0 else { return [] }
        var gflat = [Int32](); gflat.reserveCapacity(n * 3)
        for g in generators { gflat.append(g.x); gflat.append(g.y); gflat.append(g.z) }
        var dflat: [Int32]? = nil
        if let deltas {
            var d = [Int32](repeating: 0, count: n * 3)
            for i in 0 ..< min(n, deltas.count) {
                d[i * 3 + 0] = deltas[i].x; d[i * 3 + 1] = deltas[i].y; d[i * 3 + 2] = deltas[i].z
            }
            dflat = d
        }
        var out = [Int32](repeating: 0, count: n * 6)
        let rc = gflat.withUnsafeBufferPointer { gp -> Int32 in
            out.withUnsafeMutableBufferPointer { op in
                if let dflat {
                    return dflat.withUnsafeBufferPointer { dp in
                        s4_leaf_override(gp.baseAddress, dp.baseAddress, Int32(n), op.baseAddress)
                    }
                } else {
                    return s4_leaf_override(gp.baseAddress, nil, Int32(n), op.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_leaf_override rc=\(rc)"); return nil }
        return (0 ..< n * 2).map { SIMD3<Int32>(out[$0 * 3], out[$0 * 3 + 1], out[$0 * 3 + 2]) }
    }

    /// Convenience for the UI: an sRGB8 palette (`k` a power of two) → the Haar
    /// `level` node colours as sRGB8 (the abstraction cascade). Used by the capture
    /// shutter (`level 4` → 16 colours) and review. sRGB8 → OKLab Q16 → haarAnalyze →
    /// haarLevelNodes → sRGB8, all through the verified Zig kernels.
    static func haarLevelColors(palette srgb: [SIMD3<UInt8>], level: Int) -> [SIMD3<UInt8>]? {
        let n = srgb.count
        guard n > 0, (n & (n - 1)) == 0, level >= 0, (1 << level) <= n else { return nil }
        // CANONICAL forward: sRGB8 -> OKLab Q16 through the owned Zig kernel
        // (s4_srgb8_to_oklab_q16: integer matmul + icbrtQ16), NOT ColorScience float
        // cbrtf + round. This is the SAME transform training and the substrate use, so
        // the surfaced shutter cascade is byte-exact with the Haskell golden (no
        // train/display skew). Matches this function's own doc contract above.
        let rgbFlat = srgb.flatMap { [$0.x, $0.y, $0.z] }
        guard let q16 = srgb8ToOklab(rgb: rgbFlat, k: n) else { return nil }
        let leaves = (0 ..< n).map { SIMD3<Int32>(q16[$0 * 3], q16[$0 * 3 + 1], q16[$0 * 3 + 2]) }
        guard let hp = haarAnalyze(leaves: leaves),
              let nodes = haarLevelNodes(level: level, root: hp.root, offsets: hp.offsets) else { return nil }
        let flat = nodes.flatMap { [$0.x, $0.y, $0.z] }
        guard let out = paletteToSRGB8(centroidsQ16: flat, k: nodes.count) else { return nil }
        return (0 ..< nodes.count).map { SIMD3<UInt8>(out[$0 * 3], out[$0 * 3 + 1], out[$0 * 3 + 2]) }
    }

    struct SignificanceResult { let indices: [UInt8]; let cellStats: [Int32] }  // cellStats: k×7

    /// Rebalance indices to ≥ minPopulation per slot; emit k×7 cell stats
    /// (meanLab, stdLab, count, all Q16 except count).
    static func significanceFill(oklabQ16: [Int32], centroids: [Int32], k: Int,
                                 minPop: Int, indices: [UInt8]) -> SignificanceResult? {
        let p = Int32(oklabQ16.count / 3)
        var idx = indices
        var cells = [Int32](repeating: 0, count: k * 7)
        let rc = oklabQ16.withUnsafeBufferPointer { px in
            centroids.withUnsafeBufferPointer { c in
                idx.withUnsafeMutableBufferPointer { ii in
                    cells.withUnsafeMutableBufferPointer { cc in
                        s4_significance_fill(px.baseAddress, c.baseAddress, p, Int32(k),
                                             Int32(minPop), ii.baseAddress, cc.baseAddress, nil, 0)
                    }
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_significance_fill rc=\(rc)"); return nil }
        return SignificanceResult(indices: idx, cellStats: cells)
    }

    /// k Q16 OKLab centroids → k×3 sRGB8 (the GIF local colour table).
    static func paletteToSRGB8(centroidsQ16: [Int32], k: Int) -> [UInt8]? {
        var rgb = [UInt8](repeating: 0, count: k * 3)
        let rc = centroidsQ16.withUnsafeBufferPointer { c in
            rgb.withUnsafeMutableBufferPointer { r in
                s4_palette_oklab_to_srgb8(c.baseAddress, Int32(k), r.baseAddress, nil, 0)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_palette_oklab_to_srgb8 rc=\(rc)"); return nil }
        return rgb
    }

    /// k sRGB8 triples → k OKLab Q16 (decode; lossy inverse of `paletteToSRGB8`).
    /// Used by the look round-trip to bring a display palette back into OKLab.
    static func srgb8ToOklab(rgb: [UInt8], k: Int) -> [Int32]? {
        var out = [Int32](repeating: 0, count: k * 3)
        let rc = rgb.withUnsafeBufferPointer { r in
            out.withUnsafeMutableBufferPointer { o in
                s4_srgb8_to_oklab_q16(r.baseAddress, Int32(k), o.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_srgb8_to_oklab_q16 rc=\(rc)"); return nil }
        return out
    }

    // ── Look transfer / LUT extraction (R3D .cube) ────────────────────────────
    // The on-screen "look" and the exported 3D LUT are two projections of ONE
    // OKLab palette→palette transform derived from the captured palette's
    // luminance-zone chroma profile. Mirrors SixFour.Spec.{ZoneProfile,
    // LookTransfer,CubeLut}; byte-exact (golden-gated by lut_fixture_test.zig).

    /// The luminance-zone chroma profile of a palette — the data-driven source of
    /// a look. `meanA/B/C` each hold `numZones` Q16 values; `global` is the
    /// empty-zone fallback. Fed to `lookTransfer` (preview) and `extractLUT`.
    struct ZoneProfile {
        let numZones: Int
        let meanA: [Int32]
        let meanB: [Int32]
        let meanC: [Int32]
        let global: SIMD3<Int32>
    }

    /// Look transform parameters (Q16). A "look variant" is a choice of these over
    /// a live-derived profile (`LookVariant` maps to one). Defaults match the spec.
    struct LookParams {
        var strength: Int32   = 49152      // 0.75
        var chromaMin: Int32  = 6553       // 0.1
        var chromaMax: Int32  = 196608     // 3.0
        var polarity: Int32   = 65536      // +1 (−65536 = complement)
        var chromaEps: Int32  = 64
    }

    /// Analyse a 256-colour OKLab Q16 palette into its luminance-zone profile.
    static func lookZoneProfile(paletteOklabQ16: [Int32], numZones: Int = 8) -> ZoneProfile? {
        let p = Int32(paletteOklabQ16.count / 3)
        var meanA = [Int32](repeating: 0, count: numZones)
        var meanB = [Int32](repeating: 0, count: numZones)
        var meanC = [Int32](repeating: 0, count: numZones)
        var global = [Int32](repeating: 0, count: 3)
        let rc = paletteOklabQ16.withUnsafeBufferPointer { pal in
            meanA.withUnsafeMutableBufferPointer { a in
                meanB.withUnsafeMutableBufferPointer { b in
                    meanC.withUnsafeMutableBufferPointer { c in
                        global.withUnsafeMutableBufferPointer { g in
                            s4_zone_profile_q16(pal.baseAddress, p, Int32(numZones),
                                                a.baseAddress, b.baseAddress, c.baseAddress,
                                                g.baseAddress)
                        }
                    }
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_zone_profile_q16 rc=\(rc)"); return nil }
        return ZoneProfile(numZones: numZones, meanA: meanA, meanB: meanB, meanC: meanC,
                           global: SIMD3(global[0], global[1], global[2]))
    }

    /// Map K OKLab Q16 colours through the look transform (the live PREVIEW look).
    /// Returns transferred OKLab Q16 (K·3); pair with `paletteToSRGB8` to display.
    static func lookTransfer(oklabQ16: [Int32], profile: ZoneProfile, params: LookParams) -> [Int32]? {
        let k = Int32(oklabQ16.count / 3)
        var out = [Int32](repeating: 0, count: oklabQ16.count)
        let rc = oklabQ16.withUnsafeBufferPointer { inp in
            profile.meanA.withUnsafeBufferPointer { a in
                profile.meanB.withUnsafeBufferPointer { b in
                    profile.meanC.withUnsafeBufferPointer { c in
                        out.withUnsafeMutableBufferPointer { o in
                            s4_look_transfer_q16(inp.baseAddress, k,
                                                 a.baseAddress, b.baseAddress, c.baseAddress,
                                                 Int32(profile.numZones),
                                                 params.strength, params.chromaMin, params.chromaMax,
                                                 params.polarity, params.chromaEps,
                                                 o.baseAddress)
                        }
                    }
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_look_transfer_q16 rc=\(rc)"); return nil }
        return out
    }

    /// Build the `size`³ .cube as Q16 sRGB-encoded triples in .cube order (R
    /// fastest). For R3D: input domain Log3G10/RWGRGB, output Rec.709 sRGB-gamma.
    /// `LUTFile` formats these `Double(v)/65536` to 6 decimals.
    static func extractLUT(profile: ZoneProfile, params: LookParams, size: Int = 65) -> [Int32]? {
        let count = size * size * size * 3
        var cube = [Int32](repeating: 0, count: count)
        let rc = profile.meanA.withUnsafeBufferPointer { a in
            profile.meanB.withUnsafeBufferPointer { b in
                profile.meanC.withUnsafeBufferPointer { c in
                    cube.withUnsafeMutableBufferPointer { o in
                        s4_build_cube_q16(Int32(size),
                                          a.baseAddress, b.baseAddress, c.baseAddress,
                                          Int32(profile.numZones),
                                          params.strength, params.chromaMin, params.chromaMax,
                                          params.polarity, params.chromaEps,
                                          o.baseAddress, count)
                    }
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_build_cube_q16 rc=\(rc)"); return nil }
        return cube
    }

    /// Assemble GIF89a bytes from per-frame indices (T·P) + sRGB8 palettes (T·K·3).
    static func gifAssemble(indices: [UInt8], palettesRGB: [UInt8], frameCount: Int,
                            side: Int, k: Int, delayCs: UInt16, comment: String?) -> Data? {
        let bound = s4_gif_encode_burst_bound(Int32(frameCount), Int32(side), Int32(k))
        guard bound > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: bound)
        var outLen: Int = 0
        let commentBytes: [UInt8] = comment.map { Array($0.utf8) } ?? []
        let rc = indices.withUnsafeBufferPointer { idx in
            palettesRGB.withUnsafeBufferPointer { pal in
                commentBytes.withUnsafeBufferPointer { cmt in
                    out.withUnsafeMutableBufferPointer { o in
                        s4_gif_assemble(idx.baseAddress, pal.baseAddress, Int32(frameCount),
                                        Int32(side), Int32(k), delayCs,
                                        cmt.baseAddress, Int32(commentBytes.count),
                                        o.baseAddress, bound, &outLen)
                    }
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_gif_assemble rc=\(rc)"); return nil }
        return Data(out[0..<outLen])
    }

    // MARK: - V2.1 pre-collapse field
    //
    // Thin Swift surfaces over the V2.1 pre-collapse-field kernels (ports of
    // SixFour.Spec.V21Field). A "curve" carries one channel's per-level energy or
    // count; collapse of a curve is the sRGB byte the V2 boundary consumes. These
    // are ADDITIVE: no MVP1 path calls them. Each returns nil on rc != S4_RC_OK.

    /// Per channel-curve, the energy-MINIMISING level (argmin, lowest index wins
    /// ties) as an sRGB byte (`s4_v21_collapse`). `curves` is `p·3·nLevels` Q16
    /// energies (pixel-major: pixel, channel R,G,B, then level). Returns `p·3`
    /// sRGB bytes. `nLevels <= 256` (the level is the byte).
    static func collapseV21(curves: [Int32], p: Int, nLevels: Int) -> [UInt8]? {
        guard p > 0, nLevels > 0, curves.count == p * 3 * nLevels else { return nil }
        var out = [UInt8](repeating: 0, count: p * 3)
        let rc = curves.withUnsafeBufferPointer { c in
            out.withUnsafeMutableBufferPointer { o in
                s4_v21_collapse(c.baseAddress, Int32(p), Int32(nLevels), o.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_collapse rc=\(rc)"); return nil }
        return out
    }

    struct OctantLiftCurveResult { let coarse: [Int32]; let residuals: [Int32] }

    /// Per-level octant-lift driver (`s4_v21_octant_lift_curve`): drives the gated
    /// byte-exact `s4_octant_lift` over each of `nLevels` curve levels.
    /// `octantCurves` is `8·nLevels` (cell-major, level-contiguous). Returns the
    /// coarse curve (`nLevels`) and 7 residual curves (`7·nLevels`, residual-major).
    static func octantLiftCurveV21(octantCurves: [Int32], nLevels: Int) -> OctantLiftCurveResult? {
        guard nLevels > 0, octantCurves.count == 8 * nLevels else { return nil }
        var coarse = [Int32](repeating: 0, count: nLevels)
        var residuals = [Int32](repeating: 0, count: 7 * nLevels)
        let rc = octantCurves.withUnsafeBufferPointer { oc in
            coarse.withUnsafeMutableBufferPointer { co in
                residuals.withUnsafeMutableBufferPointer { re in
                    s4_v21_octant_lift_curve(oc.baseAddress, Int32(nLevels),
                                             co.baseAddress, re.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_octant_lift_curve rc=\(rc)"); return nil }
        return OctantLiftCurveResult(coarse: coarse, residuals: residuals)
    }

    /// Per-level integer opponent transform of the neighbour delta
    /// (`s4_v21_opponent_delta`). `bin1`/`bin2` are `3·nLevels` (R,G,B curves,
    /// level-contiguous) Q16. Returns `3·nLevels` (L,a,b) delta curves. Computed
    /// in i64; the kernel refuses on i32-envelope overflow.
    static func opponentDeltaV21(bin1: [Int32], bin2: [Int32], nLevels: Int) -> [Int32]? {
        guard nLevels > 0, bin1.count == 3 * nLevels, bin2.count == 3 * nLevels else { return nil }
        var out = [Int32](repeating: 0, count: 3 * nLevels)
        let rc = bin1.withUnsafeBufferPointer { b1 in
            bin2.withUnsafeBufferPointer { b2 in
                out.withUnsafeMutableBufferPointer { o in
                    s4_v21_opponent_delta(b1.baseAddress, b2.baseAddress, Int32(nLevels), o.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_opponent_delta rc=\(rc)"); return nil }
        return out
    }

    /// Captured-bin energy curve (`s4_v21_counts_to_energy`): `E(level) = total -
    /// count(level)`, `total` = sum of a curve's counts (argmin E = the mode).
    /// `counts` is `p·3·nLevels` (pixel-major, R,G,B, then level), non-negative.
    /// Returns `p·3·nLevels` energies. Per-curve total in i64; the kernel refuses
    /// on i32-envelope overflow.
    static func countsToEnergyV21(counts: [Int32], p: Int, nLevels: Int) -> [Int32]? {
        guard p > 0, nLevels > 0, counts.count == p * 3 * nLevels else { return nil }
        var out = [Int32](repeating: 0, count: p * 3 * nLevels)
        let rc = counts.withUnsafeBufferPointer { c in
            out.withUnsafeMutableBufferPointer { o in
                s4_v21_counts_to_energy(c.baseAddress, Int32(p), Int32(nLevels), o.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_counts_to_energy rc=\(rc)"); return nil }
        return out
    }

    /// The monotone 1-D optimal-transport map `T = F⁻¹∘F` between two EQUAL-MASS
    /// count histograms (`s4_v21_transport`): the per-rank displacement
    /// `d[k] = q_dst[k] − q_src[k]` on the sorted-quantile mass line. `src`/`dst`
    /// are `p·3·nLevels` counts (pixel-major, R,G,B, then level), each per-(cell,
    /// channel) curve summing to `mass`. Returns `p·3·mass` displacements. Restores
    /// the V2.1 time axis: an anchor curve + this map reconstructs a frame's curve
    /// (`pushforwardV21`). Returns nil on a shape/mass violation.
    static func transportV21(src: [Int32], dst: [Int32], p: Int, nLevels: Int, mass: Int) -> [Int32]? {
        guard p > 0, nLevels > 0, mass > 0,
              src.count == p * 3 * nLevels, dst.count == p * 3 * nLevels else { return nil }
        var out = [Int32](repeating: 0, count: p * 3 * mass)
        let rc = src.withUnsafeBufferPointer { s in
            dst.withUnsafeBufferPointer { d in
                out.withUnsafeMutableBufferPointer { o in
                    s4_v21_transport(s.baseAddress, d.baseAddress, Int32(p), Int32(nLevels),
                                     Int32(mass), o.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_transport rc=\(rc)"); return nil }
        return out
    }

    /// Apply a per-rank displacement to a source curve and re-bin (`s4_v21_pushforward`),
    /// reproducing the transported curve. `src` is `p·3·nLevels` counts (each curve
    /// summing to `mass`); `disp` is `p·3·mass` rank displacements. Returns
    /// `p·3·nLevels` counts. With `disp = transportV21(src, dst)` yields `dst`
    /// byte-exact; with the negated displacement it inverts back to `src`. Returns nil
    /// on a shape/mass violation or a landing level outside `0..<nLevels`.
    static func pushforwardV21(src: [Int32], disp: [Int32], p: Int, nLevels: Int, mass: Int) -> [Int32]? {
        guard p > 0, nLevels > 0, mass > 0,
              src.count == p * 3 * nLevels, disp.count == p * 3 * mass else { return nil }
        var out = [Int32](repeating: 0, count: p * 3 * nLevels)
        let rc = src.withUnsafeBufferPointer { s in
            disp.withUnsafeBufferPointer { d in
                out.withUnsafeMutableBufferPointer { o in
                    s4_v21_pushforward(s.baseAddress, d.baseAddress, Int32(p), Int32(nLevels),
                                       Int32(mass), o.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_pushforward rc=\(rc)"); return nil }
        return out
    }

    /// Histogram accumulation (`s4_v21_accumulate_hist`): box-decimate a FINE grid
    /// into coarse voxels and, per voxel per channel, count fine samples at each
    /// value level. `fine` is `ft·fy·fx·3` u8, layout `(((ft·fy + y)·fx + x)·3 +
    /// ch)`. Returns the zeroed-and-filled counts `ct·cy·cx·3·nLevels`, layout
    /// `((coarseVoxel·3 + ch)·nLevels + value)` where `ct = ft/dt`, `cy = fy/dy`,
    /// `cx = fx/dx`. Dimensions must be divisible by the decimation factors; the
    /// kernel refuses a value >= nLevels.
    static func accumulateHistV21(fine: [UInt8], fx: Int, fy: Int, ft: Int,
                                  dx: Int, dy: Int, dt: Int, nLevels: Int) -> [Int32]? {
        guard fx > 0, fy > 0, ft > 0, dx > 0, dy > 0, dt > 0, nLevels > 0,
              fx % dx == 0, fy % dy == 0, ft % dt == 0,
              fine.count == ft * fy * fx * 3 else { return nil }
        let count = (ft / dt) * (fy / dy) * (fx / dx) * 3 * nLevels
        var out = [Int32](repeating: 0, count: count)
        let rc = fine.withUnsafeBufferPointer { f in
            out.withUnsafeMutableBufferPointer { o in
                s4_v21_accumulate_hist(f.baseAddress, Int32(fx), Int32(fy), Int32(ft),
                                       Int32(dx), Int32(dy), Int32(dt), Int32(nLevels),
                                       o.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_accumulate_hist rc=\(rc)"); return nil }
        return out
    }

    /// Ground-state centering (`s4_v21_centered_energy`): subtract each curve's
    /// minimum, so the GIF byte (argmin) sits at energy 0. `curves` is `p·3·nLevels`
    /// Q16 energies; returns `p·3·nLevels` centered energies. The kernel refuses on
    /// i32-envelope overflow.
    static func centeredEnergyV21(curves: [Int32], p: Int, nLevels: Int) -> [Int32]? {
        guard p > 0, nLevels > 0, curves.count == p * 3 * nLevels else { return nil }
        var out = [Int32](repeating: 0, count: p * 3 * nLevels)
        let rc = curves.withUnsafeBufferPointer { c in
            out.withUnsafeMutableBufferPointer { o in
                s4_v21_centered_energy(c.baseAddress, Int32(p), Int32(nLevels), o.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_centered_energy rc=\(rc)"); return nil }
        return out
    }

    /// The mode-relative ENCODER INPUT (`s4_v21_mode_relative`): each curve centered
    /// and reindexed about its own mode, so the argmin is pinned to relative-0 and the
    /// absolute mode is WITHHELD (the GIF supplies it via `anchorAtV21`). `curves` is
    /// `p·3·nLevels`; returns `p·3·nLevels`. The kernel refuses on i32-envelope overflow.
    static func modeRelativeV21(curves: [Int32], p: Int, nLevels: Int) -> [Int32]? {
        guard p > 0, nLevels > 0, curves.count == p * 3 * nLevels else { return nil }
        var out = [Int32](repeating: 0, count: p * 3 * nLevels)
        let rc = curves.withUnsafeBufferPointer { c in
            out.withUnsafeMutableBufferPointer { o in
                s4_v21_mode_relative(c.baseAddress, Int32(p), Int32(nLevels), o.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_mode_relative rc=\(rc)"); return nil }
        return out
    }

    /// Anchor (`s4_v21_anchor_at`), the left inverse of `modeRelativeV21` given the GIF
    /// byte: `out[l] = rel[(l - mode) mod n]`, so `anchorAtV21` of `modeRelativeV21(e)` at
    /// the curve's modes reproduces the centered curve (field + GIF reconstruct the field).
    /// `rel` is `p·3·nLevels`; `modes` is `p·3` (the per-curve GIF level, e.g. from
    /// `collapseV21`). Returns `p·3·nLevels`.
    static func anchorAtV21(rel: [Int32], modes: [Int32], p: Int, nLevels: Int) -> [Int32]? {
        guard p > 0, nLevels > 0, rel.count == p * 3 * nLevels, modes.count == p * 3 else { return nil }
        var out = [Int32](repeating: 0, count: p * 3 * nLevels)
        let rc = rel.withUnsafeBufferPointer { r in
            modes.withUnsafeBufferPointer { m in
                out.withUnsafeMutableBufferPointer { o in
                    s4_v21_anchor_at(r.baseAddress, m.baseAddress, Int32(p), Int32(nLevels), o.baseAddress)
                }
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_v21_anchor_at rc=\(rc)"); return nil }
        return out
    }
}
