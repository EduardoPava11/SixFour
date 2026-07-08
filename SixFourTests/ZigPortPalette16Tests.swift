//  ZigPortPalette16Tests.swift
//  Swift port of Native/src/palette16_test.zig (2026-07-06). Test methods are
//  named after the Zig test names, one method per Zig `test`.
//  (Native/src/palette16_bench.zig is a benchmark harness — NOT ported.)
//
//  Host tests for the GIF89a-camera color head. Self-contained: no fixtures,
//  no allocator in the kernels under test. The two load-bearing tests mirror
//  the Haskell spec:
//    * SUMS ARE THE PYRAMID CARRIER: pooling composes exactly on block-sums
//      (Spec.V21Pyramid lawPyramidTransitive, here byte-for-byte).
//    * MEANS ARE NOT: a witness where round-half-up means pooled 64->32->16
//      differ from 64->16 — why the GCT is a final realization, never a rung.

import XCTest
@testable import SixFour

final class ZigPortPalette16Tests: XCTestCase {

    /// The Zig test file's deterministic LCG fill (fillLcg).
    private func fillLcg(_ buf: inout [UInt8], _ seed0: UInt64) {
        var s = seed0
        for i in 0..<buf.count {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            buf[i] = UInt8((s >> 33) & 0xff)
        }
    }

    // test "constant frame: every palette slot is that color (16x16 = 256 slots)"
    func testConstantFrameEveryPaletteSlotIsThatColor() {
        var frame = [UInt8](repeating: 0, count: 64 * 64 * 3)
        var i = 0
        while i < frame.count {
            frame[i] = 10
            frame[i + 1] = 20
            frame[i + 2] = 30
            i += 3
        }
        var gct = [UInt8](repeating: 0, count: 768)
        XCTAssertEqual(S4_RC_OK, s4_palette16_gct(frame, 64, &gct))
        i = 0
        while i < 768 {
            XCTAssertEqual(UInt8(10), gct[i])
            XCTAssertEqual(UInt8(20), gct[i + 1])
            XCTAssertEqual(UInt8(30), gct[i + 2])
            i += 3
        }
    }

    // test "bin-constant frame: the GCT is exactly the scene's own 16x16 view"
    func testBinConstantFrameGCTIsExactlyTheScenesOwn16x16View() {
        // 32x32 frame, q=2: paint each 2x2 bin with the byte (by*16+bx) mod 256 on
        // all channels — the palette must reproduce the bin values verbatim.
        var frame = [UInt8](repeating: 0, count: 32 * 32 * 3)
        for y in 0..<32 {
            for x in 0..<32 {
                let v = UInt8(((y / 2) * 16 + (x / 2)) & 0xff)
                let px = (y * 32 + x) * 3
                frame[px] = v
                frame[px + 1] = v
                frame[px + 2] = v
            }
        }
        var gct = [UInt8](repeating: 0, count: 768)
        XCTAssertEqual(S4_RC_OK, s4_palette16_gct(frame, 32, &gct))
        for slot in 0..<256 {
            let v = UInt8(slot & 0xff)
            XCTAssertEqual(v, gct[slot * 3])
            XCTAssertEqual(v, gct[slot * 3 + 1])
            XCTAssertEqual(v, gct[slot * 3 + 2])
        }
    }

    // test "rounding realization is round-half-up, deterministic"
    func testRoundingRealizationIsRoundHalfUpDeterministic() {
        // One 2x2 bin (side=2, out_side=1): {0,1,1,1} -> 0.75 -> 1; {0,0,0,1} ->
        // 0.25 -> 0; {0,0,1,1} -> 0.5 -> 1 (half rounds UP, documented).
        let cases: [(px: [UInt8], want: UInt8)] = [
            (px: [0, 1, 1, 1], want: 1),
            (px: [0, 0, 0, 1], want: 0),
            (px: [0, 0, 1, 1], want: 1),
        ]
        for c in cases {
            var frame = [UInt8](repeating: 0, count: 2 * 2 * 3)
            for i in 0..<4 {
                frame[i * 3] = c.px[i]
                frame[i * 3 + 1] = c.px[i]
                frame[i * 3 + 2] = c.px[i]
            }
            var sums = [UInt64](repeating: 0, count: 3)
            XCTAssertEqual(S4_RC_OK, s4_pool_sums_srgb8(frame, 2, 1, &sums))
            var out = [UInt8](repeating: 0, count: 3)
            XCTAssertEqual(S4_RC_OK, s4_sums_to_srgb8(sums, 1, 4, &out))
            XCTAssertEqual(c.want, out[0])
        }
    }

