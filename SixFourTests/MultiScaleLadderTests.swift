import Testing
@testable import SixFour

/// The Loom's capture scheduler + the Swift↔Zig multi-scale bridge. Covers the
/// PURE schedule/assembly logic (off-device) and exercises `SixFourNative.renderSelect`
/// / `multiScaleIntegrate` end-to-end (pure-integer Zig, runs anywhere), mirroring the
/// Haskell/Zig goldens (`Spec.RenderSelect` / `Spec.MultiScaleIntegrate`).
struct MultiScaleLadderTests {

    private let sensor = MultiScaleLadder.SensorLimits(
        minISO: 32, maxISO: 3200, minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 1.0 / 5)

    // MARK: - schedule (the CaptureDiversity recipe, pure)

    @Test func scheduleTilesEVCoarseHighestFineZero() {
        let stops = MultiScaleLadder.schedule(evSpreadStops: 6, sensor: sensor,
                                              referenceDuration: 1.0 / 240, referenceISO: 100)
        #expect(stops.count == 3)
        let fine = stops.first { $0.scale == .fine64 }!
        let mid = stops.first { $0.scale == .mid32 }!
        let coarse = stops.first { $0.scale == .coarse16 }!
        // Fine is the reference (0 stops); coarse carries the full spread; mid is between.
        #expect(fine.evOffsetStops == 0)
        #expect(coarse.evOffsetStops > mid.evOffsetStops)
        #expect(mid.evOffsetStops > fine.evOffsetStops)
        // Coarse = longer exposure AND higher gain than fine (shadows).
        #expect(coarse.durationSeconds >= fine.durationSeconds)
        #expect(coarse.iso >= fine.iso)
    }

    @Test func scheduleStaysInSensorEnvelope() {
        let stops = MultiScaleLadder.schedule(evSpreadStops: 20, sensor: sensor,
                                              referenceDuration: 1.0 / 240, referenceISO: 100)
        for s in stops {
            #expect(s.iso >= sensor.minISO && s.iso <= sensor.maxISO)
            #expect(s.durationSeconds >= sensor.minDurationSeconds
                    && s.durationSeconds <= sensor.maxDurationSeconds)
        }
    }

    // MARK: - assembleVolume (pure stacking)

    @Test func assembleVolumeStacksFramesInOrder() {
        // coarse16: 16 frames × 16×16.
        let frames = (0 ..< 16).map { f in [Int32](repeating: Int32(f), count: 16 * 16) }
        let vol = MultiScaleLadder.assembleVolume(scale: .coarse16, frames: frames)
        #expect(vol?.count == 16 * 16 * 16)
        // frame f occupies [f*256, f*256+256) at value f.
        #expect(vol?[0] == 0)
        #expect(vol?[256] == 1)
        #expect(vol?[16 * 256 - 1] == 15)
    }

    @Test func assembleVolumeRejectsWrongShape() {
        #expect(MultiScaleLadder.assembleVolume(scale: .fine64, frames: [[1, 2, 3]]) == nil)
    }

    // MARK: - the Swift↔Zig bridge (renderSelect, side = 8 to match the golden)

    @Test func renderSelectDepth2IsFineIdentity() throws {
        let v16 = [Int32](repeating: 1, count: 2 * 2 * 2)
        let v32 = [Int32](repeating: 2, count: 4 * 4 * 4)
        let v64 = (0 ..< 8 * 8 * 8).map { Int32($0) }
        let depth = [Int32](repeating: 2, count: 2 * 2 * 2) // all fine
        let out = try #require(MultiScaleLadder.fuse(depth: depth, v16: v16, v32: v32, v64: v64, side: 8))
        #expect(out == v64)   // depth 2 everywhere = V64 untouched
    }

    @Test func renderSelectDepth0SelectsIndependentCoarse() throws {
        // V16 distinct per coarse cell; V64 a different constant ⇒ output is V16, not a pool.
        let v16 = (0 ..< 8).map { Int32($0 + 100) }
        let v32 = [Int32](repeating: 0, count: 4 * 4 * 4)
        let v64 = [Int32](repeating: -7, count: 8 * 8 * 8)
        let depth = [Int32](repeating: 0, count: 8) // all coarse
        let out = try #require(MultiScaleLadder.fuse(depth: depth, v16: v16, v32: v32, v64: v64, side: 8))
        // every output voxel = its coarse cell's V16 value (block-replicated 4×), never -7.
        for t in 0 ..< 8 {
            for y in 0 ..< 8 {
                for x in 0 ..< 8 {
                    let si = ((t / 4) * 2 + (y / 4)) * 2 + (x / 4)
                    #expect(out[(t * 8 + y) * 8 + x] == v16[si])
                }
            }
        }
    }

    // MARK: - the integrator bridge (conservation, mirrors Spec.MultiScaleIntegrate)

    @Test func integratorConservesPhotons() throws {
        let nSub = 12, nCells = 3, nScales = 3
        let photons: [UInt16] = (0 ..< nCells * nSub).map { UInt16(($0 * 37) % 1000) }
        let owner: [Int32] = (0 ..< nSub).map { Int32($0 % 3) }
        let vols = try #require(SixFourNative.multiScaleIntegrate(
            photons: photons, owner: owner, nScales: nScales, nCells: nCells, nSubslices: nSub))
        // per cell: the 3 scales' volumes sum to the raw photon total.
        for cell in 0 ..< nCells {
            let volSum = (0 ..< nScales).reduce(Int64(0)) { $0 + vols[$1 * nCells + cell] }
            let raw = (0 ..< nSub).reduce(Int64(0)) { $0 + Int64(photons[cell * nSub + $1]) }
            #expect(volSum == raw)
        }
    }
}
