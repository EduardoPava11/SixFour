import CoreVideo
import Testing
@testable import SixFour

/// Gate for the GIF89a-camera color head device circuit: the Zig floor
/// (`s4_pool_sums_bgra8`), the Metal path (`p16PoolSumsBGRA`) parity against
/// it, the exact-adds ladder cadence (20→10→5 Hz on the sums carrier), and the
/// kinematic halting-prior floor (`s4_certified_order`) on particle streams.
struct ColorHeadTests {

    /// A deterministic 32BGRA pixel buffer (LCG-filled, stride ≥ 4·width).
    private func makeBuffer(width: Int, height: Int, seed: UInt64) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        guard let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buf)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var s = seed
        for y in 0..<height {
            for i in 0..<(width * 4) {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                p[y * stride + i] = UInt8((s >> 33) & 0xff)
            }
        }
        return buf
    }

    @Test func zigFloorPoolsConstantBufferExactly() throws {
        // Constant color: every 64-rung bin sum must be q² · channel value.
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 128, 128,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        let buf = try #require(pb)
        CVPixelBufferLockBaseAddress(buf, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buf))
        let stride = CVPixelBufferGetBytesPerRow(buf)
        let p = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<128 {
            for x in 0..<128 {
                p[y * stride + x * 4] = 30      // B
                p[y * stride + x * 4 + 1] = 20  // G
                p[y * stride + x * 4 + 2] = 10  // R
                p[y * stride + x * 4 + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buf, [])

        let head = ColorHead(cropSide: 128)
        let sums = try #require(head.poolSums64(from: buf))
        // crop side 128, 64 bins → q = 2, area 4.
        #expect(sums[0] == 4 * 10) // R
        #expect(sums[1] == 4 * 20) // G
        #expect(sums[2] == 4 * 30) // B
        #expect(sums.count == 64 * 64 * 3)
        // Every bin of a constant frame carries the same per-channel sums.
        for bin in 0..<(64 * 64) {
            #expect(sums[bin * 3] == 40 && sums[bin * 3 + 1] == 80 && sums[bin * 3 + 2] == 120)
        }
    }

    /// The GPU path must match the Zig floor u64-for-u64 (deterministic
    /// integer accumulation, same crop contract). Skips where Metal is absent.
    @Test func metalParityAgainstZigFloor() throws {
        guard let metal = ColorHeadMetal() else { return } // no GPU: floor-only
        let buf = try #require(makeBuffer(width: 320, height: 240, seed: 20260704))
        let head = ColorHead(cropSide: 192)
        let zig = try #require(head.poolSums64(from: buf))
        let gpu = try #require(metal.poolSums64(from: buf, maxSide: 192))
        #expect(zig == gpu)
    }

    /// The ladder derives 32/16 rungs by exact adds on the sums carrier, at
    /// the GIF-exact cadences: 32-rung every 2nd tick, 16-rung + GCT every
    /// 4th; transitivity means the 16-rung equals the direct 2×2×2×(2×2)
    /// pooling of the four source ticks.
    @Test func ladderCadenceAndTransitivity() throws {
        let head = ColorHead(cropSide: 128)
        var frames: [[UInt64]] = []
        for t in 0..<4 {
            let buf = try #require(makeBuffer(width: 128, height: 128, seed: 7 &+ UInt64(t)))
            let sums = try #require(head.poolSums64(from: buf))
            frames.append(sums)
            head.ingest(sums)
        }
        #expect(head.tick == 4)
        let f16 = try #require(head.latest16)
        // Direct: pool each tick 64→16 spatially (two 2×2 steps), then sum all four.
        var direct = [UInt64](repeating: 0, count: 16 * 16 * 3)
        for f in frames {
            let s32 = ColorHead.poolSpatial2(f, side: 64)
            let s16 = ColorHead.poolSpatial2(s32, side: 32)
            for i in 0..<direct.count { direct[i] += s16[i] }
        }
        #expect(f16 == direct)
        #expect(head.latestGCT?.count == 768)
    }

    /// Constant scene → every particle certifies order 0; a linearly ramping
    /// scene certifies order 1 — the halting-prior floor from exact integers.
    @Test func haltFloorCertifiesKinematicOrder() {
        let head = ColorHead(cropSide: 128, historyTicks: 16)
        let base = [UInt64](repeating: 5, count: 64 * 64 * 3)
        // 24 ticks → 6 sixteen-rung frames; constant per-tick sums.
        for _ in 0..<24 { head.ingest(base) }
        let ordersConst = head.haltFloor(cap: 3)
        #expect(ordersConst.allSatisfy { $0 == 0 })

        // Ramping scene: per-tick sums grow linearly → 16-rung frames (sums of
        // 4 ticks) are also linear in the frame index → order 1.
        let head2 = ColorHead(cropSide: 128, historyTicks: 16)
        for t in 0..<24 {
            head2.ingest([UInt64](repeating: UInt64(1 + t), count: 64 * 64 * 3))
        }
        let ordersRamp = head2.haltFloor(cap: 3)
        #expect(ordersRamp.allSatisfy { $0 == 1 })
    }
}
