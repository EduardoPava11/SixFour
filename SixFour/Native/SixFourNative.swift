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

    // MARK: - Color Atlas board (deterministic Q16 mass)

    /// Deterministic Q16 board-mass channel for a list of Q16 OKLab colours
    /// (`s4_board_mass_q16`, the owned port of `SixFour.Spec.BoardQ16.boardMassQ16`):
    /// integer floor-div binning → integer counts → ONE round-half-up of
    /// `count·2¹⁶/total` per bin. Returns the 16³ = 4096 Q16 channel (each ∈ [0, 65536]).
    /// Byte-exact across Haskell/Zig/Swift — closes the float-histogram determinism hole
    /// at the policy/value board input (replaces the non-dyadic `1/total` normalise).
    static func boardMassQ16(colorsQ16 colors: [SIMD3<Int32>]) -> [Int32]? {
        let n = colors.count
        var flat = [Int32](); flat.reserveCapacity(n * 3)
        for c in colors { flat.append(c.x); flat.append(c.y); flat.append(c.z) }
        var mass = [Int32](repeating: 0, count: AtlasBoard16.binCount)
        let rc = flat.withUnsafeBufferPointer { fp in
            mass.withUnsafeMutableBufferPointer { mp in
                s4_board_mass_q16(fp.baseAddress, Int32(n), mp.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_board_mass_q16 rc=\(rc)"); return nil }
        return mass
    }

    /// Q16 mass from precomputed integer per-bin counts (`s4_board_counts_to_mass_q16`,
    /// `SixFour.Spec.BoardQ16.massQ16`): for the pixel channel whose counts come from a
    /// per-frame slot→bin table (integer, so already order-independent). `counts.count`
    /// is the channel length (16³ = 4096); `total` is the exact element count.
    static func boardMassQ16(counts: [Int32], total: Int) -> [Int32]? {
        let bins = counts.count
        var mass = [Int32](repeating: 0, count: bins)
        let rc = counts.withUnsafeBufferPointer { cp in
            mass.withUnsafeMutableBufferPointer { mp in
                s4_board_counts_to_mass_q16(cp.baseAddress, Int32(bins), Int32(total), mp.baseAddress)
            }
        }
        guard rc == S4_RC_OK else { log.error("s4_board_counts_to_mass_q16 rc=\(rc)"); return nil }
        return mass
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
        let floats = srgb.map { c -> SIMD3<Float> in
            let lab = ColorScience.srgb8ToOKLab(c.x, c.y, c.z)
            return SIMD3<Float>(lab.L, lab.a, lab.b)
        }
        let q16 = oklabToQ16(floats)
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
}
