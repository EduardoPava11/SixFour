//! The cyclic palette environment and its entropy — a 1:1 Rust port of
//! `~/SixFour/spec/src/SixFour/Spec/Cyclic.hs` (MATH.md §8). The Haskell spec
//! stays the source of truth; names match deliberately.
//!
//! A looping GIF is a cyclic sequence of `T` palettes; each palette is `K`
//! OKLab colours with population weights. Everything here is invariant under
//! the cyclic shift `Z_T` (no canonical start frame) and the palette gauge
//! `S_K` (no canonical colour order) — see the descriptor + its tests.

use crate::color::{dist_sq, Oklab};

/// Entropic-OT regularisation + iteration count for the transition plans.
#[derive(Clone, Copy, Debug)]
pub struct Params {
    pub eps: f64,
    pub iters: usize,
}
impl Default for Params {
    fn default() -> Self {
        Params { eps: 0.1, iters: 20 }
    }
}

/// One frame: a palette of `K` OKLab colours + their population weights.
#[derive(Clone, Debug)]
pub struct Frame {
    pub palette: Vec<Oklab>,
    pub weights: Vec<f64>,
}

/// A cyclic stack of `T` frames (frame `T-1` transitions back to frame 0).
#[derive(Clone, Debug)]
pub struct CyclicStack {
    pub frames: Vec<Frame>,
}

pub const DESCRIPTOR_DIM: usize = 16;

// ---- per-frame entropy (Def 15, 16) -------------------------------------

/// Def 15. Shannon entropy of the weight distribution, `-Σ w ln w`.
pub fn palette_entropy(weights: &[f64]) -> f64 {
    let s: f64 = weights.iter().sum();
    if s <= 0.0 {
        return 0.0;
    }
    -weights
        .iter()
        .map(|&w| {
            let p = w / s;
            if p > 0.0 {
                p * p.ln()
            } else {
                0.0
            }
        })
        .sum::<f64>()
}

/// Def 16. Differential entropy of the Gaussian fit to the weighted palette:
/// `½ ln((2πe)³ |Σ|)` with `Σ` the weighted 3×3 OKLab covariance.
pub fn gaussian_color_entropy(palette: &[Oklab], weights: &[f64]) -> f64 {
    let n = palette.len();
    let s: f64 = weights.iter().sum();
    let p: Vec<f64> = if s <= 0.0 {
        vec![1.0 / (n.max(1) as f64); n]
    } else {
        weights.iter().map(|&w| w / s).collect()
    };
    let (mut ml, mut ma, mut mb) = (0.0, 0.0, 0.0);
    for i in 0..n {
        ml += p[i] * palette[i][0];
        ma += p[i] * palette[i][1];
        mb += p[i] * palette[i][2];
    }
    let (mut sll, mut sla, mut slb, mut saa, mut sab, mut sbb) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    for i in 0..n {
        let dl = palette[i][0] - ml;
        let da = palette[i][1] - ma;
        let db = palette[i][2] - mb;
        sll += p[i] * dl * dl;
        sla += p[i] * dl * da;
        slb += p[i] * dl * db;
        saa += p[i] * da * da;
        sab += p[i] * da * db;
        sbb += p[i] * db * db;
    }
    let det = sll * (saa * sbb - sab * sab) - sla * (sla * sbb - sab * slb)
        + slb * (sla * sab - saa * slb);
    let two_pi_e = 2.0 * std::f64::consts::PI * std::f64::consts::E;
    0.5 * (two_pi_e.powi(3) * det.max(1e-12)).ln()
}

// ---- transitions, transport, deltas (Def 13, 14; Thm 4) -----------------

/// OKLab squared-distance cost matrix `C[i,j]`.
pub fn cost_matrix(pa: &[Oklab], pb: &[Oklab]) -> Vec<Vec<f64>> {
    pa.iter()
        .map(|&a| pb.iter().map(|&b| dist_sq(a, b)).collect())
        .collect()
}

fn normalise(w: &[f64]) -> Vec<f64> {
    let s: f64 = w.iter().sum();
    if s <= 0.0 {
        w.to_vec()
    } else {
        w.iter().map(|&x| x / s).collect()
    }
}

