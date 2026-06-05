// CellAlgebra.swift — the on-device port of the base/fiber cell algebra.
//
// Source of truth: spec/src/SixFour/Spec/CellFiber.hs + CellGrid.hs.
// Verified byte-for-byte against Generated/CellContract.swift (see
// SixFourTests/CellAlgebraTests.swift). NO BLEND: render never synthesises a
// colour. A clean cell shows its claim; a contested cell (>=2 claims) shows the
// reserved `contestedSentinel`; an empty cell shows `neutralColor`. Overlap is
// detected and made visible — never averaged, never an error.
//
// Dependency-free (Tier-2 CLAUDE.md): imports only `simd`.

import simd

/// One OKLab colour in Q16 fixed point: (L, a, b), each `value · 2^16`.
public typealias SFColor = SIMD3<Int32>

/// A cell: the set of colours claimed at one place, held as a canonical
/// ascending-sorted, duplicate-free array (mirrors Haskell `Data.Set`, whose
/// `toAscList` is the arrival-free fold order). The bounded join-semilattice
/// carrier of the WHAT axis.
public struct SFCell: Equatable {
    /// Unique claims in ascending (L, a, b) lexicographic order — the canonical
    /// order `shimmer(at:)` indexes. This is `Spec.CellFiber.claims`.
    public private(set) var claims: [SFColor]

    /// ⊥ — the empty claim. `render()` ⊥ = `CellContract.neutralColor`.
    public init() { self.claims = [] }

    /// Build a cell from raw claims: dedup + ascending sort (the `Data.Set`
    /// normal form), so the carrier is a true set and the fold order is canonical.
    public init(_ rawClaims: [SFColor]) {
        let sorted = rawClaims.sorted(by: SFCell.ascending)
        var out: [SFColor] = []
        out.reserveCapacity(sorted.count)
        for c in sorted where out.last != c { out.append(c) }
        self.claims = out
    }

    /// The join ⊕ = set union (idempotent, commutative, associative).
    public func join(_ other: SFCell) -> SFCell {
        SFCell(self.claims + other.claims)
    }

    /// Did two+ widgets claim this place? The total, exact "I want to know"
    /// predicate — never throws, never blends. `Spec.CellFiber.isContested`.
    public var isContested: Bool { claims.count > 1 }

    /// Observable colour — NO BLEND. ⊥ → neutral; singleton → that exact claim;
    /// ≥2 → the loud `contestedSentinel`. `render` never invents a colour
    /// (`Spec.CellFiber.lawNoSynthesis`).
    public func render() -> SFColor {
        switch claims.count {
        case 0:  return CellContract.neutralColor
        case 1:  return claims[0]
        default: return CellContract.contestedSentinel
        }
    }

    /// The opt-in OVERLAP EFFECT: time-multiplex the claimants on the 20fps clock
    /// — show claimant `tick mod n`. Always a REAL claimant, never a mixture
    /// (`Spec.CellFiber.lawShimmerIsClaimant`). Tick is normalised so negative
    /// ticks index correctly (matching Haskell `mod` for a positive divisor).
    public func shimmer(at tick: Int) -> SFColor {
        let n = claims.count
        if n == 0 { return CellContract.neutralColor }
        let i = ((tick % n) + n) % n
        return claims[i]
    }

    /// Lexicographic ascending order on (L, a, b) — the `Data.Set` order.
    static func ascending(_ a: SFColor, _ b: SFColor) -> Bool {
        if a.x != b.x { return a.x < b.x }
        if a.y != b.y { return a.y < b.y }
        return a.z < b.z
    }
}

/// The option-c observer (the WHERE axis, `Spec.CellGrid.renderGridAt`): at clock
/// tick `t`, a contested cell inside a flagged effect-zone SHIMMERS its claimants
/// (the cool effect); a contested cell OUTSIDE an effect-zone shows the loud
/// `contestedSentinel` (a layout bug you must see); a clean cell renders verbatim.
/// NO blend on any path (`Spec.CellGrid.lawNoSilentMerge`).
public func renderCell(_ cell: SFCell, tick: Int, inEffectZone: Bool) -> SFColor {
    if cell.isContested {
        return inEffectZone ? cell.shimmer(at: tick) : CellContract.contestedSentinel
    }
    return cell.render()
}
