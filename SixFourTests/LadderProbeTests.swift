import CoreVideo
import Testing
@testable import SixFour

/// THE LADDER PROBE, GATED WITHOUT A CAMERA: synthetic x420 bursts drive the
/// probe end to end — every rung of {16,32,64,128,256} pools from the same
/// crop, the fold byte-identities (`Spec.LadderColorTime.lawPoolTransitive` /
/// `lawFoldOrderInvariant` on device) hold on NON-uniform content, honest
/// SKIPPED reporting for rungs that don't divide the crop, and the `[proof]`
/// summary lines carry the shapes the device checklist reads. The content
/// varies per pixel AND per tick so an indexing bug (transposed bins, wrong
/// stride, off-by-one crop) cannot pass the byte-identity vacuously.
struct LadderProbeTests {

    /// A synthetic x420 buffer whose luma varies per pixel via `yAt` (video
    /// range 64…940) over neutral-but-varying chroma — same plane layout as the
    /// capture feed (10-bit codes in the top bits of 16-bit words).
    private func makeX420(w: Int, h: Int, yAt: (Int, Int) -> UInt16) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                  kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                  nil, &pb) == kCVReturnSuccess, let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0) / 2
        let yPtr = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt16.self)
        for row in 0..<h {
            for col in 0..<w { yPtr[row * yStride + col] = yAt(row, col) << 6 }
        }
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1) / 2
        let cH = CVPixelBufferGetHeightOfPlane(pb, 1)
        let cW = CVPixelBufferGetWidthOfPlane(pb, 1)
        let cPtr = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt16.self)
        for row in 0..<cH {
            for col in 0..<cW {
                cPtr[row * cStride + col * 2] = UInt16(512 + (row + col) % 64) << 6
                cPtr[row * cStride + col * 2 + 1] = UInt16(512 - (row * 3) % 64) << 6
            }
        }
        return pb
    }

    /// Drive `ticks` synthetic frames through head + probe; content shifts per
    /// tick so the temporal fold has real structure.
    private func runBurst(head: ColorHead, probe: LadderProbe, w: Int, h: Int, ticks: Int) -> Bool {
        for t in 0..<ticks {
            guard let pb = makeX420(w: w, h: h, yAt: { row, col in
                UInt16(64 + (row * 31 + col * 7 + t * 131) % 877)
            }) else { return false }
            guard let sums = head.poolSums64(fromX420: pb) else { return false }
            head.ingest(sums)
            probe.ingest(head: head, directSums64: sums)
        }
        return true
    }

    @Test func allRungsPoolAndFoldsAreByteIdentical() {
        // Crop 256: every probe rung {16,32,64,128,256} divides it.
        let head = ColorHead(cropSide: 256)
        let probe = LadderProbe()
        guard runBurst(head: head, probe: probe, w: 320, h: 256, ticks: 4) else {
            Issue.record("synthetic burst refused"); return
        }
        let lines = probe.summaryLines()
        // Every rung arrived every tick.
        for side in [16, 32, 64, 128, 256] {
            #expect(lines.contains { $0.contains("rung \(side)²: 4/4 frames") },
                    "missing rung \(side)² census line in \(lines)")
        }
        // The three transitivity identities held on every tick, byte-exact.
        #expect(lines.contains { $0.contains("pool(256→64) == direct64 BYTE-IDENTICAL (4/4") })
        #expect(lines.contains { $0.contains("pool(128→64) == direct64 BYTE-IDENTICAL (4/4") })
        #expect(lines.contains { $0.contains("pool(64→32→16) == direct16 BYTE-IDENTICAL (4/4") })
        // The temporal fold is order-invariant and the canonical collapse reports.
        #expect(lines.contains { $0.contains("foldl==foldr: temporal accumulation order-invariant") })
        #expect(lines.contains { $0.contains("collapse: canonical 64³ cell-tensor record") })
        #expect(lines.contains { $0.contains("4 slices × 64·64·3 u64") })
    }

    @Test func nonDividingRungsReportSkippedHonestly() {
        // Crop 192: 16/32/64 divide, 128 and 256 do not — the probe must say so,
        // never silently truncate the census (the no-silent-caps rule).
        let head = ColorHead(cropSide: 192)
        let probe = LadderProbe()
        guard runBurst(head: head, probe: probe, w: 192, h: 192, ticks: 2) else {
            Issue.record("synthetic burst refused"); return
        }
        let lines = probe.summaryLines()
        #expect(lines.contains { $0.contains("rung 256²: SKIPPED") && $0.contains("crop 192") })
        #expect(lines.contains { $0.contains("rung 128²: SKIPPED") && $0.contains("crop 192") })
        #expect(lines.contains { $0.contains("rung 64²: 2/2 frames") })
        #expect(lines.contains { $0.contains("pool(64→32→16) == direct16 BYTE-IDENTICAL (2/2") })
        // The unexercised fine folds must say so, not claim a pass.
        #expect(lines.contains { $0.contains("pool(256→64) == direct64 not exercised") })
    }

    @Test func probePoolRefusesOutsideTheX420Path() {
        // No x420 frame has pooled: the tap must refuse (no scratch to pool).
        let head = ColorHead(cropSide: 256)
        #expect(head.probePool(outSide: 64) == nil)
        // And a non-dividing rung refuses even after a valid frame.
        guard let pb = makeX420(w: 320, h: 256, yAt: { _, _ in 512 }),
              head.poolSums64(fromX420: pb) != nil else {
            Issue.record("synthetic frame refused"); return
        }
        #expect(head.probePool(outSide: 96) == nil)   // 256 % 96 != 0
        #expect(head.probePool(outSide: 128) != nil)
    }
}
