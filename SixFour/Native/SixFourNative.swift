import Foundation
import os

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
}
