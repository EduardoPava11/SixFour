# FINDINGS — global-collapse task space (synthetic, pre-NN)

_Computed by `cargo run -p explore`. T=64 frames × K=256 colours ⇒ 16384 candidate colours; collapse → one global palette of 256. All distances in OKLab. This is a **measurement** pass — no NN, no design choices asserted ahead of the numbers._

## 1–2. Candidate geometry + collapse fidelity floor

| config | distinct | effDim | NN-space | fid k-means | fid median-cut |
|---|---:|---:|---:|---:|---:|
| baseline | 4913 | 1.81 | 0.0033 | 0.00017 | 0.00022 |
| spread=0.02 | 1732 | 1.83 | 0.0018 | 0.00008 | 0.00010 |
| spread=0.06 | 4913 | 1.81 | 0.0033 | 0.00017 | 0.00022 |
| spread=0.12 | 7895 | 1.79 | 0.0049 | 0.00030 | 0.00039 |
| spread=0.18 | 9204 | 1.78 | 0.0052 | 0.00043 | 0.00053 |
| clusters=4 | 4081 | 1.49 | 0.0031 | 0.00032 | 0.00017 |
| clusters=12 | 7047 | 1.99 | 0.0044 | 0.00054 | 0.00043 |
| clusters=32 | 9978 | 2.04 | 0.0060 | 0.00070 | 0.00063 |
| clusters=64 | 11197 | 1.97 | 0.0065 | 0.00087 | 0.00075 |
| gamut=0.4 | 5519 | 1.76 | 0.0037 | 0.00015 | 0.00022 |
| gamut=0.7 | 5189 | 1.83 | 0.0036 | 0.00017 | 0.00021 |
| gamut=1.0 | 4212 | 1.75 | 0.0029 | 0.00015 | 0.00020 |
| conc_skew=0.0 | 4913 | 1.80 | 0.0033 | 0.00020 | 0.00022 |
| conc_skew=1.0 | 4913 | 1.81 | 0.0033 | 0.00017 | 0.00022 |
| conc_skew=3.0 | 4913 | 1.79 | 0.0033 | 0.00014 | 0.00019 |
| pop_drift=0.0 | 4913 | 1.80 | 0.0033 | 0.00017 | 0.00021 |
| pop_drift=0.5 | 4913 | 1.81 | 0.0033 | 0.00017 | 0.00022 |
| pop_drift=1.0 | 4913 | 1.82 | 0.0033 | 0.00016 | 0.00020 |

Fidelity floor (k-means) spans **0.00008 … 0.00087** OKLab²; effective colour dimensionality **1.49 … 2.04** (of 3).

## 3. Does the index/population info help the collapse?

| config | fid weighted | fid unweighted | Δ% (weighted better) |
|---|---:|---:|---:|
| baseline | 0.00017 | 0.00018 | +9.4% |
| spread=0.02 | 0.00008 | 0.00008 | +0.8% |
| spread=0.06 | 0.00017 | 0.00018 | +9.4% |
| spread=0.12 | 0.00030 | 0.00033 | +11.5% |
| spread=0.18 | 0.00043 | 0.00048 | +8.9% |
| clusters=4 | 0.00032 | 0.00032 | -0.0% |
| clusters=12 | 0.00054 | 0.00063 | +13.9% |
| clusters=32 | 0.00070 | 0.00076 | +8.0% |
| clusters=64 | 0.00087 | 0.00094 | +8.2% |
| gamut=0.4 | 0.00015 | 0.00017 | +9.9% |
| gamut=0.7 | 0.00017 | 0.00019 | +8.0% |
| gamut=1.0 | 0.00015 | 0.00016 | +8.7% |
| conc_skew=0.0 | 0.00020 | 0.00020 | +1.1% |
| conc_skew=1.0 | 0.00017 | 0.00018 | +9.4% |
| conc_skew=3.0 | 0.00014 | 0.00017 | +17.9% |
| pop_drift=0.0 | 0.00017 | 0.00018 | +5.8% |
| pop_drift=0.5 | 0.00017 | 0.00018 | +9.4% |
| pop_drift=1.0 | 0.00016 | 0.00018 | +10.3% |

Mean improvement from population weighting: **+8.4%** — **measurably helps** → the NN should ingest per-colour populations (the index map), not palettes alone.

## 4. §8 descriptor distribution over the ensemble (16-D)

| # | component | mean | sd |
|---:|---|---:|---:|
| 0 | mean H(P_t) | 4.5693 | 0.2352 |
| 1 | sd H(P_t) | 0.0150 | 0.0078 |
| 2 | mean H_g | -3.6772 | 0.5770 |
| 3 | sd H_g | 0.4990 | 0.1649 |
| 4 | total transport | 2.5623 | 0.4339 |
| 5 | mean transport | 0.0400 | 0.0068 |
| 6 | mean H(Γ) | 9.0140 | 0.4710 |
| 7 | specEnt H(P_t) | 0.8295 | 0.2515 |
| 8 | specEnt H_g | 1.1988 | 0.1354 |
| 9 | specEnt cost | 1.0181 | 0.1988 |
| 10 | entropyRate | -9.6759 | 2.7383 |
| 11 | holonomyDefect | 0.9961 | 0.0000 |
| 12 | acPow k=1 | 0.4328 | 0.1374 |
| 13 | acPow k=2 | 0.0379 | 0.0869 |
| 14 | acPow k=3 | 0.0012 | 0.0028 |
| 15 | acPow k=4 | 0.0002 | 0.0009 |

Scale-invariant effective dimensionality (participation ratio of the 15-component correlation eigenvalues): ~**5.1** axes (top eigenvalues 4.24, 3.52, 2.59). Degenerate components (no variation across the sweep): **holonomyDefect**.

## 5. Holonomy defect vs OT regularisation ε (baseline)

| ε | holonomy defect (K−tr M)/K |
|---:|---:|
| 0.02 | 0.9961 |
| 0.05 | 0.9961 |
| 0.10 | 0.9961 |

The loop-closure measure only becomes informative as ε shrinks (sharper transport); at the descriptor's default ε the plans are too diffuse, so holonomy pins near 1. Pick the descriptor ε from this curve, not by default.

## Implications for `look-nn` design

- **Fidelity floor is non-zero** (0.0001–0.0009 OKLab²): a single 256-palette cannot perfectly reproduce 64 per-frame palettes. The learned look must operate *near* this floor — its 'signature' is a controlled deviation from it, not arbitrary.
- **Colour spread is ~1.5–2.0-D**: the global palette decoder must cover a (near-)volumetric region, not a 1-D ramp — argues for a decoder that emits full 3-D OKLab points, not a 1-D curve.
- **Population/index value = +8.4%**: **measurably helps** → the NN should ingest per-colour populations (the index map), not palettes alone — directly answers the 'two inputs (palettes + index map)' question with a measured number.
- **NN conditioning vector**: the 16-D descriptor has only ~**5** independent axes (correlation-eigenvalue participation ratio), and `holonomyDefect` saturates (≈0.996 for any ε at T=64) — so condition on a compact vector and drop/replace the holonomy feature.
- **Baseline to beat**: weighted k-means is the fidelity floor; the look-nn is justified only where a *learned, personal* deviation is worth its fidelity cost.

