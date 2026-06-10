import simd

/// On-device look taxonomy — hand port of `SixFour.Spec.LookCategory`, pinned to
/// `LookCategoryContract` by `LookCategoryGoldenTests`. The first visible surface of
/// the personalization spine: `classify` = nearest OKLab prototype (Euclidean, ties →
/// lowest index, mirroring the spec's left-biased `minimumBy`); `descriptor` = a
/// palette's mean OKLab. The learned per-user step (`Spec.LookCategory.btGradStep`)
/// lands once the look-net forward pass is wired.
enum SFLookCategory {

    /// Category names in classify tie-break order (from the generated contract).
    static var names: [String] { LookCategoryContract.names }

    /// Nearest-prototype category index for an OKLab descriptor `(L, a, b)`.
    static func classify(_ d: SIMD3<Float>) -> Int {
        var best = 0
        var bestDist = Float.greatestFiniteMagnitude
        for (i, p) in LookCategoryContract.prototypes.enumerated() {
            let dl = d.x - Float(p.x)
            let da = d.y - Float(p.y)
            let db = d.z - Float(p.z)
            let dist = dl * dl + da * da + db * db
            if dist < bestDist {        // strict < ⇒ ties keep the lowest index
                bestDist = dist
                best = i
            }
        }
        return best
    }

    /// A palette's look descriptor: the component-wise mean OKLab; empty ⇒ neutral
    /// centre `(0.5, 0, 0)` (so the function is total — matches the spec).
    static func descriptor(_ oklab: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !oklab.isEmpty else { return SIMD3<Float>(0.5, 0, 0) }
        var sum = SIMD3<Float>(0, 0, 0)
        for c in oklab { sum += c }
        return sum / Float(oklab.count)
    }

    /// The look category NAME of a whole palette (descriptor → classify → name).
    static func name(_ oklab: [SIMD3<Float>]) -> String {
        names[classify(descriptor(oklab))]
    }
}
