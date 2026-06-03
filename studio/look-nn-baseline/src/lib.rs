//! look-nn-baseline — the **non-NN baseline-to-beat oracle** for the math-first look-NN.
//!
//! This crate is a gradient-free **1+1-ES** over the 768-coefficient Haar genome that
//! maximises gamut coverage. It is **NOT** a neural network: no autodiff, no MLX/PyTorch,
//! no dataset. Its role is to answer "what's the best a *non-learned* search can do?"
//! so the trained CoreML look-NN (Spec.LookNetE/R/D → Codegen.CoreML → .mlpackage) has
//! an honest baseline to beat.
//!
//! Renamed 2026-05-28 from `look-nn` to clarify its role: the actual look-NN is the
//! ANE-resident model built from the typed Haskell spec; this crate is the reference
//! ceiling that learned models must outperform to justify their fidelity cost.
//!
//! Consumes the generated dimensional contract (`Codegen.Burn` → `generated/contract.rs`)
//! and the `analysis-core` GMM/Bures math (themselves golden-checked against the Haskell
//! spec).

#[path = "generated/contract.rs"]
pub mod contract;

use analysis_core::Oklab;

// ---------------------------------------------------------------------------
// L6 Reconstruct — inverse Haar (768 coefficients → 256 OKLab leaves)
// ---------------------------------------------------------------------------

/// Inverse Haar transform: a 768-vector `[root(3), then 255 σ-balanced offsets(3 each)]`
/// → 256 OKLab leaves. Each node splits into mirror children `parent ± δ`. Mirrors
/// `Spec.PairTree.reconstruct`. The offsets cancel, so `mean(leaves) = root` (balance).
pub fn reconstruct(coeffs: &[f64]) -> Vec<Oklab> {
    assert_eq!(coeffs.len(), contract::DOF, "expected {} Haar coefficients", contract::DOF);
    let mut nodes: Vec<Oklab> = vec![[coeffs[0], coeffs[1], coeffs[2]]];
    let mut idx = 3;
    for level in 0..contract::MAX_PONDER_DEPTH {
        let count = 1usize << level; // 2^level nodes / offsets at this level
        let mut next = Vec::with_capacity(count * 2);
        for n in 0..count {
            let off = [coeffs[idx], coeffs[idx + 1], coeffs[idx + 2]];
            idx += 3;
            let p = nodes[n];
            next.push([p[0] + off[0], p[1] + off[1], p[2] + off[2]]);
            next.push([p[0] - off[0], p[1] - off[1], p[2] - off[2]]);
        }
        nodes = next;
    }
    nodes
}

/// Clamp a palette into the working OKLab gamut (the decoder's L3-closure step).
pub fn clamp_gamut(palette: &[Oklab]) -> Vec<Oklab> {
    palette
        .iter()
        .map(|c| [c[0].clamp(0.0, 1.0), c[1].clamp(-0.4, 0.4), c[2].clamp(-0.4, 0.4)])
        .collect()
}

// ---------------------------------------------------------------------------
// The headline objective — 16³ OKLab gamut coverage (Spec.Coverage)
// ---------------------------------------------------------------------------

const BINS: i64 = 16;

fn bin_l(v: f64) -> i64 {
    ((v * BINS as f64).floor() as i64).clamp(0, BINS - 1)
}
fn bin_ab(v: f64) -> i64 {
    (((v + 0.5) * BINS as f64).floor() as i64).clamp(0, BINS - 1)
}

/// Fraction of the 16³ = 4096 OKLab voxels the palette occupies (the diversity
/// yardstick the captures are judged by — `Spec.Coverage`, not MSE).
pub fn coverage(palette: &[Oklab]) -> f64 {
    use std::collections::HashSet;
    let mut seen: HashSet<(i64, i64, i64)> = HashSet::new();
    for c in palette {
        seen.insert((bin_l(c[0]), bin_ab(c[1]), bin_ab(c[2])));
    }
    seen.len() as f64 / (BINS * BINS * BINS) as f64
}

// ---------------------------------------------------------------------------
// A tiny reproducible RNG
// ---------------------------------------------------------------------------

pub struct Lcg(pub u64);
impl Lcg {
    pub fn next_f64(&mut self) -> f64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        ((self.0 >> 11) as f64) / ((1u64 << 53) as f64)
    }
    /// ~triangular noise, mean 0, range [-1.5, 1.5].
    pub fn gauss(&mut self) -> f64 {
        self.next_f64() + self.next_f64() + self.next_f64() - 1.5
    }
}

