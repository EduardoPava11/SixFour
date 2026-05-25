//! Controllable synthetic 64³ GIF generator for the exploration study.
//! Produces a `CyclicStack` (per-frame OKLab palettes + per-colour populations)
//! whose geometry and dynamics are set by `SynthParams`, so we can probe how
//! the collapse task changes as we sweep each knob.

use crate::color::srgb_to_oklab;
use crate::cyclic::{CyclicStack, Frame};

#[derive(Clone, Copy, Debug)]
pub struct SynthParams {
    /// Number of distinct colour clusters.
    pub n_clusters: usize,
    /// Intra-cluster spread (sRGB stddev, ~0.0..0.2).
    pub spread: f64,
    /// Temporal motion amplitude of clusters over the loop (~0.0..0.4).
    pub drift: f64,
    /// Overall RGB coverage (0..1; 1 ≈ full cube around mid-grey).
    pub gamut: f64,
    /// Population skew (0 ≈ uniform usage; higher ≈ a few dominant colours).
    pub conc_skew: f64,
    pub seed: u64,
}

impl Default for SynthParams {
    fn default() -> Self {
        SynthParams { n_clusters: 6, spread: 0.06, drift: 0.18, gamut: 0.8, conc_skew: 1.0, seed: 1 }
    }
}

/// Tiny LCG (reproducible, dependency-free).
struct Lcg(u64);
impl Lcg {
    fn f64(&mut self) -> f64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        ((self.0 >> 11) as f64) / ((1u64 << 53) as f64)
    }
    /// ~triangular noise, mean 0, range [-1.5, 1.5].
    fn gauss(&mut self) -> f64 {
        self.f64() + self.f64() + self.f64() - 1.5
    }
}

/// Build a controlled synthetic stack: `t_count` frames × `k` colours.
pub fn synth_stack(p: &SynthParams, t_count: usize, k: usize) -> CyclicStack {
    let nc = p.n_clusters.max(1);
    let mut r = Lcg(p.seed.wrapping_mul(2_654_435_761).wrapping_add(11));

    // Cluster bases / drift phases (per channel).
    let mut base = vec![[0.0f64; 3]; nc];
    let mut phase = vec![[0.0f64; 3]; nc];
    for c in 0..nc {
        for ch in 0..3 {
            base[c][ch] = 0.5 + (r.f64() - 0.5) * p.gamut;
            phase[c][ch] = 6.283 * r.f64();
        }
    }
    // Per-slot cluster assignment + fixed intra-cluster offset.
    let mut slot_cluster = vec![0usize; k];
    let mut offset = vec![[0.0f64; 3]; k];
    for s in 0..k {
        slot_cluster[s] = s % nc;
        for ch in 0..3 {
            offset[s][ch] = r.gauss() * p.spread;
        }
    }
    // Per-slot populations (constant across frames), skewed, summing to 4096.
    let mut weights = vec![0.0f64; k];
    let exp = 1.0 + p.conc_skew * 4.0;
    let mut wsum = 0.0;
    for s in 0..k {
        let w = (r.f64()).powf(exp) + 1e-3; // +floor so every colour is used
        weights[s] = w;
        wsum += w;
    }
    for w in weights.iter_mut() {
        *w = *w / wsum * 4096.0;
    }

    let frames = (0..t_count)
        .map(|t| {
            let u = 2.0 * std::f64::consts::PI * (t as f64) / (t_count as f64);
            let palette = (0..k)
                .map(|s| {
                    let c = slot_cluster[s];
                    let rgb = [0, 1, 2].map(|ch| {
                        let center = (base[c][ch] + p.drift * (u + phase[c][ch]).sin()).clamp(0.0, 1.0);
                        (center + offset[s][ch]).clamp(0.0, 1.0)
                    });
                    srgb_to_oklab(rgb)
                })
                .collect();
            Frame { palette, weights: weights.clone() }
        })
        .collect();

    CyclicStack { frames }
}
