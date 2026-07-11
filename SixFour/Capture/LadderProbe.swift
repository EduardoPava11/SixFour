import Foundation

/// THE LADDER PROBE — the device half of the ladder–color-time theorem, plus the
/// training-data capability census up the resolution ladder (Stage 0 of
/// docs/REBUILD-2026-07-10-PLAN.md; gated by `Feature.ladderProbe`).
///
/// Per burst tick (fed by `CaptureSession` right after `ColorHead.ingest`), the
/// probe pools the SAME converted x420 crop at every rung of `{16,32,64,128,256}`
/// that divides the actual crop — the 64 rung reuses the canonical direct sums,
/// the others tap `ColorHead.probePool` (same kernel, same crop, same
/// linearization; only the bin geometry differs). It then verifies the fold
/// algebra of `Spec.LadderColorTime` on the real photons:
///
///  * TRANSITIVITY (`lawPoolTransitive`): folding the independently-pooled 256²
///    (and 128²) sums down to 64² by exact u64 2×2 adds must be BYTE-IDENTICAL
///    to the direct crop→64² pool — two different pooling paths over the same
///    pixel partition. Likewise crop→64→32→16 vs the direct crop→16².
///  * FOLD SYMMETRY (`lawFoldOrderInvariant`): at burst end, the temporal
///    accumulation of the 64-rung cube in tick order vs reverse tick order must
///    agree — the commutative monoid does not care about arrival order.
///
/// Every rung's burst cube is HELD for the full burst (the honest memory test:
/// these cubes are exactly the training-data records the rebuild wants to
/// generate) and per-rung pool cost is timed against the 50 ms tick budget.
/// `summaryLines()` renders the once-per-burst `[proof]` log lines.
///
/// Deliberately AVFoundation-free and queue-confined (same delegate-queue
/// discipline as `ColorHead`); telemetry/log only — no GIF byte and no record
/// byte depends on the probe.
final class LadderProbe {

    /// The probe ladder, coarse to fine — `Spec.LadderColorTime.ladderSides`,
    /// symmetric about the canonical 64 (octaves 2,1,0,1,2).
    static let rungs = [16, 32, 64, 128, 256]
    /// The canonical rung every other rung folds onto (the "64 reality").
    static let canonicalRung = 64

    /// Per-rung burst state. `cube` is t-major (side·side·3 u64 per slice) —
    /// the same layout as the `.s4cr` v2 rung cubes.
    private struct RungState {
        let side: Int
        var cube: [UInt64] = []
        var frames = 0
        var poolNsTotal: UInt64 = 0
        var poolNsMax: UInt64 = 0
        var undividedTicks = 0
    }

    private var states: [RungState]
    private var ticks = 0
    private var cropSide = 0
    /// Fold-check tallies: [pass, fail] per identity, counted per tick.
    private var fold256Pass = 0, fold256Fail = 0
    private var fold128Pass = 0, fold128Fail = 0
    private var fold16Pass = 0, fold16Fail = 0

    init() {
        states = LadderProbe.rungs.map { RungState(side: $0) }
        // Reserve every rung cube UP FRONT (~128 MiB total): the probe is
        // constructed at burst setup, BEFORE frame 0 lands — reserving here
        // keeps the allocation (and its page faults) off the first tick.
        // PHASE P run 2026-07-11 measured the lazy version as a 95 ms first
        // tick and 2 dropped warmup frames; the checklist bar is dropped=0.
        for i in states.indices {
            states[i].cube.reserveCapacity(64 * states[i].side * states[i].side * 3)
        }
    }

    /// One probe tick. `directSums64` is the canonical crop→64² pool the shipped
    /// path already computed; the probe never re-pools the 64 rung (so the fold
    /// checks compare against the exact bytes the app ships, not a twin).
    func ingest(head: ColorHead, directSums64: [UInt64]) {
        ticks += 1
        cropSide = head.lastCropSide
        var sumsBySide = [Int: [UInt64]]()

        for i in states.indices {
            let side = states[i].side
            let sums: [UInt64]?
            if side == LadderProbe.canonicalRung {
                sums = directSums64
            } else {
                let t0 = DispatchTime.now().uptimeNanoseconds
                sums = head.probePool(outSide: side)
                let ns = DispatchTime.now().uptimeNanoseconds - t0
                if sums != nil {
                    states[i].poolNsTotal += ns
                    if ns > states[i].poolNsMax { states[i].poolNsMax = ns }
                }
            }
            guard let sums else {
                states[i].undividedTicks += 1
                continue
            }
            states[i].cube.append(contentsOf: sums)
            states[i].frames += 1
            sumsBySide[side] = sums
        }

        // TRANSITIVITY on this tick's photons (Spec.LadderColorTime.lawPoolTransitive):
        // fold the finer independent pools onto the canonical rung, byte-compare.
        if let s256 = sumsBySide[256] {
            let folded = ColorHead.poolSpatial2(ColorHead.poolSpatial2(s256, side: 256), side: 128)
            if folded == directSums64 { fold256Pass += 1 } else { fold256Fail += 1 }
        }
        if let s128 = sumsBySide[128] {
            if ColorHead.poolSpatial2(s128, side: 128) == directSums64 {
                fold128Pass += 1
            } else {
                fold128Fail += 1
            }
        }
        if let s16 = sumsBySide[16] {
            let via32 = ColorHead.poolSpatial2(ColorHead.poolSpatial2(directSums64, side: 64), side: 32)
            if via32 == s16 { fold16Pass += 1 } else { fold16Fail += 1 }
        }
    }

