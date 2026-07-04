//! GIF89a-camera COLOR HEAD — the 16x16 palette bin. DEPENDENCY-FREE: this file
//! imports NOTHING (not even std); pure integer arithmetic, caller owns all
//! memory, i32 rc (0 == ok), C ABI. Host-testable via palette16_test.zig.
//!
//! WHAT A GIF89a CAMERA SEES, made literal: the standard declares the Global
//! Color Table (768 bytes = 256 RGB triples) BEFORE the first pixel index — a
//! GIF camera sees its 256-color vocabulary first and content second. The
//! 16x16 bin grid makes that vocabulary a coarse image of the scene itself:
//! 16x16 = 256 = one coarse bin per palette slot (Spec law, V21Pyramid), so the
//! palette IS the scene's own 16x16 view, row-major bin (by*16+bx) = slot index.
//!
//! CARRIER vs REALIZATION (why two kernels): the pyramid's transitivity law
//! (Spec.V21Pyramid lawPyramidTransitive) holds for BLOCK-SUMS, which compose
//! exactly (sums of sums == sums). Rounded integer MEANS do not compose (the
//! teeth test in palette16_test.zig shows pooling means twice != once). So the
//! LEARNING path carries u64 sums (s4_pool_sums_srgb8, exact, transitive) and
//! the palette bytes are a final rounding realization (s4_sums_to_srgb8,
//! round-half-up, deterministic). s4_palette16_gct composes the two: one call,
//! sensor square in, GCT block out — color out of the way.
//!
//! TIME IS QUANTIZED BY THE STANDARD: the Graphic Control Extension delay is a
//! u16 in CENTISECONDS. The shipped burst is 64 frames at 20 fps = a 3.2 s =
//! 320 cs window. Keeping the spacetime voxel isotropic (the 2x2x2 octant lift
//! pools x, y AND t together) means side s plays the same window: delay(s) =
//! 320/s cs. That is an integer iff s divides 320 = 2^6 * 5 — so among the
//! power-of-two rungs, 64 @ 20 fps (delay 5) is the FINEST GIF-exact rung, and
//! downward the ladder is exact: 32 @ 10 fps (delay 10), 16 @ 5 fps (delay 20).
//! 128 would need 2.5 cs and the constant-bitrate alternative (fps ~ 1/s^2:
//! 80 fps, 320 fps) would need 1.25 cs — GIF89a cannot say either. The standard
//! itself votes for the isotropic octave ladder and caps it at 64.
//! s4_ladder_delay_cs encodes this law.
//!
//! TWO POOLING REGIMES (the measurement path, bottom of this file):
//! s4_pool_sums_srgb8 averages gamma-encoded bytes — deterministic, byte-exact,
//! NOT radiometric (feeds the GCT realization). s4_pool_sums_linear_srgb8 /
//! s4_pool_sums_linear_hlg10 linearize through LITERAL GOLDEN inverse-EOTF LUTs
//! FIRST, then sum — bin sums become ∝ scene light (exact on the 'x420' HLG
//! feed, approximate on the tone-mapped sRGB feed). The capture contract (which
//! AVFoundation format, who converts Y'CbCr, who expands video range) is
//! recorded at the section header below. Display note: 16³ == 32³ == 64³ AT
//! PRINT — every rung renders on the same canvas (block replication, the
//! pixelated look popping is presentation); rungs differ in information, never
//! in printed size.

pub const S4_RC_OK: i32 = 0;
pub const S4_RC_BAD_ARGS: i32 = -1;
pub const S4_RC_NOT_REPRESENTABLE: i32 = -2;

/// The shipped isotropic burst window, in centiseconds: 64 frames @ 20 fps.
pub const S4_WINDOW_CS: i32 = 320;

