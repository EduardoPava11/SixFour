import Foundation

/// The cross-view BRUSH CONTRACT: given a brushed palette index and the radix
/// genome, which palette indices highlight TOGETHER. One definition shared by every
/// view (cube, grid, cloud, tree, picker) so a single `brushedIndex` lights the same
/// colours everywhere — the Step-5 unification.
///
/// - 16² (`.b16`) → just the index (Flat: each colour is independent).
/// - 4⁴ (`.b4`)  → the four opponent-quadrant siblings sharing the index's deepest
///   Quad4 parent (`k & ~3 … +3`) — brushing a colour lights its quad.
/// - 2⁸ (`.b2`)  → the σ-pair `{k, k^1}` — a colour and its σ-mirror `(L,−a,−b)`.
///
/// The primary index is always a member.
enum BrushSet {
    static func indices(_ k: Int, branching: PaletteBranching) -> [Int] {
        guard k >= 0 else { return [] }
        switch branching {
        case .b16: return [k]
        case .b4:  let base = k & ~3; return [base, base + 1, base + 2, base + 3]
        case .b2:  return [k, k ^ 1]
        }
    }

    /// The cube's integer brush MODE — MUST match the `voxel_raymarch` kernel:
    /// 0 = single (16²), 1 = quad (4⁴), 2 = σ-pair (2⁸).
    static func mode(_ branching: PaletteBranching) -> Int32 {
        switch branching {
        case .b16: return 0
        case .b4:  return 1
        case .b2:  return 2
        }
    }

    /// Mirror of the kernel's per-voxel brush predicate (gated against `indices`):
    /// does palette index `k` highlight, given the brushed index and the cube mode?
    static func kernelHit(_ k: Int, brushedIndex bk: Int, mode: Int32) -> Bool {
        if bk < 0 { return false }
        if k == bk { return true }
        switch mode {
        case 2:  return k == (bk ^ 1)            // σ-pair
        case 1:  return (k & ~3) == (bk & ~3)    // quad
        default: return false                    // single
        }
    }
}