    /// FOLD SYMMETRY at burst end (`lawFoldOrderInvariant` on device): accumulate
    /// the canonical cube's slices elementwise in tick order and in REVERSE tick
    /// order — the commutative monoid must not see the arrival order.
    private func temporalFoldSymmetric() -> Bool? {
        guard let s = states.first(where: { $0.side == LadderProbe.canonicalRung }),
              s.frames > 0 else { return nil }
        let n = s.side * s.side * 3
        var forward = [UInt64](repeating: 0, count: n)
        var reverse = [UInt64](repeating: 0, count: n)
        for f in 0..<s.frames {
            let base = f * n
            for j in 0..<n { forward[j] &+= s.cube[base + j] }
        }
        for f in stride(from: s.frames - 1, through: 0, by: -1) {
            let base = f * n
            for j in 0..<n { reverse[j] &+= s.cube[base + j] }
        }
        return forward == reverse
    }

    private func mib(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / (1024 * 1024))
    }

    /// The once-per-burst `[proof]` lines (rendered here, logged by the caller —
    /// pure, so tests can assert on them without a camera or a logger).
    func summaryLines() -> [String] {
        var lines: [String] = []
        var totalBytes = 0
        for s in states.reversed() { // fine → coarse, the census reading order
            totalBytes += s.cube.count * MemoryLayout<UInt64>.stride
            if s.frames == 0 {
                lines.append("[proof] rung \(s.side)²: SKIPPED (\(s.undividedTicks) ticks; "
                    + "rung does not divide crop \(cropSide))")
                continue
            }
            let binPx = s.frames > 0 && cropSide >= s.side ? cropSide / s.side : 0
            var line = "[proof] rung \(s.side)²: \(s.frames)/\(ticks) frames, "
                + "crop \(cropSide)→\(binPx)×\(binPx) px bins"
            if s.side != LadderProbe.canonicalRung {
                let meanMs = Double(s.poolNsTotal) / Double(max(1, s.frames)) / 1e6
                let maxMs = Double(s.poolNsMax) / 1e6
                line += String(format: ", pool mean %.2f ms, max %.2f ms", meanMs, maxMs)
            } else {
                line += " (canonical — shipped path)"
            }
            line += ", cube \(mib(s.cube.count * MemoryLayout<UInt64>.stride)) MiB"
            lines.append(line)
        }
        func verdict(_ pass: Int, _ fail: Int, _ name: String) -> String {
            fail == 0 && pass > 0
                ? "[proof] fold: \(name) BYTE-IDENTICAL (\(pass)/\(pass) ticks — lawPoolTransitive on device)"
                : "[proof] fold: \(name) \(fail > 0 ? "FAILED \(fail)/\(pass + fail) ticks" : "not exercised")"
        }
        lines.append(verdict(fold256Pass, fold256Fail, "pool(256→64) == direct64"))
        lines.append(verdict(fold128Pass, fold128Fail, "pool(128→64) == direct64"))
        lines.append(verdict(fold16Pass, fold16Fail, "pool(64→32→16) == direct16"))
        switch temporalFoldSymmetric() {
        case .some(true):
            lines.append("[proof] foldl==foldr: temporal accumulation order-invariant "
                + "(lawFoldOrderInvariant on device)")
        case .some(false):
            lines.append("[proof] foldl==foldr: FAILED — temporal accumulation is order-sensitive")
        case .none:
            lines.append("[proof] foldl==foldr: not exercised (no canonical frames)")
        }
        if let c = states.first(where: { $0.side == LadderProbe.canonicalRung }), c.frames > 0 {
            lines.append("[proof] collapse: canonical 64³ cell-tensor record "
                + "\(mib(c.cube.count * MemoryLayout<UInt64>.stride)) MiB, "
                + "\(c.frames) slices × 64·64·3 u64")
        }
        lines.append("[proof] probe memory: \(mib(totalBytes)) MiB held across "
            + "\(states.filter { $0.frames > 0 }.count) rung cubes")
        return lines
    }
}
