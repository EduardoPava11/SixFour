//! Classical global-palette collapse — the *fidelity floor* the learned "look"
//! model will be measured against (NOT a shipped choice). Population-weighted
//! k-means and median-cut over the ≤T·K candidate colours, plus the weighted
//! reconstruction-error metric and a test of whether population info helps.

use crate::color::{dist_sq, Oklab};
use crate::cyclic::CyclicStack;

/// Every per-frame palette colour with its population: the ≤T·K candidates.
pub fn candidates(stack: &CyclicStack) -> Vec<(Oklab, f64)> {
    let mut v = Vec::with_capacity(stack.frames.len() * stack.frames.first().map_or(0, |f| f.palette.len()));
    for f in &stack.frames {
        for (c, w) in f.palette.iter().zip(&f.weights) {
            v.push((*c, *w));
        }
    }
    v
}

fn nearest_sq(c: Oklab, g: &[Oklab]) -> f64 {
    let mut bd = f64::INFINITY;
    for &gj in g {
        let d = dist_sq(c, gj);
        if d < bd {
            bd = d;
        }
    }
    bd
}

/// Population-weighted reconstruction error of a global palette `g`:
/// `Σ w·min_j ‖c − g_j‖² / Σ w` (OKLab). Lower = more faithful collapse.
pub fn fidelity(g: &[Oklab], cands: &[(Oklab, f64)]) -> f64 {
    let mut num = 0.0;
    let mut den = 0.0;
    for &(c, w) in cands {
        num += w * nearest_sq(c, g);
        den += w;
    }
    if den > 0.0 {
        num / den
    } else {
        0.0
    }
}

/// Population-weighted Lloyd k-means → `k` global centroids.
pub fn weighted_kmeans(cands: &[(Oklab, f64)], k: usize, iters: usize, seed: u64) -> Vec<Oklab> {
    let n = cands.len();
    if n == 0 || k == 0 {
        return vec![];
    }
    let stride = (n / k).max(1);
    let off = (seed as usize) % stride;
    let mut cents: Vec<Oklab> = (0..k).map(|i| cands[((i * stride) + off) % n].0).collect();
    for _ in 0..iters {
        let mut acc = vec![[0.0f64; 3]; k];
        let mut wsum = vec![0.0f64; k];
        for &(c, w) in cands {
            let mut best = 0;
            let mut bd = f64::INFINITY;
            for (j, &cj) in cents.iter().enumerate() {
                let d = dist_sq(c, cj);
                if d < bd {
                    bd = d;
                    best = j;
                }
            }
            for ch in 0..3 {
                acc[best][ch] += w * c[ch];
            }
            wsum[best] += w;
        }
        for j in 0..k {
            if wsum[j] > 0.0 {
                for ch in 0..3 {
                    cents[j][ch] = acc[j][ch] / wsum[j];
                }
            }
        }
    }
    cents
}

/// Population-weighted median-cut → up to `k` centroids.
pub fn median_cut(cands: &[(Oklab, f64)], k: usize) -> Vec<Oklab> {
    if cands.is_empty() || k == 0 {
        return vec![];
    }
    let mut boxes: Vec<Vec<usize>> = vec![(0..cands.len()).collect()];
    while boxes.len() < k {
        let (mut bi, mut bext, mut baxis) = (0usize, -1.0f64, 0usize);
        for (i, b) in boxes.iter().enumerate() {
            if b.len() < 2 {
                continue;
            }
            for ax in 0..3 {
                let (mn, mx) = b.iter().fold((f64::INFINITY, f64::NEG_INFINITY), |(mn, mx), &idx| {
                    let v = cands[idx].0[ax];
                    (mn.min(v), mx.max(v))
                });
                if mx - mn > bext {
                    bext = mx - mn;
                    bi = i;
                    baxis = ax;
                }
            }
        }
        if bext <= 0.0 {
            break;
        }
        let mut b = boxes.swap_remove(bi);
        b.sort_by(|&a, &c| cands[a].0[baxis].partial_cmp(&cands[c].0[baxis]).unwrap());
        let total: f64 = b.iter().map(|&i| cands[i].1).sum();
        let mut cum = 0.0;
        let mut split = b.len() / 2;
        for (pos, &i) in b.iter().enumerate() {
            cum += cands[i].1;
            if cum >= total / 2.0 {
                split = pos.max(1).min(b.len() - 1);
                break;
            }
        }
        let right = b.split_off(split);
        boxes.push(b);
        boxes.push(right);
    }
    boxes
        .iter()
        .map(|b| {
            let mut acc = [0.0; 3];
            let mut w = 0.0;
            for &i in b {
                let (c, wi) = cands[i];
                for ch in 0..3 {
                    acc[ch] += wi * c[ch];
                }
                w += wi;
            }
            if w > 0.0 {
                [acc[0] / w, acc[1] / w, acc[2] / w]
            } else {
                [0.0; 3]
            }
        })
        .collect()
}

/// Does the index/population information help choose the global palette?
/// Returns (fidelity_with_populations, fidelity_ignoring_populations), both
/// evaluated against the TRUE population-weighted error. If the first is lower,
/// the index mapping is worth feeding the NN.
pub fn population_value(cands: &[(Oklab, f64)], k: usize, iters: usize, seed: u64) -> (f64, f64) {
    let g_weighted = weighted_kmeans(cands, k, iters, seed);
    let unit: Vec<(Oklab, f64)> = cands.iter().map(|&(c, _)| (c, 1.0)).collect();
    let g_unit = weighted_kmeans(&unit, k, iters, seed);
    (fidelity(&g_weighted, cands), fidelity(&g_unit, cands))
}