/// EXACT block-sum pooling of an sRGB8 square (side x side, 3 bytes/px,
/// row-major) into out_side x out_side bins: out_sums[(by*out_side+bx)*3+c] =
/// sum of channel c over the bin. Requires out_side | side. This is the
/// TRANSITIVE pyramid carrier: pooling 64->16 equals pooling 64->32->16 on
/// sums, byte-for-byte (u64 exact; no overflow: 255 * 65536^2 < 2^63).
pub export fn s4_pool_sums_srgb8(
    rgb: [*c]const u8,
    side: i32,
    out_side: i32,
    out_sums: [*c]u64,
) i32 {
    if (rgb == null or out_sums == null) return S4_RC_BAD_ARGS;
    if (side <= 0 or out_side <= 0 or out_side > side) return S4_RC_BAD_ARGS;
    if (@rem(side, out_side) != 0) return S4_RC_BAD_ARGS;
    const s: usize = @intCast(side);
    const o: usize = @intCast(out_side);
    const q: usize = s / o; // bin side

    var by: usize = 0;
    while (by < o) : (by += 1) {
        var bx: usize = 0;
        while (bx < o) : (bx += 1) {
            var sum = [3]u64{ 0, 0, 0 };
            var dy: usize = 0;
            while (dy < q) : (dy += 1) {
                const row = (by * q + dy) * s;
                var dx: usize = 0;
                while (dx < q) : (dx += 1) {
                    const px = (row + bx * q + dx) * 3;
                    sum[0] += rgb[px];
                    sum[1] += rgb[px + 1];
                    sum[2] += rgb[px + 2];
                }
            }
            const bin = (by * o + bx) * 3;
            out_sums[bin] = sum[0];
            out_sums[bin + 1] = sum[1];
            out_sums[bin + 2] = sum[2];
        }
    }
    return S4_RC_OK;
}

/// The ROUNDING REALIZATION: bin sums -> sRGB8 bytes by round-half-up integer
/// mean over `area` = (side/out_side)^2 pixels. Deterministic; NOT transitive
/// across rungs (round once, at the end — the teeth test proves why).
pub export fn s4_sums_to_srgb8(
    sums: [*c]const u64,
    out_side: i32,
    area: i64,
    out_rgb: [*c]u8,
) i32 {
    if (sums == null or out_rgb == null) return S4_RC_BAD_ARGS;
    if (out_side <= 0 or area <= 0) return S4_RC_BAD_ARGS;
    const o: usize = @intCast(out_side);
    const a: u64 = @intCast(area);
    var i: usize = 0;
    while (i < o * o * 3) : (i += 1) {
        const v: u64 = (sums[i] + a / 2) / a;
        if (v > 255) return S4_RC_BAD_ARGS; // inputs were not bytes / wrong area
        out_rgb[i] = @intCast(v);
    }
    return S4_RC_OK;
}

/// COLOR OUT OF THE WAY: sensor square in, GIF89a Global Color Table out.
/// Pools to the 16x16 bin grid and realizes the 256 round-half-up bin means as
/// the 768-byte GCT block (256 RGB triples, row-major bin order = slot order),
/// ready to place immediately after the Logical Screen Descriptor.
pub export fn s4_palette16_gct(
    rgb: [*c]const u8,
    side: i32,
    out_gct768: [*c]u8,
) i32 {
    if (rgb == null or out_gct768 == null) return S4_RC_BAD_ARGS;
    if (side <= 0 or @rem(side, 16) != 0) return S4_RC_BAD_ARGS;
    var sums: [16 * 16 * 3]u64 = undefined;
    const rc = s4_pool_sums_srgb8(rgb, side, 16, &sums);
    if (rc != S4_RC_OK) return rc;
    const q: i64 = @divExact(@as(i64, side), 16);
    return s4_sums_to_srgb8(&sums, 16, q * q, out_gct768);
}

/// THE TIME LAW: the GCE delay (integer centiseconds) that plays an s-frame
/// isotropic burst over the shipped 320 cs window. Returns the delay, or
/// S4_RC_NOT_REPRESENTABLE if GIF89a cannot say it (320/s not an integer):
/// 64 -> 5 (20 fps), 32 -> 10 (10 fps), 16 -> 20 (5 fps); 128 -> NOT (2.5 cs).
/// Among power-of-two rungs, representable iff s <= 64: the centisecond quantum
/// caps the isotropic ladder at exactly 2^6.
pub export fn s4_ladder_delay_cs(side: i32) i32 {
    if (side <= 0) return S4_RC_BAD_ARGS;
    if (@rem(S4_WINDOW_CS, side) != 0) return S4_RC_NOT_REPRESENTABLE;
    return @divExact(S4_WINDOW_CS, side);
}

