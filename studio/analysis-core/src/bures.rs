//! Bures–Wasserstein (Gaussian W₂) backbone for the collapse.
//! Bit-mirrors `~/SixFour/spec/src/SixFour/Spec/Bures.hs`. The matrix square root is
//! scaled Denman–Beavers (same algorithm as the spec, so the golden vectors agree).
//! `W₂((μ₁,Σ₁),(μ₂,Σ₂))² = ‖μ₁−μ₂‖² + tr(Σ₁+Σ₂ − 2(Σ₁^½Σ₂Σ₁^½)^½)`; the barycenter
//! covariance is the fixed point `Σ̄ = Σᵢ λᵢ (Σ̄^½ Σᵢ Σ̄^½)^½`. As Σ→0, Bures→Euclidean
//! (the law tying this to the k-means free-support floor in `collapse.rs`).

use crate::color::dist_sq;
use crate::gmm::{Cov6, Gaussian};

/// Dense 3×3 matrix, row-major.
pub type Mat3 = [[f64; 3]; 3];

pub fn from_cov6(c: Cov6) -> Mat3 {
    [[c[0], c[1], c[2]], [c[1], c[3], c[4]], [c[2], c[4], c[5]]]
}

pub fn to_cov6(m: Mat3) -> Cov6 {
    [m[0][0], m[0][1], m[0][2], m[1][1], m[1][2], m[2][2]]
}

pub fn mat_id() -> Mat3 {
    [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
}

pub fn mat_add(a: Mat3, b: Mat3) -> Mat3 {
    let mut r = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            r[i][j] = a[i][j] + b[i][j];
        }
    }
    r
}

pub fn mat_scale(s: f64, a: Mat3) -> Mat3 {
    let mut r = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            r[i][j] = s * a[i][j];
        }
    }
    r
}

pub fn mat_mul(a: Mat3, b: Mat3) -> Mat3 {
    let mut r = [[0.0; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            r[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j];
        }
    }
    r
}

pub fn mat_trace(m: Mat3) -> f64 {
    m[0][0] + m[1][1] + m[2][2]
}

/// Determinant (cofactor expansion along the first row).
pub fn det3(m: Mat3) -> f64 {
    m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
}

/// Inverse via adjugate / determinant (callers feed strictly-PD matrices).
pub fn inverse3(m: Mat3) -> Mat3 {
    let dt = det3(m);
    let invd = 1.0 / dt;
    let (a, b, c) = (m[0][0], m[0][1], m[0][2]);
    let (d, e, f) = (m[1][0], m[1][1], m[1][2]);
    let (g, h, i) = (m[2][0], m[2][1], m[2][2]);
    let ca = e * i - f * h;
    let cb = -(d * i - f * g);
    let cc = d * h - e * g;
    let cd = -(b * i - c * h);
    let ce = a * i - c * g;
    let cf = -(a * h - b * g);
    let cg = b * f - c * e;
    let ch = -(a * f - c * d);
    let ci = a * e - b * d;
    // inverse = adjugate / det = (cofactor matrix)ᵀ / det
    mat_scale(invd, [[ca, cd, cg], [cb, ce, ch], [cc, cf, ci]])
}

/// Symmetric-PSD matrix square root via scaled Denman–Beavers (Higham determinantal
/// scaling `μ = |det Y · det Z|^{-1/(2n)}`, n=3). Tiny ridge keeps iterands invertible.
pub fn sqrt_psd(a0: Mat3) -> Mat3 {
    const RIDGE: f64 = 1e-9;
    let a = mat_add(a0, mat_scale(RIDGE, mat_id()));
    let mut y = a;
    let mut z = mat_id();
    for _ in 0..50 {
        let dy = det3(y);
        let dz = det3(z);
        let gamma = (dy * dz).abs().max(1e-300).powf(-1.0 / 6.0);
        let iy = inverse3(y);
        let iz = inverse3(z);
        let y_next = mat_scale(0.5, mat_add(mat_scale(gamma, y), mat_scale(1.0 / gamma, iz)));
        let z_next = mat_scale(0.5, mat_add(mat_scale(gamma, z), mat_scale(1.0 / gamma, iy)));
        y = y_next;
        z = z_next;
    }
    y
}

