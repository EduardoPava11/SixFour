//! Continuous OKLab Gaussian-mixture substrate — the look-NN's input.
//! Bit-mirrors `~/SixFour/spec/src/SixFour/Spec/GMM.hs`. Each palette is a mixture of
//! `(mean, cov, weight)` components — exactly the `(mean, covariance, count)` the device
//! computes in `ClusterStatistics`. Replaces the deleted 88-float category code.

use crate::color::Oklab;

/// A symmetric 3×3 OKLab covariance as its six independent entries
/// `(s_LL, s_La, s_Lb, s_aa, s_ab, s_bb)` — matches `Spec.Diversity.Cov3`.
pub type Cov6 = [f64; 6];

/// One mixture component.
#[derive(Clone, Copy, Debug)]
pub struct Gaussian {
    pub mean: Oklab,
    pub cov: Cov6,
    pub weight: f64,
}

/// Per-component token width fed to the set encoder: μ(3) + Σ(6) + w(1) = 10.
pub const GMM_TOKEN_DIM: usize = 10;

/// A component as its flat 10-float token `[μL,μa,μb, ΣLL,ΣLa,ΣLb,Σaa,Σab,Σbb, w]`.
pub fn gaussian_token(g: &Gaussian) -> [f64; GMM_TOKEN_DIM] {
    [
        g.mean[0], g.mean[1], g.mean[2],
        g.cov[0], g.cov[1], g.cov[2], g.cov[3], g.cov[4], g.cov[5],
        g.weight,
    ]
}

/// A degenerate (zero-covariance) point-mass component.
pub fn point_mass(mean: Oklab, weight: f64) -> Gaussian {
    Gaussian { mean, cov: [0.0; 6], weight }
}

/// Lift a bare weighted-candidate cloud to a point-mass mixture.
pub fn point_mass_gmm(cands: &[(Oklab, f64)]) -> Vec<Gaussian> {
    cands.iter().map(|&(c, w)| point_mass(c, w)).collect()
}

pub fn total_weight(gm: &[Gaussian]) -> f64 {
    gm.iter().map(|g| g.weight).sum()
}

/// Renormalise weights to sum to 1 (no-op when total weight is non-positive).
pub fn normalize_gmm(gm: &[Gaussian]) -> Vec<Gaussian> {
    let s = total_weight(gm);
    if s <= 0.0 {
        gm.to_vec()
    } else {
        gm.iter().map(|g| Gaussian { weight: g.weight / s, ..*g }).collect()
    }
}

/// L1 Pool: merge the per-frame mixtures into one capture mixture and renormalise.
pub fn pool_gmm(frames: &[Vec<Gaussian>]) -> Vec<Gaussian> {
    let all: Vec<Gaussian> = frames.iter().flat_map(|f| f.iter().copied()).collect();
    normalize_gmm(&all)
}

/// Mixture mean `μ = Σ pᵢ μᵢ`. Permutation-invariant.
pub fn mixture_mean(gm: &[Gaussian]) -> Oklab {
    let s = total_weight(gm);
    if s <= 0.0 {
        return [0.0; 3];
    }
    let mut m = [0.0f64; 3];
    for g in gm {
        for ax in 0..3 {
            m[ax] += g.weight * g.mean[ax];
        }
    }
    [m[0] / s, m[1] / s, m[2] / s]
}

/// Mixture covariance by the law of total covariance: within `Σ pᵢ Σᵢ` plus between
/// `Σ pᵢ (μᵢ−μ)(μᵢ−μ)ᵀ`. For point masses (Σᵢ=0) this is the pure between term, equal
/// to `geometry`'s weighted covariance — the cross-check the spec proves.
pub fn mixture_covariance(gm: &[Gaussian]) -> Cov6 {
    let s = total_weight(gm);
    if s <= 0.0 {
        return [0.0; 6];
    }
    let mu = mixture_mean(gm);
    let mut q = [0.0f64; 6];
    for g in gm {
        let p = g.weight / s;
        let dl = g.mean[0] - mu[0];
        let da = g.mean[1] - mu[1];
        let db = g.mean[2] - mu[2];
        q[0] += p * (g.cov[0] + dl * dl);
        q[1] += p * (g.cov[1] + dl * da);
        q[2] += p * (g.cov[2] + dl * db);
        q[3] += p * (g.cov[3] + da * da);
        q[4] += p * (g.cov[4] + da * db);
        q[5] += p * (g.cov[5] + db * db);
    }
    q
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: &[f64], b: &[f64], tol: f64) -> bool {
        a.len() == b.len() && a.iter().zip(b).all(|(&x, &y)| (x - y).abs() <= tol)
    }

    // The fixture from `Codegen.Burn` (studio/look-nn/src/generated/contract.rs::golden).
    fn fixture() -> Vec<Gaussian> {
        point_mass_gmm(&[([0.20, 0.05, -0.10], 1.0), ([0.80, -0.10, 0.10], 2.0)])
    }

    #[test]
    fn token_width_is_10() {
        assert_eq!(GMM_TOKEN_DIM, 10);
        assert_eq!(gaussian_token(&fixture()[0]).len(), 10);
    }

    #[test]
    fn pool_renormalises_weights() {
        let pooled = pool_gmm(&[fixture(), fixture()]);
        assert!((total_weight(&pooled) - 1.0).abs() < 1e-12);
        assert_eq!(pooled.len(), 4);
    }

    // GOLDEN cross-check vs the Haskell reference (Spec.GMM via Codegen.Burn).
    #[test]
    fn golden_mixture_moments_match_haskell() {
        let gm = fixture();
        let mean_golden = [0.6, -5.000000000000001e-2, 3.333333333333333e-2];
        let cov_golden = [
            8.000000000000002e-2, -2.0e-2, 2.666666666666667e-2,
            5.0e-3, -6.666666666666666e-3, 8.88888888888889e-3,
        ];
        assert!(close(&mixture_mean(&gm), &mean_golden, 1e-9), "mean: {:?}", mixture_mean(&gm));
        assert!(close(&mixture_covariance(&gm), &cov_golden, 1e-9), "cov: {:?}", mixture_covariance(&gm));
    }
}
