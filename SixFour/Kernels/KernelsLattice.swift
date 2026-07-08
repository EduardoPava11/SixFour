//  KernelsLattice.swift
//  Swift port of the LATTICE section of Native/src/kernels.zig (2026-07-06);
//  byte-exact twin, golden-gated.
//
//  Covers the reversible integer substrate (the owned S-transform / lifting
//  scheme): the pair-lift core, the integer Haar (analyze / reconstruct /
//  level-nodes), the RGBT 2×2 quad lift, the 2×2×2 octant lift, the cube-ladder
//  level/rung operators, the temporal Haar split/join, the deterministic Q16
//  board mass channels, the half→Q16 widening edge, and the .cube LUT builder
//  (`s4_build_cube_q16` with its private RED-front-end / OKLab / look-transfer
//  helper tree).
//
//  TRANSLATION SEMANTICS (see KernelsCore.swift for the full dictionary):
//  Zig `@divFloor` → `s4DivFloor`/`s4DivFloor64`; Zig `@divTrunc` and integer
//  `/` → Swift `/`; Zig `+`/`-`/`*` (trapping) → Swift `+`/`-`/`*` (trapping);
//  Zig `@intCast` (trapping) → trapping numeric init; Zig `@bitCast` →
//  bitPattern initializers. The 2×2(×2) averages are FLOOR divisions
//  (`@divFloor(d, 2)` in kernels.zig sLift64/liftChecked) — NEVER `>> 1`-vs-`/`
//  folklore: floor division on possibly-negative details is the load-bearing
//  choice (see the DIVFLOOR adversarial test).

// ── return codes (private per-file copies of kernels.zig RC_*) ───────────────
private let rcOK: Int32 = 0
private let rcNullPtr: Int32 = 1
private let rcBadShape: Int32 = 2
private let rcScratchTooSmall: Int32 = 3
private let rcOutputTooSmall: Int32 = 4
private let rcInfeasibleSignificance: Int32 = 5
private let rcBadDitherMode: Int32 = 6
/// A reversible-substrate input (or a derived lift intermediate) fell outside
/// the proven-invertible Q16 domain |v| <= SUBSTRATE_BOUND. The kernel REFUSES
/// rather than wrap silently: the total-function contract is "invert exactly,
/// or return this code, but never corrupt."
private let rcOutOfRange: Int32 = 7
private let rcNotImplemented: Int32 = 100

// ── reversible-substrate domain bound + total-function lift core ─────────────
//
// FORM follows FUNCTION. The SixFour reversible substrate is a bit-exact integer
// S-transform (lifting scheme) over Q16 OKLab triples, built from ONE pair-lift
// L(x,y) = (y + floor((x-y)/2), x-y) and its exact inverse. A function FITS this
// form iff it is (1) pure integer, (2) TOTAL = exactly invertible on a stated
// finite domain and otherwise REFUSES with a result code (never silently
// corrupts), and (3) overflow-proof so every surfaced intermediate equals its
// true i64 value narrowed losslessly to i32.
//
// THE ONE BOUND. Every input leaf / generator / delta-sum / cube-cell / frame
// channel must satisfy |v| ≤ B = 2^29 − 1.
//
// PROOF SKETCH that B keeps the WHOLE substrate i32-safe (max i32 = 2^31 − 1):
//   • Single-level detail d = x − y with |x|,|y| ≤ B:  |d| ≤ 2B = 2^30 − 2.
//   • Lifted parent p = y + floor(d/2) = floor((x+y)/2) stays within ±B.
//   • Multi-level Haar: each level lifts already-bounded parents, so every
//     per-level detail is again ≤ 2B and every parent ≤ B.
//   • RGBT quad (the binding worst case): the second-level high band's detail
//     |a1 − c1| ≤ 4B = 2^31 − 4 ≤ 2^31 − 1 — FITS i32 exactly; one tick past B
//     would overflow, so B is the TIGHT bound for the quad.
//
// All compute below is done in Int64 (so the CHECK itself never overflows),
// then range-checked and narrowed back to Int32 or refused with rcOutOfRange.
private let substrateBound: Int64 = (1 << 29) - 1 // B = 2^29 − 1
private let detailBound: Int64 = 2 * ((1 << 29) - 1) // 2B = max legal single-level detail

@inline(__always)
private func isPow2(_ n: Int32) -> Bool {
    return n > 0 && (n & (n - 1)) == 0
}

@inline(__always)
private func inBound(_ v: Int64, _ bound: Int64) -> Bool {
    return v >= -bound && v <= bound
}

/// True iff every channel of `n` interleaved triples (3n i32) is within ±B.
private func leavesInDomain(_ p: UnsafePointer<Int32>, _ n: Int) -> Bool {
    var i = 0
    while i < n * 3 {
        if !inBound(Int64(p[i]), substrateBound) { return false }
        i += 1
    }
    return true
}

/// Forward pair-lift in i64: (x,y) → (low, high) = (y + floor((x-y)/2), x-y).
/// Returns rcOK and writes the narrowed i32 result, or rcOutOfRange if any
/// computed value (detail OR parent) falls outside its proven i32-safe envelope
/// — so the surfaced intermediate is ALWAYS the true i64 value or an explicit
/// refusal, never a silent wrap.
@inline(__always)
private func liftChecked(_ x: Int32, _ y: Int32, _ outLow: inout Int32, _ outHigh: inout Int32) -> Int32 {
    let d = Int64(x) - Int64(y) // true detail, no wrap
    if !inBound(d, detailBound) { return rcOutOfRange }
    let p = Int64(y) + s4DivFloor64(d, 2) // true lifted parent (FLOOR division)
    if !inBound(p, substrateBound) { return rcOutOfRange }
    outLow = Int32(p)
    outHigh = Int32(d)
    return rcOK
}

/// Inverse pair-lift in i64: (low, high) → (x, y), y = low − floor(high/2),
/// x = y + high. Validates the SUPPLIED band values (attacker-influenced on the
/// override / Core-AI path): |high| ≤ 2B, |low| ≤ B, and the reconstructed x,y
/// must land back within ±B. Refuses with rcOutOfRange otherwise.
@inline(__always)
private func unliftChecked(_ low: Int32, _ high: Int32, _ outX: inout Int32, _ outY: inout Int32) -> Int32 {
    if !inBound(Int64(high), detailBound) { return rcOutOfRange }
    if !inBound(Int64(low), substrateBound) { return rcOutOfRange }
    let y = Int64(low) - s4DivFloor64(Int64(high), 2)
    let x = y + Int64(high)
    if !inBound(y, substrateBound) || !inBound(x, substrateBound) { return rcOutOfRange }
    outX = Int32(x)
    outY = Int32(y)
    return rcOK
}

// ── owned integer Haar (reversible lifting / S-transform) ─────────────────────
// The palette's dimensional space as EXACT integer math: a node stores the full
// detail d = x - y and a lifted floor-average parent = y + floor(d/2); the inverse
// recovers (x, y) exactly for all integers. So reconstruct∘analyze = id BYTE-EXACT
// (no tolerance) and a coefficient move (+δ then −δ) is exactly reversible. Mirrors
// SixFour.Spec.PairTreeFixed. n must be a power of two; offsets are laid out
// coarsest-first (level ℓ's 2^ℓ details at indices [2^ℓ−1 .. 2^(ℓ+1)−1)).