// ─────────────────────────────────────────────────────────────────────────────
// THE MEASUREMENT PATH: inverse-EOTF LUTs + linear pooling.
//
// CAPTURE CONTRACT (the AVFoundation format decision, recorded here):
//   * MEASUREMENT path: request the 10-bit HDR feed 'x420'
//     (kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, BT.2020 / HLG).
//     Swift converts Y'CbCr -> R'G'B' with the integer BT.2020 matrix and
//     expands video range to FULL range 0..1023 BEFORE calling this file —
//     s4_pool_sums_linear_hlg10 is full-range and REFUSES codes > 1023
//     (totality: refuse out-of-range, never absorb). Only on this path are
//     bin sums ∝ scene radiance (shot noise then gives free error bars:
//     photon-limited bins satisfy variance ≈ gain × mean).
//   * LEAN / DETERMINISTIC fallback: the 8-bit sRGB/P3 path via
//     s4_pool_sums_linear_srgb8 — removes the gamma distortion of plain byte
//     pooling (the mid-gray trap: a {0,0,255,255} bin pools to byte 128 =
//     linear 14146, but its true linear mean is 32768 — a 2.3x radiometric
//     error, see the teeth test). Stage-4 ISP local tone mapping has already
//     bent absolute radiometry on this feed; documented, accepted.
//   * The EOTF applies to R'G'B' PLANES only, never to Y'CbCr directly (Y' is
//     a nonlinear mix of primaries); there is deliberately no Y' LUT kernel.
//
// The tables are LITERAL GOLDENS (generated offline; reference math below), so
// cross-device determinism never depends on comptime float or libm semantics.
// Reference: sRGB inverse EOTF  lin = c/12.92 for c <= 0.04045 else
// ((c+0.055)/1.055)^2.4, c = v/255;  HLG inverse OETF (BT.2100)
// lin = e^2/3 for e <= 0.5 else (exp((e-c)/a)+b)/12 with a=0.17883277,
// b=0.28466892, c=0.55991073, e = v/1023. Both scaled round(lin*65535),
// clamped to u16.
// ─────────────────────────────────────────────────────────────────────────────

pub const S4_RC_OUT_OF_RANGE: i32 = -3;

/// sRGB (8-bit code) -> scene-linear u16, literal golden table.
pub const srgb_to_linear16 = [256]u16{
        0,    20,    40,    60,    80,    99,   119,   139,   159,   179,   199,   219,   241,   264,   288,   313,
      340,   367,   396,   427,   458,   491,   526,   562,   599,   637,   677,   718,   761,   805,   851,   898,
      947,   997,  1048,  1101,  1156,  1212,  1270,  1330,  1391,  1453,  1517,  1583,  1651,  1720,  1790,  1863,
     1937,  2013,  2090,  2170,  2250,  2333,  2418,  2504,  2592,  2681,  2773,  2866,  2961,  3058,  3157,  3258,
     3360,  3464,  3570,  3678,  3788,  3900,  4014,  4129,  4247,  4366,  4488,  4611,  4736,  4864,  4993,  5124,
     5257,  5392,  5530,  5669,  5810,  5953,  6099,  6246,  6395,  6547,  6700,  6856,  7014,  7174,  7335,  7500,
     7666,  7834,  8004,  8177,  8352,  8528,  8708,  8889,  9072,  9258,  9445,  9635,  9828, 10022, 10219, 10417,
    10619, 10822, 11028, 11235, 11446, 11658, 11873, 12090, 12309, 12530, 12754, 12980, 13209, 13440, 13673, 13909,
    14146, 14387, 14629, 14874, 15122, 15371, 15623, 15878, 16135, 16394, 16656, 16920, 17187, 17456, 17727, 18001,
    18277, 18556, 18837, 19121, 19407, 19696, 19987, 20281, 20577, 20876, 21177, 21481, 21787, 22096, 22407, 22721,
    23038, 23357, 23678, 24002, 24329, 24658, 24990, 25325, 25662, 26001, 26344, 26688, 27036, 27386, 27739, 28094,
    28452, 28813, 29176, 29542, 29911, 30282, 30656, 31033, 31412, 31794, 32179, 32567, 32957, 33350, 33745, 34143,
    34544, 34948, 35355, 35764, 36176, 36591, 37008, 37429, 37852, 38278, 38706, 39138, 39572, 40009, 40449, 40891,
    41337, 41785, 42236, 42690, 43147, 43606, 44069, 44534, 45002, 45473, 45947, 46423, 46903, 47385, 47871, 48359,
    48850, 49344, 49841, 50341, 50844, 51349, 51858, 52369, 52884, 53401, 53921, 54445, 54971, 55500, 56032, 56567,
    57105, 57646, 58190, 58737, 59287, 59840, 60396, 60955, 61517, 62082, 62650, 63221, 63795, 64372, 64952, 65535,
};

