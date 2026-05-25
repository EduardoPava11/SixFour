import Foundation
import simd

/// Forces **strict per-frame surjectivity** on a dithered frame: every one
/// of the `K` palette slots must be referenced by at least one pixel, so the
/// frame can join a `CompleteVoxelVolume` (see `StageContract.swift`).
///
/// Why it's needed: Stage A Lloyd k-means with `K = 256` on 4096 pixels
/// routinely leaves **dead clusters** on low-variance frames — a centroid
/// occupies a palette slot that no pixel maps to after error-diffusion
/// dithering. That is an "empty slot." A pure encode-time gate would *reject*
/// such frames; instead we repair them.
///
/// How: the **furthest-point reseeding** heuristic from classic k-means
/// empty-cluster handling. For each empty slot we relocate its dead centroid
/// onto the current worst-fit ("donor") pixel and reassign that pixel to the
/// slot. This is doubly good — it fills the slot *and* drops reconstruction
/// error at the donated pixel (its new colour is an exact match).
///
/// Termination & soundness: a donor is only taken from a slot that still has
/// a surplus (count > 1), so repair never creates a *new* empty slot. Because
/// `pixelCount (4096) ≥ K (256)`, the surplus pool (`pixelCount − usedSlots`)
/// always covers the empty slots, so the rescue cannot fail. The degenerate
/// all-identical frame is handled too: every donated slot gets the same
/// colour, which is still surjective (256 distinct indices, possibly
/// duplicate colours) — exactly the "all 256 colours used per frame" contract.
enum PerFrameSurjectivity {

    /// Returns `(palette, indices)` where `indices` provably uses every value
    /// in `0..<K`. Slots already covered are untouched; only dead slots move.
    static func rescue(
        palette: [SIMD3<Float>],
        indices: [UInt8],
        pixels: [SIMD3<Float>],
        K: Int = SixFourShape.K
    ) -> (palette: [SIMD3<Float>], indices: [UInt8]) {
        precondition(palette.count == K, "rescue: palette must have K entries")
        precondition(indices.count == pixels.count, "rescue: indices/pixels length mismatch")
        precondition(pixels.count >= K, "rescue: need ≥ K pixels to cover K slots")

        var counts = [Int](repeating: 0, count: K)
        for ix in indices { counts[Int(ix)] += 1 }

        var unused: [Int] = []
        unused.reserveCapacity(K)
        for k in 0..<K where counts[k] == 0 { unused.append(k) }
        if unused.isEmpty { return (palette, indices) }   // already surjective — common, fast path

        // Donor candidates: pixels ordered by current reconstruction error,
        // worst first. Donating a high-error pixel to a fresh slot is exactly
        // where a new colour helps most.
        let order = Array(0..<pixels.count).sorted { lhs, rhs in
            sqDist(pixels[lhs], palette[Int(indices[lhs])]) >
            sqDist(pixels[rhs], palette[Int(indices[rhs])])
        }

        var pal = palette
        var idx = indices
        var cursor = 0
        for u in unused {
            // Walk down the worst-fit list to the next pixel whose current
            // slot has a surplus, so donating it won't empty that slot.
            while cursor < order.count {
                let p = order[cursor]
                cursor += 1
                let from = Int(idx[p])
                if counts[from] > 1 {
                    counts[from] -= 1
                    pal[u] = pixels[p]      // dead centroid → exact donor colour
                    idx[p] = UInt8(u)
                    counts[u] = 1
                    break
                }
            }
        }
        return (pal, idx)
    }

    @inline(__always)
    private static func sqDist(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return simd_dot(d, d)
    }
}