/// Forward integer Haar: 2^D leaves → root + (2^D − 1) detail offsets (Q16,
/// interleaved L,a,b). `scratch` ≥ n·3·4 bytes (a working copy of the leaves).
@_cdecl("s4_haar_analyze")
public func s4_haar_analyze(
    _ leaves_q16: UnsafePointer<Int32>?,
    _ n: Int32,
    _ out_root_q16: UnsafeMutablePointer<Int32>?,
    _ out_offsets_q16: UnsafeMutablePointer<Int32>?,
    _ scratch: UnsafeMutableRawPointer?,
    _ scratch_cap: Int
) -> Int32 {
    guard let leaves = leaves_q16, let outRoot = out_root_q16, let outOffsets = out_offsets_q16 else { return rcNullPtr }
    if !isPow2(n) { return rcBadShape }
    let nn = Int(n)
    let need = nn * 3 * MemoryLayout<Int32>.size
    guard let scratchRaw = scratch, scratch_cap >= need else { return rcScratchTooSmall }
    // TOTALITY: refuse any out-of-domain leaf rather than wrap d=x−y silently.
    if !leavesInDomain(leaves, nn) { return rcOutOfRange }
    let work = scratchRaw.assumingMemoryBound(to: Int32.self)
    var i = 0
    while i < nn * 3 {
        work[i] = leaves[i]
        i += 1
    }

    var cur = nn
    while cur > 1 {
        let half = cur / 2
        let outStart = half - 1 // 2^ℓ − 1
        i = 0
        while i < half {
            var c = 0
            while c < 3 {
                let x = work[(2 * i) * 3 + c]
                let y = work[(2 * i + 1) * 3 + c]
                // i64 compute + narrow-or-refuse: lifted parent and detail are the
                // true wide-truth values, never a silent i32 wrap.
                var lo: Int32 = 0
                var hi: Int32 = 0
                let rc = liftChecked(x, y, &lo, &hi)
                if rc != rcOK { return rc }
                work[i * 3 + c] = lo // lifted parent
                outOffsets[(outStart + i) * 3 + c] = hi // detail
                c += 1
            }
            i += 1
        }
        cur = half
    }
    outRoot[0] = work[0]
    outRoot[1] = work[1]
    outRoot[2] = work[2]
    s4log("haar_an   n=\(n) (reversible lifting)")
    return rcOK
}

/// Inverse integer Haar: root + (2^D − 1) offsets → 2^D leaves. Exact inverse of
/// `s4_haar_analyze`. In-place expansion (no scratch).
/// TOTAL: domain is root |v| ≤ B and each detail |d| ≤ 2B (the image of a legal
/// analyze); any node/leaf the i64 inverse would push outside ±B returns
/// `rcOutOfRange` rather than wrapping (matters on the attacker-influenced
/// offsets/Core-AI path).
@_cdecl("s4_haar_reconstruct")
public func s4_haar_reconstruct(
    _ root_q16: UnsafePointer<Int32>?,
    _ offsets_q16: UnsafePointer<Int32>?,
    _ n: Int32,
    _ out_leaves_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let root = root_q16, let offsets = offsets_q16, let out = out_leaves_q16 else { return rcNullPtr }
    if !isPow2(n) { return rcBadShape }
    let nn = Int(n)
    // TOTALITY: the root must be in-domain (|node| ≤ B). Per-detail/per-node bounds
    // are enforced inside unliftChecked as the tree expands (the supplied offsets
    // are attacker-influenced on the override / Core-AI path).
    if !inBound(Int64(root[0]), substrateBound) || !inBound(Int64(root[1]), substrateBound) ||
        !inBound(Int64(root[2]), substrateBound) { return rcOutOfRange }
    out[0] = root[0]
    out[1] = root[1]
    out[2] = root[2]

    var cur = 1
    while cur < nn {
        let outStart = cur - 1 // 2^ℓ − 1
        var i = cur
        while i > 0 {
            i -= 1
            var c = 0
            while c < 3 {
                let node = out[i * 3 + c]
                let d = offsets[(outStart + i) * 3 + c]
                var x: Int32 = 0
                var y: Int32 = 0
                let rc = unliftChecked(node, d, &x, &y)
                if rc != rcOK { return rc }
                out[(2 * i) * 3 + c] = x // x
                out[(2 * i + 1) * 3 + c] = y // y
                c += 1
            }
        }
        cur *= 2
    }
    s4log("haar_rec  n=\(n) (reversible lifting)")
    return rcOK
}

/// The node colours at a given Haar pairing `level` — the abstraction cascade
/// (256 leaves → 16 level-4 → 4 level-2 → 1 root). Identical to `s4_haar_reconstruct`
/// stopped after `level` expansions, so it is BYTE-EXACT vs
/// `SixFour.Spec.PairTreeFixed.levelNodesFixed`. Writes `2^level` nodes (Q16, L,a,b
/// interleaved) into `out_nodes_q16`. `n` = total leaves (2^D); requires
/// `0 ≤ level ≤ D`. In-place expansion (no scratch). SixFour surfaces level 4 (16
/// colours) as the capture shutter.
/// TOTAL: same domain as `s4_haar_reconstruct` (root |v| ≤ B, detail |d| ≤ 2B);
/// returns `rcOutOfRange` instead of surfacing a wrapped node. This is the exact
/// UI-surfacing path the silent-overflow defect rode, so the guard is load-bearing.
@_cdecl("s4_haar_level_nodes")
public func s4_haar_level_nodes(
    _ level: Int32,
    _ root_q16: UnsafePointer<Int32>?,
    _ offsets_q16: UnsafePointer<Int32>?,
    _ n: Int32,
    _ out_nodes_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let root = root_q16, let offsets = offsets_q16, let out = out_nodes_q16 else { return rcNullPtr }
    if !isPow2(n) || level < 0 { return rcBadShape }
    let nn = Int(n)
    var target = 1 // 2^level
    var k: Int32 = 0
    while k < level {
        target *= 2
        k += 1
    }
    if target > nn { return rcBadShape } // level must not exceed tree depth

    // TOTALITY: same image-domain validation as s4_haar_reconstruct — this is the
    // exact UI surfacing path (level 4 = the 16-colour shutter); it must NEVER emit
    // a wrapped node.
    if !inBound(Int64(root[0]), substrateBound) || !inBound(Int64(root[1]), substrateBound) ||
        !inBound(Int64(root[2]), substrateBound) { return rcOutOfRange }
    out[0] = root[0]
    out[1] = root[1]
    out[2] = root[2]

    var cur = 1
    while cur < target {
        let outStart = cur - 1 // 2^ℓ − 1
        var i = cur
        while i > 0 {
            i -= 1
            var c = 0
            while c < 3 {
                let node = out[i * 3 + c]
                let d = offsets[(outStart + i) * 3 + c]
                var x: Int32 = 0
                var y: Int32 = 0
                let rc = unliftChecked(node, d, &x, &y)
                if rc != rcOK { return rc }
                out[(2 * i) * 3 + c] = x // x
                out[(2 * i + 1) * 3 + c] = y // y
                c += 1
            }
        }
        cur *= 2
    }
    s4log("haar_lvl  level=\(level) nodes=\(target)")
    return rcOK
}