/// Squared Bures–Wasserstein distance. Mean term = Euclidean OKLab (identity metric);
/// covariance term = the Bures form. Reduces to `dist_sq` when both covariances vanish.
pub fn bures_distance_sq(g1: &Gaussian, g2: &Gaussian) -> f64 {
    let dmu = dist_sq(g1.mean, g2.mean);
    let s1 = sqrt_psd(from_cov6(g1.cov));
    let inner = sqrt_psd(mat_mul(s1, mat_mul(from_cov6(g2.cov), s1)));
    let cross = mat_trace(inner);
    let t = mat_trace(from_cov6(g1.cov)) + mat_trace(from_cov6(g2.cov)) - 2.0 * cross;
    dmu + t.max(0.0)
}

/// Bures–Wasserstein barycenter covariance of weighted covariances: the fixed point
/// `Σ̄ = Σᵢ λᵢ (Σ̄^½ Σᵢ Σ̄^½)^½`, from the linear average, weights renormalised.
pub fn bures_barycenter_cov(wcs: &[(f64, Cov6)]) -> Cov6 {
    let s: f64 = wcs.iter().map(|&(w, _)| w).sum();
    let ws: Vec<(f64, Cov6)> = if s <= 0.0 {
        wcs.to_vec()
    } else {
        wcs.iter().map(|&(w, c)| (w / s, c)).collect()
    };
    let zero = mat_scale(0.0, mat_id());
    let mut cur = ws.iter().fold(zero, |acc, &(w, c)| mat_add(acc, mat_scale(w, from_cov6(c))));
    for _ in 0..30 {
        let r = sqrt_psd(cur);
        cur = ws.iter().fold(zero, |acc, &(w, c)| {
            let term = sqrt_psd(mat_mul(r, mat_mul(from_cov6(c), r)));
            mat_add(acc, mat_scale(w, term))
        });
    }
    to_cov6(cur)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mat_close(a: Mat3, b: Mat3, tol: f64) -> bool {
        (0..3).all(|i| (0..3).all(|j| (a[i][j] - b[i][j]).abs() <= tol))
    }

    fn close6(a: &Cov6, b: &Cov6, tol: f64) -> bool {
        a.iter().zip(b).all(|(&x, &y)| (x - y).abs() <= tol)
    }

    #[test]
    fn sqrt_psd_squares_back() {
        let m = from_cov6([0.05, 0.01, 0.0, 0.04, 0.005, 0.03]);
        let r = sqrt_psd(m);
        assert!(mat_close(mat_mul(r, r), m, 1e-4), "got {:?}", mat_mul(r, r));
    }

    // GOLDEN cross-check vs the Haskell reference (Spec.Bures via Codegen.Burn).
    #[test]
    fn golden_bures_match_haskell() {
        let g1 = Gaussian { mean: [0.3, 0.0, 0.0], cov: [0.02, 0.0, 0.0, 0.01, 0.0, 0.01], weight: 1.0 };
        let g2 = Gaussian { mean: [0.7, 0.0, 0.0], cov: [0.03, 0.0, 0.0, 0.02, 0.0, 0.015], weight: 1.0 };
        let dist_golden = 0.1632308394204244;
        let bary_golden = [
            2.4747490538907516e-2, 0.0, 0.0,
            1.457113952257385e-2, 0.0, 1.237380700617534e-2,
        ];
        assert!((bures_distance_sq(&g1, &g2) - dist_golden).abs() < 1e-6, "dist {}", bures_distance_sq(&g1, &g2));
        let bary = bures_barycenter_cov(&[(0.5, g1.cov), (0.5, g2.cov)]);
        assert!(close6(&bary, &bary_golden, 1e-6), "bary {:?}", bary);
    }

    // The bridge law: Σ→0 ⇒ Bures distance = plain Euclidean OKLab.
    #[test]
    fn sigma_zero_reduces_to_euclidean() {
        let g1 = Gaussian { mean: [0.2, 0.1, -0.1], cov: [0.0; 6], weight: 1.0 };
        let g2 = Gaussian { mean: [0.8, -0.1, 0.1], cov: [0.0; 6], weight: 1.0 };
        assert!((bures_distance_sq(&g1, &g2) - dist_sq(g1.mean, g2.mean)).abs() < 1e-4);
    }
}