/// Def 13. Entropic-OT transition plan `Γ[i,j] = u_i K_{ij} v_j` between two
/// weighted palettes. Mirrors `StageB`'s Sinkhorn-Knopp scaling (now local).
pub fn transition_plan(p: Params, cost: &[Vec<f64>], wa: &[f64], wb: &[f64]) -> Vec<Vec<f64>> {
    let nc = cost.len();
    let nk = if nc == 0 { 0 } else { cost[0].len() };
    let a = normalise(wa);
    let b = normalise(wb);
    let kernel: Vec<Vec<f64>> = cost
        .iter()
        .map(|row| row.iter().map(|&c| (-c / p.eps).exp()).collect())
        .collect();
    let mut u = vec![1.0; nc];
    let mut v = vec![1.0; nk];
    for _ in 0..p.iters {
        for k in 0..nk {
            let mut ktu = 0.0;
            for i in 0..nc {
                ktu += u[i] * kernel[i][k];
            }
            v[k] = if ktu == 0.0 { 0.0 } else { b[k] / ktu };
        }
        for i in 0..nc {
            let mut kv = 0.0;
            for k in 0..nk {
                kv += v[k] * kernel[i][k];
            }
            u[i] = if kv == 0.0 { 0.0 } else { a[i] / kv };
        }
    }
    (0..nc)
        .map(|i| (0..nk).map(|k| u[i] * kernel[i][k] * v[k]).collect())
        .collect()
}

/// Def 17. Transport cost `Σ Γ[i,j] · cost[i,j]`.
pub fn transport_cost(plan: &[Vec<f64>], cost: &[Vec<f64>]) -> f64 {
    plan.iter()
        .zip(cost)
        .map(|(pr, cr)| pr.iter().zip(cr).map(|(&p, &c)| p * c).sum::<f64>())
        .sum()
}

/// Def 17. Transport entropy `-Σ Γ ln Γ`.
pub fn transport_entropy(plan: &[Vec<f64>]) -> f64 {
    -plan
        .iter()
        .flat_map(|row| row.iter())
        .map(|&p| if p > 0.0 { p * p.ln() } else { 0.0 })
        .sum::<f64>()
}

/// Def 14 (aligned). Cyclic first difference `Δ[t,k] = P_{t+1}[k] − P_t[k]`.
pub fn aligned_delta(stack: &CyclicStack) -> Vec<Vec<Oklab>> {
    let nt = stack.frames.len();
    (0..nt)
        .map(|t| {
            let a = &stack.frames[t].palette;
            let b = &stack.frames[(t + 1) % nt].palette;
            a.iter()
                .zip(b)
                .map(|(&x, &y)| [y[0] - x[0], y[1] - x[1], y[2] - x[2]])
                .collect()
        })
        .collect()
}

/// Thm 4. Holonomy defect `(K − tr(M)) / K`, where `M` is the product of the
/// per-transition row-stochastic transport maps around the loop. A *trace*,
/// hence conjugation- (cyclic-shift-) invariant; 0 iff the loop closes.
pub fn holonomy_defect(p: Params, stack: &CyclicStack) -> f64 {
    let nt = stack.frames.len();
    if nt == 0 {
        return 0.0;
    }
    let nk = stack.frames[0].palette.len();
    let mut m = identity(nk);
    for t in 0..nt {
        let fa = &stack.frames[t];
        let fb = &stack.frames[(t + 1) % nt];
        let cost = cost_matrix(&fa.palette, &fb.palette);
        let plan = transition_plan(p, &cost, &fa.weights, &fb.weights);
        let map = row_stochastic(&plan);
        m = mat_mul(&map, &m);
    }
    let tr: f64 = (0..nk).map(|i| m[i][i]).sum();
    (nk as f64 - tr) / nk as f64
}

// ---- spectral functionals (Def 18, 19) ----------------------------------

/// Power spectrum via naive DFT: `power[k] = |Σ_n x[n] e^{-2πi k n / N}|²`.
pub fn dft_power(xs: &[f64]) -> Vec<f64> {
    let n = xs.len();
    let nd = n as f64;
    (0..n)
        .map(|k| {
            let (mut re, mut im) = (0.0, 0.0);
            for (idx, &x) in xs.iter().enumerate() {
                let ang = -2.0 * std::f64::consts::PI * (k as f64) * (idx as f64) / nd;
                re += x * ang.cos();
                im += x * ang.sin();
            }
            re * re + im * im
        })
        .collect()
}

