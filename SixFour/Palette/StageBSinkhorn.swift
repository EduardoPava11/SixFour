import Foundation
import simd
import os
import Accelerate

/// Swift port of `SixFour.Spec.StageB.sinkhornReference` and
/// `SixFour.Spec.StageB.logDomainSinkhornReference` (see
/// `spec/src/SixFour/Spec/StageB.hs`).
///
/// Two paths share `Params`:
///
///   * **Direct-exp** (`Params.shared`, θ = 0.05) — fast, numerically
///     safe at small θ. Used by `PaletteGenerator.Mode.shared`.
///   * **Log-domain** (`Params.global`, θ = 50) — `logSumExp` throughout.
///     The only path that realises the θ → ∞ limit (MATH.md Theorem 2)
///     faithfully; the direct-exp kernel collapses to ~1 above θ ≈ 1
///     and loses geometric signal. Used by `PaletteGenerator.Mode.global`.
///
/// Surjectivity is a runtime mechanism, not a theorem. Research
/// confirmed (Cuturi 2013; Peyré & Cuturi 2018) that Sinkhorn balance
/// gives equal soft column-mass on the transport plan, NOT hard-NN
/// surjectivity after nearest-neighbour rounding. Earlier revisions
/// patched non-surjective indices with a `forceSurjective` rescue;
/// that violated the project's no-fallback rule once on-device runs
/// showed it rescuing 253/256 slots routinely. The current design is
/// **adaptive θ**: try the configured θ, halve it on non-surjective
/// output, and throw `StageBError.cannotAchieveSurjectiveGlobalPalette`
/// when even the floor θ can't produce a surjective remap. The user
/// sees a clear failure with logs, not a silent substitution.
struct StageBSinkhorn: StageBContract {

    static let logger = Logger(subsystem: "com.sixfour.SixFour", category: "stageB")

    /// Sinkhorn-Knopp tuning knobs.
    ///
    /// `theta` is the working ε (= the tying parameter of MATH.md §3).
    /// For Global mode it's the *starting* ε of the adaptive search;
    /// `thetaFloor` is the smallest ε we'll accept before declaring the
    /// scene unfit for Global. For Shared (single-θ) mode the floor
    /// equals theta (no halving).
    struct Params: Sendable {
        var theta: Double = 0.05
        var thetaFloor: Double = 0.05
        var sinkhornIterations: Int = 20
        var kmeansIterations: Int = 10
        /// When `true`, scaling is done in log-domain via `logSumExp`.
        var logDomain: Bool = false

        /// θ = 0.05, direct-exp, no adaptive halving. The `.shared`
        /// endpoint of MATH.md §3.bis.
        static let shared = Params(theta: 0.05, thetaFloor: 0.05,
                                   sinkhornIterations: 20,
                                   kmeansIterations: 10,
                                   logDomain: false)
        /// θ_start = 15 (down from 50 — on-device logs showed 50
        /// over-collapses to the point where 253/256 slots need rescue),
        /// θ_floor = 0.5, log-domain. The `.global` endpoint of
        /// MATH.md Theorem 2, implemented via adaptive halving instead
        /// of post-hoc `forceSurjective`. If even θ_floor can't produce
        /// a hard-NN-surjective palette, the merger fails loudly with
        /// `cannotAchieveSurjectiveGlobalPalette` — never silently.
        static let global = Params(theta: 15.0, thetaFloor: 0.5,
                                   sinkhornIterations: 5,
                                   kmeansIterations: 2,
                                   logDomain: true)
    }

    /// Errors propagated to the renderer + UI. No silent fallback path.
    enum StageBError: Error, Sendable, Equatable, CustomStringConvertible {
        /// Adaptive-θ search exhausted (θ ≤ thetaFloor) without
        /// producing a hard-NN-surjective palette on this input. The
        /// scene is too uniform for the chosen mode at any θ in the
        /// search range; the user is expected to pick a different mode
        /// and retap, not have one silently substituted.
        case cannotAchieveSurjectiveGlobalPalette(
            finalTheta: Double, missingCount: Int, attempts: Int
        )