/// HLG (10-bit FULL-RANGE code) -> scene-linear u16, literal golden table.
pub const hlg_to_linear16 = [1024]u16{
        0,     0,     0,     0,     0,     1,     1,     1,     1,     2,     2,     3,     3,     4,     4,     5,
        5,     6,     7,     8,     8,     9,    10,    11,    12,    13,    14,    15,    16,    18,    19,    20,
       21,    23,    24,    26,    27,    29,    30,    32,    33,    35,    37,    39,    40,    42,    44,    46,
       48,    50,    52,    54,    56,    59,    61,    63,    65,    68,    70,    73,    75,    78,    80,    83,
       85,    88,    91,    94,    97,    99,   102,   105,   108,   111,   114,   117,   121,   124,   127,   130,
      134,   137,   140,   144,   147,   151,   154,   158,   162,   165,   169,   173,   177,   181,   184,   188,
      192,   196,   200,   205,   209,   213,   217,   221,   226,   230,   235,   239,   243,   248,   253,   257,
      262,   267,   271,   276,   281,   286,   291,   296,   301,   306,   311,   316,   321,   326,   331,   337,
      342,   347,   353,   358,   364,   369,   375,   380,   386,   392,   398,   403,   409,   415,   421,   427,
      433,   439,   445,   451,   457,   463,   470,   476,   482,   489,   495,   501,   508,   515,   521,   528,
      534,   541,   548,   555,   561,   568,   575,   582,   589,   596,   603,   610,   618,   625,   632,   639,
      647,   654,   661,   669,   676,   684,   691,   699,   707,   714,   722,   730,   738,   746,   754,   761,
      769,   778,   786,   794,   802,   810,   818,   827,   835,   843,   852,   860,   869,   877,   886,   894,
      903,   912,   921,   929,   938,   947,   956,   965,   974,   983,   992,  1001,  1010,  1019,  1029,  1038,
     1047,  1057,  1066,  1076,  1085,  1095,  1104,  1114,  1124,  1133,  1143,  1153,  1163,  1172,  1182,  1192,
     1202,  1212,  1222,  1233,  1243,  1253,  1263,  1273,  1284,  1294,  1305,  1315,  1326,  1336,  1347,  1357,
     1368,  1379,  1389,  1400,  1411,  1422,  1433,  1444,  1455,  1466,  1477,  1488,  1499,  1510,  1522,  1533,
     1544,  1556,  1567,  1579,  1590,  1602,  1613,  1625,  1637,  1648,  1660,  1672,  1684,  1695,  1707,  1719,
     1731,  1743,  1755,  1768,  1780,  1792,  1804,  1817,  1829,  1841,  1854,  1866,  1879,  1891,  1904,  1916,
     1929,  1942,  1955,  1967,  1980,  1993,  2006,  2019,  2032,  2045,  2058,  2071,  2084,  2098,  2111,  2124,
     2137,  2151,  2164,  2178,  2191,  2205,  2218,  2232,  2246,  2259,  2273,  2287,  2301,  2315,  2329,  2343,
     2357,  2371,  2385,  2399,  2413,  2427,  2441,  2456,  2470,  2484,  2499,  2513,  2528,  2542,  2557,  2572,
     2586,  2601,  2616,  2631,  2645,  2660,  2675,  2690,  2705,  2720,  2735,  2751,  2766,  2781,  2796,  2811,
     2827,  2842,  2858,  2873,  2889,  2904,  2920,  2935,  2951,  2967,  2983,  2998,  3014,  3030,  3046,  3062,
     3078,  3094,  3110,  3126,  3142,  3159,  3175,  3191,  3208,  3224,  3240,  3257,  3273,  3290,  3306,  3323,
     3340,  3357,  3373,  3390,  3407,  3424,  3441,  3458,  3475,  3492,  3509,  3526,  3543,  3560,  3578,  3595,
     3612,  3630,  3647,  3665,  3682,  3700,  3717,  3735,  3753,  3770,  3788,  3806,  3824,  3842,  3860,  3878,
     3896,  3914,  3932,  3950,  3968,  3986,  4005,  4023,  4041,  4060,  4078,  4096,  4115,  4134,  4152,  4171,
     4189,  4208,  4227,  4246,  4265,  4283,  4302,  4321,  4340,  4359,  4379,  4398,  4417,  4436,  4455,  4475,
     4494,  4513,  4533,  4552,  4572,  4591,  4611,  4631,  4650,  4670,  4690,  4710,  4729,  4749,  4769,  4789,
     4809,  4829,  4849,  4870,  4890,  4910,  4930,  4951,  4971,  4991,  5012,  5032,  5053,  5073,  5094,  5115,
     5135,  5156,  5177,  5198,  5218,  5239,  5260,  5281,  5302,  5323,  5344,  5366,  5387,  5408,  5429,  5451,
     5472,  5493,  5515,  5537,  5559,  5580,  5603,  5625,  5647,  5669,  5692,  5715,  5738,  5760,  5783,  5807,
     5830,  5853,  5877,  5901,  5924,  5948,  5973,  5997,  6021,  6046,  6070,  6095,  6120,  6145,  6170,  6195,
     6221,  6246,  6272,  6298,  6324,  6350,  6376,  6403,  6429,  6456,  6483,  6510,  6537,  6564,  6592,  6619,
     6647,  6675,  6703,  6731,  6760,  6788,  6817,  6846,  6875,  6904,  6933,  6963,  6992,  7022,  7052,  7082,
     7113,  7143,  7174,  7205,  7235,  7267,  7298,  7329,  7361,  7393,  7425,  7457,  7489,  7522,  7555,  7588,
     7621,  7654,  7687,  7721,  7755,  7789,  7823,  7857,  7892,  7926,  7961,  7996,  8032,  8067,  8103,  8139,
     8175,  8211,  8248,  8284,  8321,  8358,  8396,  8433,  8471,  8509,  8547,  8585,  8624,  8663,  8701,  8741,
     8780,  8820,  8859,  8900,  8940,  8980,  9021,  9062,  9103,  9144,  9186,  9228,  9270,  9312,  9355,  9397,
     9440,  9484,  9527,  9571,  9615,  9659,  9703,  9748,  9793,  9838,  9883,  9929,  9975, 10021, 10068, 10114,
    10161, 10208, 10256, 10303, 10351, 10400, 10448, 10497, 10546, 10595, 10645, 10695, 10745, 10795, 10846, 10897,
    10948, 10999, 11051, 11103, 11155, 11208, 11261, 11314, 11368, 11421, 11475, 11530, 11585, 11640, 11695, 11750,
    11806, 11862, 11919, 11976, 12033, 12090, 12148, 12206, 12264, 12323, 12382, 12442, 12501, 12561, 12622, 12682,
    12743, 12805, 12866, 12928, 12991, 13053, 13116, 13180, 13243, 13307, 13372, 13437, 13502, 13567, 13633, 13699,
    13766, 13833, 13900, 13968, 14036, 14104, 14173, 14242, 14312, 14382, 14452, 14523, 14594, 14665, 14737, 14809,
    14882, 14955, 15028, 15102, 15176, 15251, 15326, 15402, 15478, 15554, 15631, 15708, 15785, 15863, 15942, 16021,
    16100, 16180, 16260, 16340, 16421, 16503, 16585, 16667, 16750, 16833, 16917, 17001, 17086, 17171, 17257, 17343,
    17429, 17516, 17604, 17692, 17780, 17869, 17959, 18048, 18139, 18230, 18321, 18413, 18505, 18598, 18692, 18786,
    18880, 18975, 19071, 19167, 19263, 19360, 19458, 19556, 19655, 19754, 19854, 19954, 20055, 20156, 20258, 20361,
    20464, 20567, 20671, 20776, 20882, 20988, 21094, 21201, 21309, 21417, 21526, 21635, 21746, 21856, 21967, 22079,
    22192, 22305, 22419, 22533, 22648, 22764, 22880, 22997, 23114, 23232, 23351, 23471, 23591, 23712, 23833, 23955,
    24078, 24201, 24326, 24450, 24576, 24702, 24829, 24956, 25085, 25214, 25343, 25474, 25605, 25737, 25869, 26003,
    26137, 26271, 26407, 26543, 26680, 26818, 26956, 27095, 27235, 27376, 27518, 27660, 27803, 27947, 28092, 28237,
    28383, 28530, 28678, 28827, 28976, 29127, 29278, 29430, 29582, 29736, 29890, 30046, 30202, 30359, 30517, 30676,
    30835, 30996, 31157, 31319, 31482, 31647, 31811, 31977, 32144, 32312, 32480, 32650, 32820, 32992, 33164, 33337,
    33511, 33687, 33863, 34040, 34218, 34397, 34577, 34758, 34940, 35123, 35307, 35492, 35678, 35865, 36053, 36242,
    36432, 36623, 36815, 37009, 37203, 37398, 37595, 37792, 37991, 38191, 38392, 38593, 38796, 39001, 39206, 39412,
    39620, 39828, 40038, 40249, 40461, 40674, 40889, 41104, 41321, 41539, 41758, 41979, 42200, 42423, 42647, 42872,
    43099, 43326, 43555, 43786, 44017, 44250, 44484, 44719, 44956, 45194, 45433, 45673, 45915, 46158, 46403, 46648,
    46896, 47144, 47394, 47645, 47898, 48152, 48407, 48664, 48922, 49182, 49443, 49706, 49969, 50235, 50502, 50770,
    51040, 51311, 51584, 51858, 52134, 52411, 52689, 52970, 53252, 53535, 53820, 54106, 54394, 54684, 54975, 55268,
    55562, 55858, 56156, 56455, 56756, 57059, 57363, 57669, 57976, 58286, 58597, 58909, 59224, 59540, 59858, 60177,
    60498, 60822, 61146, 61473, 61801, 62132, 62464, 62798, 63133, 63471, 63810, 64151, 64494, 64839, 65186, 65535,
};

