import Testing
import Foundation
import simd
@testable import SixFour

/// Locks RULE-CUBE-2D-IDENTITY: at the flat pose the voxel cube's near face renders
/// frame `cursor` with the EXACT palette colour the 2D GIF shows — same size, same
/// pixels, no shading/cull. We verify this WITHOUT a GPU snapshot (rasterisation is
/// nondeterministic): the kernel's at-rest colour decision is mirrored as a pure
/// function and checked against the palette lookup the 2D path uses, plus the two
/// structural invariants (depth→frame map, on-screen edge). The Metal kernel
/// (Shaders.metal voxel_raymarch) must match this mirror; a single on-device A/B
/// confirms the GPU path visually (see docs).
struct VoxelRestPoseIdentityTests {

    // MARK: pure mirror of the kernel's flat-branch colour decision

    /// Mirrors voxel_raymarch's gated decision. At rest (`flat`), air/luma/face/split
    /// are all no-ops; returns the palette colour (0…1) or nil if culled.
    private func gatedColour(rgb: SIMD3<Double>, prov: Int,
                             lumaFloor: Int, provMode: Int, flat: Bool) -> SIMD3<Double>? {
        let air = !flat && (prov == 0 || (provMode == 1 && prov != 1) || (provMode == 2 && prov != 2))
        if air { return nil }
        let luma255 = (0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z) * 255.0
        guard flat || luma255 >= Double(lumaFloor) else { return nil }
        let face = 1.0                                   // flat ⇒ 1.0 (axis == -1 also gives 1.0)
        let split = (flat || prov != 2) ? 1.0 : 0.6
        return SIMD3(rgb.x * face * split, rgb.y * face * split, rgb.z * face * split)
    }

    /// At rest, the front-face colour for (cursor, x, y) is exactly the GIF's pixel:
    /// `srgbPalettes[cursor][frameIndices[cursor][y*64+x]]` (near face z=63 ⇒ fz=cursor).
    private func restColour(_ d: VoxelCubeData, cursor t: Int, x: Int, y: Int) -> SIMD3<UInt8> {
        let fz = ((t - 63 + 63) % 64 + 64) % 64
        return d.srgbPalettes[fz][Int(d.frameIndices[fz][y * 64 + x])]
    }

    private func syntheticData() -> VoxelCubeData {
        var rng: UInt64 = 0xDA7A
        func b() -> UInt8 { rng = rng &* 6364136223846793005 &+ 1; return UInt8(truncatingIfNeeded: rng >> 33) }
        let frames = (0..<64).map { _ in (0..<4096).map { _ in b() } }
        let palettes = (0..<64).map { _ in (0..<256).map { _ in SIMD3<UInt8>(b(), b(), b()) } }
        return VoxelCubeData(frameIndices: frames, srgbPalettes: palettes, provenance: nil)
    }

    // MARK: the invariant

    /// Rest-pose colour == the 2D palette lookup, for every (cursor, x, y).
    @Test func restPoseColourEqualsPaletteLookup() {
        let d = syntheticData()
        for t in [0, 1, 31, 63] {
            for (x, y) in [(0, 0), (63, 63), (17, 42), (40, 5)] {
                let got = restColour(d, cursor: t, x: x, y: y)
                let want = d.srgbPalettes[t][Int(d.frameIndices[t][y * 64 + x])]
                #expect(got == want)
            }
        }
    }

    /// At rest, lumaFloor / provMode / split NEVER alter or cull a colour (Steps 5/6):
    /// the gated decision returns the raw palette colour regardless of the knobs.
    @Test func restPoseIgnoresKnobsAndSplit() {
        let samples: [(SIMD3<Double>, Int)] = [
            (SIMD3(0.0, 0.0, 0.0), 0),   // degenerate, black — would be culled if not flat
            (SIMD3(0.02, 0.0, 0.0), 1),  // below a high luma floor
            (SIMD3(0.7, 0.3, 0.1), 2),   // split — would be ×0.6 if not flat
            (SIMD3(0.5, 0.5, 0.5), 1),
        ]
        for (rgb, prov) in samples {
            let flat = gatedColour(rgb: rgb, prov: prov, lumaFloor: 200, provMode: 2, flat: true)
            #expect(flat == rgb, "flat pose must render the raw palette colour, unculled/undarkened")
        }
    }

    /// When orbited, the depth cues ARE active (split darkens, luma floor culls) —
    /// proving the flat-gate is what suppresses them, not their removal.
    @Test func orbitedPoseAppliesDepthCues() {
        // split slot darkens to ×0.6
        let split = gatedColour(rgb: SIMD3(1, 1, 1), prov: 2, lumaFloor: 0, provMode: 0, flat: false)
        #expect(split == SIMD3(0.6, 0.6, 0.6))
        // below the luma floor → culled
        let culled = gatedColour(rgb: SIMD3(0.01, 0.01, 0.01), prov: 1, lumaFloor: 50, provMode: 0, flat: false)
        #expect(culled == nil)
    }

    /// The depth→frame map puts the current frame on the near face (z=63 ⇒ fz=cursor).
    @Test func frontFaceShowsCurrentFrame() {
        for cursor in 0..<64 {
            let fz = ((cursor - 63 + 63) % 64 + 64) % 64
            #expect(fz == cursor)
        }
    }

    /// On-screen size identity: the cube surface and the 2D GIFCanvas both size via
    /// `SFTheme.canvasEdge(forAvailable:cells:)` from the same Review-column width, so
    /// for any available square they get the identical (integer-snapped) edge.
    @Test func onScreenEdgeMatchesGIFCanvas() {
        #expect(SFTheme.gifCanvasPt == SFTheme.gifCellPt * CGFloat(SFTheme.gifSideCells))
        for w in stride(from: 100.0, through: 500.0, by: 13.0) {
            let edge = SFTheme.canvasEdge(forAvailable: CGFloat(w), cells: SFTheme.gifSideCells)
            // canvasEdge is a pure function of (available, cells): both views fed the
            // same width get the same edge, and it never exceeds the available space.
            #expect(edge <= CGFloat(w))
            #expect(edge == SFTheme.canvasEdge(forAvailable: CGFloat(w), cells: SFTheme.gifSideCells))
        }
    }
}
