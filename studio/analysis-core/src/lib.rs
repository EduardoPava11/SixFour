//! analysis-core — decode a 64³ SixFour GIF and compute its cyclic
//! palette-environment descriptor (MATH.md §8). The shared foundation for the
//! `viz` tool and the future per-user "look" NN (burn).

pub mod collapse;
pub mod color;
pub mod cyclic;
pub mod geometry;
pub mod gif_io;
pub mod look;
pub mod synth;

pub use collapse::{candidates, fidelity, median_cut, population_value, weighted_kmeans};
pub use color::Oklab;
pub use cyclic::{descriptor, CyclicStack, Frame, Params, DESCRIPTOR_DIM};
pub use geometry::{color_pca, distinct_count, effective_dim, mean_nn_spacing};
pub use look::{affine_look, global_collapse, LookCode, LOOK_DIM};
pub use gif_io::{load_stack, synth_color, synthetic_stack, write_sample_gif};
pub use synth::{synth_stack, SynthParams};

#[cfg(test)]
mod tests {
    use super::cyclic::*;
    use super::gif_io::*;

    fn close(a: &[f64], b: &[f64], tol: f64) -> bool {
        a.len() == b.len() && a.iter().zip(b).all(|(&x, &y)| (x - y).abs() <= tol)
    }

    // Thm 4: cyclic deltas telescope to zero per colour.
    #[test]
    fn cyclic_deltas_close() {
        let stk = synthetic_stack(6, 12);
        let d = aligned_delta(&stk);
        let k = stk.frames[0].palette.len();
        for c in 0..k {
            let mut s = [0.0f64; 3];
            for t in 0..d.len() {
                for ax in 0..3 {
                    s[ax] += d[t][c][ax];
                }
            }
            assert!(s.iter().all(|v| v.abs() < 1e-9), "colour {c} did not close: {s:?}");
        }
    }

    // Thm 5: descriptor is S_K (palette relabel) invariant.
    #[test]
    fn descriptor_gauge_invariant() {
        let p = Params::default();
        let stk = synthetic_stack(6, 12);
        let k = stk.frames[0].palette.len();
        let perm: Vec<usize> = (0..k).map(|i| (i * 5 + 3) % k).collect(); // bijection (gcd(5,12)=1)
        let permuted = CyclicStack {
            frames: stk
                .frames
                .iter()
                .map(|f| Frame {
                    palette: perm.iter().map(|&j| f.palette[j]).collect(),
                    weights: perm.iter().map(|&j| f.weights[j]).collect(),
                })
                .collect(),
        };
        assert!(close(&descriptor(p, &stk), &descriptor(p, &permuted), 1e-7));
    }

    // Thm 5: descriptor is Z_T (frame-rotation) invariant.
    #[test]
    fn descriptor_cyclic_shift_invariant() {
        let p = Params::default();
        let stk = synthetic_stack(6, 12);
        let nt = stk.frames.len();
        let rotated = CyclicStack {
            frames: (0..nt).map(|i| stk.frames[(i + 1) % nt].clone()).collect(),
        };
        assert!(close(&descriptor(p, &stk), &descriptor(p, &rotated), 1e-7));
    }

    // Def 15 bounds: 0 ≤ H(w) ≤ ln K.
    #[test]
    fn palette_entropy_bounds() {
        let w = vec![1.0, 3.0, 0.0, 7.0, 2.0, 5.0, 1.0, 4.0];
        let h = palette_entropy(&w);
        assert!(h >= -1e-9 && h <= (w.len() as f64).ln() + 1e-9);
    }

    // Def 18: a constant (still) loop has zero spectral entropy.
    #[test]
    fn spectral_entropy_constant_is_zero() {
        assert!(spectral_entropy(&[3.0; 8]) <= 1e-12);
    }

    // Def 18: a single-frequency loop has spectral entropy = ln 2 (two AC bins).
    #[test]
    fn spectral_entropy_single_freq_is_ln2() {
        let xs: Vec<f64> = (0..8)
            .map(|n| (2.0 * std::f64::consts::PI * n as f64 / 8.0).cos())
            .collect();
        assert!((spectral_entropy(&xs) - std::f64::consts::LN_2).abs() < 1e-9);
    }

    // Full decode path: write a real 64×64×8 GIF, decode it, check completeness.
    #[test]
    fn gif_roundtrip_is_complete_and_describable() {
        let path = std::env::temp_dir().join("sixfour_sample_test.gif");
        let path = path.to_str().unwrap();
        write_sample_gif(path, 8).expect("write");
        let stk = load_stack(path).expect("load");
        assert_eq!(stk.frames.len(), 8);
        for f in &stk.frames {
            assert_eq!(f.palette.len(), 256);
            assert_eq!(f.weights.len(), 256);
            assert!((f.weights.iter().sum::<f64>() - 4096.0).abs() < 0.5, "weights sum to pixel count");
            assert!(f.weights.iter().all(|&w| w > 0.0), "surjective: every colour used");
        }
        assert_eq!(descriptor(Params::default(), &stk).len(), DESCRIPTOR_DIM);
    }

    // --- Phase A study primitives (sanity; the directional findings are
    //     measured in the `explore` binary, not asserted here) ---

    #[test]
    fn fidelity_increases_with_spread() {
        use crate::{collapse, synth::{synth_stack, SynthParams}};
        let base = SynthParams { n_clusters: 6, spread: 0.02, drift: 0.1, gamut: 0.8, conc_skew: 1.0, pop_drift: 0.5, seed: 3 };
        let wide = SynthParams { spread: 0.15, ..base };
        let fid = |p: &SynthParams| {
            let s = synth_stack(p, 16, 64);
            let c = collapse::candidates(&s);
            collapse::fidelity(&collapse::weighted_kmeans(&c, 64, 10, 1), &c)
        };
        let (lo, hi) = (fid(&base), fid(&wide));
        assert!(hi > lo, "more intra-cluster spread must raise collapse error: lo={lo}, hi={hi}");
    }

    #[test]
    fn population_value_runs_finite() {
        use crate::{collapse, synth::{synth_stack, SynthParams}};
        let s = synth_stack(&SynthParams { conc_skew: 2.5, ..SynthParams::default() }, 24, 128);
        let (fw, fu) = collapse::population_value(&collapse::candidates(&s), 64, 12, 1);
        assert!(fw.is_finite() && fu.is_finite() && fw >= 0.0 && fu >= 0.0);
    }

    #[test]
    fn geometry_sane() {
        use crate::{collapse, geometry, synth::{synth_stack, SynthParams}};
        let c = collapse::candidates(&synth_stack(&SynthParams::default(), 16, 128));
        let ed = geometry::effective_dim(geometry::color_pca(&c));
        assert!(ed > 0.5 && ed <= 3.0001, "effective dim out of range: {ed}");
        assert!(geometry::distinct_count(&c, 0.01) > 0);
        assert!(geometry::mean_nn_spacing(&c, 64, 1) >= 0.0);
    }
}