    // test "LAW (pyramid carrier): block-sums compose exactly, 64->16 == 64->32->16"
    func testLawPyramidCarrierBlockSumsComposeExactly64To16Equals64To32To16() {
        var frame = [UInt8](repeating: 0, count: 64 * 64 * 3)
        fillLcg(&frame, 20260703)

        var direct = [UInt64](repeating: 0, count: 16 * 16 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_srgb8(frame, 64, 16, &direct))

        // Two-step: sums to 32, re-expressed as a synthetic image is impossible
        // without loss — so compose on SUMS directly: pool the 32x32 sums by 2x2
        // block-sum addition (what pooling means on the carrier).
        var mid = [UInt64](repeating: 0, count: 32 * 32 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_srgb8(frame, 64, 32, &mid))
        var twostep = [UInt64](repeating: 0, count: 16 * 16 * 3)
        for by in 0..<16 {
            for bx in 0..<16 {
                for c in 0..<3 {
                    var acc: UInt64 = 0
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            acc += mid[(((by * 2 + dy) * 32) + (bx * 2 + dx)) * 3 + c]
                        }
                    }
                    twostep[(by * 16 + bx) * 3 + c] = acc
                }
            }
        }
        XCTAssertEqual(direct, twostep)
    }

    // test "TEETH: rounded means do NOT compose across rungs (why sums are the carrier)"
    func testTeethRoundedMeansDoNotComposeAcrossRungs() {
        // Search small frames deterministically for a witness where rounding at
        // the mid rung shifts the final byte (instead of hand-picking one).
        var found = false
        var seed: UInt64 = 1
        while seed < 200 && !found {
            var frame = [UInt8](repeating: 0, count: 4 * 4 * 3)
            fillLcg(&frame, seed)

            // direct: 4x4 -> 1x1 mean
            var s1 = [UInt64](repeating: 0, count: 3)
            _ = s4_pool_sums_srgb8(frame, 4, 1, &s1)
            var direct = [UInt8](repeating: 0, count: 3)
            _ = s4_sums_to_srgb8(s1, 1, 16, &direct)

            // staged: 4x4 -> 2x2 bytes -> 1x1 bytes (rounding TWICE)
            var s2 = [UInt64](repeating: 0, count: 2 * 2 * 3)
            _ = s4_pool_sums_srgb8(frame, 4, 2, &s2)
            var mid = [UInt8](repeating: 0, count: 2 * 2 * 3)
            _ = s4_sums_to_srgb8(s2, 2, 4, &mid)
            var s3 = [UInt64](repeating: 0, count: 3)
            _ = s4_pool_sums_srgb8(mid, 2, 1, &s3)
            var staged = [UInt8](repeating: 0, count: 3)
            _ = s4_sums_to_srgb8(s3, 1, 4, &staged)

            if direct != staged { found = true }
            seed += 1
        }
        XCTAssertTrue(found)
    }

    // test "bad args are refused, not absorbed"
    func testBadArgsAreRefusedNotAbsorbed() {
        var frame = [UInt8](repeating: 0, count: 48 * 48 * 3)
        fillLcg(&frame, 7)
        var gct = [UInt8](repeating: 0, count: 768)
        // 48 is a multiple of 16 -> OK; 40 is not.
        XCTAssertEqual(S4_RC_OK, s4_palette16_gct(frame, 48, &gct))
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_palette16_gct(frame, 40, &gct))
        var sums = [UInt64](repeating: 0, count: 3)
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_pool_sums_srgb8(frame, 48, 0, &sums))
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_pool_sums_srgb8(frame, 16, 48, &sums))
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_pool_sums_srgb8(nil, 16, 16, &sums))
    }

    // test "LAW (the time law): GIF89a centiseconds cap the isotropic ladder at 64"
    func testLawTheTimeLawGIF89aCentisecondsCapTheIsotropicLadderAt64() {
        XCTAssertEqual(Int32(5), s4_ladder_delay_cs(64)) // 20 fps
        XCTAssertEqual(Int32(10), s4_ladder_delay_cs(32)) // 10 fps
        XCTAssertEqual(Int32(20), s4_ladder_delay_cs(16)) //  5 fps
        XCTAssertEqual(Int32(40), s4_ladder_delay_cs(8)) //  2.5 fps
        // 128 @ 40 fps needs 2.5 cs — GIF89a cannot say it.
        XCTAssertEqual(S4_RC_NOT_REPRESENTABLE, s4_ladder_delay_cs(128))
        XCTAssertEqual(S4_RC_NOT_REPRESENTABLE, s4_ladder_delay_cs(256))
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_ladder_delay_cs(0))
    }

    // ── The measurement path: inverse-EOTF LUTs + linear pooling ──

    // test "GOLDEN SPOTS: sRGB and HLG inverse-EOTF tables match the reference math"
    func testGoldenSpotsSRGBAndHLGInverseEOTFTablesMatchTheReferenceMath() {
        // sRGB: lin = c/12.92 (c<=0.04045) else ((c+0.055)/1.055)^2.4, c=v/255.
        XCTAssertEqual(UInt16(0), srgb_to_linear16[0])
        XCTAssertEqual(UInt16(20), srgb_to_linear16[1])
        XCTAssertEqual(UInt16(199), srgb_to_linear16[10]) // linear segment
        XCTAssertEqual(UInt16(219), srgb_to_linear16[11]) // past threshold
        XCTAssertEqual(UInt16(14146), srgb_to_linear16[128]) // mid-gray
        XCTAssertEqual(UInt16(65535), srgb_to_linear16[255])
        // HLG (BT.2100 inverse OETF, full-range 10-bit): e^2/3 below the knee.
        XCTAssertEqual(UInt16(0), hlg_to_linear16[0])
        XCTAssertEqual(UInt16(5451), hlg_to_linear16[511]) // knee left
        XCTAssertEqual(UInt16(5472), hlg_to_linear16[512]) // knee right
        XCTAssertEqual(UInt16(65186), hlg_to_linear16[1022])
        XCTAssertEqual(UInt16(65535), hlg_to_linear16[1023]) // clamped top
    }

    // test "LAW: both LUTs are monotone nondecreasing (a valid transfer inverse)"
    func testLawBothLUTsAreMonotoneNondecreasing() {
        for i in 0..<255 {
            XCTAssertLessThanOrEqual(srgb_to_linear16[i], srgb_to_linear16[i + 1])
        }
        for i in 0..<1023 {
            XCTAssertLessThanOrEqual(hlg_to_linear16[i], hlg_to_linear16[i + 1])
        }
    }

    // test "linear pooling, constant frame: sums == area * LUT[v] exactly (both feeds)"
    func testLinearPoolingConstantFrameSumsEqualAreaTimesLUTExactlyBothFeeds() {
        let frame8 = [UInt8](repeating: 200, count: 32 * 32 * 3)
        var sums = [UInt64](repeating: 0, count: 16 * 16 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_linear_srgb8(frame8, 32, 16, &sums))
        for v in sums { XCTAssertEqual(4 * UInt64(srgb_to_linear16[200]), v) }

        let frame10 = [UInt16](repeating: 700, count: 32 * 32 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_linear_hlg10(frame10, 32, 16, &sums))
        for v in sums { XCTAssertEqual(4 * UInt64(hlg_to_linear16[700]), v) }
    }

    // test "TOTALITY: an out-of-range 10-bit code refuses the WHOLE frame, no partial sums"
    func testTotalityAnOutOfRange10BitCodeRefusesTheWholeFrameNoPartialSums() {
        var frame10 = [UInt16](repeating: 100, count: 16 * 16 * 3)
        frame10[frame10.count - 1] = 1024 // one poison code at the very end
        var sums = [UInt64](repeating: 0xAAAAAAAAAAAAAAAA, count: 16 * 16 * 3)
        XCTAssertEqual(S4_RC_OUT_OF_RANGE, s4_pool_sums_linear_hlg10(frame10, 16, 16, &sums))
        for v in sums { XCTAssertEqual(UInt64(0xAAAAAAAAAAAAAAAA), v) } // untouched
        XCTAssertEqual(S4_RC_OUT_OF_RANGE, s4_hlg10_to_linear16(1024))
        XCTAssertEqual(Int32(hlg_to_linear16[1023]), s4_hlg10_to_linear16(1023))
    }

    // test "TEETH (the mid-gray trap): gamma-pool-then-linearize != linearize-then-pool, 2.3x apart"
    func testTeethTheMidGrayTrapGammaPoolThenLinearizeNotEqualLinearizeThenPool() {
        // One 2x2 bin: {0, 0, 255, 255} on all channels.
        var frame = [UInt8](repeating: 0, count: 2 * 2 * 3)
        for i in 0..<4 {
            let v: UInt8 = i < 2 ? 0 : 255
            frame[i * 3] = v
            frame[i * 3 + 1] = v
            frame[i * 3 + 2] = v
        }
        // Gamma path: pool bytes -> byte 128 -> linearize -> 14146.
        var gsums = [UInt64](repeating: 0, count: 3)
        _ = s4_pool_sums_srgb8(frame, 2, 1, &gsums)
        var gbyte = [UInt8](repeating: 0, count: 3)
        _ = s4_sums_to_srgb8(gsums, 1, 4, &gbyte)
        XCTAssertEqual(UInt8(128), gbyte[0])
        let gammaThenLin = UInt64(srgb_to_linear16[Int(gbyte[0])])
        // Linear path: linearize -> pool -> mean 32768 (round-half-up of 32767.5).
        var lsums = [UInt64](repeating: 0, count: 3)
        _ = s4_pool_sums_linear_srgb8(frame, 2, 1, &lsums)
        let linMean: UInt64 = (lsums[0] + 2) / 4
        XCTAssertEqual(UInt64(14146), gammaThenLin)
        XCTAssertEqual(UInt64(32768), linMean)
        XCTAssertTrue(2 * gammaThenLin < linMean) // the trap is >2x, not a rounding nit
    }

    // test "LAW: linear sums keep the transitive carrier property, 64->16 == 64->32->16"
    func testLawLinearSumsKeepTheTransitiveCarrierProperty64To16Equals64To32To16() {
        var frame = [UInt8](repeating: 0, count: 64 * 64 * 3)
        fillLcg(&frame, 99)
        var direct = [UInt64](repeating: 0, count: 16 * 16 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_linear_srgb8(frame, 64, 16, &direct))
        var mid = [UInt64](repeating: 0, count: 32 * 32 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_linear_srgb8(frame, 64, 32, &mid))
        var twostep = [UInt64](repeating: 0, count: 16 * 16 * 3)
        for by in 0..<16 {
            for bx in 0..<16 {
                for c in 0..<3 {
                    var acc: UInt64 = 0
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            acc += mid[(((by * 2 + dy) * 32) + (bx * 2 + dx)) * 3 + c]
                        }
                    }
                    twostep[(by * 16 + bx) * 3 + c] = acc
                }
            }
        }
        XCTAssertEqual(direct, twostep)
    }

    // ── The inverse-EOTF realization: linear16 sums → sRGB8 (Spec.RadiometricRealize) ──

    // test "GOLDEN SPOTS: srgb_encode_thresh16 matches the reference math"
    func testGoldenSpotsSrgbEncodeThresh16MatchesTheReferenceMath() {
        // thresh[v] = round(srgbToLinear((v-0.5)/255)*65535); thresh[0]=0.
        XCTAssertEqual(UInt16(0), srgb_encode_thresh16[0])
        XCTAssertEqual(UInt16(10), srgb_encode_thresh16[1])
        XCTAssertEqual(UInt16(30), srgb_encode_thresh16[2])
        XCTAssertEqual(UInt16(189), srgb_encode_thresh16[10])
        XCTAssertEqual(UInt16(3309), srgb_encode_thresh16[64])
        XCTAssertEqual(UInt16(14027), srgb_encode_thresh16[128])
        XCTAssertEqual(UInt16(65243), srgb_encode_thresh16[255])
    }

    // test "LAW: srgb_encode_thresh16 is monotone nondecreasing"
    func testLawSrgbEncodeThresh16IsMonotoneNondecreasing() {
        for i in 0..<255 {
            XCTAssertLessThanOrEqual(srgb_encode_thresh16[i], srgb_encode_thresh16[i + 1])
        }
    }

    // test "KEYSTONE LAW: encode is the EXACT inverse of the decode (round-trips all 256 codes)"
    func testKeystoneLawEncodeIsTheExactInverseOfTheDecodeRoundTripsAll256Codes() {
        for v in 0..<256 {
            XCTAssertEqual(UInt8(v), s4_linear16_to_srgb8(srgb_to_linear16[v]))
        }
        // Endpoints and the mid-gray witness.
        XCTAssertEqual(UInt8(0), s4_linear16_to_srgb8(0))
        XCTAssertEqual(UInt8(255), s4_linear16_to_srgb8(65535))
        XCTAssertEqual(UInt8(128), s4_linear16_to_srgb8(14146))
        XCTAssertEqual(UInt8(188), s4_linear16_to_srgb8(32768))
    }

    // test "end-to-end sRGB-primary realization: hand-mean sums = count*14146 → byte 128"
    func testEndToEndSRGBPrimaryRealizationHandMeanSumsCount14146GivesByte128() {
        let count: Int64 = 256
        let sums = [UInt64](repeating: UInt64(14146) * UInt64(count), count: 16 * 16 * 3)
        var out = [UInt8](repeating: 0, count: 768)
        XCTAssertEqual(S4_RC_OK, s4_sums_to_srgb8_linear(sums, 16, count, &out))
        for b in out { XCTAssertEqual(UInt8(128), b) }
    }

    // test "constant-frame realization: pool_linear_srgb8 then realize == the byte back"
    func testConstantFrameRealizationPoolLinearSrgb8ThenRealizeEqualsTheByteBack() {
        // A constant sRGB byte 200: linearize → pool → mean == srgb_to_linear16[200]
        // → encode round-trips to 200 (encode∘decode identity).
        let frame = [UInt8](repeating: 200, count: 32 * 32 * 3)
        var sums = [UInt64](repeating: 0, count: 16 * 16 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_linear_srgb8(frame, 32, 16, &sums))
        var out = [UInt8](repeating: 0, count: 768)
        let area: Int64 = 4 // (32/16)^2
        XCTAssertEqual(S4_RC_OK, s4_sums_to_srgb8_linear(sums, 16, area, &out))
        for b in out { XCTAssertEqual(UInt8(200), b) }
    }

    // test "EDGE/TOTALITY: count<=0 and mean>65535 refuse; black→0, saturation→255"
    func testEdgeTotalityCountLeqZeroAndMeanOver65535RefuseBlackToZeroSaturationTo255() {
        var sums: [UInt64] = [0, 0, 0]
        var out = [UInt8](repeating: 0, count: 3)
        // count<=0 → BAD_ARGS (uninitialized-crop / black case).
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_sums_to_srgb8_linear(sums, 1, 0, &out))
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_sums_bt2020_to_srgb8(sums, 1, 0, &out))
        // black: sum 0, count 4 → mean 0 → byte 0.
        XCTAssertEqual(S4_RC_OK, s4_sums_to_srgb8_linear(sums, 1, 4, &out))
        XCTAssertEqual(UInt8(0), out[0])
        // saturation: sum = count*65535 → mean 65535 → byte 255.
        sums = [4 * 65535, 4 * 65535, 4 * 65535]
        XCTAssertEqual(S4_RC_OK, s4_sums_to_srgb8_linear(sums, 1, 4, &out))
        XCTAssertEqual(UInt8(255), out[0])
        // mean>65535 (byte-sums fed by mistake, or too-small count) → BAD_ARGS.
        sums = [4 * 65535 + 4, 0, 0]
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_sums_to_srgb8_linear(sums, 1, 4, &out))
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_sums_bt2020_to_srgb8(sums, 1, 4, &out))
    }

    // test "TEETH: realize (mean-then-encode) does NOT compose across rungs"
    func testTeethRealizeMeanThenEncodeDoesNotComposeAcrossRungs() {
        // Same style as the gamma teeth: search small linear16 frames where the
        // round-half-up linear MEAN encoded once differs from encoding the mid rung
        // then re-meaning the codes. Non-linear encode ⇒ a witness must exist.
        var found = false
        var seed: UInt64 = 1
        while seed < 300 && !found {
            // 4 linear16 leaves in one channel (a 2x2 bin), values in [0,65535].
            var leaves = [UInt64](repeating: 0, count: 4)
            var s = seed
            for i in 0..<4 {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                leaves[i] = (s >> 40) & 0xFFFF
            }
            // direct: mean of 4 → encode once.
            let direct = s4_linear16_to_srgb8(UInt16((leaves[0] + leaves[1] + leaves[2] + leaves[3] + 2) / 4))
            // staged: encode each pair-mean (2 sub-bins), decode back, re-mean, encode.
            let m0 = UInt16((leaves[0] + leaves[1] + 1) / 2)
            let m1 = UInt16((leaves[2] + leaves[3] + 1) / 2)
            let b0 = s4_linear16_to_srgb8(m0)
            let b1 = s4_linear16_to_srgb8(m1)
            let staged = s4_linear16_to_srgb8(
                UInt16((UInt64(srgb_to_linear16[Int(b0)]) + UInt64(srgb_to_linear16[Int(b1)]) + 1) / 2))
            if direct != staged { found = true }
            seed += 1
        }
        XCTAssertTrue(found)
    }

    // test "BT.2020→sRGB gamut: grey axis is a bit-exact fixed point; endpoints hold"
    func testBT2020ToSRGBGamutGreyAxisIsABitExactFixedPointEndpointsHold() {
        // Row sums == 32768 ⇒ grey (r==g==b) maps to itself exactly. Realize a
        // constant BT.2020-grey bin and confirm the byte equals the sRGB round-trip.
        let greys: [UInt16] = [0, 14146, 32768, 65535]
        for gval in greys {
            let sums: [UInt64] = [4 * UInt64(gval), 4 * UInt64(gval), 4 * UInt64(gval)]
            var out = [UInt8](repeating: 0, count: 3)
            XCTAssertEqual(S4_RC_OK, s4_sums_bt2020_to_srgb8(sums, 1, 4, &out))
            let want = s4_linear16_to_srgb8(gval)
            XCTAssertEqual(want, out[0])
            XCTAssertEqual(want, out[1])
            XCTAssertEqual(want, out[2])
        }
    }

    // test "BT.2020→sRGB gamut: Q15 rows sum to 32768 (grey-preserving invariant)"
    func testBT2020ToSRGBGamutQ15RowsSumTo32768GreyPreservingInvariant() {
        let m = bt2020_to_srgb_q15
        XCTAssertEqual(Int32(32768), m[0] + m[1] + m[2])
        XCTAssertEqual(Int32(32768), m[3] + m[4] + m[5])
        XCTAssertEqual(Int32(32768), m[6] + m[7] + m[8])
    }

    // test "BT.2020→sRGB gamut: a saturated BT.2020 primary does NOT refuse (clamp, not BAD_ARGS)"
    func testBT2020ToSRGBGamutASaturatedBT2020PrimaryDoesNotRefuseClampNotBadArgs() {
        // Pure BT.2020 red bin (R=65535, G=B=0) is in-gamut for BT.2020 but out of
        // the sRGB gamut; the deterministic clamp keeps it legal (RC_OK, R byte 255)
        // instead of tripping the mean>65535 totality guard.
        let sums: [UInt64] = [4 * 65535, 0, 0]
        var out = [UInt8](repeating: 0, count: 3)
        XCTAssertEqual(S4_RC_OK, s4_sums_bt2020_to_srgb8(sums, 1, 4, &out))
        XCTAssertEqual(UInt8(255), out[0]) // 54411/32768 > 1 → clamps to 255
        XCTAssertEqual(UInt8(0), out[1]) //  negative G → clamps to 0
        XCTAssertEqual(UInt8(0), out[2]) //  negative B → clamps to 0
    }

    // test "BGRA camera pooling == RGB pooling on the same pixels (stride + crop respected)"
    func testBGRACameraPoolingEqualsRGBPoolingOnTheSamePixelsStrideAndCropRespected() {
        // Build a 40-wide x 36-tall BGRA image with stride 192 (> 40*4 = 160),
        // pool the 32x32 window at offset (4, 2), and compare against
        // s4_pool_sums_srgb8 on the equivalent tight RGB crop.
        // image is 40 px wide; the 32-px window at x0=4 + stride enforce the width
        let H = 36
        let STRIDE = 192
        var bgra = [UInt8](repeating: 0, count: H * STRIDE)
        fillLcg(&bgra, 77)
        var rgb = [UInt8](repeating: 0, count: 32 * 32 * 3)
        for y in 0..<32 {
            for x in 0..<32 {
                let src = (2 + y) * STRIDE + (4 + x) * 4
                rgb[(y * 32 + x) * 3] = bgra[src + 2]
                rgb[(y * 32 + x) * 3 + 1] = bgra[src + 1]
                rgb[(y * 32 + x) * 3 + 2] = bgra[src]
            }
        }
        var a = [UInt64](repeating: 0, count: 16 * 16 * 3)
        var b = [UInt64](repeating: 0, count: 16 * 16 * 3)
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_bgra8(bgra, Int32(STRIDE), 4, 2, 32, 16, &a))
        XCTAssertEqual(S4_RC_OK, s4_pool_sums_srgb8(rgb, 32, 16, &b))
        XCTAssertEqual(b, a)
        // Window overrunning the row refuses.
        XCTAssertEqual(S4_RC_BAD_ARGS, s4_pool_sums_bgra8(bgra, Int32(STRIDE), 20, 0, 32, 16, &a))
    }
}