/// Scalar sRGB lookup (C ABI convenience for the Swift capture layer).
pub export fn s4_srgb8_to_linear16(v: u8) u16 {
    return srgb_to_linear16[v];
}

/// Scalar HLG lookup; returns the linear value (>= 0) or S4_RC_OUT_OF_RANGE.
pub export fn s4_hlg10_to_linear16(v: u16) i32 {
    if (v > 1023) return S4_RC_OUT_OF_RANGE;
    return hlg_to_linear16[v];
}

/// RADIOMETRIC pooling, sRGB feed: linearize each byte through the golden LUT,
/// THEN block-sum (linearize-then-sum; the reverse order is the mid-gray trap).
/// Same transitive u64 sums carrier as s4_pool_sums_srgb8; sums are now in
/// linear-light u16 units (no overflow: 65535 * 4096^2 * safety < 2^63).
pub export fn s4_pool_sums_linear_srgb8(
    rgb: [*c]const u8,
    side: i32,
    out_side: i32,
    out_sums: [*c]u64,
) i32 {
    if (rgb == null or out_sums == null) return S4_RC_BAD_ARGS;
    if (side <= 0 or out_side <= 0 or out_side > side) return S4_RC_BAD_ARGS;
    if (@rem(side, out_side) != 0) return S4_RC_BAD_ARGS;
    const s: usize = @intCast(side);
    const o: usize = @intCast(out_side);
    const q: usize = s / o;

    var by: usize = 0;
    while (by < o) : (by += 1) {
        var bx: usize = 0;
        while (bx < o) : (bx += 1) {
            var sum = [3]u64{ 0, 0, 0 };
            var dy: usize = 0;
            while (dy < q) : (dy += 1) {
                const row = (by * q + dy) * s;
                var dx: usize = 0;
                while (dx < q) : (dx += 1) {
                    const px = (row + bx * q + dx) * 3;
                    sum[0] += srgb_to_linear16[rgb[px]];
                    sum[1] += srgb_to_linear16[rgb[px + 1]];
                    sum[2] += srgb_to_linear16[rgb[px + 2]];
                }
            }
            const bin = (by * o + bx) * 3;
            out_sums[bin] = sum[0];
            out_sums[bin + 1] = sum[1];
            out_sums[bin + 2] = sum[2];
        }
    }
    return S4_RC_OK;
}

