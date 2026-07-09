//  WangTiling.swift
//  THE SCROLL's substrate — hand-written Swift twin of `Spec.WangTiling`.
//
//  The authority is the Haskell spec (Tier 0): the Jeandel–Rao 11-tile aperiodic
//  Wang set (arXiv:1506.06492 Fig 3 = Labbé T0) served by Labbé's toral coding
//  (arXiv:1903.06137) as a RANDOM-ACCESS oracle `tileIndexAt(m,n)` — O(1), no
//  search, context-free, so any tube slice materializes independently. The 11
//  tiles are read as the 11 landed S/K/I ops (the tiling IS the state machine);
//  a θ_up-shaped gene derives an 11-op ATTENTION row that modulates expression
//  but never the schedule; the boot-resolve ladder crystallizes 16²→32²→64² at
//  ticks 4/8/16.
//
//  ARITHMETIC CONTRACT: everything is EXACT — ℚ(φ) numbers `a + b·φ`
//  (φ² = φ + 1) with rational coefficients over `Int128`; sign and floor are
//  pure integer decisions (sign of U + V√5 via U² vs 5V², floor via integer
//  square root + one exact sign correction). NO floats anywhere, matching the
//  spec's `QPhi` word for word, so the emitted tiling is cross-device bit-exact.
//  `Int128` headroom: cell coordinates are safe far beyond ±10¹⁵ (the squares
//  compared stay below 2¹²⁷); the golden-parity tests pin ±10⁹ windows.
//
//  GOLDEN PARITY (the CaptureRecordTests literal pattern): WangTilingTests
//  carries copied literals from the spec — `goldenWindow8`
//  (lawGoldenWindowPinned), two ±10⁹ far windows, the tile→op table
//  (lawOpAssignmentPinned), four slice-op sequences, two attention rows
//  (exact rationals), and the 4/8/16 reveal ladder. Any drift between this twin
//  and `Spec.WangTiling` is a failed test, never a debugging session.
//
//  UI-independent by design (no UIKit/SwiftUI import): the Tube layer feeds
//  scenes but never draws.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Exact ℚ(φ) arithmetic (twin of Spec.WangTiling.QPhi — no floats)
// ─────────────────────────────────────────────────────────────────────────────

/// A reduced rational over `Int128` (`den > 0`, `gcd(num, den) == 1`).
/// Internal carrier of the oracle only — never crosses the Tube API.
struct S4Frac128: Equatable, Sendable {
    let num: Int128
    let den: Int128

    init(_ n: Int128, _ d: Int128) {
        precondition(d != 0, "S4Frac128: zero denominator")
        let s: Int128 = d < 0 ? -1 : 1
        let g = S4Frac128.gcd(n.magnitude, d.magnitude)
        if g == 0 {
            num = 0
            den = 1
        } else {
            num = s * n / Int128(g)
            den = s * d / Int128(g)
        }
    }

    static func gcd(_ a: UInt128, _ b: UInt128) -> UInt128 {
        var x = a
        var y = b
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    static func + (a: S4Frac128, b: S4Frac128) -> S4Frac128 {
        S4Frac128(a.num * b.den + b.num * a.den, a.den * b.den)
    }
    static func - (a: S4Frac128, b: S4Frac128) -> S4Frac128 {
        S4Frac128(a.num * b.den - b.num * a.den, a.den * b.den)
    }
    static func * (a: S4Frac128, b: S4Frac128) -> S4Frac128 {
        S4Frac128(a.num * b.num, a.den * b.den)
    }
}

/// A number `a + b·φ` with exact rational coefficients, φ = (1+√5)/2, φ² = φ+1.
/// Twin of the spec's `QPhi` — the ONLY numeric carrier of the toral oracle.
struct S4QPhi: Equatable, Sendable {
    let a: S4Frac128
    let b: S4Frac128

    init(_ a: S4Frac128, _ b: S4Frac128) {
        self.a = a
        self.b = b
    }

    /// Integer QPhi `ia + ib·φ` (spec `QPhi (fromInteger ia) (fromInteger ib)`).
    init(_ ia: Int, _ ib: Int) {
        self.a = S4Frac128(Int128(ia), 1)
        self.b = S4Frac128(Int128(ib), 1)
    }

