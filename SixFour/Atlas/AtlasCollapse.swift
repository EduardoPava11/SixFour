import Foundation
import simd

/// COLOR ATLAS — the curated palette at the `PaletteCollapse` seam
/// (docs/COLOR-ATLAS.md §8 Phase D).
///
/// `AtlasCollapse` is the protocol's atlas implementation: when a curated
/// global palette exists it IS the collapse result (the user's decision replaces
/// the maximin floor); otherwise it degrades silently to the deterministic
/// `FarthestPointCollapse` (the tiered-fallthrough discipline — every tier
/// deterministic, the fallthrough total). The render-path injection itself goes
/// through `DeterministicRenderer.renderGlobalPalette(curatedLeavesQ16:)` so
/// dither / significance rescue / sRGB / gifAssemble / SHA-256 all run
/// downstream unchanged (WYSIWYG: the protocol remains the display/editor seam).
struct AtlasCollapse: PaletteCollapse {
    /// The curated 256 Q16 leaves (the Compare winner with anchors substituted).
    let curatedLeavesQ16: [SIMD3<Int32>]

    func collapse(perFramePalettes: [[OKLabQ16]], k: Int) -> CollapsedPalette {
        guard curatedLeavesQ16.count == k else {
            return FarthestPointCollapse().collapse(perFramePalettes: perFramePalettes, k: k)
        }
        // `chosenIndices` is a WITNESS for the maximin golden only (see
        // `CollapsedPalette`); a curated palette is not chosen from the pooled
        // cloud, so the witness is empty by definition.
        return CollapsedPalette(leaves: curatedLeavesQ16, chosenIndices: [])
    }
}

/// The ONE handoff point between the curation UI (writer: `AtlasState.choose`)
/// and the render driver (reader: `CaptureViewModel.renderDeterministicGlobal`,
/// gated by `AppSettings.colorAtlasEnabled`). Persisted in `UserDefaults` as the
/// leaves' little-endian Q16 bytes (256×3×4 = 3072 B) so a curated palette
/// survives launches — curation happens in review, the render happens on the
/// NEXT capture.
@MainActor
final class AtlasPaletteStore {
    static let shared = AtlasPaletteStore()

    private static let key = "sixfour.colorAtlas.curated.v1"
    private let defaults: UserDefaults
    private var cached: [SIMD3<Int32>]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cached = Self.decode(defaults.data(forKey: Self.key))
    }

    /// The curated global palette (Q16 OKLab leaves), or nil when none has been
    /// chosen yet. Setting persists; setting nil clears.
    var curatedLeavesQ16: [SIMD3<Int32>]? {
        get { cached }
        set {
            cached = newValue
            if let leaves = newValue {
                defaults.set(Self.encode(leaves), forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }

    /// Leaves → little-endian Int32 triples.
    private static func encode(_ leaves: [SIMD3<Int32>]) -> Data {
        var data = Data(capacity: leaves.count * 12)
        for c in leaves {
            for v in [c.x, c.y, c.z] {
                withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    /// Bytes → leaves; nil for absent/odd-sized data (corruption ⇒ no palette,
    /// the render falls back to the deterministic collapse).
    private static func decode(_ data: Data?) -> [SIMD3<Int32>]? {
        guard let data, !data.isEmpty, data.count % 12 == 0 else { return nil }
        let n = data.count / 12
        var leaves = [SIMD3<Int32>]()
        leaves.reserveCapacity(n)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0 ..< n {
                let base = i * 12
                let x = Int32(littleEndian: raw.loadUnaligned(fromByteOffset: base, as: Int32.self))
                let y = Int32(littleEndian: raw.loadUnaligned(fromByteOffset: base + 4, as: Int32.self))
                let z = Int32(littleEndian: raw.loadUnaligned(fromByteOffset: base + 8, as: Int32.self))
                leaves.append(SIMD3<Int32>(x, y, z))
            }
        }
        return leaves
    }
}