/// RADIOMETRIC pooling, 10-bit HLG feed (full-range R'G'B' codes 0..1023 in
/// u16 storage, interleaved RGB). TOTAL: pre-scans the whole frame and refuses
/// any out-of-range code BEFORE writing a single sum (no partial output).
pub export fn s4_pool_sums_linear_hlg10(
    rgb10: [*c]const u16,
    side: i32,
    out_side: i32,
    out_sums: [*c]u64,
) i32 {
    if (rgb10 == null or out_sums == null) return S4_RC_BAD_ARGS;
    if (side <= 0 or out_side <= 0 or out_side > side) return S4_RC_BAD_ARGS;
    if (@rem(side, out_side) != 0) return S4_RC_BAD_ARGS;
    const s: usize = @intCast(side);
    const o: usize = @intCast(out_side);
    const q: usize = s / o;

    var i: usize = 0;
    while (i < s * s * 3) : (i += 1) {
        if (rgb10[i] > 1023) return S4_RC_OUT_OF_RANGE;
    }

    var by: usize = 0;
    while (by < o) : (by += 1) {
        var bx: usize = 0;
        while (bx < o) : (bx += 1) {
            var sum = [3]u64{ 0, 0, 0 };
            var dy: usize = 0;
            while (dy < q) : (dy += 1) {
                const row = (by * q + dy) * s;
                var dx: usize = 0;
                while (dx < q) : (dx += 1) {
                    const px = (row + bx * q + dx) * 3;
                    sum[0] += hlg_to_linear16[rgb10[px]];
                    sum[1] += hlg_to_linear16[rgb10[px + 1]];
                    sum[2] += hlg_to_linear16[rgb10[px + 2]];
                }
            }
            const bin = (by * o + bx) * 3;
            out_sums[bin] = sum[0];
            out_sums[bin + 1] = sum[1];
            out_sums[bin + 2] = sum[2];
        }
    }
    return S4_RC_OK;
}

