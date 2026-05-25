//! explore — PRELIMINARY measurement study of the global-collapse task, BEFORE
//! any NN design. Sweeps controllable synthetic 64³ GIFs and computes:
//!   1. candidate-colour geometry (distinct count, effective dim, NN spacing)
//!   2. collapse fidelity floor (weighted k-means + median-cut)
//!   3. value of index/population info (weighted vs unweighted collapse)
//!   4. §8 descriptor distribution over the ensemble
//! Writes studio/FINDINGS.md. Run with `--release` (the §8 holonomy is heavy).

use analysis_core::synth::{synth_stack, SynthParams};
use analysis_core::{collapse, descriptor, geometry, Params, DESCRIPTOR_DIM};
use std::fmt::Write as _;

const T: usize = 64;
const K: usize = 256;
const KG: usize = 256; // global palette size
const KM_ITERS: usize = 12;

const DESC_NAMES: [&str; DESCRIPTOR_DIM] = [
    "mean H(P_t)", "sd H(P_t)", "mean H_g", "sd H_g",
    "total transport", "mean transport", "mean H(Γ)",
    "specEnt H(P_t)", "specEnt H_g", "specEnt cost",
    "entropyRate", "holonomyDefect",
    "acPow k=1", "acPow k=2", "acPow k=3", "acPow k=4",
];

struct Row {
    label: String,
    distinct: usize,
    eff_dim: f64,
    nn: f64,
    fid_km: f64,
    fid_mc: f64,
    fid_w: f64,
    fid_u: f64,
}

fn measure(label: &str, p: &SynthParams) -> (Row, Vec<f64>) {
    eprintln!("  {label} ...");
    let s = synth_stack(p, T, K);
    let c = collapse::candidates(&s);
    let g_km = collapse::weighted_kmeans(&c, KG, KM_ITERS, 1);
    let g_mc = collapse::median_cut(&c, KG);
    let (fid_w, fid_u) = collapse::population_value(&c, KG, KM_ITERS, 1);
    let d = descriptor(Params::default(), &s);
    (
        Row {
            label: label.to_string(),
            distinct: geometry::distinct_count(&c, 0.01),
            eff_dim: geometry::effective_dim(geometry::color_pca(&c)),
            nn: geometry::mean_nn_spacing(&c, 200, 1),
            fid_km: collapse::fidelity(&g_km, &c),
            fid_mc: collapse::fidelity(&g_mc, &c),
            fid_w,
            fid_u,
        },
        d,
    )
}

