import CoreVideo
import Testing
@testable import SixFour

/// THE MEASUREMENT PATH'S SWIFT HALF, GATED: the capture contract in
/// `palette16.zig` assigns Swift the Y'CbCr→R'G'B' integer BT.2020 matrix and
/// the video→full range expansion; the Zig floor owns everything after (HLG
/// golden LUT + linear pooling). These tests pin the Swift half to the float
/// BT.2020 reference (±1 code) and the endpoints exactly, then run one
/// synthetic x420 buffer end to end through `s4_pool_sums_linear_hlg10`.
struct X420MeasurementPathTests {

    // MARK: - The endpoints are exact

    @Test func videoRangeEndpointsAreExact() {
        // Video black / white with neutral chroma.
        let black = ColorHead.x420RGB10(y: 64, cb: 512, cr: 512)
        #expect(black == (0, 0, 0))
        let white = ColorHead.x420RGB10(y: 940, cb: 512, cr: 512)
        #expect(white == (1023, 1023, 1023))
        // Range expansion is a clamp, not absorption: sub-black and super-white
        // pin to the rails.
        let subBlack = ColorHead.x420RGB10(y: 0, cb: 512, cr: 512)
        #expect(subBlack == (0, 0, 0))
        let superWhite = ColorHead.x420RGB10(y: 1023, cb: 512, cr: 512)
        #expect(superWhite == (1023, 1023, 1023))
    }

    @Test func neutralChromaIsAchromatic() {
        for y in Swift.stride(from: 64, through: 940, by: 73) {
            let (r, g, b) = ColorHead.x420RGB10(y: y, cb: 512, cr: 512)
            #expect(r == g && g == b)
        }
    }

    // MARK: - The integer matrix tracks the float BT.2020 reference

    /// Float BT.2020 NCL reference (Kr 0.2627, Kb 0.0593): normalized
    /// Y = (Y'−64)/876, C = (C'−512)/896; R = Y + 1.4746·Cr,
    /// G = Y − 0.16455·Cb − 0.57135·Cr, B = Y + 1.8814·Cb; ×1023, clamped.
    private func reference(y: Int, cb: Int, cr: Int) -> (Double, Double, Double) {
        let yn = Double(y - 64) / 876.0
        let cbn = Double(cb - 512) / 896.0
        let crn = Double(cr - 512) / 896.0
        let clamp: (Double) -> Double = { min(1023, max(0, $0 * 1023)) }
        return (clamp(yn + 1.4746 * crn),
                clamp(yn - 0.16455 * cbn - 0.57135 * crn),
                clamp(yn + 1.8814 * cbn))
    }

    @Test func integerMatrixMatchesFloatReferenceWithinOneCode() {
        for y in Swift.stride(from: 64, through: 940, by: 41) {
            for cb in Swift.stride(from: 64, through: 960, by: 89) {
                for cr in Swift.stride(from: 64, through: 960, by: 89) {
                    let (r, g, b) = ColorHead.x420RGB10(y: y, cb: cb, cr: cr)
                    let (rf, gf, bf) = reference(y: y, cb: cb, cr: cr)
                    #expect(abs(Double(r) - rf) <= 1.0, "R at y=\(y) cb=\(cb) cr=\(cr)")
                    #expect(abs(Double(g) - gf) <= 1.0, "G at y=\(y) cb=\(cb) cr=\(cr)")
                    #expect(abs(Double(b) - bf) <= 1.0, "B at y=\(y) cb=\(cb) cr=\(cr)")
                }
            }
        }
    }

    // MARK: - End to end: synthetic x420 buffer → linear16 bin sums

    /// A wSide×hSide x420 buffer filled with one (y, cb, cr): samples sit in
    /// the top 10 bits of 16-bit words, chroma interleaved CbCr at 4:2:0.
    private func makeX420(w: Int, h: Int, y: UInt16, cb: UInt16, cr: UInt16) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                  kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                  nil, &pb) == kCVReturnSuccess, let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0) / 2
        let yPtr = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt16.self)
        for row in 0..<h {
            for col in 0..<w { yPtr[row * yStride + col] = y << 6 }
        }
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1) / 2
        let cH = CVPixelBufferGetHeightOfPlane(pb, 1)
        let cW = CVPixelBufferGetWidthOfPlane(pb, 1)
        let cPtr = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt16.self)
        for row in 0..<cH {
            for col in 0..<cW {
                cPtr[row * cStride + col * 2] = cb << 6
                cPtr[row * cStride + col * 2 + 1] = cr << 6
            }
        }
        return pb
    }

    @Test func constantWhitePoolsToFullScaleLinearSums() {
        let head = ColorHead(cropSide: 128)
        guard let pb = makeX420(w: 192, h: 128, y: 940, cb: 512, cr: 512) else {
            Issue.record("x420 CVPixelBuffer unavailable"); return
        }
        guard let sums = head.poolSums64(fromX420: pb) else {
            Issue.record("poolSums64(fromX420:) refused a valid buffer"); return
        }
        // 128-px crop into 64 bins ⇒ 4 px per bin, every pixel full-range white
        // ⇒ each channel sum is exactly 4 × hlg_to_linear16(1023).
        let expected = UInt64(4) * UInt64(s4_hlg10_to_linear16(1023))
        #expect(sums.allSatisfy { $0 == expected })
    }

    @Test func bgraBufferIsRefusedByTheX420Path() {
        let head = ColorHead(cropSide: 128)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 128, 128,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pb else { Issue.record("BGRA CVPixelBuffer unavailable"); return }
        #expect(head.poolSums64(fromX420: pb) == nil)
    }
}
