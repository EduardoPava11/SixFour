import Foundation

/// THE MULTISCALE ENCODE BRIDGE (Feature.multiScaleRender) — turns one 64³ burst into an
/// adaptively multiscale 64³ GIF by feeding the halt-floor depth field through the byte-exact
/// select render (`MultiScaleLadder.fuse` → `s4_render_select`), then reassembling the fused cube
/// back into `[OKLabTile]` for the SAME five `DeterministicRenderer` kernels. Motion regions stay
/// 64³ (fine), static regions collapse to block-replicated 16³ (chunky) — detail where the scene
/// earns it (`SixFour.Spec.HaltDepth` / `HaltDepthBridge`).
///
/// DERIVED-CAPTURE default: the three scale volumes are POOLED from the single 64³ burst (2×2×2
/// spacetime mean), not independent exposures — a byte-valid render that `MultiScaleCapture` flags
/// as failing cross-scale independence (H(coarse|fine)=0). The EV-bracketed independent capture
/// (`MultiScaleLadder.schedule`/`applyExposure`, `Feature.multiScaleLadder`) is the device-only upgrade.
///
/// SAFETY (the all-fine == current-renderer invariant): the fine volume V64 is the tile channels
/// BIT-CAST to Int32 (`Float.bitPattern`); `s4_render_select` is a pure per-region COPY, so a
/// depth-2 region round-trips its value bit-for-bit. Therefore an all-depth-2 field reproduces the
/// input tiles EXACTLY (`MultiScaleRenderTests`) — the multiscale analog of zero-gene==floor.
enum MultiScaleRender {

    /// Fuse the burst tiles to the multiscale cube for a given per-region `depthField` (region-major
    /// `16³`, one depth 0/1/2 per 4×4×4 region — from `HaltDepthBridge`). Returns nil (caller falls
    /// back to the uniform 64³ tiles) unless the shapes are the shipped 64³ geometry.
    static func fusedTiles(from tiles: [OKLabTile], depthField: [Int32]) -> [OKLabTile]? {
        let side = 64, frames = 64, perFrame = side * side
        guard tiles.count == frames,
              tiles.allSatisfy({ $0.side == side && $0.pixels.count == perFrame }),
              depthField.count == 16 * 16 * 16
        else { return nil }

        // Per channel (L,a,b): fine volume = tiles' channel bit-cast to Int32 (lossless); coarse
        // volumes = 2×2×2-pooled floats bit-cast; fuse by the depth field.
        var fused: [[Int32]] = []
        fused.reserveCapacity(3)
        for c in 0 ..< 3 {
            let v64f = channelVolume(tiles: tiles, channel: c)           // 64³ Float, t-y-x
            let v32f = poolHalf(v64f, side: 64, frames: 64)             // 32³
            let v16f = poolHalf(v32f, side: 32, frames: 32)             // 16³
            guard let f = MultiScaleLadder.fuse(depth: depthField,
                                                v16: bitcast(v16f), v32: bitcast(v32f),
                                                v64: bitcast(v64f), side: side)
            else { return nil }
            fused.append(f)
        }

        // Reassemble the fused cube into per-frame OKLab tiles (decode the bit-cast back to Float).
        var out: [OKLabTile] = []
        out.reserveCapacity(frames)
        for t in 0 ..< frames {
            var px = [SIMD3<Float>](repeating: .zero, count: perFrame)
            let base = t * perFrame
            for i in 0 ..< perFrame {
                px[i] = SIMD3<Float>(unbit(fused[0][base + i]),
                                     unbit(fused[1][base + i]),
                                     unbit(fused[2][base + i]))
            }
            out.append(OKLabTile(side: side, pixels: px, captureNanos: tiles[t].captureNanos,
                                 palette: [], finalShift: 0))
        }
        return out
    }

    // MARK: - internals

    /// One channel's 64³ volume from the tiles, t-major then y then x (matching `s4_render_select`).
    private static func channelVolume(tiles: [OKLabTile], channel c: Int) -> [Float] {
        let perFrame = 64 * 64
        var v = [Float](repeating: 0, count: 64 * perFrame)
        for t in 0 ..< 64 {
            let px = tiles[t].pixels
            let base = t * perFrame
            for i in 0 ..< perFrame { v[base + i] = px[i][c] }
        }
        return v
    }

    /// 2×2×2 spacetime mean pool: (frames × side × side) → (frames/2 × side/2 × side/2), t-y-x.
    private static func poolHalf(_ v: [Float], side: Int, frames: Int) -> [Float] {
        let hs = side / 2, hf = frames / 2
        var out = [Float](repeating: 0, count: hf * hs * hs)
        for t in 0 ..< hf {
            for y in 0 ..< hs {
                for x in 0 ..< hs {
                    var s: Float = 0
                    for dt in 0 ..< 2 {
                        let tt = 2 * t + dt
                        for dy in 0 ..< 2 {
                            let yy = 2 * y + dy
                            for dx in 0 ..< 2 {
                                s += v[(tt * side + yy) * side + (2 * x + dx)]
                            }
                        }
                    }
                    out[(t * hs + y) * hs + x] = s / 8
                }
            }
        }
        return out
    }

    /// Lossless Float→Int32 (bit pattern) so the select render is an exact per-region copy.
    private static func bitcast(_ v: [Float]) -> [Int32] { v.map { Int32(bitPattern: $0.bitPattern) } }
    /// Inverse of `bitcast` for one value.
    private static func unbit(_ i: Int32) -> Float { Float(bitPattern: UInt32(bitPattern: i)) }
}
