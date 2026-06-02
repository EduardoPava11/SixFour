import simd

/// The three radix GENOMES the 16²/4⁴/2⁸ controls select — the form the look-NN
/// occupies. `project` maps the collapsed 256 OKLab leaves onto the genome subspace
/// for a `PaletteBranching` and returns the reconstructed 256 leaves (the GIF colour
/// table the radix yields). "Set the control = set the genome": the radix choice
/// reaches the collapse output here, before any trained NN exists.
///
/// - 16² (`.b16`) → **Flat** (768): identity — the maximin leaves unchanged.
/// - 4⁴ (`.b4`)  → **Quad4** (513): the opponent-quadrant projection (lossy).
/// - 2⁸ (`.b2`)  → **σ-pair** (384): the σ-mirror projection (lossy).
///
/// Quad4 and σ-pair are LOSSY (they shift colours) — the deliberate inductive bias
/// of those branchings. Hand-written port of `Spec.Quad4` + `Spec.SigmaPairHead`,
/// gated within tolerance against `GenomeGolden` (`GenomeGoldenTests`).
enum BranchedPalette {

    static func project(_ leaves: [SIMD3<Double>], branching: PaletteBranching) -> [SIMD3<Double>] {
        switch branching {
        case .b16: return leaves                                   // Flat: identity
        case .b4:  return Quad4.reconstruct(Quad4.analyze(leaves)) // opponent-quadrant
        case .b2:  return sigmaPairProject(leaves)                 // σ-mirror
        }
    }

    // MARK: Q16 EXACT integer projections (byte-exact cross-device)

    /// The BYTE-EXACT integer (Q16) genome projection — the shipped path. Unlike
    /// `project` (Double, tolerance-gated), this is exact integer math: it reproduces
    /// the Haskell `Spec.Quad4Fixed` / `Spec.SigmaPairFixed` golden EXACTLY, so a 4⁴
    /// or 2⁸ GIFB global colour table is byte-exact across devices (Flat 16² already
    /// is). Quad4 is a pure-Swift integer port; σ-pair reuses the owned Zig `s4_haar`.
    static func projectQ16(_ leaves: [SIMD3<Int32>], branching: PaletteBranching) -> [SIMD3<Int32>] {
        switch branching {
        case .b16: return leaves                       // Flat: identity
        case .b4:  return quad4ProjectQ16(leaves)      // exact ÷4 opponent-quadrant
        case .b2:  return sigmaPairProjectQ16(leaves)  // integer Haar + exact σ-reflect
        }
    }

    /// Exact integer Quad4 projection (mirrors `Spec.Quad4Fixed.quad4ProjectFixed`).
    /// `÷4` is FLOOR division (`>> 2`, arithmetic shift) to match the Haskell `div`;
    /// exact on the Quad4 subspace (children sums are multiples of 4).
    private static func quad4ProjectQ16(_ leaves: [SIMD3<Int32>]) -> [SIMD3<Int32>] {
        @inline(__always) func div4(_ v: SIMD3<Int32>) -> SIMD3<Int32> {
            SIMD3<Int32>(v.x >> 2, v.y >> 2, v.z >> 2)   // arithmetic shift == floor ÷4
        }
        // analyze (÷4 reduce), offsets coarsest-first
        var cur = leaves
        var acc: [[(SIMD3<Int32>, SIMD3<Int32>)]] = []
        while cur.count > 1 {
            var parents: [SIMD3<Int32>] = []
            var offs: [(SIMD3<Int32>, SIMD3<Int32>)] = []
            var i = 0
            while i + 3 < cur.count {
                let c0 = cur[i], c1 = cur[i + 1], c2 = cur[i + 2], c3 = cur[i + 3]
                parents.append(div4(c0 &+ c1 &+ c2 &+ c3))
                offs.append((div4((c0 &+ c1) &- (c2 &+ c3)), div4((c0 &- c1) &+ (c2 &- c3))))
                i += 4
            }
            acc.insert(offs, at: 0)
            cur = parents
        }
        // reconstruct: child = parent ± δ₁ ± δ₂, order (++,+-,-+,--)
        var nodes = [cur.first ?? SIMD3<Int32>(repeating: 0)]
        for offs in acc {
            var next: [SIMD3<Int32>] = []
            next.reserveCapacity(nodes.count * 4)
            for (parent, d) in zip(nodes, offs) {
                let pp = parent &+ d.0, pm = parent &- d.0
                next.append(pp &+ d.1); next.append(pp &- d.1)
                next.append(pm &+ d.1); next.append(pm &- d.1)
            }
            nodes = next
        }
        return nodes
    }

    /// Exact integer σ-pair projection (mirrors `Spec.SigmaPairFixed`): the 128 even
    /// leaves through the owned Zig integer Haar (`s4_haar`), interleaved with their
    /// exact integer σ-reflection σ(L,a,b)=(L,−a,−b).
    private static func sigmaPairProjectQ16(_ leaves: [SIMD3<Int32>]) -> [SIMD3<Int32>] {
        var evens: [SIMD3<Int32>] = []
        evens.reserveCapacity(leaves.count / 2)
        var i = 0
        while i < leaves.count { evens.append(leaves[i]); i += 2 }
        guard let (root, offs) = SixFourNative.haarAnalyze(leaves: evens),
              let ci = SixFourNative.haarReconstruct(root: root, offsets: offs) else {
            return leaves
        }
        var out: [SIMD3<Int32>] = []
        out.reserveCapacity(ci.count * 2)
        for c in ci {
            out.append(c)
            out.append(SIMD3<Int32>(c.x, 0 &- c.y, 0 &- c.z))   // σ-reflect (exact)
        }
        return out
    }