/// Def 18. Spectral entropy over the AC bins (DC dropped); 0 if no AC power.
/// `Z_T`-invariant (cyclic shift = phase rotation).
pub fn spectral_entropy(xs: &[f64]) -> f64 {
    let pw = dft_power(xs);
    let ac = &pw[1.min(pw.len())..];
    let tot: f64 = ac.iter().sum();
    if tot <= 1e-12 {
        return 0.0;
    }
    -ac.iter()
        .map(|&a| {
            let p = a / tot;
            if p > 0.0 {
                p * p.ln()
            } else {
                0.0
            }
        })
        .sum::<f64>()
}

/// Def 19. Kolmogorov–Szegő entropy-rate estimate from the AC periodogram.
pub fn entropy_rate(xs: &[f64]) -> f64 {
    let pw = dft_power(xs);
    let ac = &pw[1.min(pw.len())..];
    let tot: f64 = ac.iter().sum();
    let n = ac.len() as f64;
    if tot <= 1e-12 || n <= 0.0 {
        return 0.0;
    }
    0.5 * (2.0 * std::f64::consts::PI * std::f64::consts::E).ln()
        + (1.0 / (2.0 * n)) * ac.iter().map(|&a| a.max(1e-12).ln()).sum::<f64>()
}

// ---- the invariant descriptor (Def 20) ----------------------------------

/// Def 20. The 16-D `Z_T × S_K`-invariant descriptor — the NN feature seam.
pub fn descriptor(p: Params, stack: &CyclicStack) -> Vec<f64> {
    let nt = stack.frames.len();
    let hw: Vec<f64> = stack.frames.iter().map(|f| palette_entropy(&f.weights)).collect();
    let hg: Vec<f64> = stack
        .frames
        .iter()
        .map(|f| gaussian_color_entropy(&f.palette, &f.weights))
        .collect();
    let mut costs = Vec::with_capacity(nt);
    let mut tpents = Vec::with_capacity(nt);
    for t in 0..nt {
        let fa = &stack.frames[t];
        let fb = &stack.frames[(t + 1) % nt];
        let cost = cost_matrix(&fa.palette, &fb.palette);
        let plan = transition_plan(p, &cost, &fa.weights, &fb.weights);
        costs.push(transport_cost(&plan, &cost));
        tpents.push(transport_entropy(&plan));
    }
    let ac = {
        let pw = dft_power(&hw);
        let ac = pw[1.min(pw.len())..].to_vec();
        let tot: f64 = ac.iter().sum();
        if tot <= 1e-12 {
            vec![0.0; ac.len()]
        } else {
            ac.iter().map(|&a| a / tot).collect()
        }
    };
    let coeff = |i: usize| -> f64 { ac.get(i).copied().unwrap_or(0.0) };

    vec![
        mean(&hw),
        sd(&hw),
        mean(&hg),
        sd(&hg),
        costs.iter().sum(),
        mean(&costs),
        mean(&tpents),
        spectral_entropy(&hw),
        spectral_entropy(&hg),
        spectral_entropy(&costs),
        entropy_rate(&hw),
        holonomy_defect(p, stack),
        coeff(0),
        coeff(1),
        coeff(2),
        coeff(3),
    ]
}

// ---- small helpers ------------------------------------------------------

fn mean(xs: &[f64]) -> f64 {
    if xs.is_empty() {
        0.0
    } else {
        xs.iter().sum::<f64>() / xs.len() as f64
    }
}
fn sd(xs: &[f64]) -> f64 {
    if xs.is_empty() {
        return 0.0;
    }
    let m = mean(xs);
    (xs.iter().map(|&x| (x - m) * (x - m)).sum::<f64>() / xs.len() as f64).sqrt()
}
fn identity(n: usize) -> Vec<Vec<f64>> {
    (0..n)
        .map(|i| (0..n).map(|j| if i == j { 1.0 } else { 0.0 }).collect())
        .collect()
}
fn row_stochastic(plan: &[Vec<f64>]) -> Vec<Vec<f64>> {
    plan.iter()
        .map(|row| {
            let s: f64 = row.iter().sum();
            if s <= 0.0 {
                row.clone()
            } else {
                row.iter().map(|&x| x / s).collect()
            }
        })
        .collect()
}
fn mat_mul(a: &[Vec<f64>], b: &[Vec<f64>]) -> Vec<Vec<f64>> {
    let nk = b.len();
    let nj = if nk == 0 { 0 } else { b[0].len() };
    a.iter()
        .map(|arow| {
            (0..nj)
                .map(|j| (0..nk).map(|k| arow[k] * b[k][j]).sum())
                .collect()
        })
        .collect()
}
