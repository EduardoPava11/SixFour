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
    srgb_to_oklab([c[0] as f64 / 255.0, c[1] as f64 / 255.0, c[2] as f64 / 255.0])
}

/// sRGB triple in [0,1] → OKLab.
pub fn srgb_to_oklab(c: [f64; 3]) -> Oklab {
    linear_srgb_to_oklab([srgb_to_linear(c[0]), srgb_to_linear(c[1]), srgb_to_linear(c[2])])
}

/// Linear-sRGB (D65) triple → OKLab — the M1/M2 core shared by `srgb_to_oklab`
/// and the CIE-Lab path. (`f64::cbrt` is negative-safe, matching `Color.hs`.)
pub fn linear_srgb_to_oklab(rgb: [f64; 3]) -> Oklab {
    let (r, g, b) = (rgb[0], rgb[1], rgb[2]);
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

// ---- CIE L*a*b* (Illuminant C) → OKLab ----------------------------------
//
// The World Color Survey chips are published as CIE L*a*b* under **Illuminant
// C, 2° observer**, but OKLab is defined on linear sRGB whose white is **D65**.
// Feeding C-referred Lab straight in would bias every colour toward blue and
// silently skew the opponent-pair geometry the look design depends on, so we
// adapt C→D65 (Bradford) between Lab→XYZ and XYZ→linear-sRGB.

/// CIE white points, XYZ normalised to Y = 1 (2° observer).
const WHITE_C: [f64; 3] = [0.980_74, 1.0, 1.182_32];
const WHITE_D65: [f64; 3] = [0.950_47, 1.0, 1.088_83];

/// Bradford cone-response matrix and its inverse (the standard CAT matrices).
const BRADFORD: [[f64; 3]; 3] = [
    [0.895_1, 0.266_4, -0.161_4],
    [-0.750_2, 1.713_5, 0.036_7],
    [0.038_9, -0.068_5, 1.029_6],
];
const BRADFORD_INV: [[f64; 3]; 3] = [
    [0.986_992_9, -0.147_054_3, 0.159_962_7],
    [0.432_305_3, 0.518_360_3, 0.049_291_2],
    [-0.008_528_7, 0.040_042_8, 0.968_486_7],
];
/// XYZ (D65) → linear sRGB (IEC 61966-2-1 primaries).
const XYZ_D65_TO_LINEAR_SRGB: [[f64; 3]; 3] = [
    [3.240_454_2, -1.537_138_5, -0.498_531_4],
    [-0.969_266_0, 1.876_010_8, 0.041_556_0],
    [0.055_643_4, -0.204_025_9, 1.057_225_2],
];

#[inline]
fn mat3_vec(m: &[[f64; 3]; 3], v: [f64; 3]) -> [f64; 3] {
    [
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    ]
}

/// CIE L*a*b* (L*∈[0,100]) → XYZ under the given white point (Y-normalised).
pub fn cie_lab_to_xyz(lab: [f64; 3], white: [f64; 3]) -> [f64; 3] {
    const EPS: f64 = 216.0 / 24389.0; // CIE standard ε
    const KAPPA: f64 = 24389.0 / 27.0; // CIE standard κ
    let fy = (lab[0] + 16.0) / 116.0;
    let fx = fy + lab[1] / 500.0;
    let fz = fy - lab[2] / 200.0;
    let inv = |f: f64| {
        let f3 = f * f * f;
        if f3 > EPS {
            f3
        } else {
            (116.0 * f - 16.0) / KAPPA
        }
    };
    let yr = if lab[0] > KAPPA * EPS {
        let t = (lab[0] + 16.0) / 116.0;
        t * t * t
    } else {
        lab[0] / KAPPA
    };
    [inv(fx) * white[0], yr * white[1], inv(fz) * white[2]]
}

/// Bradford chromatic adaptation from `src` white to `dst` white.
fn bradford_adapt(xyz: [f64; 3], src: [f64; 3], dst: [f64; 3]) -> [f64; 3] {
    let cs = mat3_vec(&BRADFORD, src);
    let cd = mat3_vec(&BRADFORD, dst);
    let cone = mat3_vec(&BRADFORD, xyz);
    let scaled = [cone[0] * cd[0] / cs[0], cone[1] * cd[1] / cs[1], cone[2] * cd[2] / cs[2]];
    mat3_vec(&BRADFORD_INV, scaled)
}

/// CIE L*a*b* under Illuminant C → OKLab. Adapts C→D65 (Bradford) so the result
/// lives in OKLab's native D65 space. Used to place the WCS chips + B–K foci.
pub fn cie_lab_c_to_oklab(lab: [f64; 3]) -> Oklab {
    let xyz_c = cie_lab_to_xyz(lab, WHITE_C);
    let xyz_d65 = bradford_adapt(xyz_c, WHITE_C, WHITE_D65);
    linear_srgb_to_oklab(mat3_vec(&XYZ_D65_TO_LINEAR_SRGB, xyz_d65))
}

/// Squared Euclidean distance in OKLab (mirrors `okLabDistanceSquared`).
#[inline]
pub fn dist_sq(a: Oklab, b: Oklab) -> f64 {
    let dl = a[0] - b[0];
    let da = a[1] - b[1];
    let db = a[2] - b[2];
    dl * dl + da * da + db * db
}

/// Axis-weighted squared OKLab distance: `Σ wᵢ·Δᵢ²`. A diagonal special case of
/// the learnable PSD metric in `trainer/train_metric.py`; used to encode the
/// L > a > b importance hierarchy when choosing colour pairs (see `crate::wcs`).
#[inline]
pub fn dist_sq_weighted(a: Oklab, b: Oklab, w: [f64; 3]) -> f64 {
    let dl = a[0] - b[0];
    let da = a[1] - b[1];
    let db = a[2] - b[2];
    w[0] * dl * dl + w[1] * da * da + w[2] * db * db
}

#[cfg(test)]
mod tests {
    use super::*;

    // L*=100,a*=b*=0 reproduces the reference white exactly (no matrices involved).
    #[test]
    fn lab_white_is_white_xyz() {
        let xyz = cie_lab_to_xyz([100.0, 0.0, 0.0], WHITE_C);
        for ax in 0..3 {
            assert!((xyz[ax] - WHITE_C[ax]).abs() < 1e-9, "axis {ax}: {} vs {}", xyz[ax], WHITE_C[ax]);
        }
    }

    // Adapting the source white to the dest white must land on the dest white
    // (cone responses cancel) — verifies the Bradford CAT is wired correctly.
    #[test]
    fn bradford_maps_c_white_to_d65_white() {
        let w = bradford_adapt(WHITE_C, WHITE_C, WHITE_D65);
        for ax in 0..3 {
            assert!((w[ax] - WHITE_D65[ax]).abs() < 5e-3, "axis {ax}: {} vs {}", w[ax], WHITE_D65[ax]);
        }
    }

    // CIE white → OKLab L ≈ 1, achromatic.
    #[test]
    fn white_maps_to_oklab_unit_lightness() {
        let c = cie_lab_c_to_oklab([100.0, 0.0, 0.0]);
        assert!((c[0] - 1.0).abs() < 5e-3, "L = {}", c[0]);
        assert!(c[1].abs() < 5e-3 && c[2].abs() < 5e-3, "a,b = {},{}", c[1], c[2]);
    }

    // A neutral grey (a*=b*=0) stays achromatic in OKLab after adaptation.
    #[test]
    fn neutral_grey_stays_achromatic() {
        let c = cie_lab_c_to_oklab([50.0, 0.0, 0.0]);
        assert!(c[1].abs() < 5e-3 && c[2].abs() < 5e-3, "a,b = {},{}", c[1], c[2]);
    }

    // The C→D65 adaptation must measurably move a saturated colour vs. skipping
    // it (treating C-referred XYZ as if it were D65). If these matched, the
    // adaptation would be dead code biasing the categories. Use a vivid blue.
    #[test]
    fn adaptation_is_live() {
        let lab = [40.0, 10.0, -50.0];
        let adapted = cie_lab_c_to_oklab(lab);
        let xyz_c = cie_lab_to_xyz(lab, WHITE_C);
        let no_adapt = linear_srgb_to_oklab(mat3_vec(&XYZ_D65_TO_LINEAR_SRGB, xyz_c));
        assert!(dist_sq(adapted, no_adapt) > 1e-6, "adaptation had no effect: {:?} vs {:?}", adapted, no_adapt);
    }
}