// ── RGBT-4D reversible lifting (mirror of SixFour.Spec.RGBTLift / .CubeLadder) ──
// The 2-D-Haar S-transform with floor division (@divFloor) — IDENTICAL arithmetic to
// the integer Haar above, the Swift RGBT4DLift port, and the spec. The Metal kernel
// must match this byte-for-byte; all gate on the spec golden (rgbt4d_golden.json /
// RGBT4DGolden.swift) — never against each other directly.
//
// 2×2 block (a,b,c,d) → sub-bands (R,G,B,T)=(LL,LH,HL,HH).
// The owned integer S-transform (lifting scheme, JPEG2000-lossless lineage), factored
// into ONE shared pair-lift so the spatial 2×2 RGBT lift and the temporal one-level
// Haar split call the SAME math (no inline copies — reuse-first, no duplicated kernels).
// Forward: (x,y) → (low, high) = (y + floor((x-y)/2), x - y). Mirrors
// SixFour.Spec.TemporalLoop liftPairT (per channel) and SixFour.Spec.RGBTLift's
// S-transform. All four sLift applications compute in i64 (so the worst-case
// second-level high-band detail ≤ 4B = 2^31−4 is formed without wrap) and narrow
// back to i32.

@inline(__always)
private func sLift64(_ x: Int64, _ y: Int64) -> (low: Int64, high: Int64) {
    let d = x - y
    return (y + s4DivFloor64(d, 2), d)
}

@inline(__always)
private func sUnlift64(_ low: Int64, _ high: Int64) -> (x: Int64, y: Int64) {
    let y = low - s4DivFloor64(high, 2)
    return (y + high, y)
}

/// 2×2 separable Haar = four sLift applications (rows then columns). Computed in
/// i64 so the 4B second-level high-band intermediate never wraps. In-domain the
/// narrowing Int32 inits are proven safe (≤ 4B fits i32).
@inline(__always)
private func rgbtLiftQuad(_ q0: Int32, _ q1: Int32, _ q2: Int32, _ q3: Int32) -> (Int32, Int32, Int32, Int32) {
    let a = sLift64(Int64(q0), Int64(q1)) // (la, ha)
    let c = sLift64(Int64(q2), Int64(q3)) // (lc, hc)
    let l = sLift64(a.low, c.low) // (R, G)
    let h = sLift64(a.high, c.high) // (B, T)  ← operands are details ≤2B ⇒ |h| ≤ 4B (fits i32)
    return (Int32(l.low), Int32(l.high), Int32(h.low), Int32(h.high)) // (LL=R, LH=G, HL=B, HH=T)
}

/// Domain check for the inverse quad's SUPPLIED bands (attacker-influenced): every
/// sUnlift intermediate and the four reconstructed cells must fit i32 and the
/// reconstructed 2×2 block must land within ±B (the image of a legal lift). i64
/// throughout so the check never wraps. Returns rcOK / rcOutOfRange.
@inline(__always)
private func rgbtUnliftQuadChecked(
    _ r0: Int32, _ r1: Int32, _ r2: Int32, _ r3: Int32,
    _ out: inout (Int32, Int32, Int32, Int32)
) -> Int32 {
    // Forward bands of a legal lift: R=LL (parent, ≤B), G=LH & B=HL (first/second
    // level low-band-of-detail, ≤2B), T=HH (second-level high-band detail, ≤4B).
    if !inBound(Int64(r0), substrateBound) { return rcOutOfRange } // LL
    if !inBound(Int64(r1), detailBound) { return rcOutOfRange } // LH ≤2B
    if !inBound(Int64(r2), detailBound) { return rcOutOfRange } // HL ≤2B
    if !inBound(Int64(r3), 4 * substrateBound) { return rcOutOfRange } // HH ≤4B
    let lo = sUnlift64(Int64(r0), Int64(r1)) // (la, lc) — parents ≤B
    let hi = sUnlift64(Int64(r2), Int64(r3)) // (ha, hc) — details ≤2B
    let a = sUnlift64(lo.x, hi.x) // (a, b)
    let c = sUnlift64(lo.y, hi.y) // (c, d)
    if !inBound(a.x, substrateBound) || !inBound(a.y, substrateBound) ||
        !inBound(c.x, substrateBound) || !inBound(c.y, substrateBound) { return rcOutOfRange }
    out = (Int32(a.x), Int32(a.y), Int32(c.x), Int32(c.y))
    return rcOK
}

/// 2×2 → RGBT lift on one block (4 ints in, 4 ints out). Bijective with s4_rgbt_unlift_quad.
/// TOTAL: the 4 inputs each must be |v| ≤ B = SUBSTRATE_BOUND. This is the BINDING
/// case for the whole substrate's bound: the second-level high band reaches 4B, so
/// one tick past B would overflow i32; an out-of-domain block returns rcOutOfRange.
@_cdecl("s4_rgbt_lift_quad")
public func s4_rgbt_lift_quad(_ in_q16: UnsafePointer<Int32>?, _ out_q16: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let inp = in_q16, let out = out_q16 else { return rcNullPtr }
    let q0 = inp[0], q1 = inp[1], q2 = inp[2], q3 = inp[3]
    // TOTALITY: the 4 input cells must each be in-domain (|v| ≤ B). This is the
    // BINDING constraint — the second-level high-band detail a[1]−c[1] reaches 4B
    // = 2^31−4 (fits i32) at |input|=B, and 4(B+1)=2^31 overflows just past it.
    if !inBound(Int64(q0), substrateBound) || !inBound(Int64(q1), substrateBound) ||
        !inBound(Int64(q2), substrateBound) || !inBound(Int64(q3), substrateBound) { return rcOutOfRange }
    let o = rgbtLiftQuad(q0, q1, q2, q3)
    out[0] = o.0
    out[1] = o.1
    out[2] = o.2
    out[3] = o.3
    return rcOK
}

/// Inverse of s4_rgbt_lift_quad.
/// TOTAL: the 4 (R,G,B,T) bands must be the image of a legal lift; a quartet whose
/// i64 inverse leaves ±B returns rcOutOfRange rather than wrapping.
@_cdecl("s4_rgbt_unlift_quad")
public func s4_rgbt_unlift_quad(_ in_q16: UnsafePointer<Int32>?, _ out_q16: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let inp = in_q16, let out = out_q16 else { return rcNullPtr }
    var o: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
    // TOTALITY: validate the supplied bands + reconstructed cells (image of a legal
    // lift) and compute in i64; refuse rather than wrap.
    let rc = rgbtUnliftQuadChecked(inp[0], inp[1], inp[2], inp[3], &o)
    if rc != rcOK { return rc }
    out[0] = o.0
    out[1] = o.1
    out[2] = o.2
    out[3] = o.3
    return rcOK
}