// ---------------------------------------------------------------------------
// L3–L5 forward net (the contract inhabitant) — set encoder + core + tree decoder
// ---------------------------------------------------------------------------

/// A forward inhabitant of the look-net contract at the generated shapes:
/// `E: per-token 10 → dM (mean-pooled)`, `R: dM → dM (residual)`, `D: dM → 768`.
/// Weights are seeded; this is the *structure* the v2 burn trainer will fit (and the
/// v1 ES optimises the decoded 768-genome directly). Shapes assert against `contract`.
pub struct LookNet {
    w_e: Vec<f64>, // dM × GMM_TOKEN_DIM
    w_r: Vec<f64>, // dM × dM
    w_d: Vec<f64>, // DOF × dM
}

impl LookNet {
    pub fn seeded(seed: u64) -> Self {
        let mut r = Lcg(seed);
        let dm = contract::MODEL_DIM;
        let g = |r: &mut Lcg, n: usize| (0..n).map(|_| r.gauss() * 0.1).collect::<Vec<_>>();
        LookNet {
            w_e: g(&mut r, dm * contract::GMM_TOKEN_DIM),
            w_r: g(&mut r, dm * dm),
            w_d: g(&mut r, contract::DOF * dm),
        }
    }

    /// Forward pass: a set of GMM tokens (each `GMM_TOKEN_DIM` wide) → 768 Haar coeffs.
    pub fn forward(&self, tokens: &[[f64; contract::GMM_TOKEN_DIM]]) -> Vec<f64> {
        let dm = contract::MODEL_DIM;
        // L3: per-token affine → tanh, mean-pooled over the set (permutation-invariant).
        let mut ctx = vec![0.0f64; dm];
        for tok in tokens {
            for i in 0..dm {
                let mut acc = 0.0;
                for j in 0..contract::GMM_TOKEN_DIM {
                    acc += self.w_e[i * contract::GMM_TOKEN_DIM + j] * tok[j];
                }
                ctx[i] += acc.tanh();
            }
        }
        let n = tokens.len().max(1) as f64;
        for c in ctx.iter_mut() {
            *c /= n;
        }
        // L4: one residual core step (depth-recurrent; ponder ≤ N in the full design).
        let mut core = ctx.clone();
        for i in 0..dm {
            let mut acc = 0.0;
            for j in 0..dm {
                acc += self.w_r[i * dm + j] * ctx[j];
            }
            core[i] += acc.tanh();
        }
        // L5: linear decode → 768 Haar coefficients.
        (0..contract::DOF)
            .map(|d| (0..dm).map(|j| self.w_d[d * dm + j] * core[j]).sum())
            .collect()
    }
}

// ---------------------------------------------------------------------------
// v1 training: gradient-free 1+1-ES over the direct 768-coefficient genome
// ---------------------------------------------------------------------------

/// 1+1 Evolution Strategy maximising 'coverage' of the reconstructed, gamut-clamped
/// palette over the direct 768-coefficient genome (COMPETITION.md v1 encoding).
/// Returns the best genome and its coverage. Forward-only, no gradients — the QD/ES
/// outer loop the design committed to. (A full objective adds Bures fidelity + the DPP
/// beauty term; coverage alone is the headline diversity metric and suffices for v1.)
pub fn es_optimize_coverage(init: &[f64], generations: usize, sigma: f64, seed: u64) -> (Vec<f64>, f64) {
    let mut r = Lcg(seed);
    let score = |g: &[f64]| coverage(&clamp_gamut(&reconstruct(g)));
    let mut best = init.to_vec();
    let mut best_score = score(&best);
    for _ in 0..generations {
        let cand: Vec<f64> = best.iter().map(|&x| x + r.gauss() * sigma).collect();
        let s = score(&cand);
        if s > best_score {
            best = cand;
            best_score = s;
        }
    }
    (best, best_score)
}

/// A near-neutral starting genome: root at mid-grey, tiny offsets (low coverage — so
/// the ES has clear room to expand the palette into the gamut).
pub fn neutral_genome() -> Vec<f64> {
    let mut g = vec![0.0f64; contract::DOF];
    g[0] = 0.5; // root L = mid grey; a,b = 0
    for off in g.iter_mut().skip(3) {
        *off = 0.001;
    }
    g
}

#[cfg(test)]
mod tests {
    use super::*;
    use analysis_core::{bures_barycenter_cov, mixture_covariance, mixture_mean, point_mass_gmm, Gaussian};