fn main() {
    let base = SynthParams::default();
    let mut configs: Vec<(String, SynthParams)> = vec![("baseline".into(), base)];
    for sp in [0.02, 0.06, 0.12, 0.18] {
        configs.push((format!("spread={sp:.2}"), SynthParams { spread: sp, ..base }));
    }
    for nc in [4usize, 12, 32, 64] {
        configs.push((format!("clusters={nc}"), SynthParams { n_clusters: nc, ..base }));
    }
    for g in [0.4, 0.7, 1.0] {
        configs.push((format!("gamut={g:.1}"), SynthParams { gamut: g, ..base }));
    }
    for cs in [0.0, 1.0, 3.0] {
        configs.push((format!("conc_skew={cs:.1}"), SynthParams { conc_skew: cs, ..base }));
    }

    eprintln!("running {} configs (T={T}, K={K}, collapse→{KG})", configs.len());
    let mut rows = Vec::new();
    let mut descs = Vec::new();
    for (label, p) in &configs {
        let (r, d) = measure(label, p);
        rows.push(r);
        descs.push(d);
    }

    // descriptor distribution
    let n = descs.len() as f64;
    let mut mean = vec![0.0; DESCRIPTOR_DIM];
    for d in &descs {
        for i in 0..DESCRIPTOR_DIM {
            mean[i] += d[i];
        }
    }
    mean.iter_mut().for_each(|m| *m /= n);
    let mut var = vec![0.0; DESCRIPTOR_DIM];
    for d in &descs {
        for i in 0..DESCRIPTOR_DIM {
            var[i] += (d[i] - mean[i]).powi(2);
        }
    }
    var.iter_mut().for_each(|v| *v /= n);
    let sd: Vec<f64> = var.iter().map(|v| v.sqrt()).collect();
    let sv: f64 = var.iter().sum();
    let sv2: f64 = var.iter().map(|x| x * x).sum();
    let desc_eff_dim = if sv2 > 0.0 { sv * sv / sv2 } else { 0.0 };
    // top-3 most-varying components (by sd, scaled by |mean| to compare across scales)
    let mut ranked: Vec<usize> = (0..DESCRIPTOR_DIM).collect();
    ranked.sort_by(|&a, &b| {
        let ra = sd[a] / (mean[a].abs() + 1e-9);
        let rb = sd[b] / (mean[b].abs() + 1e-9);
        rb.partial_cmp(&ra).unwrap()
    });

    // summaries
    let mean_impr = rows
        .iter()
        .filter(|r| r.fid_u > 0.0)
        .map(|r| (r.fid_u - r.fid_w) / r.fid_u)
        .sum::<f64>()
        / rows.len() as f64
        * 100.0;
    let fmin = rows.iter().map(|r| r.fid_km).fold(f64::INFINITY, f64::min);
    let fmax = rows.iter().map(|r| r.fid_km).fold(f64::NEG_INFINITY, f64::max);
    let edmin = rows.iter().map(|r| r.eff_dim).fold(f64::INFINITY, f64::min);
    let edmax = rows.iter().map(|r| r.eff_dim).fold(f64::NEG_INFINITY, f64::max);

    // ---- FINDINGS.md ----
    let mut s = String::new();
    let _ = writeln!(s, "# FINDINGS — global-collapse task space (synthetic, pre-NN)\n");
    let _ = writeln!(
        s,
        "_Computed by `cargo run -p explore`. T={T} frames × K={K} colours ⇒ {} candidate colours; \
         collapse → one global palette of {KG}. All distances in OKLab. This is a **measurement** \
         pass — no NN, no design choices asserted ahead of the numbers._\n",
        T * K
    );

    let _ = writeln!(s, "## 1–2. Candidate geometry + collapse fidelity floor\n");
    let _ = writeln!(s, "| config | distinct | effDim | NN-space | fid k-means | fid median-cut |");
    let _ = writeln!(s, "|---|---:|---:|---:|---:|---:|");
    for r in &rows {
        let _ = writeln!(
            s,
            "| {} | {} | {:.2} | {:.4} | {:.5} | {:.5} |",
            r.label, r.distinct, r.eff_dim, r.nn, r.fid_km, r.fid_mc
        );
    }
    let _ = writeln!(
        s,
        "\nFidelity floor (k-means) spans **{fmin:.5} … {fmax:.5}** OKLab²; effective colour \
         dimensionality **{edmin:.2} … {edmax:.2}** (of 3).\n"
    );

    let _ = writeln!(s, "## 3. Does the index/population info help the collapse?\n");
    let _ = writeln!(s, "| config | fid weighted | fid unweighted | Δ% (weighted better) |");
    let _ = writeln!(s, "|---|---:|---:|---:|");
    for r in &rows {
        let d = if r.fid_u > 0.0 { (r.fid_u - r.fid_w) / r.fid_u * 100.0 } else { 0.0 };
        let _ = writeln!(s, "| {} | {:.5} | {:.5} | {:+.1}% |", r.label, r.fid_w, r.fid_u, d);
    }
    let verdict = if mean_impr > 5.0 {
        "**measurably helps** → the NN should ingest per-colour populations (the index map), not palettes alone"
    } else if mean_impr > 1.0 {
        "**helps modestly** → worth including populations as an auxiliary input"
    } else {
        "**negligible** → palette-only input may suffice (re-check on richer data)"
    };
    let _ = writeln!(s, "\nMean improvement from population weighting: **{mean_impr:+.1}%** — {verdict}.\n");

    let _ = writeln!(s, "## 4. §8 descriptor distribution over the ensemble (16-D)\n");
    let _ = writeln!(s, "| # | component | mean | sd |");
    let _ = writeln!(s, "|---:|---|---:|---:|");
    for i in 0..DESCRIPTOR_DIM {
        let _ = writeln!(s, "| {} | {} | {:.4} | {:.4} |", i, DESC_NAMES[i], mean[i], sd[i]);
    }
    let _ = writeln!(
        s,
        "\nDescriptor spans ~**{desc_eff_dim:.1}** effective axes (participation ratio of component \
         variances). Most-varying components across the sweep: **{}**, **{}**, **{}**.\n",
        DESC_NAMES[ranked[0]], DESC_NAMES[ranked[1]], DESC_NAMES[ranked[2]]
    );

    let _ = writeln!(s, "## Implications for `look-nn` design\n");
    let _ = writeln!(s, "- **Fidelity floor is non-zero** ({fmin:.4}–{fmax:.4} OKLab²): a single 256-palette cannot perfectly reproduce 64 per-frame palettes. The learned look must operate *near* this floor — its 'signature' is a controlled deviation from it, not arbitrary.");
    let _ = writeln!(s, "- **Colour spread is ~{edmin:.1}–{edmax:.1}-D**: the global palette decoder must cover a (near-)volumetric region, not a 1-D ramp — argues for a decoder that emits full 3-D OKLab points, not a 1-D curve.");
    let _ = writeln!(s, "- **Population/index value = {mean_impr:+.1}%**: {verdict} — directly answers the 'two inputs (palettes + index map)' question with a measured number.");
    let _ = writeln!(s, "- **NN input features**: the high-variance descriptor components ({}, {}) carry the most signal distinguishing GIFs; the descriptor's ~{desc_eff_dim:.0} effective axes suggest a compact conditioning vector is enough.", DESC_NAMES[ranked[0]], DESC_NAMES[ranked[1]]);
    let _ = writeln!(s, "- **Baseline to beat**: weighted k-means is the fidelity floor; the look-nn is justified only where a *learned, personal* deviation is worth its fidelity cost.\n");

    std::fs::write("FINDINGS.md", &s).expect("write FINDINGS.md");
    eprintln!("wrote FINDINGS.md ({} configs)", rows.len());
}