/// The 2×2×2 → 1 OCTANT lift (OctreeCell.liftOct): 8 cells (a,b,c,d near-z face,
/// e,f,g,h far-z face) → 1 coarse + 7 detail. Two xy-quad lifts (s4_rgbt_lift_quad's
/// rgbtLiftQuad) then one Haar (liftChecked) along z on the two coarse R=LL values.
/// out = [rr, g0,b0,t0, g1,b1,t1, dz] = OctBand coarse + (the 6 face details + z detail).
/// TOTAL: the 8 inputs must each be |v| ≤ B; refuses with rcOutOfRange rather than wrap.
/// The learned-token VolumeOctant substrate, byte-exact against OctreeCell.liftOct.
@_cdecl("s4_octant_lift")
public func s4_octant_lift(_ in_q16: UnsafePointer<Int32>?, _ out_q16: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let inp = in_q16, let out = out_q16 else { return rcNullPtr }
    var i = 0
    while i < 8 {
        if !inBound(Int64(inp[i]), substrateBound) { return rcOutOfRange }
        i += 1
    }
    let o0 = rgbtLiftQuad(inp[0], inp[1], inp[2], inp[3]) // near face (r0,g0,b0,t0)
    let o1 = rgbtLiftQuad(inp[4], inp[5], inp[6], inp[7]) // far face  (r1,g1,b1,t1)
    var rr: Int32 = 0
    var dz: Int32 = 0
    let rc = liftChecked(o0.0, o1.0, &rr, &dz) // sLift(r0, r1)
    if rc != rcOK { return rc }
    out[0] = rr // coarse
    out[1] = o0.1 // g0
    out[2] = o0.2 // b0
    out[3] = o0.3 // t0
    out[4] = o1.1 // g1
    out[5] = o1.2 // b1
    out[6] = o1.3 // t1
    out[7] = dz // z detail
    return rcOK
}

/// The exact inverse of s4_octant_lift (OctreeCell.unliftOct): sUnlift the z stage,
/// then unlift each face quad. TOTAL: validates the supplied bands (coarse ≤B, z-detail
/// ≤2B, face bands via rgbtUnliftQuadChecked) and refuses rather than wrap.
@_cdecl("s4_octant_unlift")
public func s4_octant_unlift(_ in_q16: UnsafePointer<Int32>?, _ out_q16: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let inp = in_q16, let out = out_q16 else { return rcNullPtr }
    var r0: Int32 = 0
    var r1: Int32 = 0
    let rcZ = unliftChecked(inp[0], inp[7], &r0, &r1) // sUnlift(rr, dz)
    if rcZ != rcOK { return rcZ }
    var nearCells: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
    var farCells: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
    let rc0 = rgbtUnliftQuadChecked(r0, inp[1], inp[2], inp[3], &nearCells) // (r0,g0,b0,t0)
    if rc0 != rcOK { return rc0 }
    let rc1 = rgbtUnliftQuadChecked(r1, inp[4], inp[5], inp[6], &farCells) // (r1,g1,b1,t1)
    if rc1 != rcOK { return rc1 }
    out[0] = nearCells.0
    out[1] = nearCells.1
    out[2] = nearCells.2
    out[3] = nearCells.3
    out[4] = farCells.0
    out[5] = farCells.1
    out[6] = farCells.2
    out[7] = farCells.3
    return rcOK
}

/// ONE up-rung of a scalar cube in the DEVICE volume layout ((t*side + r)*side + c,
/// col fastest): every coarse voxel becomes its 2x2x2 block via the gated
/// s4_octant_unlift; output cell (2t+dt, 2r+dr, 2c+dc) = octant lane dt*4+dr*2+dc
/// (near-t face first, so the octant z axis IS the time axis — the B2.3 pin).
/// `details` may be nil (the zero-detail deterministic floor; zero-gene == floor)
/// or [side^3 * 7] i32 voxel-major COMMITTED bands (a somatic theta_up's Q16-committed
/// invention — the float layer stays OUTSIDE this operator: a pure integer stage of
/// the cascade sandwich). Byte-exact against
/// SixFour.Spec.SelfSimilarReconstruct.expandRungVolume (cube_expand fixture test).
/// This is the export rung's CPU oracle: 16^3 -> 32^3 -> 64^3 -> ... -> 256^3 is this
/// operator iterated. TOTAL: refuses (propagating s4_octant_unlift's checks) rather
/// than wrap.
@_cdecl("s4_cube_expand_rung")
public func s4_cube_expand_rung(
    _ vol: UnsafePointer<Int32>?,
    _ side: Int32,
    _ details: UnsafePointer<Int32>?,
    _ out: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let vol = vol, let out = out else { return rcNullPtr }
    if side <= 0 { return rcBadShape }
    let s = Int(side)
    let s2 = 2 * s
    var bands = [Int32](repeating: 0, count: 8)
    var block = [Int32](repeating: 0, count: 8)
    return bands.withUnsafeMutableBufferPointer { bandsBuf in
        block.withUnsafeMutableBufferPointer { blockBuf in
            let bandsPtr = bandsBuf.baseAddress!
            let blockPtr = blockBuf.baseAddress!
            var t = 0
            while t < s {
                var r = 0
                while r < s {
                    var c = 0
                    while c < s {
                        let i = (t * s + r) * s + c
                        bandsPtr[0] = vol[i]
                        if let details = details {
                            var k = 0
                            while k < 7 {
                                bandsPtr[k + 1] = details[i * 7 + k]
                                k += 1
                            }
                        }
                        // (bands 1..7 stay zero on the nil-details floor arm —
                        // they are never written after the zeroed init.)
                        let rc = s4_octant_unlift(bandsPtr, blockPtr)
                        if rc != rcOK { return rc }
                        var lane = 0
                        var dt = 0
                        while dt < 2 {
                            var dr = 0
                            while dr < 2 {
                                var dc = 0
                                while dc < 2 {
                                    out[((2 * t + dt) * s2 + (2 * r + dr)) * s2 + (2 * c + dc)] = blockPtr[lane]
                                    lane += 1
                                    dc += 1
                                }
                                dr += 1
                            }
                            dt += 1
                        }
                        c += 1
                    }
                    r += 1
                }
                t += 1
            }
            return rcOK
        }
    }
}

/// One 2-D-Haar level over a side×side row-major grid (side even): tile into 2×2
/// blocks, lift each → coarse (side/2)² plane + (side/2)² detail triples (G,B,T).
/// The TILING is where Metal (2-D threads) and Zig/Swift (loops) could diverge — pinned here.
/// TOTAL: every grid cell must be |v| ≤ B (the per-tile RGBT 4B envelope governs);
/// an out-of-domain grid returns rcOutOfRange rather than wrapping a tile.
@_cdecl("s4_cube_lift_level")
public func s4_cube_lift_level(
    _ side: Int32,
    _ grid: UnsafePointer<Int32>?,
    _ out_coarse: UnsafeMutablePointer<Int32>?,
    _ out_details: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let grid = grid, let outCoarse = out_coarse, let outDetails = out_details else { return rcNullPtr }
    if side <= 0 || side % 2 != 0 { return rcBadShape }
    let s = Int(side)
    let h = s / 2
    // TOTALITY: every grid cell must be in-domain (|v| ≤ B); each 2×2 tile feeds
    // rgbtLiftQuad whose 4B intermediate bound governs. (Scalar cells, not triples.)
    var k = 0
    while k < s * s {
        if !inBound(Int64(grid[k]), substrateBound) { return rcOutOfRange }
        k += 1
    }
    var by = 0
    while by < h {
        var bx = 0
        while bx < h {
            let o = rgbtLiftQuad(
                grid[(2 * by) * s + 2 * bx],
                grid[(2 * by) * s + 2 * bx + 1],
                grid[(2 * by + 1) * s + 2 * bx],
                grid[(2 * by + 1) * s + 2 * bx + 1]
            )
            let bi = by * h + bx
            outCoarse[bi] = o.0
            outDetails[bi * 3 + 0] = o.1
            outDetails[bi * 3 + 1] = o.2
            outDetails[bi * 3 + 2] = o.3
            bx += 1
        }
        by += 1
    }
    return rcOK
}