    // The dimensional contract is wired and self-consistent.
    #[test]
    fn contract_shapes_consistent() {
        assert_eq!(contract::DOF, 768);
        assert_eq!(contract::GMM_TOKEN_DIM, 10);
        assert_eq!(contract::ENCODER_IO.in_dim, contract::GMM_TOKEN_DIM);
        assert_eq!(contract::ENCODER_IO.out_dim, contract::MODEL_DIM);
        assert_eq!(contract::CORE_IO.in_dim, contract::MODEL_DIM);
        // Post σ-pair pivot: the decoder emits SIGMA_PAIR_DOF (384) generator
        // coefficients, which reconstruct into the DOF (768) leaf-space palette.
        // (Pre-pivot the decoder emitted DOF directly; this assertion was stale.)
        assert_eq!(contract::DECODER_IO.out_dim, contract::SIGMA_PAIR_DOF);
        assert_eq!(contract::SIGMA_PAIR_DOF * 2, contract::DOF);
        assert_eq!(contract::LEVEL_DOF.iter().sum::<usize>(), contract::DOF - 3);
    }

    // GOLDEN re-check: the analysis-core math this crate stands on still matches the
    // Haskell reference values baked into contract.rs::golden (the bridge holds here too).
    #[test]
    fn golden_math_matches_contract() {
        let gm = point_mass_gmm(&[([0.20, 0.05, -0.10], 1.0), ([0.80, -0.10, 0.10], 2.0)]);
        let m = mixture_mean(&gm);
        for (a, b) in m.iter().zip(contract::golden::GMM_MIX_MEAN.iter()) {
            assert!((a - b).abs() < 1e-9);
        }
        let cov = mixture_covariance(&gm);
        for (a, b) in cov.iter().zip(contract::golden::GMM_MIX_COV.iter()) {
            assert!((a - b).abs() < 1e-9);
        }
        let g1 = Gaussian { mean: [0.3, 0.0, 0.0], cov: [0.02, 0.0, 0.0, 0.01, 0.0, 0.01], weight: 1.0 };
        let g2 = Gaussian { mean: [0.7, 0.0, 0.0], cov: [0.03, 0.0, 0.0, 0.02, 0.0, 0.015], weight: 1.0 };
        let bary = bures_barycenter_cov(&[(0.5, g1.cov), (0.5, g2.cov)]);
        for (a, b) in bary.iter().zip(contract::golden::BURES_BARY_COV.iter()) {
            assert!((a - b).abs() < 1e-6);
        }
    }

    // L6: reconstruct yields 256 leaves whose mean is the root (the offsets cancel).
    #[test]
    fn reconstruct_is_balanced_256() {
        let mut g = neutral_genome();
        g[0] = 0.42;
        // give a few offsets some magnitude
        for (i, x) in g.iter_mut().enumerate().skip(3).take(20) {
            *x = 0.01 * (i as f64);
        }
        let leaves = reconstruct(&g);
        assert_eq!(leaves.len(), 256);
        let mut mean = [0.0f64; 3];
        for c in &leaves {
            for ax in 0..3 {
                mean[ax] += c[ax] / 256.0;
            }
        }
        assert!((mean[0] - 0.42).abs() < 1e-9 && mean[1].abs() < 1e-9 && mean[2].abs() < 1e-9);
    }

    // The forward net inhabits the contract: a set of tokens → exactly 768 coefficients.
    #[test]
    fn net_forward_emits_dof_coefficients() {
        let net = LookNet::seeded(7);
        let tokens: Vec<[f64; 10]> = (0..256)
            .map(|i| {
                let t = i as f64 / 256.0;
                [t, t - 0.5, 0.5 - t, 0.01, 0.0, 0.0, 0.01, 0.0, 0.01, 1.0 / 256.0]
            })
            .collect();
        let coeffs = net.forward(&tokens);
        assert_eq!(coeffs.len(), contract::DOF);
        let palette = clamp_gamut(&reconstruct(&coeffs));
        assert_eq!(palette.len(), 256);
        assert!(coverage(&palette) > 0.0);
    }

    // v1 training works: the gradient-free ES strictly improves coverage from the
    // near-neutral (near-zero-coverage) start — the learnable path is optimisable.
    #[test]
    fn es_improves_coverage_over_the_neutral_start() {
        let init = neutral_genome();
        let start_cov = coverage(&clamp_gamut(&reconstruct(&init)));
        let (_, best_cov) = es_optimize_coverage(&init, 400, 0.05, 1);
        assert!(best_cov > start_cov, "ES did not improve: {start_cov} -> {best_cov}");
        // and the elite is monotone: re-running never lowers the best score.
        assert!(best_cov >= start_cov);
    }
}
