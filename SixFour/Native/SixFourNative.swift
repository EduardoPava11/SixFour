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

    // MARK: - Look-NN deploy blob

    /// The look-NN genome, loaded from the MLX-trained deploy blob produced by
    /// `trainer/export_look_net_blob.py`. Mirrors `S4LookNetWeights` in
    /// `Native/include/sixfour_native.h`. The float pointers ALIAS into the
    /// `blob` `Data` passed to `loadLookNet`, so the blob must outlive any use
    /// of these buffers (no copy, no allocation crosses the FFI boundary).
    /// Weights are RAW (pre-σ-mask); the forward pass applies the
    /// σ-block-diagonal mask exactly as the Haskell spec / MLX port do.
    struct LookNetWeights {
        let phi: UnsafePointer<Float>       // (64, 10)
        let w1: UnsafePointer<Float>        // (64, 64)
        let w2: UnsafePointer<Float>        // (64, 64)
        let haltW: UnsafePointer<Float>     // (1, 2)
        let haltB: UnsafePointer<Float>     // (1,)
        let heads: [UnsafePointer<Float>]   // 8 × (head_dim, 64)
        let headDims: [Int32]               // {3,3,6,12,24,48,96,192}
    }

    /// Parse a look-NN deploy blob via the Zig `s4_load_look_net` ABI. Returns
    /// `nil` on a malformed blob (bad magic / version / truncation). The
    /// returned pointers alias into `blob`; keep `blob` alive while using them.
    ///
    /// NOTE: the underlying Zig kernel is a declared contract (header + this
    /// seam); the real parse may land beyond the `s4_probe` spike. This Swift
    /// surface pins the type/signature so the consumer compiles against it.
    static func loadLookNet(_ blob: Data) -> LookNetWeights? {
        blob.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> LookNetWeights? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            var out = S4LookNetWeights()
            let rc = s4_load_look_net(base, raw.count, &out)
            guard rc == 0 else {
                log.error("s4_load_look_net failed: rc=\(rc)")
                return nil
            }
            let headCount = Int(S4_LOOK_NET_HEAD_COUNT)
            let heads: [UnsafePointer<Float>] = withUnsafePointer(to: out.heads) { tuplePtr in
                tuplePtr.withMemoryRebound(to: UnsafePointer<Float>?.self, capacity: headCount) { p in
                    (0..<headCount).map { p[$0]! }
                }
            }
            let headDims: [Int32] = withUnsafePointer(to: out.head_dims) { tuplePtr in
                tuplePtr.withMemoryRebound(to: Int32.self, capacity: headCount) { p in
                    Array(UnsafeBufferPointer(start: p, count: headCount))
                }
            }
            return LookNetWeights(
                phi: out.phi, w1: out.w1, w2: out.w2,
                haltW: out.halt_w, haltB: out.halt_b,
                heads: heads, headDims: headDims
            )
        }
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
    /// NOTE: the underlying `s4_gif_encode_burst` kernel is a declared contract
    /// (header + this seam); its body lands across the spec-first rollout
    /// stages. Until then it returns `S4_RC_NOT_IMPLEMENTED` and this returns
    /// `nil` — the seam exists so the renderer can compile against it.
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
}
