import Foundation
import simd

/// Shared Octree quantization core (Gervautz & Purgathofer 1988, OKLab).
///
/// `assign` is the inherently-sequential part — build the 8-bit-lattice octree,
/// greedily merge the smallest-count reducible node until ≤ K leaves, then walk
/// each pixel to its surviving leaf. It returns per-pixel cluster slots that are
/// IDENTICAL on the CPU oracle (`OctreeReference`) and the GPU pipeline
/// (`OctreePalettePipeline`) — both call this. The two paths differ only in how
/// they turn `(pixels, assignments)` into per-cluster (mean, Σ, count): CPU
/// `statsCPU` vs the `octreeStatsKernel`. So the partition never diverges and
/// parity is just fixed-point vs Double on the moments.
enum OctreeQuantizer {
    static let maxDepth: Int = 8

    /// Sequential tree core → per-pixel cluster slot in `[0, liveCount)`.
    static func assign(pixels: [SIMD3<Float>], K: Int) -> (assignments: [UInt16], liveCount: Int) {
        let pixelCount = pixels.count
        var pool: [Node] = [Node(depth: 0)]
        pool.reserveCapacity(min(pixelCount, 4096))

        for p in 0..<pixelCount {
            let lab = pixels[p]
            insert(pool: &pool,
                   L: quantizeL(lab.x), a: quantizeAB(lab.y), b: quantizeAB(lab.z))
        }

        var nLeaves = countLeaves(in: pool)
        while nLeaves > K {
            guard let parentIdx = findBestReducibleNode(pool: pool) else { break }
            // Merging m all-leaf children into their parent drops the leaf count
            // by (m − 1) — NOT 1. Tracking the true delta is essential: a stale
            // count exits the loop early with > K live leaves, which then
            // produces assignment slots ≥ K and an out-of-bounds cluster write.
            nLeaves -= mergeChildren(into: parentIdx, pool: &pool)
        }

        var leafNodeIdx: [Int] = []
        leafNodeIdx.reserveCapacity(K)
        for (i, n) in pool.enumerated() where n.isLeaf && n.count > 0 {
            leafNodeIdx.append(i)
        }
        var leafSlot = [Int: Int](minimumCapacity: leafNodeIdx.count)
        for (slot, nodeIdx) in leafNodeIdx.enumerated() { leafSlot[nodeIdx] = slot }

        var assignments = [UInt16](repeating: 0, count: pixelCount)
        for p in 0..<pixelCount {
            let lab = pixels[p]
            let leafNode = walkToLeaf(pool: pool,
                                      L: quantizeL(lab.x), a: quantizeAB(lab.y), b: quantizeAB(lab.z))
            assignments[p] = UInt16(leafSlot[leafNode] ?? 0)
        }
        return (assignments, leafNodeIdx.count)
    }

    /// Per-cluster (mean, Σ, count) + MSE from pixels + assignments — the CPU
    /// path (oracle). The GPU pipeline computes the same from `octreeStatsKernel`.
    static func statsCPU(pixels: [SIMD3<Float>], assignments: [UInt16], K: Int)
        -> (clusters: [ClusterStatistics.Cluster], mse: Float) {
        var count = [Double](repeating: 0, count: K)
        var sumL = [Double](repeating: 0, count: K), sumA = [Double](repeating: 0, count: K), sumB = [Double](repeating: 0, count: K)
        var sumLL = [Double](repeating: 0, count: K), sumAA = [Double](repeating: 0, count: K), sumBB = [Double](repeating: 0, count: K)
        var sumLA = [Double](repeating: 0, count: K), sumLB = [Double](repeating: 0, count: K), sumAB = [Double](repeating: 0, count: K)
        for p in 0..<pixels.count {
            let k = Int(assignments[p])
            let lab = pixels[p]
            let L = Double(lab.x), A = Double(lab.y), B = Double(lab.z)
            count[k] += 1
            sumL[k] += L; sumA[k] += A; sumB[k] += B
            sumLL[k] += L * L; sumAA[k] += A * A; sumBB[k] += B * B
            sumLA[k] += L * A; sumLB[k] += L * B; sumAB[k] += A * B
        }
        var clusters = [ClusterStatistics.Cluster](repeating: ClusterStatistics.Cluster(
            mean: .zero, covariance: ClusterStatistics.Cluster.emptyCovariance, count: 0), count: K)
        for k in 0..<K where count[k] > 0 {
            let inv = 1.0 / count[k]
            let mL = sumL[k] * inv, mA = sumA[k] * inv, mB = sumB[k] * inv
            let LL = max(0, sumLL[k] * inv - mL * mL)
            let aa = max(0, sumAA[k] * inv - mA * mA)
            let bb = max(0, sumBB[k] * inv - mB * mB)
            let La = sumLA[k] * inv - mL * mA
            let Lb = sumLB[k] * inv - mL * mB
            let ab = sumAB[k] * inv - mA * mB
            clusters[k] = ClusterStatistics.Cluster(
                mean: SIMD3<Float>(Float(mL), Float(mA), Float(mB)),
                covariance: simd_float3x3(columns: (
                    SIMD3<Float>(Float(LL), Float(La), Float(Lb)),
                    SIMD3<Float>(Float(La), Float(aa), Float(ab)),
                    SIMD3<Float>(Float(Lb), Float(ab), Float(bb)))),
                count: UInt32(count[k]))
        }
        var sse: Double = 0
        for p in 0..<pixels.count {
            let d = pixels[p] - clusters[Int(assignments[p])].mean
            sse += Double(simd_dot(d, d))
        }
        return (clusters, Float(sse / Double(pixels.count)))
    }

