import Testing
@testable import SixFour

/// The Swift twin of `Spec.GatedResidual` — the determinism-safe learned-residual
/// gate. Asserts the same laws the spec proves (the gate scales an already
/// golden-gated `rawBands`, so its own laws are what remain to pin on device).
struct GatedResidualTests {

    private let theta: [Double] = [0.10, -0.20, 0.05, 0.30, 0.10, -0.10, -0.20, 0.00,
                                   0.15, 0.05, 0.20, -0.05, 0.10, -0.10, 0.20, -0.15,
                                   0.10, 0.00, 0.20, -0.20, 0.10]
    private let coarses = [0, 10_000, 32_768, 60_000]

    @Test func zeroGateIsTheByteExactFloor() {
        for v in coarses {
            #expect(GatedResidual.gatedCommitted(theta: theta, coarse: v, alpha: 0).allSatisfy { $0 == 0 })
        }
    }

    @Test func gateIsContractiveTowardTheFloor() {
        for v in coarses {
            let raw = DeviceTrainStepCPU.rawBands(theta: theta, coarse: v)
            for a in [-3.0, -0.5, 0.5, 2.0, 5.0] {
                let gated = GatedResidual.gatedRawBands(theta: theta, coarse: v, alpha: a)
                #expect(zip(gated, raw).allSatisfy { abs($0) <= abs($1) + 1e-12 })
            }
        }
    }

    @Test func gateEarnsMonotonicallyTowardUngated() {
        for v in coarses {
            let raw = DeviceTrainStepCPU.rawBands(theta: theta, coarse: v)
            let g1 = GatedResidual.gatedRawBands(theta: theta, coarse: v, alpha: 0.5)
            let g2 = GatedResidual.gatedRawBands(theta: theta, coarse: v, alpha: 2.0)
            // |g(0.5)| ≤ |g(2)| ≤ |raw|, per band — the gene earns its contribution.
            #expect(zip(g1, g2).allSatisfy { abs($0) <= abs($1) + 1e-12 })
            let gFull = GatedResidual.gatedRawBands(theta: theta, coarse: v, alpha: 20)
            #expect(zip(gFull, raw).allSatisfy { abs($0 - $1) <= 1e-6 * (1 + abs($1)) })
        }
    }
}

/// META-INIT yields progress (research report §5 item 4): a Reptile `W₀` learned
/// over a FAMILY of captures lets a HELD-OUT capture converge in a few steps far
/// better than the same few steps from the zero floor the device kernel uses today.
/// If this holds, threading `W₀` into `deviceTrainSimtKernel` is worth the kernel
/// change; if it didn't, the one-dispatch fit would be wishful.
struct MetaInitProgressTests {

    /// A capture whose 7 detail bands are LINEAR in the coarse with per-capture
    /// amplitude `amp` — the family shares a direction, varies in scale, so a
    /// centroid `W₀` is a genuinely useful starting point.
    private func capture(amp: Double, n: Int = 16) -> [MetaInit.Pair] {
        let c = [0.10, -0.08, 0.06, 0.12, -0.05, 0.09, -0.07]
        return (0..<n).map { i in
            let vt = 0.1 + 0.8 * Double(i) / Double(n - 1)
            let coarse = Int((vt * 65536).rounded())
            let detail = c.map { DeviceTrainStepCPU.quantizeQ16(amp * $0 * vt) }
            return MetaInit.Pair(coarse: coarse, detail: detail)
        }
    }

    @Test func metaInitBeatsZeroInitInFewSteps() {
        let family = [0.6, 0.8, 1.0, 1.2, 1.4].map { capture(amp: $0) }
        let w0 = MetaInit.reptile(captures: family, outerSteps: 300, innerSteps: 5,
                                  eta: 0.5, epsilon: 0.2)
        let heldOut = capture(amp: 0.9)                 // interpolated, unseen
        let zero = [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount)
        let fewSteps = 5

        let fromMeta = MetaInit.loss(MetaInit.trainFrom(w0, steps: fewSteps, eta: 0.5, pairs: heldOut), heldOut)
        let fromZero = MetaInit.loss(MetaInit.trainFrom(zero, steps: fewSteps, eta: 0.5, pairs: heldOut), heldOut)

        #expect(fromMeta < fromZero)              // meta-init YIELDS PROGRESS…
        #expect(fromMeta < 0.5 * fromZero)        // …and by a wide margin in 5 steps
        // Sanity: the task is genuinely learnable (long training from zero → ~0),
        // so the win is meta-init reaching low loss FAST, not an unlearnable target.
        let converged = MetaInit.loss(MetaInit.trainFrom(zero, steps: 3000, eta: 0.5, pairs: heldOut), heldOut)
        #expect(converged < fromMeta)
    }