    // MARK: σ-pair (2⁸) — mirrors Spec.SigmaPairHead.{analyzePaired,reconstructPaired}

    /// `reconstructPaired ∘ analyzePaired`: take the 128 even leaves as the cᵢ
    /// generators, Haar-analyse→reconstruct them (depth-7), then interleave each cᵢ
    /// with its σ-reflection σ(L,a,b)=(L,−a,−b). The odd leaves are regenerated as
    /// σ(cᵢ), so the result is σ-symmetric by construction.
    private static func sigmaPairProject(_ leaves: [SIMD3<Double>]) -> [SIMD3<Double>] {
        var evens: [SIMD3<Double>] = []
        evens.reserveCapacity(leaves.count / 2)
        var i = 0
        while i < leaves.count { evens.append(leaves[i]); i += 2 }

        let ci = PaletteHaarTree.reconstruct(PaletteHaarTree.analyze(evens))
        var out: [SIMD3<Double>] = []
        out.reserveCapacity(ci.count * 2)
        for c in ci {
            out.append(c)
            out.append(SIMD3<Double>(c.x, -c.y, -c.z))   // σ-reflect
        }
        return out
    }
}

/// The depth-4 4-ary opponent-quadrant tree (`Spec.Quad4`): each non-leaf node has
/// two OKLab offsets `(δ₁, δ₂)`; the four children are `parent ± δ₁ ± δ₂` in fixed
/// `(+ +),(+ −),(− +),(− −)` order. 513 DOF over 256 leaves.
enum Quad4 {
    typealias Node = (root: SIMD3<Double>, levels: [[(SIMD3<Double>, SIMD3<Double>)]])

    /// Forward 4-ary analyse (mirrors `Spec.Quad4.quad4Analyze`): per quad,
    /// `parent = mean`, `δ₁ = ((c₀+c₁)−(c₂+c₃))/4`, `δ₂ = ((c₀−c₁)+(c₂−c₃))/4`;
    /// recurse on the parents. Offsets accumulated coarsest-first.
    static func analyze(_ leaves: [SIMD3<Double>]) -> Node {
        var cur = leaves
        var acc: [[(SIMD3<Double>, SIMD3<Double>)]] = []
        while cur.count > 1 {
            var parents: [SIMD3<Double>] = []
            var offs: [(SIMD3<Double>, SIMD3<Double>)] = []
            var i = 0
            while i + 3 < cur.count {
                let c0 = cur[i], c1 = cur[i + 1], c2 = cur[i + 2], c3 = cur[i + 3]
                parents.append((c0 + c1 + c2 + c3) * 0.25)
                offs.append((((c0 + c1) - (c2 + c3)) * 0.25, ((c0 - c1) + (c2 - c3)) * 0.25))
                i += 4
            }
            acc.insert(offs, at: 0)   // coarsest level ends up first
            cur = parents
        }
        return (cur.first ?? SIMD3<Double>(repeating: 0), acc)
    }

    /// child(parent, δ₁, δ₂, quadrant) in the fixed `(++),(+−),(−+),(−−)` order.
    static func child(_ p: SIMD3<Double>, _ d1: SIMD3<Double>, _ d2: SIMD3<Double>, _ q: Int) -> SIMD3<Double> {
        switch q {
        case 0:  return p + d1 + d2
        case 1:  return p + d1 - d2
        case 2:  return p - d1 + d2
        default: return p - d1 - d2
        }
    }

    /// Inverse: expand the tree into 256 leaves (`Spec.Quad4.reconstruct`).
    static func reconstruct(_ node: Node) -> [SIMD3<Double>] {
        var nodes = [node.root]
        for offs in node.levels {
            var next: [SIMD3<Double>] = []
            next.reserveCapacity(nodes.count * 4)
            for (parent, d) in zip(nodes, offs) {
                next.append(child(parent, d.0, d.1, 0))
                next.append(child(parent, d.0, d.1, 1))
                next.append(child(parent, d.0, d.1, 2))
                next.append(child(parent, d.0, d.1, 3))
            }
            nodes = next
        }
        return nodes
    }
}

/// Navigation over the 4⁴ opponent-quadrant genome tree for `Quad4DrillView` — pure,
/// so the drill math is unit-tested independently of the SwiftUI presentation.
enum Quad4Nav {
    static let depth = 4

    /// 4-ary node index of a path (positional, base 4): `Σ pathᵢ·4^(n−1−i)`.
    static func nodeIndex(_ path: ArraySlice<Int>) -> Int {
        path.reduce(0) { $0 * 4 + $1 }
    }

    /// The reconstructed colour at `path` (the node's parent) plus its four
    /// opponent-quadrant children. At a full-depth path the node IS a leaf and
    /// `children == [parent]`. `tree = Quad4.analyze(leaves)` (levels coarsest-first).
    static func nodeAndChildren(_ tree: Quad4.Node, path: [Int])
        -> (parent: SIMD3<Double>, children: [SIMD3<Double>]) {
        var parent = tree.root
        for level in 0 ..< path.count where level < tree.levels.count {
            let idx = nodeIndex(path.prefix(level))
            let (d1, d2) = tree.levels[level][idx]
            parent = Quad4.child(parent, d1, d2, path[level])
        }
        if path.count < tree.levels.count {
            let idx = nodeIndex(path[...])
            let (d1, d2) = tree.levels[path.count][idx]
            return (parent, (0 ..< 4).map { Quad4.child(parent, d1, d2, $0) })
        }
        return (parent, [parent])   // leaf
    }

    /// The 256-leaf index a full-depth path addresses (= its 4-ary number).
    static func leafIndex(_ path: [Int]) -> Int { nodeIndex(path[...]) }
}
