//! The LOOK contract in Rust — a 1:1 mirror of `SixFour.Spec.Look` (MATH.md §9).
//! The verifiable part of the per-user look: a bounded `LookCode`, a reference
//! `affine_look` transform, and the global collapse. A future MLX-trained warp
//! is another inhabitant of the same contract (neutral=identity, gamut-closed,
//! bounded, continuous) — these properties are tested here, weight-independent.

use crate::color::{dist_sq, Oklab};
use crate::cyclic::CyclicStack;

pub const LOOK_DIM: usize = 4; // warmth, contrast, saturation, lift
pub const LOOK_BOUND_MAX: f64 = 0.8;
pub const LOOK_LIPSCHITZ: f64 = 1.5;

/// A bounded control vector in [-1,1]^LOOK_DIM. Control-surface-agnostic: named
/// knobs / latent / a transformer-on-top all map into this.
#[derive(Clone, Copy, Debug)]
pub struct LookCode(pub [f64; LOOK_DIM]);

impl LookCode {
    pub fn neutral() -> Self {
        LookCode([0.0; LOOK_DIM])
    }
    /// Rejects out-of-box values.
    pub fn new(v: [f64; LOOK_DIM]) -> Option<Self> {
        if v.iter().all(|&x| (-1.0..=1.0).contains(&x)) {
            Some(LookCode(v))
        } else {
            None
        }
    }
}

/// Reference (non-learned) look transform: a residual, clamped colour-space
/// warp. Neutral code ⇒ identity. Mirrors Haskell `affineLook`.
pub fn affine_look(code: &LookCode, palette: &[Oklab]) -> Vec<Oklab> {
    let v = code.0;
    let warmth = v[0].tanh() * 0.08;
    let contrast = 1.0 + 0.5 * v[1].tanh();
    let sat = 1.0 + 0.5 * v[2].tanh();
    let lift = v[3].tanh() * 0.10;
    let cl = |lo: f64, hi: f64, x: f64| x.max(lo).min(hi);
    palette
        .iter()
        .map(|c| {
            [
                cl(0.0, 1.0, 0.5 + (c[0] - 0.5) * contrast + lift),
                cl(-0.4, 0.4, c[1] * sat + warmth),
                cl(-0.4, 0.4, c[2] * sat + warmth),
            ]
        })
        .collect()
}

/// Collapse a per-frame stack to one global palette `G` (population-weighted
/// k-means) + per-frame local→global index remaps (nearest in OKLab). The
/// global analog of the per-frame `CompleteVoxelVolume`.
pub fn global_collapse(stack: &CyclicStack, k_global: usize, iters: usize) -> (Vec<Oklab>, Vec<Vec<u8>>) {
    let cands = crate::collapse::candidates(stack);
    let g = crate::collapse::weighted_kmeans(&cands, k_global, iters, 1);
    let remap = stack
        .frames
        .iter()
        .map(|f| {
            f.palette
                .iter()
                .map(|&c| {
                    let mut best = 0usize;
                    let mut bd = f64::INFINITY;
                    for (j, &gj) in g.iter().enumerate() {
                        let d = dist_sq(c, gj);
                        if d < bd {
                            bd = d;
                            best = j;
                        }
                    }
                    best as u8
                })
                .collect()
        })
        .collect();
    (g, remap)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::synth::{synth_stack, SynthParams};

    fn max_disp(a: &[Oklab], b: &[Oklab]) -> f64 {
        a.iter().zip(b).map(|(p, q)| dist_sq(*p, *q).sqrt()).fold(0.0, f64::max)
    }
    fn pal() -> Vec<Oklab> {
        synth_stack(&SynthParams::default(), 1, 64).frames[0].palette.clone()
    }

    #[test]
    fn neutral_is_identity() {
        let p = pal();
        assert!(max_disp(&affine_look(&LookCode::neutral(), &p), &p) < 1e-9);
    }

    #[test]
    fn gamut_closure() {
        let p = pal();
        for code in [[1.0, 1.0, 1.0, 1.0], [-1.0, -1.0, -1.0, -1.0], [0.5, -0.7, 0.3, -0.2]] {
            let out = affine_look(&LookCode(code), &p);
            assert!(out.iter().all(|c| (0.0..=1.0).contains(&c[0]) && c[1].abs() <= 0.4 + 1e-9 && c[2].abs() <= 0.4 + 1e-9));
        }
    }

    #[test]
    fn bounded_and_continuous() {
        let p = pal();
        let s = LookCode([0.6, -0.3, 0.8, 0.1]);
        let s2 = LookCode([0.65, -0.3, 0.8, 0.1]);
        assert!(max_disp(&affine_look(&s, &p), &p) <= LOOK_BOUND_MAX + 1e-9);
        let ds = ((s.0[0] - s2.0[0]).powi(2)).sqrt();
        assert!(max_disp(&affine_look(&s, &p), &affine_look(&s2, &p)) <= LOOK_LIPSCHITZ * ds + 1e-9);
    }

    #[test]
    fn collapse_is_valid() {
        let stk = synth_stack(&SynthParams::default(), 8, 64);
        let (g, remap) = global_collapse(&stk, 64, 8);
        assert_eq!(g.len(), 64);
        assert!(remap.iter().all(|f| f.iter().all(|&i| (i as usize) < 64)));
    }
}