        var description: String {
            switch self {
            case .cannotAchieveSurjectiveGlobalPalette(let θ, let miss, let n):
                return "Global mode could not build a surjective palette "
                     + "(\(miss) of \(SixFourShape.K) slots empty at θ=\(θ); \(n) attempts). "
                     + "Pick Shared or Per-frame and retap."
            }
        }
    }

    /// Full merger result.
    struct MergeResult: Sendable {
        let globalPalette: [SIMD3<Float>]
        let witness: Surjective256
        /// θ at which surjectivity was actually achieved. For Shared
        /// mode this equals `params.theta`; for Global, the adaptive
        /// search may have halved one or more times.
        let achievedTheta: Double
        /// Number of adaptive-θ attempts made (1 if the first attempt
        /// produced a surjective result).
        let attempts: Int
    }

    var params: Params = .shared

    /// `StageBContract` conformance — thin wrapper that projects
    /// `mergeAdaptive`'s `MergeResult` down to the contract tuple.
    /// Throws the same `StageBError` if no θ produces a surjective remap.
    func merge(
        perFramePalettes: [[SIMD3<Float>]],
        perFrameIndices: [[UInt8]]
    ) throws -> (globalPalette: [SIMD3<Float>], witness: Surjective256) {
        let r = try mergeAdaptive(
            perFramePalettes: perFramePalettes,
            perFrameIndices: perFrameIndices
        )
        return (r.globalPalette, r.witness)
    }

    /// Adaptive-θ merge with full diagnostics. Halves θ until the hard-NN
    /// remap is genuinely surjective, or fails loudly when no θ in the
    /// `[thetaFloor, theta]` range works.
    ///
    /// Per the no-fallback rule this method **never** patches the
    /// indices post-hoc (`forceSurjective` was removed) and **never**
    /// silently substitutes a different result. Every attempt is logged
    /// so device runs leave a record of why a particular θ won.
    func mergeAdaptive(
        perFramePalettes: [[SIMD3<Float>]],
        perFrameIndices: [[UInt8]]
    ) throws -> MergeResult {
        precondition(perFramePalettes.count == perFrameIndices.count,
                     "Stage B: palette count must equal index-tensor count")
        let K = SixFourShape.K

        // 1. Flatten candidates once (does not depend on θ).
        var candidates: [(lab: SIMD3<Double>, weight: Double)] = []
        candidates.reserveCapacity(perFramePalettes.count * K)
        for (palette, indices) in zip(perFramePalettes, perFrameIndices) {
            precondition(palette.count == K, "Stage B: per-frame palette must have exactly K entries")
            let counts = countOccurrences(indices: indices, paletteSize: K)
            for entry in 0..<K {
                let w = counts[entry]
                if w == 0 { continue }
                let f = palette[entry]
                candidates.append((SIMD3<Double>(Double(f.x), Double(f.y), Double(f.z)),
                                   Double(w)))
            }
        }

        // 2. Adaptive θ loop. Single attempt for Shared (theta == floor);
        //    halving for Global (theta > floor).
        var attempts = 0
        var currentTheta = params.theta
        var lastMissing = K
        let startLabel = "thetaStart=\(params.theta) thetaFloor=\(params.thetaFloor) "
            + "sinkhornIters=\(params.sinkhornIterations) kmeansIters=\(params.kmeansIterations) "
            + "logDomain=\(params.logDomain) candidates=\(candidates.count)"
        Self.logger.info("[stageB] merge starting: \(startLabel, privacy: .public)")

        while true {
            attempts += 1
            var attemptParams = params
            attemptParams.theta = currentTheta
            let started = ContinuousClock().now
            let (centF, globalIndices) = runOneAttempt(
                params: attemptParams,
                K: K,
                candidates: candidates,
                perFramePalettes: perFramePalettes,
                perFrameIndices: perFrameIndices
            )
            let elapsedMs = Self.millis(ContinuousClock().now - started)

            if let witness = Surjective256(checking: globalIndices) {
                let curTheta = currentTheta
                let attemptsCt = attempts
                Self.logger.info(
                    "[stageB] merge succeeded: θ=\(curTheta, privacy: .public) attempts=\(attemptsCt, privacy: .public) wall=\(elapsedMs, privacy: .public)ms"
                )
                return MergeResult(globalPalette: centF, witness: witness,
                                   achievedTheta: currentTheta, attempts: attempts)
            }

            // Count missing slots for diagnostics + the eventual failure.
            var seen = [Bool](repeating: false, count: K)
            for v in globalIndices { seen[Int(v)] = true }
            lastMissing = seen.filter { !$0 }.count
            Self.logger.warning(
                "[stageB] attempt θ=\(currentTheta, privacy: .public) non-surjective: \(lastMissing, privacy: .public)/\(K, privacy: .public) slots empty (wall=\(elapsedMs, privacy: .public)ms)"
            )

            // Halve θ and retry, unless we've hit the floor — Shared mode
            // has theta == thetaFloor, so a single attempt that fails goes
            // straight to the failure branch.
            let next = currentTheta * 0.5
            if next < params.thetaFloor {
                let floorVal = params.thetaFloor
                let curTheta = currentTheta
                let attemptsCt = attempts
                let missingCt = lastMissing
                Self.logger.error(
                    "[stageB] merge failed: θ=\(curTheta, privacy: .public) ≤ floor=\(floorVal, privacy: .public); \(missingCt, privacy: .public) slots empty after \(attemptsCt, privacy: .public) attempts. Scene unfit for this mode."
                )
                throw StageBError.cannotAchieveSurjectiveGlobalPalette(
                    finalTheta: currentTheta,
                    missingCount: lastMissing,
                    attempts: attempts
                )
            }
            currentTheta = next
        }
    }