    // MARK: - Quantization (must match OctreeShaders.metal)

    @inline(__always) static func quantizeL(_ v: Float) -> UInt8 {
        UInt8(min(255, max(0, Int(v * 256))))
    }
    @inline(__always) static func quantizeAB(_ v: Float) -> UInt8 {
        UInt8(min(255, max(0, Int((v + 0.5) * 256))))
    }

    // MARK: - Node + tree (lifted verbatim from the former OctreeExtractor)

    /// Octree node. Only `count` + structure matter here: the greedy merge is
    /// count-based, and per-cluster (mean, Σ) are computed downstream from the
    /// pixel→slot assignments (CPU `statsCPU` or `octreeStatsKernel`), so the
    /// node carries no colour sums.
    private struct Node {
        var children: (Int, Int, Int, Int, Int, Int, Int, Int) = (-1,-1,-1,-1,-1,-1,-1,-1)
        var count: UInt32 = 0
        var depth: Int = 0
        var isLeaf: Bool = true
    }

    @inline(__always)
    private static func childIndex(of node: Node, octant: Int) -> Int {
        switch octant {
        case 0: return node.children.0; case 1: return node.children.1
        case 2: return node.children.2; case 3: return node.children.3
        case 4: return node.children.4; case 5: return node.children.5
        case 6: return node.children.6; default: return node.children.7
        }
    }
    @inline(__always)
    private static func setChildIndex(of node: inout Node, octant: Int, value: Int) {
        switch octant {
        case 0: node.children.0 = value; case 1: node.children.1 = value
        case 2: node.children.2 = value; case 3: node.children.3 = value
        case 4: node.children.4 = value; case 5: node.children.5 = value
        case 6: node.children.6 = value; default: node.children.7 = value
        }
    }
    @inline(__always)
    private static func octant(L: UInt8, a: UInt8, b: UInt8, depth d: Int) -> Int {
        let shift = 7 - d
        let bL = (Int(L) >> shift) & 1
        let bA = (Int(a) >> shift) & 1
        let bB = (Int(b) >> shift) & 1
        return (bL << 2) | (bA << 1) | bB
    }

    private static func insert(pool: inout [Node], L: UInt8, a: UInt8, b: UInt8) {
        var nodeIdx = 0
        for d in 0..<maxDepth {
            let octr = octant(L: L, a: a, b: b, depth: d)
            let childIdx = childIndex(of: pool[nodeIdx], octant: octr)
            if childIdx == -1 {
                let newIdx = pool.count
                pool.append(Node(depth: d + 1))
                setChildIndex(of: &pool[nodeIdx], octant: octr, value: newIdx)
                pool[nodeIdx].isLeaf = false
                nodeIdx = newIdx
            } else {
                nodeIdx = childIdx
            }
        }
        pool[nodeIdx].count &+= 1
    }

    private static func walkToLeaf(pool: [Node], L: UInt8, a: UInt8, b: UInt8) -> Int {
        var nodeIdx = 0
        for d in 0..<maxDepth {
            if pool[nodeIdx].isLeaf { return nodeIdx }
            let octr = octant(L: L, a: a, b: b, depth: d)
            let childIdx = childIndex(of: pool[nodeIdx], octant: octr)
            if childIdx == -1 { return nodeIdx }
            nodeIdx = childIdx
        }
        return nodeIdx
    }

    private static func countLeaves(in pool: [Node]) -> Int {
        var n = 0
        for node in pool where node.isLeaf && node.count > 0 { n += 1 }
        return n
    }

    private static func findBestReducibleNode(pool: [Node]) -> Int? {
        var bestIdx: Int? = nil
        var bestCount = UInt32.max
        var bestDepth = -1
        for (i, node) in pool.enumerated() {
            if node.isLeaf { continue }
            var allLeaf = true
            var combined: UInt32 = 0
            var anyChild = false
            for o in 0..<8 {
                let c = childIndex(of: node, octant: o)
                if c == -1 { continue }
                anyChild = true
                if !pool[c].isLeaf { allLeaf = false; break }
                combined &+= pool[c].count
            }
            if !allLeaf || !anyChild { continue }
            if node.depth > bestDepth || (node.depth == bestDepth && combined < bestCount) {
                bestIdx = i
                bestCount = combined
                bestDepth = node.depth
            }
        }
        return bestIdx
    }

    /// Fold all live (all-leaf) children into `parentIdx`, returning the leaf
    /// count reduction `(liveChildren − 1)`: the children (all leaves) vanish
    /// and the previously-internal parent becomes one leaf.
    private static func mergeChildren(into parentIdx: Int, pool: inout [Node]) -> Int {
        var combinedCount = pool[parentIdx].count
        var liveChildren = 0
        for o in 0..<8 {
            let c = childIndex(of: pool[parentIdx], octant: o)
            if c == -1 { continue }
            liveChildren += 1
            combinedCount &+= pool[c].count
            pool[c].isLeaf = false
            pool[c].count = 0
            setChildIndex(of: &pool[parentIdx], octant: o, value: -1)
        }
        pool[parentIdx].count = combinedCount
        pool[parentIdx].isLeaf = true
        return max(0, liveChildren - 1)
    }
}