/// Exact inverse of s4_cube_lift_level: coarse h² + details h²·3 → 2h×2h grid.
/// TOTAL: each (coarse, 3 details) quartet must be the image of a legal lift
/// (the RGBT 4B envelope); a quartet whose i64 inverse leaves ±B returns
/// `rcOutOfRange` rather than wrapping.
@_cdecl("s4_cube_unlift_level")
public func s4_cube_unlift_level(
    _ half: Int32,
    _ coarse: UnsafePointer<Int32>?,
    _ details: UnsafePointer<Int32>?,
    _ out_grid: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let coarse = coarse, let details = details, let outGrid = out_grid else { return rcNullPtr }
    if half <= 0 { return rcBadShape }
    let h = Int(half)
    let s = 2 * h
    var by = 0
    while by < h {
        var bx = 0
        while bx < h {
            let bi = by * h + bx
            var q: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
            // TOTALITY: validate supplied bands (image of a legal cube_lift) + i64 compute.
            let rc = rgbtUnliftQuadChecked(coarse[bi], details[bi * 3 + 0], details[bi * 3 + 1], details[bi * 3 + 2], &q)
            if rc != rcOK { return rc }
            outGrid[(2 * by) * s + 2 * bx] = q.0
            outGrid[(2 * by) * s + 2 * bx + 1] = q.1
            outGrid[(2 * by + 1) * s + 2 * bx] = q.2
            outGrid[(2 * by + 1) * s + 2 * bx + 1] = q.3
            bx += 1
        }
        by += 1
    }
    return rcOK
}

/// One level of the temporal integer Haar split over a sequence of `n` OKLab triples (Q16) —
/// the TEMPORAL half of SixFour.Spec.VoxelReduce, mirroring SixFour.Spec.TemporalLoop.haarSplitTime.
/// Adjacent frames pair into a lifted parent (low) and a detail (high) via the OWNED `sLift` per
/// channel (no new lift math; reuse-first, no duplicated kernels). An odd
/// trailing frame is carried into the low band with no detail. Exactly inverted by
/// s4_haar_join_level. in: n·3 i32 (frame-major). out_low: (n/2 + n%2)·3. out_high: (n/2)·3.
/// TOTAL: every input frame channel must be |v| ≤ B; out-of-domain frames return
/// `rcOutOfRange` (the i64 lift never wraps).
@_cdecl("s4_haar_split_level")
public func s4_haar_split_level(
    _ n: Int32,
    _ in_q16: UnsafePointer<Int32>?,
    _ out_low: UnsafeMutablePointer<Int32>?,
    _ out_high: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let inp = in_q16, let outLow = out_low, let outHigh = out_high else { return rcNullPtr }
    if n < 0 { return rcBadShape }
    let nn = Int(n)
    // TOTALITY: every input frame channel must be in-domain (|v| ≤ B); single sLift
    // level ⇒ |detail| ≤ 2B fits i32.
    if !leavesInDomain(inp, nn) { return rcOutOfRange }
    let pairs = nn / 2
    var i = 0
    while i < pairs {
        var c = 0
        while c < 3 {
            var lo: Int32 = 0
            var hi: Int32 = 0
            let rc = liftChecked(inp[(2 * i) * 3 + c], inp[(2 * i + 1) * 3 + c], &lo, &hi)
            if rc != rcOK { return rc }
            outLow[i * 3 + c] = lo
            outHigh[i * 3 + c] = hi
            c += 1
        }
        i += 1
    }
    if nn % 2 == 1 { // carry the odd tail into the low band, no detail
        var c = 0
        while c < 3 {
            outLow[pairs * 3 + c] = inp[(nn - 1) * 3 + c]
            c += 1
        }
    }
    return rcOK
}

/// Exact inverse of s4_haar_split_level (mirrors SixFour.Spec.TemporalLoop.haarJoinTime): rebuild
/// the n-frame sequence from (low, high) via the OWNED `sUnlift`. `low_n = n/2 + n%2`,
/// `high_n = n/2`, so n = low_n + high_n and `low_n - high_n ∈ {0,1}`. out: n·3 i32.
/// TOTAL: low must be |v| ≤ B and high |d| ≤ 2B (the image of a legal split);
/// otherwise `rcOutOfRange` (no silent wrap in the i64 join).
@_cdecl("s4_haar_join_level")
public func s4_haar_join_level(
    _ low_n: Int32,
    _ high_n: Int32,
    _ low: UnsafePointer<Int32>?,
    _ high: UnsafePointer<Int32>?,
    _ out_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let low = low, let high = high, let out = out_q16 else { return rcNullPtr }
    if low_n < 0 || high_n < 0 || low_n < high_n || low_n - high_n > 1 { return rcBadShape }
    let hn = Int(high_n)
    var i = 0
    while i < hn {
        var c = 0
        while c < 3 {
            var x: Int32 = 0
            var y: Int32 = 0
            // TOTALITY: validate supplied bands (|low| ≤ B, |high| ≤ 2B) + i64 compute.
            let rc = unliftChecked(low[i * 3 + c], high[i * 3 + c], &x, &y)
            if rc != rcOK { return rc }
            out[(2 * i) * 3 + c] = x
            out[(2 * i + 1) * 3 + c] = y
            c += 1
        }
        i += 1
    }
    if Int(low_n) > hn { // the carried odd tail
        // The odd-tail carry is a copy (no lift); validate it stays in-domain.
        var c = 0
        while c < 3 {
            let v = low[hn * 3 + c]
            if !inBound(Int64(v), substrateBound) { return rcOutOfRange }
            out[(2 * hn) * 3 + c] = v
            c += 1
        }
    }
    return rcOK
}

// ─────────────────────────────────────────────────────────────────────────
// Color Atlas board — deterministic Q16 mass (port of SixFour.Spec.BoardQ16).
//
// The AlphaZero policy/value reads the 16³ board; its base mass channels were
// built by a float histogram that normalised by a non-dyadic 1/total — a float
// leak at the FIRST matmul that desyncs the argmax cross-device. These kernels
// are the byte-exact integer replacement: integer floor-div binning, integer
// counts (associative ⇒ permutation-invariant EXACTLY), and ONE round-half-up
// of count·2¹⁶/total per bin. The Haskell module is the source of truth; a
// future Metal port MUST reuse `boardFloorDiv` (int `/` truncates toward zero
// on negatives — the @divFloor trap from the SIMT bit-agreement contract).
// ─────────────────────────────────────────────────────────────────────────

private let boardBinsPerAxis: Int32 = 16
private let boardBins = 16 * 16 * 16 // 4096
private let boardBinWidthQ16: Int32 = 65536 / 16 // 4096
private let boardHalfQ16: Int32 = 32768 // 0.5 in Q16 (a/b axis offset)

/// Floor division by a positive divisor (matches Haskell `div` / Zig @divFloor;
/// the explicit helper a Metal port must call instead of int `/`).
@inline(__always)
private func boardFloorDiv(_ n: Int32, _ d: Int32) -> Int32 {
    return s4DivFloor(n, d)
}

@inline(__always)
private func boardClampBin(_ i: Int32) -> Int32 {
    return max(0, min(boardBinsPerAxis - 1, i))
}

/// Flat bin index of a Q16 OKLab triple — exactly Spec.BoardQ16.binOfQ16 then binIndex.
@inline(__always)
private func boardBinIndexQ16(_ l: Int32, _ a: Int32, _ b: Int32) -> Int {
    let bl = boardClampBin(boardFloorDiv(l, boardBinWidthQ16))
    let ba = boardClampBin(boardFloorDiv(a + boardHalfQ16, boardBinWidthQ16))
    let bb = boardClampBin(boardFloorDiv(b + boardHalfQ16, boardBinWidthQ16))
    return Int((bl * boardBinsPerAxis + ba) * boardBinsPerAxis + bb)
}

