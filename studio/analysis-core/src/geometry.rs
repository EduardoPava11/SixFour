//! Candidate-colour geometry: how the ≤T·K per-frame colours sit in colour
//! space. Distinct-colour count, weighted PCA (analytic symmetric-3×3
//! eigenvalues) + participation-ratio effective dimensionality, NN spacing.

use crate::color::{dist_sq, Oklab};
use std::collections::HashSet;

/// Distinct colours within a grid of cell size `eps` (O(n)).
pub fn distinct_count(cands: &[(Oklab, f64)], eps: f64) -> usize {
    let mut set: HashSet<(i64, i64, i64)> = HashSet::new();
    for &(c, _) in cands {
        set.insert((
            (c[0] / eps).round() as i64,
            (c[1] / eps).round() as i64,
            (c[2] / eps).round() as i64,
        ));
    }
    set.len()
}

/// Weighted 3×3 covariance eigenvalues (descending) of the candidate colours.
pub fn color_pca(cands: &[(Oklab, f64)]) -> [f64; 3] {
    let mut wsum = 0.0;
    let mut mean = [0.0; 3];
    for &(c, w) in cands {
        wsum += w;
        for ch in 0..3 {
            mean[ch] += w * c[ch];
        }
    }
    if wsum <= 0.0 {
        return [0.0; 3];
    }
    for ch in 0..3 {
        mean[ch] /= wsum;
    }
    let (mut a11, mut a22, mut a33, mut a12, mut a13, mut a23) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    for &(c, w) in cands {
        let d = [c[0] - mean[0], c[1] - mean[1], c[2] - mean[2]];
        a11 += w * d[0] * d[0];
        a22 += w * d[1] * d[1];
        a33 += w * d[2] * d[2];
        a12 += w * d[0] * d[1];
        a13 += w * d[0] * d[2];
        a23 += w * d[1] * d[2];
    }
    for v in [&mut a11, &mut a22, &mut a33, &mut a12, &mut a13, &mut a23] {
        *v /= wsum;
    }
    sym3_eigenvalues(a11, a22, a33, a12, a13, a23)
}

/// Analytic eigenvalues of a symmetric 3×3 (Smith's method), descending.
fn sym3_eigenvalues(a11: f64, a22: f64, a33: f64, a12: f64, a13: f64, a23: f64) -> [f64; 3] {
    let p1 = a12 * a12 + a13 * a13 + a23 * a23;
    if p1 == 0.0 {
        let mut e = [a11, a22, a33];
        e.sort_by(|x, y| y.partial_cmp(x).unwrap());
        return e;
    }
    let q = (a11 + a22 + a33) / 3.0;
    let p2 = (a11 - q).powi(2) + (a22 - q).powi(2) + (a33 - q).powi(2) + 2.0 * p1;
    let p = (p2 / 6.0).sqrt();
    let (b11, b22, b33) = ((a11 - q) / p, (a22 - q) / p, (a33 - q) / p);
    let (b12, b13, b23) = (a12 / p, a13 / p, a23 / p);
    let det_b = b11 * (b22 * b33 - b23 * b23) - b12 * (b12 * b33 - b23 * b13)
        + b13 * (b12 * b23 - b22 * b13);
    let r = (det_b / 2.0).clamp(-1.0, 1.0);
    let phi = r.acos() / 3.0;
    let e1 = q + 2.0 * p * phi.cos();
    let e3 = q + 2.0 * p * (phi + 2.0 * std::f64::consts::PI / 3.0).cos();
    let e2 = 3.0 * q - e1 - e3;
    let mut e = [e1, e2, e3];
    e.sort_by(|x, y| y.partial_cmp(x).unwrap());
    e
}

/// Participation-ratio effective dimensionality ∈ [0,3]: (Σλ)² / Σλ².
/// ~1 = colours on a line, ~2 = a plane, ~3 = a full volume.
pub fn effective_dim(eig: [f64; 3]) -> f64 {
    let s: f64 = eig.iter().sum();
    let s2: f64 = eig.iter().map(|x| x * x).sum();
    if s2 <= 0.0 {
        0.0
    } else {
        s * s / s2
    }
}

/// Mean nearest-neighbour spacing in OKLab over a stride sample of queries.
pub fn mean_nn_spacing(cands: &[(Oklab, f64)], sample: usize, seed: u64) -> f64 {
    let n = cands.len();
    if n < 2 {
        return 0.0;
    }
    let m = sample.min(n);
    let step = (n / m).max(1);
    let mut acc = 0.0;
    let mut cnt = 0usize;
    let mut i = (seed as usize) % step;
    while i < n && cnt < m {
        let ci = cands[i].0;
        let mut bd = f64::INFINITY;
        for (j, &(cj, _)) in cands.iter().enumerate() {
            if j == i {
                continue;
            }
            let d = dist_sq(ci, cj);
            if d < bd {
                bd = d;
            }
        }
        acc += bd.sqrt();
        cnt += 1;
        i += step;
    }
    if cnt > 0 {
        acc / cnt as f64
    } else {
        0.0
    }
}