    /// Rational QPhi `(an/ad) + (bn/bd)·φ`.
    init(_ an: Int, _ ad: Int, _ bn: Int, _ bd: Int) {
        self.a = S4Frac128(Int128(an), Int128(ad))
        self.b = S4Frac128(Int128(bn), Int128(bd))
    }

    static let phi = S4QPhi(0, 1)

    static func fromInt(_ n: Int) -> S4QPhi { S4QPhi(n, 0) }

    static func + (x: S4QPhi, y: S4QPhi) -> S4QPhi { S4QPhi(x.a + y.a, x.b + y.b) }
    static func - (x: S4QPhi, y: S4QPhi) -> S4QPhi { S4QPhi(x.a - y.a, x.b - y.b) }

    /// Exact multiplication through φ² = φ + 1:
    /// `(a+bφ)(c+dφ) = ac+bd + (ad+bc+bd)φ` (spec `qMul`).
    static func * (x: S4QPhi, y: S4QPhi) -> S4QPhi {
        S4QPhi(x.a * y.a + x.b * y.b, x.a * y.b + x.b * y.a + x.b * y.b)
    }

    /// Sign of `U + V·√5` for integers U, V — pure integer case analysis
    /// (U² vs 5V²; equality impossible unless both vanish, √5 irrational).
    /// Twin of spec `signRoot5`.
    static func signRoot5(_ u: Int128, _ v: Int128) -> Int {
        if u == 0 && v == 0 { return 0 }
        if v == 0 { return u > 0 ? 1 : -1 }
        if u == 0 { return v > 0 ? 1 : -1 }
        if u > 0 && v > 0 { return 1 }
        if u < 0 && v < 0 { return -1 }
        if u > 0 { return u * u > 5 * v * v ? 1 : -1 } // v < 0
        return 5 * v * v > u * u ? 1 : -1 // u < 0, v > 0
    }

    /// Common-denominator integer view: `a + bφ = (A + Bφ)/d`, `d > 0`
    /// (spec `integerView`).
    var integerView: (A: Int128, B: Int128, d: Int128) {
        let g = S4Frac128.gcd(a.den.magnitude, b.den.magnitude)
        let d = a.den / Int128(g) * b.den // lcm, exact
        return (a.num * (d / a.den), b.num * (d / b.den), d)
    }

    /// Exact sign (−1, 0, +1): `a + bφ = (2A + B + B√5)/(2d)` (spec `signQPhi`).
    var signum: Int {
        let (bigA, bigB, _) = integerView
        return S4QPhi.signRoot5(2 * bigA + bigB, bigB)
    }

    /// Integer square root (Newton, exact, total on non-negatives) — spec `isqrtI`.
    static func isqrt(_ n: Int128) -> Int128 {
        if n < 2 { return max(n, 0) }
        var x = n
        while true {
            let y = (x + n / x) / 2
            if y >= x { return x }
            x = y
        }
    }