    @Test func metaInitAloneIsAlreadyCloseToTheHeldOutOptimum() {
        let family = [0.6, 0.8, 1.0, 1.2, 1.4].map { capture(amp: $0) }
        let w0 = MetaInit.reptile(captures: family, outerSteps: 300, innerSteps: 5,
                                  eta: 0.5, epsilon: 0.2)
        let heldOut = capture(amp: 0.9)
        let zero = [Double](repeating: 0, count: DeviceTrainStepCPU.paramCount)
        // Zero steps: W₀ evaluated as-is beats the zero floor evaluated as-is — the
        // meta-init already carries the shared structure before any on-device step.
        #expect(MetaInit.loss(w0, heldOut) < MetaInit.loss(zero, heldOut))
    }
}

/// W₀ WIRED INTO THE REAL KERNEL (`deviceTrainSimtKernel` buffer 7): the meta-init
/// now starts the on-device descent, and (1) the default path is byte-identical to the
/// old zero floor (the golden holds), (2) a good W₀ makes the few-step fit converge far
/// better than from zero — the same progress the CPU prototype showed, now on the GPU.
struct MetaInitKernelWiringTests {

    private static let q16 = 65536.0
    private static let pattern: [Double] = [0.50, 0.62, 0.44, 0.68, 0.40, 0.58, 0.46, 0.60]

    /// Structured octant voxels (8/block) with a global amplitude — the same family
    /// shape as the CPU meta-init test, so different amplitudes share a θ direction.
    private static func structured(n: Int, amp: Double) -> [Int32] {
        var b = [Int32](); b.reserveCapacity(n * 8)
        for i in 0..<n {
            let v = 0.1 + 0.8 * Double(i) / Double(max(1, n - 1))
            for x in pattern { b.append(Int32((x * amp * (0.2 + 1.6 * v) * q16).rounded())) }
        }
        return b
    }

    @Test func defaultInitIsByteIdenticalToTheZeroFloor() {
        guard let rung = RungDispatch() else { return }
        let blocks = Self.structured(n: 64, amp: 1.0)
        guard let d1 = rung.trainSimt(blocks: blocks),                                   // implicit zero
              let d2 = rung.trainSimt(blocks: blocks, w0: [Float](repeating: 0, count: 21)) // explicit zero
        else { Issue.record("dispatch nil"); return }
        #expect(d1.committed == d2.committed)
        #expect(d1.loss.bitPattern == d2.loss.bitPattern)
        #expect(d1.theta == d2.theta)
    }

    @Test func metaInitStartsTheKernelFitBetterThanZero() {
        guard let rung = RungDispatch() else { return }
        // W₀ = the fully-trained θ of one family member (a stand-in for the offline
        // Reptile centroid): trained long on amp 1.0, then reused on a held-out amp.
        guard let trained = rung.trainSimt(blocks: Self.structured(n: 64, amp: 1.0), steps: 1500)
        else { Issue.record("dispatch nil"); return }
        let w0 = trained.theta

        let heldOut = Self.structured(n: 64, amp: 0.8)
        guard let fromMeta = rung.trainSimt(blocks: heldOut, steps: 5, w0: w0),
              let fromZero = rung.trainSimt(blocks: heldOut, steps: 5) else { Issue.record("dispatch nil"); return }

        #expect(fromMeta.loss < fromZero.loss)          // W₀ YIELDS PROGRESS on the real kernel…
        #expect(fromMeta.loss < 0.5 * fromZero.loss)    // …and by a wide margin in 5 steps
    }
}