/// CAMERA-FACING pooling: pool an sRGB-encoded BGRA8 rect (the CVPixelBuffer
/// 32BGRA layout: 4 bytes/px in memory order B,G,R,A; rows `stride` bytes
/// apart) into out_side × out_side bins of R,G,B u64 sums, reading the square
/// window at pixel offset (x0, y0) of side `side` — the center-crop happens
/// HERE, byte-exact, no intermediate copy. Same transitive sums carrier as
/// s4_pool_sums_srgb8 (the Swift ladder derives 32/16 rungs by exact u64
/// adds). Gamma bytes (the GCT/floor path); linearize-then-sum stays the
/// measurement path above.
pub export fn s4_pool_sums_bgra8(
    bgra: [*c]const u8,
    stride: i32,
    x0: i32,
    y0: i32,
    side: i32,
    out_side: i32,
    out_sums: [*c]u64,
) i32 {
    if (bgra == null or out_sums == null) return S4_RC_BAD_ARGS;
    if (stride <= 0 or x0 < 0 or y0 < 0) return S4_RC_BAD_ARGS;
    if (side <= 0 or out_side <= 0 or out_side > side) return S4_RC_BAD_ARGS;
    if (@rem(side, out_side) != 0) return S4_RC_BAD_ARGS;
    if ((x0 + side) * 4 > stride) return S4_RC_BAD_ARGS; // window must fit a row
    const st: usize = @intCast(stride);
    const ox: usize = @intCast(x0);
    const oy: usize = @intCast(y0);
    const s: usize = @intCast(side);
    const o: usize = @intCast(out_side);
    const q: usize = s / o;

    var by: usize = 0;
    while (by < o) : (by += 1) {
        var bx: usize = 0;
        while (bx < o) : (bx += 1) {
            var sum = [3]u64{ 0, 0, 0 };
            var dy: usize = 0;
            while (dy < q) : (dy += 1) {
                const row = (oy + by * q + dy) * st;
                var dx: usize = 0;
                while (dx < q) : (dx += 1) {
                    const px = row + (ox + bx * q + dx) * 4;
                    sum[0] += bgra[px + 2]; // R
                    sum[1] += bgra[px + 1]; // G
                    sum[2] += bgra[px]; //     B
                }
            }
            const bin = (by * o + bx) * 3;
            out_sums[bin] = sum[0];
            out_sums[bin + 1] = sum[1];
            out_sums[bin + 2] = sum[2];
        }
    }
    return S4_RC_OK;
}
