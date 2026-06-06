import Testing
import Foundation
import simd
@testable import SixFour

/// Byte-exact parity for the surface color kernel `SurfaceColor.oklabQ16ToSrgb8`.
///
/// The kernel is a hand-written SIMD Swift port of the Zig core's
/// `s4_palette_oklab_to_srgb8` (Native/src/kernels.zig), which itself mirrors
/// `SixFour.Spec.ColorFixed.oklabToSrgb8Q16` and `@embedFile`s the same
/// `gamma_lut.bin`. These tests assert the Swift result is byte-identical to
/// the Zig core across a deterministic spread of Q16 OKLab inputs — so the
/// three implementations (Haskell spec, Zig core, Swift surface) all agree.
struct SurfaceColorParityTests {

    /// A deterministic, structured set of Q16 OKLab inputs: corners (the
    /// black/white anchors the Zig test pins), a neutral L ramp (a = b = 0),
    /// chroma sweeps, and a pseudo-random spread from an LCG so the list is
    /// reproducible. L ∈ [0, 65536]; a, b ∈ a moderate signed range so the
    /// l'm's' cubes stay inside the clamp the Zig core uses.
    static func goldenOklabInputsQ16() -> [SIMD3<Int32>] {
        let full: Int32 = 1 << 16
        var inputs: [SIMD3<Int32>] = []

        // Corners / anchors.
        inputs.append(SIMD3(0, 0, 0))           // black
        inputs.append(SIMD3(full, 2, 0))        // white (from the forward golden)
        inputs.append(SIMD3(full, 0, 0))
        inputs.append(SIMD3(full / 2, 0, 0))

        // Neutral L ramp (a = b = 0).
        for i in 1...14 {
            let v = Int32(i) * full / 15
            inputs.append(SIMD3(v, 0, 0))
        }

        // Chroma sweeps at mid-L: vary a then b across a moderate signed range.
        let midL = full / 2
        for k in stride(from: -12000, through: 12000, by: 4000) {
            inputs.append(SIMD3(midL, Int32(k), 0))
            inputs.append(SIMD3(midL, 0, Int32(k)))
            inputs.append(SIMD3(midL, Int32(k), Int32(-k)))
        }

        // Deterministic LCG spread (numerical-recipes constants), 48 triples.
        var state: UInt64 = 0x6d2b79f5
        @inline(__always) func next(_ mod: Int32) -> Int32 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let hi = Int64((state >> 33) & 0x7FFF_FFFF)
            return Int32(hi % Int64(mod))
        }
        for _ in 0..<48 {
            let l = next(full + 1)               // [0, 65536]
            let a = next(40001) - 20000          // [-20000, 20000]
            let b = next(40001) - 20000
            inputs.append(SIMD3(l, a, b))
        }
        return inputs
    }

    /// Swift `SurfaceColor.oklabQ16ToSrgb8` == Zig `s4_palette_oklab_to_srgb8`,
    /// byte-for-byte, across the whole golden set (scalar path).
    @Test func swiftMatchesZigScalar() throws {
        let inputs = Self.goldenOklabInputsQ16()
        // Flatten to the Zig core's interleaved Int32 [L,a,b,...] layout.
        var flat: [Int32] = []
        flat.reserveCapacity(inputs.count * 3)
        for v in inputs { flat.append(v.x); flat.append(v.y); flat.append(v.z) }

        let zig = try #require(
            SixFourNative.paletteToSRGB8(centroidsQ16: flat, k: inputs.count),
            "Zig s4_palette_oklab_to_srgb8 returned nil")
        #expect(zig.count == inputs.count * 3)

        for (i, lab) in inputs.enumerated() {
            let sw = SurfaceColor.oklabQ16ToSrgb8(lab)
            let zr = zig[i * 3 + 0], zg = zig[i * 3 + 1], zb = zig[i * 3 + 2]
            #expect(sw.x == zr && sw.y == zg && sw.z == zb,
                    "mismatch @\(i) lab=\(lab): swift=(\(sw.x),\(sw.y),\(sw.z)) zig=(\(zr),\(zg),\(zb))")
        }
    }

    /// The batched SIMD variant agrees with the Zig core element-for-element.
    @Test func swiftBatchedMatchesZig() throws {
        let inputs = Self.goldenOklabInputsQ16()
        var flat: [Int32] = []
        for v in inputs { flat.append(v.x); flat.append(v.y); flat.append(v.z) }

        let zig = try #require(
            SixFourNative.paletteToSRGB8(centroidsQ16: flat, k: inputs.count))
        let batched = SurfaceColor.oklabQ16ToSrgb8(inputs)
        #expect(batched.count == inputs.count)
        for i in inputs.indices {
            #expect(batched[i].x == zig[i * 3 + 0]
                 && batched[i].y == zig[i * 3 + 1]
                 && batched[i].z == zig[i * 3 + 2],
                 "batched mismatch @\(i)")
        }
    }

    /// The Haskell-pinned anchors (Zig test): black → (0,0,0), white → ≥254.
    @Test func anchorsMatchHaskellGolden() {
        let black = SurfaceColor.oklabQ16ToSrgb8(SIMD3(0, 0, 0))
        #expect(black.x == 0 && black.y == 0 && black.z == 0)

        let white = SurfaceColor.oklabQ16ToSrgb8(SIMD3(65535, 2, 0))
        #expect(white.x >= 254 && white.y >= 254 && white.z >= 254,
                "white = (\(white.x),\(white.y),\(white.z))")
    }

    /// The gamma LUT loaded by `SurfaceColor` is the full 65537-entry table
    /// (i.e. the bundle resource resolved — the fallback all-zero table would
    /// fail the white anchor above, but pin the size here too).
    @Test func gammaLutLoaded() {
        #expect(SurfaceColor.gammaLut.count == 65537)
        #expect(SurfaceColor.gammaLut[65536] == 255, "top of LUT must be opaque white")
    }
}
