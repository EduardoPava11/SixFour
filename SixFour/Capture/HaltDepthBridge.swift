import Foundation

/// THE HALT→DEPTH BRIDGE (device side) — byte-exact mirror of `SixFour.Spec.HaltDepth`.
///
/// Turns the per-slot certified kinematic order the color head already computes
/// (`ColorHead.haltFloor()` → `s4_certified_order`, 256 Int32 = the 16×16 spatial region face,
/// −1 = uncertified) into the per-region DEPTH field `s4_render_select` consumes (one depth
/// 0/1/2 per 4×4×4 region, region-major over the (side/4)³ grid). Motion earns spatial fineness,
/// stillness keeps color-time — `order ≤ 1 → 16³`, `= 2 → 32³`, `≥ 3 → 64³`.
///
/// Pure integer, no float, no allocation beyond the field. The mapping is pinned to the spec by
/// `HaltDepthBridgeTests` (the same thresholds `SixFour.Spec.HaltDepth.lawHaltDepthThresholds`
/// proves), so the Swift render path and the Haskell law can never drift.
enum HaltDepthBridge {

    /// `haltDepth`: certified order → render depth {0,1,2}. Uncertified (order < 0) → 0 (coarsest:
    /// never invent detail you cannot certify). Mirrors `Spec.HaltDepth.haltDepth` exactly.
    @inline(__always)
    static func depth(order: Int32) -> Int32 {
        if order <= 1 { return 0 }   // static / constant-velocity / uncertified
        if order == 2 { return 1 }   // acceleration
        return 2                     // order ≥ 3
    }

    /// The 16×16 spatial depth FACE: one depth per halt slot (row-major, same order as
    /// `ColorHead.haltFloor()`).
    static func depthFace(fromHaltOrders orders: [Int32]) -> [Int32] {
        orders.map(depth(order:))
    }

    /// The region-major `(gridSide)³` depth FIELD `s4_render_select` reads: the 16×16 spatial face
    /// broadcast across the temporal region axis (the halt order is spatial-only, so every
    /// temporal region slice shows the same per-(x,y) depth). `gridSide = side/4` (16 at the 64³
    /// device scale); requires `orders.count == gridSide²`.
    static func depthField(fromHaltOrders orders: [Int32], gridSide: Int) -> [Int32] {
        let face = gridSide * gridSide
        precondition(orders.count == face, "haltOrders must be gridSide² (\(face)), got \(orders.count)")
        let faceDepths = depthFace(fromHaltOrders: orders)
        var field = [Int32](repeating: 0, count: face * gridSide)
        for tr in 0 ..< gridSide {
            let base = tr * face
            for i in 0 ..< face { field[base + i] = faceDepths[i] }
        }
        return field
    }

    /// User/halt co-drive: FINEST-WINS max, clamped to {0,1,2} — mirrors `Spec.HaltDepth.mergeDepth`
    /// (the CubeBrush semilattice). The brush can only refine the halt allocation, never coarsen it.
    @inline(__always)
    static func merge(_ a: Int32, _ b: Int32) -> Int32 {
        max(clamp(a), clamp(b))
    }

    @inline(__always)
    private static func clamp(_ d: Int32) -> Int32 { max(0, min(2, d)) }
}