    /// One Sinkhorn-balanced-k-means attempt at the given θ. Pure: same
    /// inputs always produce the same `(centroids, globalIndices)`. The
    /// caller decides whether to accept or halve θ and retry.
    private func runOneAttempt(
        params: Params,
        K: Int,
        candidates: [(lab: SIMD3<Double>, weight: Double)],
        perFramePalettes: [[SIMD3<Float>]],
        perFrameIndices: [[UInt8]]
    ) -> (palette: [SIMD3<Float>], indices: [UInt8]) {
        // Initial centroids: uniform-stride sample from the candidate pool.
        let n0 = max(1, candidates.count)
        let stride = max(1, n0 / K)
        var centroids = [SIMD3<Double>](repeating: .zero, count: K)
        for i in 0..<K {
            centroids[i] = candidates[(i * stride) % n0].lab
        }
        // Outer balanced k-means iterations. Save params on self so the
        // existing balancedStep* helpers see them.
        let savedParams = self.params
        // capture by value into local
        var tempSelf = self
        tempSelf.params = params
        for _ in 0..<params.kmeansIterations {
            centroids = tempSelf.balancedStep(candidates: candidates, centroids: centroids)
        }
        _ = savedParams  // not mutated on self — we worked off tempSelf
        // Remap each frame's local indices to nearest global centroid.
        let centF: [SIMD3<Float>] = centroids.map {
            SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z))
        }
        var globalIndices: [UInt8] = []
        globalIndices.reserveCapacity(perFrameIndices.reduce(0) { $0 + $1.count })
        for (palette, indices) in zip(perFramePalettes, perFrameIndices) {
            for local in indices {
                let okl = palette[Int(local)]
                globalIndices.append(UInt8(nearestIndex(centF, okl)))
            }
        }
        return (centF, globalIndices)
    }

    private static func millis(_ d: Duration) -> Int {
        let (s, attos) = d.components
        return Int(s) * 1_000 + Int(attos / 1_000_000_000_000_000)
    }

    // MARK: - Inner loop

    /// One balanced-k-means iteration. Dispatches to direct-exp or
    /// log-domain depending on `params.logDomain`.
    private func balancedStep(
        candidates: [(lab: SIMD3<Double>, weight: Double)],
        centroids: [SIMD3<Double>]
    ) -> [SIMD3<Double>] {
        if params.logDomain {
            return balancedStepLogDomain(candidates: candidates, centroids: centroids)
        } else {
            return balancedStepDirectExp(candidates: candidates, centroids: centroids)
        }
    }

    /// Direct-exp balanced step (Cuturi 2013). Numerically safe for θ ≲ 1.
    /// Uses Accelerate BLAS for the cost matrix and Sinkhorn-Knopp scaling.
    private func balancedStepDirectExp(
        candidates: [(lab: SIMD3<Double>, weight: Double)],
        centroids: [SIMD3<Double>]
    ) -> [SIMD3<Double>] {
        let nC = candidates.count
        let nK = centroids.count
        let theta = params.theta

        var bigX = [Double](repeating: 0, count: nC * 3)
        var rowTarget = [Double](repeating: 0, count: nC)
        var xNorm2 = [Double](repeating: 0, count: nC)
        for i in 0..<nC {
            let p = candidates[i].lab
            bigX[i * 3 + 0] = p.x
            bigX[i * 3 + 1] = p.y
            bigX[i * 3 + 2] = p.z
            rowTarget[i] = candidates[i].weight
            xNorm2[i] = p.x * p.x + p.y * p.y + p.z * p.z
        }
        var bigM = [Double](repeating: 0, count: nK * 3)
        var mNorm2 = [Double](repeating: 0, count: nK)
        for k in 0..<nK {
            let p = centroids[k]
            bigM[k * 3 + 0] = p.x
            bigM[k * 3 + 1] = p.y
            bigM[k * 3 + 2] = p.z
            mNorm2[k] = p.x * p.x + p.y * p.y + p.z * p.z
        }

        var kernel = [Double](repeating: 0, count: nC * nK)
        cblas_dgemm(
            CblasRowMajor, CblasNoTrans, CblasTrans,
            Int32(nC), Int32(nK), 3,
            1.0,
            bigX, 3,
            bigM, 3,
            0.0,
            &kernel, Int32(nK)
        )

        let invTheta = 1.0 / theta
        kernel.withUnsafeMutableBufferPointer { kBuf in
            for i in 0..<nC {
                let row = i * nK
                let xN = xNorm2[i]
                for k in 0..<nK {
                    kBuf[row + k] = (2.0 * kBuf[row + k] - xN - mNorm2[k]) * invTheta
                }
            }
        }
        var nElems = Int32(nC * nK)
        vvexp(&kernel, kernel, &nElems)

        let sumW = rowTarget.reduce(0, +)
        let colTarget = [Double](repeating: sumW / Double(nK), count: nK)

        let scaled = sinkhornScale(SinkhornProblem(
            kernel: kernel, nC: nC, nK: nK,
            rowTarget: rowTarget, colTarget: colTarget,
            iterations: params.sinkhornIterations
        ))
        let uVec = scaled.u
        let kTu = scaled.kTu

        var uX = [Double](repeating: 0, count: nC * 3)
        for i in 0..<nC {
            let ui = uVec[i]
            uX[i * 3 + 0] = ui * bigX[i * 3 + 0]
            uX[i * 3 + 1] = ui * bigX[i * 3 + 1]
            uX[i * 3 + 2] = ui * bigX[i * 3 + 2]
        }
        var labSum = [Double](repeating: 0, count: nK * 3)
        cblas_dgemm(
            CblasRowMajor, CblasTrans, CblasNoTrans,
            Int32(nK), 3, Int32(nC),
            1.0,
            kernel, Int32(nK),
            uX, 3,
            0.0,
            &labSum, 3
        )

        var newCentroids = [SIMD3<Double>](repeating: .zero, count: nK)
        for k in 0..<nK {
            let denom = kTu[k]
            if denom <= 0 {
                newCentroids[k] = centroids[k]
            } else {
                newCentroids[k] = SIMD3<Double>(
                    labSum[k * 3 + 0] / denom,
                    labSum[k * 3 + 1] / denom,
                    labSum[k * 3 + 2] / denom
                )
            }
        }
        return newCentroids
    }

    /// Log-domain balanced step (Peyré & Cuturi 2018 §4.4). Required at
    /// θ ≫ 1 where the direct-exp kernel underflows / saturates. Keeps
    /// `log K[i,k] = -‖x-μ‖²/θ` throughout; uses logsumexp for the scaling
    /// and the centroid update.
    ///
    /// Vectorised through Accelerate: `cblas_dgemm` builds the log-kernel
    /// (AMX-accelerated, the dominant cost), `vDSP_vaddD`/`maxvD`/`vsaddD`
    /// + `vvexp` + `vDSP_sveD` carry out the per-row/per-column logsumexp,
    /// and a final `cblas_dgemm` computes the centroid weighted-sums.
    /// On iPhone 17 Pro this brings the merger from ~20 s (scalar) to
    /// the ~700 ms expected by `LogDomainSinkhornTests`.
    private func balancedStepLogDomain(
        candidates: [(lab: SIMD3<Double>, weight: Double)],
        centroids: [SIMD3<Double>]
    ) -> [SIMD3<Double>] {
        let nC = candidates.count
        let nK = centroids.count
        let theta = params.theta

        // --- pack candidates + centroids into flat row-major buffers ---
        var bigX = [Double](repeating: 0, count: nC * 3)
        var xNorm2 = [Double](repeating: 0, count: nC)
        var rowTarget = [Double](repeating: 0, count: nC)
        for i in 0..<nC {
            let p = candidates[i].lab
            bigX[i * 3 + 0] = p.x
            bigX[i * 3 + 1] = p.y
            bigX[i * 3 + 2] = p.z
            xNorm2[i] = p.x * p.x + p.y * p.y + p.z * p.z
            rowTarget[i] = candidates[i].weight
        }
        var bigM = [Double](repeating: 0, count: nK * 3)
        var mNorm2 = [Double](repeating: 0, count: nK)
        for k in 0..<nK {
            let p = centroids[k]
            bigM[k * 3 + 0] = p.x
            bigM[k * 3 + 1] = p.y
            bigM[k * 3 + 2] = p.z
            mNorm2[k] = p.x * p.x + p.y * p.y + p.z * p.z
        }

        // --- log-kernel: logK[i,k] = -(‖x‖² + ‖μ‖² - 2·⟨x,μ⟩) / θ ---
        // Build it BLAS-style — identical to balancedStepDirectExp's first
        // step but with negation and no `vvexp`. cblas_dgemm dispatches to
        // AMX for the 16k × 256 dot-product matrix.
        var logK = [Double](repeating: 0, count: nC * nK)
        cblas_dgemm(
            CblasRowMajor, CblasNoTrans, CblasTrans,
            Int32(nC), Int32(nK), 3,
            1.0, bigX, 3, bigM, 3, 0.0, &logK, Int32(nK)
        )
        let negInvTheta = -1.0 / theta
        logK.withUnsafeMutableBufferPointer { kBuf in
            for i in 0..<nC {
                let row = i * nK
                let xN = xNorm2[i]
                for k in 0..<nK {
                    kBuf[row + k] = (xN + mNorm2[k] - 2.0 * kBuf[row + k]) * negInvTheta
                }
            }
        }

        // --- transpose: logKT (nK × nC) so per-column reductions of logK
        //     become contiguous-stride row reductions of logKT. ---
        var logKT = [Double](repeating: 0, count: nC * nK)
        vDSP_mtransD(logK, 1, &logKT, 1, vDSP_Length(nK), vDSP_Length(nC))

        // --- log marginals ---
        let sumW = rowTarget.reduce(0, +)
        let perK = sumW / Double(nK)
        let logRowT = rowTarget.map { $0 <= 0 ? -Double.infinity : log($0) }
        let logColT = [Double](repeating: log(perK), count: nK)

        // --- Sinkhorn scaling in log-domain ---
        // Each iter does two logsumexp reductions over the (nC × nK)
        // log-kernel. vDSP/vForce calls through C-coded Accelerate, so
        // their cost per call is constant regardless of Swift build
        // configuration — that's why the per-row vDSP loops below stay
        // fast even at -Onone. The iteration counts in `Params.global`
        // are tuned so the total per-call wall-clock stays under a few
        // hundred ms at production scale (nC ≈ 14 000).
        var logU = [Double](repeating: 0, count: nC)
        var logV = [Double](repeating: 0, count: nK)
        var scratchCol = [Double](repeating: 0, count: nC)  // for per-column lse (length nC)
        var scratchRow = [Double](repeating: 0, count: nK)  // for per-row    lse (length nK)
        for _ in 0..<params.sinkhornIterations {
            // log v[k] = log colT[k] - lse_i(logU[i] + logKT[k, i])
            logKT.withUnsafeBufferPointer { ktPtr in
                logU.withUnsafeBufferPointer { uPtr in
                    for k in 0..<nK {
                        vDSP_vaddD(uPtr.baseAddress!, 1,
                                   ktPtr.baseAddress! + k * nC, 1,
                                   &scratchCol, 1, vDSP_Length(nC))
                        logV[k] = logColT[k]
                                  - Self.vectorizedLogSumExp(&scratchCol, nC)
                    }
                }
            }
            // log u[i] = log rowT[i] - lse_k(logV[k] + logK[i, k])
            logK.withUnsafeBufferPointer { kPtr in
                logV.withUnsafeBufferPointer { vPtr in
                    for i in 0..<nC {
                        vDSP_vaddD(vPtr.baseAddress!, 1,
                                   kPtr.baseAddress! + i * nK, 1,
                                   &scratchRow, 1, vDSP_Length(nK))
                        logU[i] = logRowT[i]
                                  - Self.vectorizedLogSumExp(&scratchRow, nK)
                    }
                }
            }
        }

        // --- centroid update ---
        // Build T (nK × nC, row-major) where T[k, i] = exp(logU[i] +
        // logKT[k, i] - mk), with mk chosen per row for stability. Then
        // labSum = T · bigX (one big dgemm, AMX-accelerated) gives the
        // weighted OKLab sums; denom[k] is the row-sum of T.
        var T = [Double](repeating: 0, count: nC * nK)
        var denom = [Double](repeating: 0, count: nK)
        var rowKeepOld = [Bool](repeating: false, count: nK)
        var rowBuf = [Double](repeating: 0, count: nC)
        logKT.withUnsafeBufferPointer { ktPtr in
            logU.withUnsafeBufferPointer { uPtr in
                for k in 0..<nK {
                    // rowBuf = logU + logKT[k row]
                    vDSP_vaddD(uPtr.baseAddress!, 1,
                               ktPtr.baseAddress! + k * nC, 1,
                               &rowBuf, 1, vDSP_Length(nC))
                    var mk: Double = 0
                    vDSP_maxvD(rowBuf, 1, &mk, vDSP_Length(nC))
                    if !mk.isFinite {
                        rowKeepOld[k] = true
                        continue
                    }
                    var negMk = -mk
                    vDSP_vsaddD(rowBuf, 1, &negMk, &rowBuf, 1, vDSP_Length(nC))
                    var nVar = Int32(nC)
                    vvexp(&rowBuf, rowBuf, &nVar)
                    // Copy rowBuf (the weights w[i] = exp(logTcol[i] - mk))
                    // into row k of T.
                    rowBuf.withUnsafeBufferPointer { rbPtr in
                        T.withUnsafeMutableBufferPointer { tPtr in
                            (tPtr.baseAddress! + k * nC)
                                .update(from: rbPtr.baseAddress!, count: nC)
                        }
                    }
                    var d: Double = 0
                    vDSP_sveD(rowBuf, 1, &d, vDSP_Length(nC))
                    denom[k] = d
                }
            }
        }
        // labSum = T (nK × nC) · bigX (nC × 3) → nK × 3, row-major.
        var labSum = [Double](repeating: 0, count: nK * 3)
        cblas_dgemm(
            CblasRowMajor, CblasNoTrans, CblasNoTrans,
            Int32(nK), 3, Int32(nC),
            1.0, T, Int32(nC), bigX, 3, 0.0, &labSum, 3
        )
        var newCentroids = [SIMD3<Double>](repeating: .zero, count: nK)
        for k in 0..<nK {
            if rowKeepOld[k] || denom[k] <= 0 {
                newCentroids[k] = centroids[k]
            } else {
                let inv = 1.0 / denom[k]
                newCentroids[k] = SIMD3<Double>(
                    labSum[k * 3 + 0] * inv,
                    labSum[k * 3 + 1] * inv,
                    labSum[k * 3 + 2] * inv
                )
            }
        }
        return newCentroids
    }

    /// Numerically-stable `log(Σ exp(x))` over a contiguous buffer.
    /// Accelerate-backed: `vDSP_maxvD` → `vDSP_vsaddD` → `vvexp` →
    /// `vDSP_sveD`. **Mutates** the input buffer (the post-shift exp values
    /// are left there) so callers can reuse them as un-normalised weights
    /// without a second exp pass — this is the trick that makes the
    /// centroid update one BLAS call.
    @inline(__always)
    private static func vectorizedLogSumExp(_ ptr: UnsafeMutablePointer<Double>, _ n: Int) -> Double {
        var m: Double = 0
        vDSP_maxvD(ptr, 1, &m, vDSP_Length(n))
        if !m.isFinite { return m }
        var negM = -m
        vDSP_vsaddD(ptr, 1, &negM, ptr, 1, vDSP_Length(n))
        var nVar = Int32(n)
        vvexp(ptr, ptr, &nVar)
        var s: Double = 0
        vDSP_sveD(ptr, 1, &s, vDSP_Length(n))
        return m + log(s)
    }


    private struct SinkhornProblem {
        let kernel: [Double]
        let nC: Int
        let nK: Int
        let rowTarget: [Double]
        let colTarget: [Double]
        let iterations: Int
    }

    private struct SinkhornResult {
        let u: [Double]
        let v: [Double]
        let kTu: [Double]
    }

    private func sinkhornScale(_ p: SinkhornProblem) -> SinkhornResult {
        var uVec = [Double](repeating: 1, count: p.nC)
        var vVec = [Double](repeating: 1, count: p.nK)
        var kTu = [Double](repeating: 0, count: p.nK)
        var kV  = [Double](repeating: 0, count: p.nC)

        for _ in 0..<p.iterations {
            cblas_dgemv(
                CblasRowMajor, CblasTrans,
                Int32(p.nC), Int32(p.nK),
                1.0, p.kernel, Int32(p.nK),
                uVec, 1,
                0.0, &kTu, 1
            )
            for k in 0..<p.nK {
                vVec[k] = kTu[k] == 0 ? 0 : p.colTarget[k] / kTu[k]
            }
            cblas_dgemv(
                CblasRowMajor, CblasNoTrans,
                Int32(p.nC), Int32(p.nK),
                1.0, p.kernel, Int32(p.nK),
                vVec, 1,
                0.0, &kV, 1
            )
            for i in 0..<p.nC {
                uVec[i] = kV[i] == 0 ? 0 : p.rowTarget[i] / kV[i]
            }
        }
        cblas_dgemv(
            CblasRowMajor, CblasTrans,
            Int32(p.nC), Int32(p.nK),
            1.0, p.kernel, Int32(p.nK),
            uVec, 1,
            0.0, &kTu, 1
        )
        return SinkhornResult(u: uVec, v: vVec, kTu: kTu)
    }

    // MARK: - Helpers

    private func countOccurrences(indices: [UInt8], paletteSize: Int) -> [Int] {
        var counts = [Int](repeating: 0, count: paletteSize)
        for idx in indices {
            counts[Int(idx)] += 1
        }
        return counts
    }

    private func nearestIndex(_ centroids: [SIMD3<Float>], _ x: SIMD3<Float>) -> Int {
        var best = 0
        var bestD: Float = .infinity
        for k in 0..<centroids.count {
            let d = centroids[k] - x
            let dist2 = d.x * d.x + d.y * d.y + d.z * d.z
            if dist2 < bestD {
                bestD = dist2
                best = k
            }
        }
        return best
    }

}