/// ONE round-half-up of count·2¹⁶/total (Spec.BoardQ16.massQ16). i64 intermediate:
/// count can reach 262144 (the 64³ pixel pass), so count·2¹⁶ overflows i32.
@inline(__always)
private func boardMassFromCount(_ count: Int32, _ total: Int32) -> Int32 {
    if total <= 0 { return 0 }
    let t = Int64(total)
    let num = Int64(count) * 65536 + s4DivFloor64(t, 2)
    return Int32(s4DivFloor64(num, t))
}

/// Q16 mass channel from precomputed integer per-bin counts (Spec.BoardQ16.massQ16).
/// For the pixel channel whose counts come from a per-frame slot→bin table. `bins`
/// is the channel length (16³ = 4096); `total` the exact element count.
@_cdecl("s4_board_counts_to_mass_q16")
public func s4_board_counts_to_mass_q16(
    _ counts: UnsafePointer<Int32>?,
    _ bins: Int32,
    _ total: Int32,
    _ out_mass_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let counts = counts, let out = out_mass_q16 else { return rcNullPtr }
    if bins <= 0 { return rcBadShape }
    let n = Int(bins)
    var i = 0
    while i < n {
        out[i] = boardMassFromCount(counts[i], total)
        i += 1
    }
    return rcOK
}

/// Full deterministic mass channel for a Q16 OKLab colour list (Spec.BoardQ16.boardMassQ16):
/// bin (integer floor-div) → integer count → Q16 round-half-up mass. `colors_q16` is
/// `n` interleaved (L,a,b) triples; `out_mass_q16` is the 16³ = 4096 channel.
@_cdecl("s4_board_mass_q16")
public func s4_board_mass_q16(
    _ colors_q16: UnsafePointer<Int32>?,
    _ n: Int32,
    _ out_mass_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let out = out_mass_q16 else { return rcNullPtr }
    if n < 0 { return rcBadShape }
    if n > 0 && colors_q16 == nil { return rcNullPtr }
    var counts = [Int32](repeating: 0, count: boardBins)
    if let colors = colors_q16 {
        let cnt = Int(n)
        var i = 0
        while i < cnt {
            let idx = boardBinIndexQ16(colors[i * 3 + 0], colors[i * 3 + 1], colors[i * 3 + 2])
            counts[idx] += 1
            i += 1
        }
    }
    var bi = 0
    while bi < boardBins {
        out[bi] = boardMassFromCount(counts[bi], n)
        bi += 1
    }
    return rcOK
}

// ── half → Q16 widening (the float I/O edge into the integer domain) ─────────

/// Widen IEEE-754 binary16 (half) values to Q16 i32: `out = round(half · 2^16)`,
/// round-half-away-from-zero, non-finite → 0, saturated to ±2^30 (so the result
/// never overflows i32 and any absurd HDR half is clamped well below the linear
/// range the colour kernel accepts). The half→f32 widening is EXACT (binary16 ⊂
/// binary32) and ×2^16 is an exact power of two, so the ONLY rounding is the final
/// round — fully deterministic and reproducible across devices. This is the I/O
/// edge that lifts Metal's linear-sRGB halfs into the integer fixed-point domain
/// (Q16: 1.0 → 65536) the rest of the deterministic core operates in.
@_cdecl("s4_widen_half_to_q16")
public func s4_widen_half_to_q16(
    _ halfs: UnsafePointer<UInt16>?,
    _ n: Int32,
    _ out_q16: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let halfs = halfs, let out = out_q16 else { return rcNullPtr }
    if n <= 0 { return rcBadShape }
    let nn = Int(n)
    let lim: Float = 1073741824.0 // 2^30, exactly representable, < i32 max
    var i = 0
    while i < nn {
        let h = Float16(bitPattern: halfs[i])
        let v = Float(h) // exact float widening f16 → f32
        let scaled = v * 65536.0 // exact ×2^16
        if !scaled.isFinite {
            out[i] = 0
            i += 1
            continue
        }
        // Zig: @intFromFloat(@round(clamp(scaled, -lim, lim))) — @round is
        // round-half-away-from-zero == Swift .rounded() default
        // (.toNearestOrAwayFromZero); the post-round value is integral so the
        // trapping Int32 init is exact.
        out[i] = Int32(max(-lim, min(lim, scaled)).rounded())
        i += 1
    }
    return rcOK
}

// ════════════════════════════════════════════════════════════════════════════
// Look transfer / LUT extraction (R3D .cube) — the private helper tree behind
// s4_build_cube_q16. The on-screen "look" and the exported 3D LUT are two
// projections of ONE OKLab palette→palette transform derived from the captured
// palette's luminance-zone chroma profile. Mirrors, byte-for-byte:
// SixFour.Spec.{ZoneProfile,LookTransfer,RedFrontEnd,CubeLut}.
//
// The transcendentals (Log3G10 decode, filmic exp) + the Q16 sRGB-encode output
// gamma are 1-D LUTs generated by spec/app/Fixtures.hs. In the Zig core they are
// @embedFile'd .bin goldens; here they are the byte-identical generated arrays
// in KernelsLUTData.swift (s4LutLog3g10Decode / s4LutFilmicTonemap /
// s4LutSrgbEncode — 65537 little-endian i32 each = 262148 bytes).
// ════════════════════════════════════════════════════════════════════════════

private let lutN: Int64 = 65536 // == Q16_ONE: the decode LUT is indexed directly by the Q16 encoded value
private let filmicXMaxQ16: Int64 = 1_048_576 // = 16·65536 — MUST equal SixFour.Spec.RedFrontEnd.filmicXMaxQ16
private let blackLiftQ16: Int64 = 524 // round(0.008·65536)

// RWG → Rec.709, nine Q16 constants from the COMPOSED Double matrix — the SAME
// literals as SixFour.Spec.RedFrontEnd.rwgToRec709Q16 (row-major).
private let rwgToRec709Q16: [Int64] = [129870, -59001, -5343, -11675, 98337, -21124, -6673, -35087, 107312]
// Rec.709 luminance weights, Q16 (round(0.2126/0.7152/0.0722·65536)).
private let rec709LumaQ16: [Int64] = [13933, 46871, 4732]

// Ottosson M1 (linear sRGB→LMS) and M2 (LMS'→OKLab), Q16, row-major. These are
// the SAME integer literals as SixFour.Spec.ColorFixed — the byte-exact contract.
private let m1Q16: [Int64] = [27015, 35149, 3372, 13887, 44610, 7038, 5787, 18463, 41286]
private let m2Q16: [Int64] = [13792, 52011, -267, 129630, -159160, 29530, 1698, 51300, -52997]

// Inverse matrices, Q16 — SAME integer literals as SixFour.Spec.ColorFixed.
// M2⁻¹ (OKLab→l'm's'): the a,b coefficients added to L.
private let m2iLA: Int64 = 25974
private let m2iLB: Int64 = 14143
private let m2iMA: Int64 = -6918
private let m2iMB: Int64 = -4185
private let m2iSA: Int64 = -5864
private let m2iSB: Int64 = -84639
// M1⁻¹ (LMS→linear sRGB), row-major.
private let m1invQ16: [Int64] = [267173, -216774, 15137, -83128, 171033, -22369, -275, -46099, 111910]

