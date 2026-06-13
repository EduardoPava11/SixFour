import simd

/// 64 frames = 16 RGBT groups of 4 (byte-exact twin of `Spec.GroupRGBT`). **Group-SELECT** —
/// pooling only the selected groups before the maximin collapse — is the load-bearing LAB
/// choice: WHICH of the 16 groups feed the one global palette. Pure list ops; the collapse
/// itself is the existing `FarthestPointCollapse`.
enum GroupRGBT {
    /// Frames per RGBT group (R, G, B, T).
    static let groupSize = 4
    /// Groups in a full 64-frame burst.
    static let numGroups = 16

    /// Chunk frames into consecutive groups of 4. `flatten ∘ groupsOf4 == identity`.
    static func groupsOf4<T>(_ frames: [T]) -> [[T]] {
        guard !frames.isEmpty else { return [] }
        return stride(from: 0, to: frames.count, by: groupSize).map {
            Array(frames[$0 ..< min($0 + groupSize, frames.count)])
        }
    }

    /// Keep only the frames belonging to SELECTED groups (`mask[g] == true`), original order.
    /// A mask shorter than the group count excludes the unmasked tail; longer ignores extras.
    static func selectedFrames<T>(_ mask: [Bool], _ frames: [T]) -> [T] {
        zip(mask, groupsOf4(frames)).flatMap { keep, grp in keep ? grp : [] }
    }

    /// The all-selected mask for a frame list (every group in).
    static func allSelected<T>(_ frames: [T]) -> [Bool] {
        [Bool](repeating: true, count: groupsOf4(frames).count)
    }
}
