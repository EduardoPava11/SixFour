//! sRGB ↔ OKLab, bit-mirrored from `~/SixFour/spec/src/SixFour/Spec/Color.hs`
//! (Björn Ottosson's M1/M2). f64 throughout, matching the Haskell `Double` spec.

/// An OKLab triple: L ∈ [0,1], a,b ≈ [-0.4, 0.4].
pub type Oklab = [f64; 3];

const M1: [[f64; 3]; 3] = [
    [0.412_221_470_8, 0.536_332_536_3, 0.051_445_992_9],
    [0.211_903_498_2, 0.680_699_545_1, 0.107_396_956_6],
    [0.088_302_461_9, 0.281_718_837_6, 0.629_978_700_5],
];
const M2: [[f64; 3]; 3] = [
    [0.210_454_255_3, 0.793_617_785_0, -0.004_072_046_8],
    [1.977_998_495_1, -2.428_592_205_0, 0.450_593_709_9],
    [0.025_904_037_1, 0.782_771_766_2, -0.808_675_766_0],
];

fn srgb_to_linear(x: f64) -> f64 {
    if x <= 0.04045 {
        x / 12.92
    } else {
        ((x + 0.055) / 1.055).powf(2.4)
    }
}

/// sRGB 8-bit triple → OKLab. (`f64::cbrt` returns the real cube root for
/// negative inputs, matching `Color.hs`'s explicit negative-safe `cbrt`.)
pub fn srgb8_to_oklab(c: [u8; 3]) -> Oklab {
    let r = srgb_to_linear(c[0] as f64 / 255.0);
    let g = srgb_to_linear(c[1] as f64 / 255.0);
    let b = srgb_to_linear(c[2] as f64 / 255.0);
    let l = M1[0][0] * r + M1[0][1] * g + M1[0][2] * b;
    let m = M1[1][0] * r + M1[1][1] * g + M1[1][2] * b;
    let s = M1[2][0] * r + M1[2][1] * g + M1[2][2] * b;
    let (lc, mc, sc) = (l.cbrt(), m.cbrt(), s.cbrt());
    [
        M2[0][0] * lc + M2[0][1] * mc + M2[0][2] * sc,
        M2[1][0] * lc + M2[1][1] * mc + M2[1][2] * sc,
        M2[2][0] * lc + M2[2][1] * mc + M2[2][2] * sc,
    ]
}

fn linear_to_srgb(x: f64) -> f64 {
    if x <= 0.0031308 {
        12.92 * x
    } else {
        1.055 * x.powf(1.0 / 2.4) - 0.055
    }
}

/// OKLab → sRGB 8-bit (inverse of `srgb8_to_oklab`; hard-coded inverse
/// matrices from `Color.hs`). Used for display in the visualizer.
pub fn oklab_to_srgb8(c: Oklab) -> [u8; 3] {
    let (big_l, a, b) = (c[0], c[1], c[2]);
    let l_ = big_l + 0.396_337_777_4 * a + 0.215_803_757_3 * b;
    let m_ = big_l - 0.105_561_345_8 * a - 0.063_854_172_8 * b;
    let s_ = big_l - 0.089_484_177_5 * a - 1.291_485_548_0 * b;
    let l = l_ * l_ * l_;
    let m = m_ * m_ * m_;
    let s = s_ * s_ * s_;
    let r = 4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s;
    let g = -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s;
    let bb = -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s;
    let to8 = |v: f64| (linear_to_srgb(v).clamp(0.0, 1.0) * 255.0).round() as u8;
    [to8(r), to8(g), to8(bb)]
}

/// Squared Euclidean distance in OKLab (mirrors `okLabDistanceSquared`).
#[inline]
pub fn dist_sq(a: Oklab, b: Oklab) -> f64 {
    let dl = a[0] - b[0];
    let da = a[1] - b[1];
    let db = a[2] - b[2];
    dl * dl + da * da + db * db
}
