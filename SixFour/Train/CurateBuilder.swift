import Foundation

/// THE CURATE BUILD ENGINE (LAUNCH L1.3): the GPU ladder that realises the accepted
/// 16³ into the inspection/export volumes, plus the per-frame GIF realization —
/// every stage a gated twin of an oracle, none of it invented here:
///
///   * the up-rung is `RungDispatch.expandRung` (`cubeExpandRungKernel`), byte-exact
///     vs the Zig oracle `s4_cube_expand_rung` = `Spec.SelfSimilarReconstruct.
///     expandRungVolume` (fixture-gated);
///   * the θ float layer stays OUTSIDE the kernels (the cascade sandwich):
///     `DeviceTrainStepCPU.predictCommitted` commits the bands the trainer gated
///     (`DeviceTrainGolden`), and only committed integers enter the dispatch;
///   * the realization is `Spec.CurateRealize` in Swift: contiguous frame slices
///     through the fixture-gated Zig quantizer (`s4_quantize_frame`).
///
/// `build(rungs: 2)` is BIT-EQUAL to the shipped decide preview
/// (`OctantCube.expandProposal`) — asserted in `CurateBuilderTests`, so the GPU
/// path and the CPU fallback are interchangeable by proof, not hope.
///
/// Size-parametric throughout; the app instantiates 16³ → 64³ (rungs 2, the
/// inspection tier) and 64³ → 256³ (two more rungs, the export tier — whose
/// full-frame realization awaits the quantizer-scaling row; see the header of
/// `CurateSurface`). Concurrency: not Sendable — confine like `RungDispatch`.
final class CurateBuilder {
    private let rung: RungDispatch

    /// Fails (nil) where Metal compute is unavailable; callers fall back to
    /// `OctantCube.expandProposal`, which is byte-identical by gate.
    init?() {
        guard let r = RungDispatch() else { return nil }
        self.rung = r
    }

    /// The ONE float layer, committed: per-voxel θ_up detail bands
    /// (`predictCommitted` — the same committed integers `DeviceTrainGolden`
    /// gates), voxel-major, ready for the integer expand kernel.
    static func thetaDetails(_ vol: [Int32], theta: [Double]) -> [Int32] {
        vol.flatMap { v in
            DeviceTrainStepCPU.predictCommitted(theta: theta, coarse: Int(v)).map(Int32.init)
        }
    }

    /// `Spec.ModelForward.gateDetail` in Swift: zero the 7 invented bands of every
    /// masked-off cell, so the kernel (untouched) lands the floor there — the
    /// paint gate stays a pure-integer detail transform (the sandwich holds).
    static func gateDetails(_ details: [Int32], mask: [Bool]) -> [Int32] {
        var out = details
        for cell in 0 ..< details.count / 7 where !(cell < mask.count && mask[cell]) {
            for b in 0 ..< 7 { out[cell * 7 + b] = 0 }
        }
        return out
    }

    /// One channel's ladder: `rungs` successive GPU up-rungs from a side³ scalar
    /// cube. `theta` nil = the deterministic floor at every rung; else θ invents
    /// per rung on the CURRENT coarse values (the weight-tied self-similar shape).
    /// `paintMask` (W1, device (t,r,c) order at `side³`): invention lands only in
    /// painted cells; the mask up-rungs with the volume (`OctantCube.upsampleMask`,
    /// = `lawMaskUpsampleIsBlockReplication`). nil = ungated.
    func expandLadder(base: [Int32], side: Int, rungs: Int, theta: [Double]?,
                      paintMask: [Bool]? = nil) -> [Int32]? {
        var vol = base
        var s = side
        var mask = paintMask
        for _ in 0 ..< rungs {
            var details = theta.map { Self.thetaDetails(vol, theta: $0) }
            if let m = mask, details != nil {
                details = details.map { Self.gateDetails($0, mask: m) }
            }
            guard let next = rung.expandRung(volume: vol, side: s, details: details) else {
                return nil
            }
            vol = next
            mask = mask.map { OctantCube.upsampleMask(side: s, mask: $0) }
            s *= 2
        }
        return vol
    }

    /// THE CURATED BUILD: the 16³ substrate (`Surface.coarseSubstrate` shape,
    /// side frames × side² OKLab Q16 pixels) up-rung'd `rungs` times per channel —
    /// θ invents on its trained channel only, the others ride the floor. Returns
    /// the interleaved `((t·S + r)·S + c)·3 + ch` Q16 volume at S = side·2^rungs,
    /// or nil for a malformed substrate / no GPU. `rungs: 2` == the decide
    /// preview's `OctantCube.expandProposal`, bit-for-bit (gated).
    func build(substrate: [[VoxelReduce.Px]], theta: [Double]?,
               geneChannel: Int = 0, rungs: Int,
               paintMask: [Bool]? = nil) -> [Int32]? {
        let side = substrate.count
        guard side > 0, rungs >= 0,
              substrate.allSatisfy({ $0.count == side * side }) else { return nil }
        let outSide = side << rungs
        var out = [Int32](repeating: 0, count: outSide * outSide * outSide * 3)
        for ch in 0 ..< 3 {
            var vol = [Int32](repeating: 0, count: side * side * side)
            for t in 0 ..< side {
                for p in 0 ..< side * side {
                    let px = substrate[t][p]
                    vol[t * side * side + p] = Int32(ch == 0 ? px.0 : (ch == 1 ? px.1 : px.2))
                }
            }
            guard let fine = expandLadder(base: vol, side: side, rungs: rungs,
                                          theta: ch == geneChannel ? theta : nil,
                                          paintMask: paintMask) else {
                return nil
            }
            for i in 0 ..< fine.count { out[i * 3 + ch] = fine[i] }
        }
        return out
    }

    /// `Spec.CurateRealize.volumeFrames` in Swift — the layout pin: frame t of the
    /// interleaved volume is its CONTIGUOUS slice of side²·3 ints (row-major
    /// (L,a,b) pixels, exactly the `quantizeFrame` input shape). Gated against a
    /// position-coded volume in `CurateBuilderTests` (mirrors
    /// `lawFramesPartitionVolume`).
    static func volumeFrames(side: Int, flat: [Int32]) -> [[Int32]]? {
        let fp = side * side * 3
        guard flat.count == side * fp else { return nil }
        return (0 ..< side).map { t in Array(flat[t * fp ..< (t + 1) * fp]) }
    }

    /// `Spec.CurateRealize.realizeIndexed` in Swift: every frame through the
    /// fixture-gated Zig quantizer. Frame-LOCAL by spec law, so callers may
    /// realize progressively (per frame / per t-slab) — nothing couples frames.
    static func realize(volume: [Int32], side: Int, k: Int, lloydIters: Int)
        -> [SixFourNative.QuantResult]?
    {
        guard let frames = volumeFrames(side: side, flat: volume) else { return nil }
        var out: [SixFourNative.QuantResult] = []
        out.reserveCapacity(side)
        for f in frames {
            guard let q = SixFourNative.quantizeFrame(oklabQ16: f, k: k, lloydIters: lloydIters)
            else { return nil }
            out.append(q)
        }
        return out
    }
}