private let q16i64: Int64 = 65536 // Q16_ONE as the i64 the helper tree divides by

/// Read the little-endian i32 at `idx` from a generated LUT byte array
/// (the Zig `lutI32` twin over `std.mem.readInt(i32, …, .little)`).
@inline(__always)
private func lutI32(_ lut: [UInt8], _ idx: Int64) -> Int64 {
    let i = Int(idx) * 4
    let b0 = UInt32(lut[i])
    let b1 = UInt32(lut[i + 1])
    let b2 = UInt32(lut[i + 2])
    let b3 = UInt32(lut[i + 3])
    return Int64(Int32(bitPattern: b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
}

@inline(__always)
private func clampPosOklab(_ v: Int64) -> Int64 {
    if v < 0 { return 0 }
    if v > 131072 { return 131072 } // linear ≤ 2.0 keeps icbrt inside i64
    return v
}

/// Exact integer floor cube root in Q16: floor(cbrt(x/2^16) * 2^16), i.e. the
/// largest Y with Y³ ≤ x·2^32. Pure integer binary search — bit-for-bit
/// identical to SixFour.Spec.ColorFixed.icbrtQ16. x is clamped to [0, 131072]
/// so x·2^32 ≤ 2^49 and every mid³ ≤ 2^51 stays inside i64.
private func icbrtQ16(_ xIn: Int64) -> Int64 {
    if xIn <= 0 { return 0 }
    let x: Int64 = xIn > 131072 ? 131072 : xIn
    let n = x << 32
    var lo: Int64 = 0
    var hi: Int64 = 1 << 17
    while lo < hi {
        let mid = (lo + hi + 1) / 2 // @divTrunc, operands positive
        if mid * mid * mid <= n {
            lo = mid
        } else {
            hi = mid - 1
        }
    }
    return lo
}

/// (v/2^16)^3 in Q16 = v^3 / 2^32, truncating (@divTrunc).
@inline(__always)
private func cubeQ16(_ v: Int64) -> Int64 {
    return (v * v * v) / 4294967296
}

/// Exact integer floor sqrt: largest Y with Y² ≤ n. Mirrors
/// SixFour.Spec.ColorFixed.isqrtFloor. n ≤ 2^40 (OKLab Q16 sum-of-squares) so
/// mid² ≤ 2^40 stays in i64.
private func isqrtFloor(_ n: Int64) -> Int64 {
    if n <= 0 { return 0 }
    var lo: Int64 = 0
    var hi: Int64 = 1 << 20
    while lo < hi {
        let mid = (lo + hi + 1) / 2 // @divTrunc, operands positive
        if mid * mid <= n {
            lo = mid
        } else {
            hi = mid - 1
        }
    }
    return lo
}

/// OKLab chroma magnitude in Q16 (the Q16 scale cancels): √(a²+b²).
@inline(__always)
private func chromaQ16Native(_ a: Int64, _ b: Int64) -> Int64 {
    return isqrtFloor(a * a + b * b)
}

// ── RED front-end (SixFour.Spec.RedFrontEnd) ────────────────────────────────

@inline(__always)
private func log3g10DecodeSample(_ v: Int64) -> Int64 {
    let idx: Int64 = v < 0 ? 0 : (v > lutN ? lutN : v)
    return lutI32(s4LutLog3g10Decode, idx)
}

@inline(__always)
private func filmicTonemapSample(_ x: Int64) -> Int64 {
    if x <= 0 { return 0 }
    let raw = (x * lutN) / filmicXMaxQ16 // @divTrunc, operands positive
    let idx: Int64 = raw > lutN ? lutN : raw
    return lutI32(s4LutFilmicTonemap, idx)
}

@inline(__always)
private func srgbEncodeSample(_ lin: Int64) -> Int64 {
    let idx: Int64 = lin < 0 ? 0 : (lin > lutN ? lutN : lin)
    return lutI32(s4LutSrgbEncode, idx)
}

/// One Q16 RWG/Log3G10 grid coordinate → tonemapped linear Rec.709 Q16: decode →
/// matrix → clip negatives → filmic tonemap.
private func redDecodeToLinear(_ vr: Int64, _ vg: Int64, _ vb: Int64) -> (Int64, Int64, Int64) {
    let lr = log3g10DecodeSample(vr)
    let lg = log3g10DecodeSample(vg)
    let lb = log3g10DecodeSample(vb)
    let m = rwgToRec709Q16
    let r0 = (m[0] * lr + m[1] * lg + m[2] * lb) / q16i64
    let g0 = (m[3] * lr + m[4] * lg + m[5] * lb) / q16i64
    let b0 = (m[6] * lr + m[7] * lg + m[8] * lb) / q16i64
    return (
        filmicTonemapSample(max(0, r0)),
        filmicTonemapSample(max(0, g0)),
        filmicTonemapSample(max(0, b0))
    )
}

@inline(__always)
private func gamutScaleFor(_ dev: Int64, _ y: Int64) -> Int64 {
    if dev > 0 { return ((q16i64 - y) * q16i64) / dev }
    if dev < 0 { return (y * q16i64) / (-dev) }
    return q16i64
}

@inline(__always)
private func gamutOut(_ y: Int64, _ dev: Int64, _ sc: Int64) -> Int64 {
    let v = y + (dev * sc) / q16i64
    return max(0, min(q16i64, v))
}

/// Luminance-preserving gamut compression on linear Rec.709 Q16. In-gamut input
/// is an exact fixed point.
private func gamutCompress(_ rgb: (Int64, Int64, Int64)) -> (Int64, Int64, Int64) {
    let r = rgb.0
    let g = rgb.1
    let b = rgb.2
    let yRaw = (rec709LumaQ16[0] * r + rec709LumaQ16[1] * g + rec709LumaQ16[2] * b) / q16i64
    let y = max(1, yRaw)
    let devR = r - y
    let devG = g - y
    let devB = b - y
    var sc: Int64 = q16i64
    sc = min(sc, gamutScaleFor(devR, y))
    sc = min(sc, gamutScaleFor(devG, y))
    sc = min(sc, gamutScaleFor(devB, y))
    sc = max(0, min(q16i64, sc))
    return (gamutOut(y, devR, sc), gamutOut(y, devG, sc), gamutOut(y, devB, sc))
}

/// Black lift on linear Rec.709 Q16: out = lift + v·(1−lift). Before gamut compress.
private func applyBlackLift(_ rgb: (Int64, Int64, Int64)) -> (Int64, Int64, Int64) {
    func lift(_ v: Int64) -> Int64 {
        return blackLiftQ16 + (v * (q16i64 - blackLiftQ16)) / q16i64
    }
    return (lift(rgb.0), lift(rgb.1), lift(rgb.2))
}

// ── OKLab forward/inverse single-triple helpers (the shared matrices) ─────────

@inline(__always)
private func linToOklab1(_ r0: Int64, _ g0: Int64, _ b0: Int64) -> (Int64, Int64, Int64) {
    let r = max(0, r0)
    let g = max(0, g0)
    let b = max(0, b0)
    let l = clampPosOklab((m1Q16[0] * r + m1Q16[1] * g + m1Q16[2] * b) / q16i64)
    let m = clampPosOklab((m1Q16[3] * r + m1Q16[4] * g + m1Q16[5] * b) / q16i64)
    let s = clampPosOklab((m1Q16[6] * r + m1Q16[7] * g + m1Q16[8] * b) / q16i64)
    let lc = icbrtQ16(l)
    let mc = icbrtQ16(m)
    let sc = icbrtQ16(s)
    return (
        (m2Q16[0] * lc + m2Q16[1] * mc + m2Q16[2] * sc) / q16i64,
        (m2Q16[3] * lc + m2Q16[4] * mc + m2Q16[5] * sc) / q16i64,
        (m2Q16[6] * lc + m2Q16[7] * mc + m2Q16[8] * sc) / q16i64
    )
}

@inline(__always)
private func oklabToLin1(_ bigL: Int64, _ a: Int64, _ b: Int64) -> (Int64, Int64, Int64) {
    let l_ = (q16i64 * bigL + m2iLA * a + m2iLB * b) / q16i64
    let m_ = (q16i64 * bigL + m2iMA * a + m2iMB * b) / q16i64
    let s_ = (q16i64 * bigL + m2iSA * a + m2iSB * b) / q16i64
    let l = cubeQ16(l_)
    let m = cubeQ16(m_)
    let s = cubeQ16(s_)
    return (
        (m1invQ16[0] * l + m1invQ16[1] * m + m1invQ16[2] * s) / q16i64,
        (m1invQ16[3] * l + m1invQ16[4] * m + m1invQ16[5] * s) / q16i64,
        (m1invQ16[6] * l + m1invQ16[7] * m + m1invQ16[8] * s) / q16i64
    )
}

// ── ZoneProfile + LookTransfer (SixFour.Spec.{ZoneProfile,LookTransfer}) ──────

@inline(__always)
private func zoneCenterL(_ nz: Int64, _ z: Int64) -> Int64 {
    return ((2 * z + 1) * q16i64) / (2 * nz) // @divTrunc, operands positive
}

@inline(__always)
private func meanAt(_ v: UnsafePointer<Int32>, _ z: Int64) -> Int64 {
    return Int64(v[Int(z)])
}

/// Piecewise-linear sample of the (a,b,chroma) target at lightness l, clamping at
/// the end zones. Mirrors SixFour.Spec.ZoneProfile.sampleZoneTargetQ16.
private func sampleZoneTarget(
    _ meanA: UnsafePointer<Int32>, _ meanB: UnsafePointer<Int32>, _ meanC: UnsafePointer<Int32>,
    _ nz: Int64, _ l: Int64
) -> (Int64, Int64, Int64) {
    if nz <= 1 || l <= zoneCenterL(nz, 0) {
        return (meanAt(meanA, 0), meanAt(meanB, 0), meanAt(meanC, 0))
    }
    if l >= zoneCenterL(nz, nz - 1) {
        return (meanAt(meanA, nz - 1), meanAt(meanB, nz - 1), meanAt(meanC, nz - 1))
    }
    var z: Int64 = 0
    while z < nz - 2 && l >= zoneCenterL(nz, z + 1) {
        z += 1
    }
    let lo = zoneCenterL(nz, z)
    let hi = zoneCenterL(nz, z + 1)
    let frac: Int64 = hi > lo ? ((l - lo) * q16i64) / (hi - lo) : 0
    func lerp(_ v0: Int64, _ v1: Int64, _ fr: Int64) -> Int64 {
        return v0 + ((v1 - v0) * fr) / q16i64 // @divTrunc
    }
    return (
        lerp(meanAt(meanA, z), meanAt(meanA, z + 1), frac),
        lerp(meanAt(meanB, z), meanAt(meanB, z + 1), frac),
        lerp(meanAt(meanC, z), meanAt(meanC, z + 1), frac)
    )
}

/// The chrominance-only look transform on one OKLab Q16 colour. KEEPS l. Mirrors
/// SixFour.Spec.LookTransfer.transferOklabQ16 byte-for-byte.
private func transferOklab(
    _ l: Int64,
    _ a: Int64,
    _ b: Int64,
    _ meanA: UnsafePointer<Int32>,
    _ meanB: UnsafePointer<Int32>,
    _ meanC: UnsafePointer<Int32>,
    _ nz: Int64,
    _ strength: Int64,
    _ chromaMin: Int64,
    _ chromaMax: Int64,
    _ polarity: Int64,
    _ chromaEps: Int64
) -> (Int64, Int64, Int64) {
    let t = sampleZoneTarget(meanA, meanB, meanC, nz, l)
    let targetC = t.2
    let ta = (t.0 * polarity) / q16i64
    let tb = (t.1 * polarity) / q16i64
    let aOut0 = (a * (q16i64 - strength) + ta * strength) / q16i64
    let bOut0 = (b * (q16i64 - strength) + tb * strength) / q16i64
    let curC = chromaQ16Native(aOut0, bOut0)
    let inC = chromaQ16Native(a, b)
    let cTargetBlended = (inC * (q16i64 - strength) + targetC * strength) / q16i64
    if curC < chromaEps {
        let dirC = chromaQ16Native(ta, tb)
        let safeDir = max(1, dirC)
        return (l, (ta * cTargetBlended) / safeDir, (tb * cTargetBlended) / safeDir)
    }
    let safeC = max(1, curC)
    let rawScale = (cTargetBlended * q16i64) / safeC
    let cScale = max(chromaMin, min(chromaMax, rawScale))
    return (l, (aOut0 * cScale) / q16i64, (bOut0 * cScale) / q16i64)
}

@inline(__always)
private func gridCoord(_ i: Int64, _ n: Int64) -> Int64 {
    if n <= 1 { return 0 }
    return (i * q16i64) / (n - 1) // @divTrunc, operands nonnegative
}

/// One cube voxel: grid coord → RED front-end → OKLab → look transfer → linear →
/// black lift → gamut compress → sRGB-encode (Q16). Mirrors
/// SixFour.Spec.CubeLut.cubeVoxelQ16.
private func cubeVoxel(
    _ ri: Int64,
    _ gi: Int64,
    _ bi: Int64,
    _ n: Int64,
    _ meanA: UnsafePointer<Int32>,
    _ meanB: UnsafePointer<Int32>,
    _ meanC: UnsafePointer<Int32>,
    _ nz: Int64,
    _ strength: Int64,
    _ chromaMin: Int64,
    _ chromaMax: Int64,
    _ polarity: Int64,
    _ chromaEps: Int64
) -> (Int64, Int64, Int64) {
    let lin = redDecodeToLinear(gridCoord(ri, n), gridCoord(gi, n), gridCoord(bi, n))
    let oklab = linToOklab1(lin.0, lin.1, lin.2)
    let graded = transferOklab(oklab.0, oklab.1, oklab.2, meanA, meanB, meanC, nz, strength, chromaMin, chromaMax, polarity, chromaEps)
    let linOut = oklabToLin1(graded.0, graded.1, graded.2)
    let comp = gamutCompress(applyBlackLift(linOut))
    return (srgbEncodeSample(comp.0), srgbEncodeSample(comp.1), srgbEncodeSample(comp.2))
}

// NOTE (integration, 2026-07-06): `s4_build_cube_q16` is exported by
// KernelsColor.swift (it shares the entire look-transfer helper chain there and
// is gated by lut_golden.json's full 5³ cube). This file's own copy was removed
// at merge to avoid the duplicate @_cdecl symbol; the private look/cube helpers
// above remain for the other kernels in this file.