    /// Exact floor: bracket `V√5` by `isqrt`, then correct the candidate by ONE
    /// exact `signRoot5` test — the guess is off by at most one and the final
    /// decision is a theorem, not an approximation (spec `floorQPhi`).
    var floor: Int {
        let (bigA, bigB, d) = integerView
        let p = 2 * bigA + bigB
        let v = bigB
        let w = 2 * d
        let s: Int128 = v >= 0 ? S4QPhi.isqrt(5 * v * v) : -S4QPhi.isqrt(5 * v * v) - 1
        var n0 = (p + s) / w
        // Swift `/` truncates toward zero; the spec's `div` floors. Correct.
        if (p + s) % w != 0 && ((p + s) < 0) != (w < 0) { n0 -= 1 }
        if S4QPhi.signRoot5(p - (n0 + 1) * w, v) >= 0 { n0 += 1 }
        return Int(n0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The tiling, the state machine, the gene mapping, the boot resolve
// ─────────────────────────────────────────────────────────────────────────────

/// Namespace for the tiling twin. All functions are pure and deterministic;
/// all tables are pinned copies of `Spec.WangTiling`'s (golden-gated).
enum S4WangTiling {

    // ── The Jeandel–Rao tile set T (arXiv:1506.06492 Fig 3 = Labbé T0) ───────

    /// A Wang tile `(w,e,s,n)` — west/east are the 4 HORIZONTAL carrier colors
    /// (FSM states), south/north the 5 VERTICAL grade letters. Separate
    /// alphabets, exactly as the paper's §2.1.
    struct Tile: Equatable, Sendable {
        let w: Int  // carrier consumed (west)
        let e: Int  // carrier produced (east)
        let s: Int  // grade read (south)
        let n: Int  // grade written (north)
    }

    /// The 11 tiles t0..t10 in Labbé's order — copied literal of spec `jrTiles`.
    static let tiles: [Tile] = [
        Tile(w: 2, e: 2, s: 1, n: 4),  // t0
        Tile(w: 2, e: 2, s: 0, n: 2),  // t1
        Tile(w: 3, e: 1, s: 1, n: 1),  // t2
        Tile(w: 3, e: 1, s: 2, n: 2),  // t3
        Tile(w: 3, e: 3, s: 3, n: 1),  // t4
        Tile(w: 3, e: 0, s: 1, n: 1),  // t5
        Tile(w: 0, e: 0, s: 1, n: 0),  // t6
        Tile(w: 0, e: 3, s: 2, n: 1),  // t7
        Tile(w: 1, e: 0, s: 2, n: 2),  // t8
        Tile(w: 1, e: 1, s: 4, n: 2),  // t9
        Tile(w: 1, e: 3, s: 2, n: 3),  // t10
    ]

    /// Horizontal adjacency legality (spec `edgeMatchH`): `a` west of `b`.
    static func edgeMatchH(_ a: Tile, _ b: Tile) -> Bool { a.e == b.w }

    /// Vertical adjacency legality (spec `edgeMatchV`): `lo` south of `hi`.
    static func edgeMatchV(_ lo: Tile, _ hi: Tile) -> Bool { lo.n == hi.s }

    /// A rectangular window (rows south→north, each row west→east) is a valid
    /// Wang patch iff every adjacency matches (spec `windowValid`).
    static func windowValid(_ rows: [[Tile]]) -> Bool {
        for row in rows {
            for i in 0 ..< max(0, row.count - 1) where !edgeMatchH(row[i], row[i + 1]) {
                return false
            }
        }
        for j in 0 ..< max(0, rows.count - 1) {
            for (lo, hi) in zip(rows[j], rows[j + 1]) where !edgeMatchV(lo, hi) {
                return false
            }
        }
        return true
    }

    // ── The toral oracle (arXiv:1903.06137, exact ℤ[φ]) ──────────────────────

    // The x tick lattice: 0, φ⁻² = 2−φ, φ⁻¹ = φ−1, 1, φ (spec `xTicks`).
    private static let xTicks: [S4QPhi] = [
        S4QPhi(0, 0), S4QPhi(2, -1), S4QPhi(-1, 1), S4QPhi(1, 0), S4QPhi(0, 1),
    ]

    // The y rows A..F: 0, 1, 2, φ+1, φ+2, φ+3 (spec `yA..yF`), indexed 0..5.
    private static let yRows: [S4QPhi] = [
        S4QPhi(0, 0), S4QPhi(1, 0), S4QPhi(2, 0),
        S4QPhi(1, 1), S4QPhi(2, 1), S4QPhi(3, 1),
    ]

    // The 24 convex atoms (tile letter, CCW vertices as (yRow, xTick) indices) —
    // copied literal of spec `atoms` (transcribed from Labbé's slabbe v0.8.0
    // partition data; pairwise disjoint, total volume φ(φ+3) = 4φ+1).
    // Row letters: A=0 B=1 C=2 D=3 E=4 F=5.
    private static let atoms: [(letter: Int, verts: [(row: Int, tick: Int)])] = [
        (0, [(0, 0), (0, 2), (1, 2)]),
        (0, [(0, 2), (0, 3), (1, 3)]),
        (0, [(0, 3), (0, 4), (1, 4)]),
        (1, [(0, 0), (1, 2), (1, 0)]),
        (1, [(0, 2), (1, 3), (1, 2)]),
        (1, [(0, 3), (1, 4), (1, 3)]),
        (2, [(2, 0), (4, 2), (3, 0)]),
        (3, [(1, 3), (2, 4), (4, 4), (2, 3)]),
        (4, [(2, 0), (4, 3), (4, 2)]),
        (4, [(4, 2), (4, 3), (5, 3)]),
        (5, [(3, 0), (4, 2), (4, 0)]),
        (5, [(4, 0), (4, 1), (5, 1)]),
        (5, [(4, 1), (4, 2), (5, 3)]),
        (6, [(4, 0), (5, 1), (5, 0)]),
        (6, [(4, 1), (5, 3), (5, 1)]),
        (6, [(4, 3), (5, 4), (5, 3)]),
        (7, [(3, 3), (4, 4), (4, 3)]),
        (7, [(4, 3), (4, 4), (5, 4)]),
        (7, [(1, 0), (4, 3), (2, 0)]),
        (8, [(1, 2), (4, 4), (2, 2)]),
        (9, [(1, 0), (1, 2), (2, 2)]),
        (9, [(1, 2), (1, 3), (2, 3)]),
        (9, [(1, 3), (1, 4), (2, 4)]),
        (10, [(1, 0), (3, 3), (4, 3)]),
    ]

    // Atoms with resolved vertex coordinates (computed once, immutable).
    private static let atomPolys: [(letter: Int, poly: [(x: S4QPhi, y: S4QPhi)])] =
        atoms.map { atom in
            (atom.letter, atom.verts.map { (xTicks[$0.tick], yRows[$0.row]) })
        }

    /// The generic seed point p = (1/3, 1/5) ∈ ℚ(φ)² (spec `seedPoint`; its
    /// ℤ²-orbit provably never touches an atom boundary — denominator argument
    /// in the spec's module header). Changing it changes every golden.
    static let seedPoint: (x: S4QPhi, y: S4QPhi) =
        (S4QPhi(1, 3, 0, 1), S4QPhi(1, 5, 0, 1))

    /// Reduce a plane point into the fundamental domain `[0,φ) × [0,φ+3)` of
    /// ℝ²/Γ₀, Γ₀ = ⟨(φ,0), (1,φ+3)⟩ — two exact floors, no search (spec
    /// `reduceTorus`; the inverses live in ℚ(φ): 1/(φ+3) = (4−φ)/11, 1/φ = φ−1).
    static func reduceTorus(_ x: S4QPhi, _ y: S4QPhi) -> (x: S4QPhi, y: S4QPhi) {
        let k2 = (y * S4QPhi(4, 11, -1, 11)).floor
        let x1 = x - S4QPhi.fromInt(k2)
        let y1 = y - S4QPhi.fromInt(k2) * S4QPhi(3, 1)
        let k1 = (x1 * S4QPhi(-1, 1)).floor
        let x2 = x1 - S4QPhi.fromInt(k1) * S4QPhi.phi
        return (x2, y1)
    }

    // Strict interior of a CCW convex polygon: every edge cross-product positive
    // (spec `insideConvex`; strictness is safe — the generic orbit avoids
    // boundaries by theorem).
    private static func insideConvex(_ poly: [(x: S4QPhi, y: S4QPhi)],
                                     _ px: S4QPhi, _ py: S4QPhi) -> Bool {
        for i in 0 ..< poly.count {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            let cross = (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)
            if cross.signum <= 0 { return false }
        }
        return true
    }

    /// THE ORACLE, index form (spec `tileIndexAt`): the tile letter 0..10 at
    /// cell `(m,n)` — the atom of `seedPoint + (m,n)` reduced into the
    /// fundamental domain. O(1), context-free, total for the generic seed.
    static func tileIndexAt(_ m: Int, _ n: Int) -> Int {
        let p = reduceTorus(seedPoint.x + S4QPhi.fromInt(m),
                            seedPoint.y + S4QPhi.fromInt(n))
        for atom in atomPolys where insideConvex(atom.poly, p.x, p.y) {
            return atom.letter
        }
        preconditionFailure("S4WangTiling.tileIndexAt: boundary point (non-generic seed?)")
    }

    /// THE ORACLE (spec `tileAt`): edge-matching with all four neighbours is a
    /// theorem of the construction (arXiv:1903.06137 Prop 8.1).
    static func tileAt(_ m: Int, _ n: Int) -> Tile { tiles[tileIndexAt(m, n)] }

    /// A w×h window anchored at `(m0,n0)`: rows n0..n0+h−1 (south→north), each
    /// row m0..m0+w−1 (west→east) — spec `oracleWindow`.
    static func window(at anchor: (m: Int, n: Int), width: Int, height: Int) -> [[Tile]] {
        (0 ..< height).map { j in
            (0 ..< width).map { i in tileAt(anchor.m + i, anchor.n + j) }
        }
    }

    // ── The state machine: the 11 tiles = the 11 landed S/K/I ops ────────────

    /// An axis subset of the voxel x:y:t (the OctantViews Walsh–Hadamard band
    /// address; `Spec.OctantViews.axisSubsets` order governs).
    struct AxisSet: OptionSet, Hashable, Sendable {
        let rawValue: Int
        static let x = AxisSet(rawValue: 1)
        static let y = AxisSet(rawValue: 2)
        static let t = AxisSet(rawValue: 4)
    }

    /// One of the 11 landed ops (spec `TileOp`): the work-0 splitting `I`, a
    /// per-axis surjection `K_a` (kills the a-containing bands), or a section
    /// `S_A` over one band (zero-gene choice = the zero-detail floor — the gene
    /// lives only on S).
    enum TileOp: Equatable, Hashable, Sendable {
        case i
        case k(AxisSet)  // single axis
        case s(AxisSet)  // nonempty axis subset
    }

    /// The canonical op alphabet, graded 1+3+3+3+1 = 11 (spec `opsCanonical`;
    /// order PINNED — attention rows index into it).
    static let opsCanonical: [TileOp] = [
        .i,
        .k(.x), .k(.y), .k(.t),
        .s(.x), .s(.y), .s(.t),
        .s([.x, .y]), .s([.x, .t]), .s([.y, .t]),
        .s([.x, .y, .t]),
    ]

    /// The 7 detail bands in canonical order (spec `detailSubsets` =
    /// `drop 1 axisSubsets`): {x},{y},{t},{xy},{xt},{yt},{xyt}. θ_up's 21 words
    /// are these bands × 3 channels, band-major.
    static let detailBands: [AxisSet] = [
        .x, .y, .t, [.x, .y], [.x, .t], [.y, .t], [.x, .y, .t],
    ]

    /// The tile→op DECISION OF RECORD as indices into `opsCanonical` — copied
    /// literal of the spec table (lawOpAssignmentPinned): every grade-raising
    /// tile carries an S, K only on grade-lowering tiles, I on t7 (the most
    /// frequent tile — the packet-economy floor).
    static let opIndexOfTile: [Int] = [10, 7, 9, 4, 1, 5, 2, 0, 6, 3, 8]

    /// The op tile `i` fires (spec `opOfIndex`).
    static func opOfIndex(_ i: Int) -> TileOp { opsCanonical[opIndexOfTile[i]] }

    // ── The tube schedule: slices of 4 (the pour group) ───────────────────────

    /// Rows per tube slice = `framesPerRealize W16` = 4 — THE POUR group (four
    /// fine frames = one coarse frame), never a free constant (spec `sliceRows`).
    static let sliceRows = 4

    /// Columns per slice = `sideOf W16` = 16 — the coarse palette-basis width
    /// (spec `sliceWidth`).
    static let sliceWidth = 16

    /// Slice `s` of the tube: the 4-row window at rows 4s..4s+3, addressable
    /// independently (spec `sliceWindow` — random access is the whole point).
    static func sliceWindow(_ s: Int) -> [[Tile]] {
        window(at: (0, sliceRows * s), width: sliceWidth, height: sliceRows)
    }

    /// The op sequence slice `s` fires, as indices into `opsCanonical`
    /// (row-major over `sliceWindow`) — the SYNTAX a gene modulates but never
    /// mutates (spec `sliceOps`, index form for compact goldens).
    static func sliceOpIndices(_ s: Int) -> [Int] {
        (0 ..< sliceRows).flatMap { j in
            (0 ..< sliceWidth).map { m in opIndexOfTile[tileIndexAt(m, sliceRows * s + j)] }
        }
    }

    /// The op sequence slice `s` fires (spec `sliceOps`).
    static func sliceOps(_ s: Int) -> [TileOp] {
        sliceOpIndices(s).map { opsCanonical[$0] }
    }

    // ── Gene = attention (modulates expression, never the schedule) ──────────

    /// An exact attention weight — a reduced rational (`den > 0`).
    struct Weight: Equatable, Sendable {
        let num: Int
        let den: Int
    }

    /// One Q16 unit — the uniform floor share every op keeps (spec `q16One`).
    static let q16One = 65536

    /// The gene's L1 energy on detail band `b` (0..6): Σ|word| over the band's
    /// 3 channels (spec `geneBandEnergy`). `gene` is the θ_up 21-word layout
    /// (7 bands × 3 channels, band-major), padded/truncated to shape.
    static func geneBandEnergy(_ gene: [Int], band: Int) -> Int {
        (0 ..< 3).reduce(0) { acc, ch in
            let i = 3 * band + ch
            return acc + (i < gene.count ? abs(gene[i]) : 0)
        }
    }

    /// THE GENE MAPPING (spec `attentionOf`): the 11-op attention row over
    /// `opsCanonical`, exact rationals. Each `S_A` earns its band's energy;
    /// each `K_a` earns what the a-containing bands left on the table
    /// (Σ_{A∋a} (eMax − e_A)); `I` keeps the floor. One `q16One` floor
    /// everywhere makes the zero gene exactly uniform (1/11 each); the row sums
    /// to exactly 1.
    static func attentionOf(gene: [Int]) -> [Weight] {
        let es = (0 ..< 7).map { geneBandEnergy(gene, band: $0) }
        let eMax = es.max() ?? 0
        let raws: [Int] = opsCanonical.map { op in
            switch op {
            case .i:
                return q16One
            case .s(let bandSet):
                let b = detailBands.firstIndex(of: bandSet)!
                return q16One + es[b]
            case .k(let axis):
                var leftover = 0
                for (b, bandSet) in detailBands.enumerated() where bandSet.contains(axis) {
                    leftover += eMax - es[b]
                }
                return q16One + leftover
            }
        }
        let total = raws.reduce(0, +)
        return raws.map { r in
            let g = Int(S4Frac128.gcd(UInt128(r), UInt128(total)))
            return Weight(num: r / g, den: total / g)
        }
    }

    /// The attention row as pinned Q16 words: `floor(num·65536 / den)` — the
    /// deterministic integer projection the generator spends (a pinned rounding
    /// choice of THIS twin; the exact rationals above are the spec surface).
    static func attentionQ16(gene: [Int]) -> [Int32] {
        attentionOf(gene: gene).map { w in Int32(w.num * q16One / w.den) }
    }

    // ── Boot resolve: the √N crystallize schedule ─────────────────────────────

    /// The three preview rungs of the inverted pyramid (spec `WeaveRung`,
    /// restricted to what the boot ladder needs).
    enum TubeRung: CaseIterable, Equatable, Sendable {
        case r16, r32, r64

        /// Fine frames one unit pools (spec `Spec.WeaveOrder.unitsOf`): 4/2/1.
        var unitsOf: Int {
            switch self {
            case .r16: return 4
            case .r32: return 2
            case .r64: return 1
            }
        }

        /// The boot mirror: the reveal ladder plays the pour ladder in REVERSE
        /// (spec `bootMirror`; W64 ↔ W16, W32 self-mirrored).
        var bootMirror: TubeRung {
            switch self {
            case .r16: return .r64
            case .r32: return .r32
            case .r64: return .r16
            }
        }
    }

    /// The tick at which rung `p` becomes statistically trustworthy at boot:
    /// `framesPerRealize W16 (= 4) · unitsOf (bootMirror p)` — 4/8/16, NO new
    /// constant (spec `revealTick`; reciprocity `revealTick p · unitsOf p = 16`).
    static func revealTick(_ p: TubeRung) -> Int { 4 * p.bootMirror.unitsOf }

    /// The rungs revealed (trustworthy) at tick `t`, coarse-first — the UI's
    /// boot crystallize readout. Empty at tick 0: trust is EARNED, never
    /// animated (spec `revealAt`).
    static func revealAt(_ t: Int) -> [TubeRung] {
        [TubeRung.r16, .r32, .r64].filter { t >= revealTick($0) }
    }
}
