# FINDINGS — global-collapse task space (synthetic, pre-NN)

_Computed by `cargo run -p explore`. T=64 frames × K=256 colours ⇒ 16384 candidate colours; collapse → one global palette of 256. All distances in OKLab. This is a **measurement** pass — no NN, no design choices asserted ahead of the numbers._

## 1–2. Candidate geometry + collapse fidelity floor

| config | distinct | effDim | NN-space | fid k-means | fid median-cut |
|---|---:|---:|---:|---:|---:|
| baseline | 4913 | 1.78 | 0.0033 | 0.00020 | 0.00024 |
| spread=0.02 | 1732 | 1.80 | 0.0018 | 0.00010 | 0.00012 |
| spread=0.06 | 4913 | 1.78 | 0.0033 | 0.00020 | 0.00024 |
| spread=0.12 | 7895 | 1.75 | 0.0049 | 0.00033 | 0.00042 |
| spread=0.18 | 9204 | 1.73 | 0.0052 | 0.00045 | 0.00054 |
| clusters=4 | 4081 | 1.51 | 0.0031 | 0.00033 | 0.00017 |
| clusters=12 | 7047 | 1.90 | 0.0044 | 0.00061 | 0.00040 |
| clusters=32 | 9978 | 2.02 | 0.0060 | 0.00071 | 0.00064 |
| clusters=64 | 11197 | 1.92 | 0.0065 | 0.00087 | 0.00081 |
| gamut=0.4 | 5519 | 1.75 | 0.0037 | 0.00018 | 0.00023 |
| gamut=0.7 | 5189 | 1.80 | 0.0036 | 0.00021 | 0.00026 |
| gamut=1.0 | 4212 | 1.72 | 0.0029 | 0.00019 | 0.00022 |
| conc_skew=0.0 | 4913 | 1.78 | 0.0033 | 0.00021 | 0.00024 |
| conc_skew=1.0 | 4913 | 1.78 | 0.0033 | 0.00020 | 0.00024 |
| conc_skew=3.0 | 4913 | 1.76 | 0.0033 | 0.00019 | 0.00021 |

Fidelity floor (k-means) spans **0.00010 … 0.00087** OKLab²; effective colour dimensionality **1.51 … 2.02** (of 3).

## 3. Does the index/population info help the collapse?

| config | fid weighted | fid unweighted | Δ% (weighted better) |
|---|---:|---:|---:|
| baseline | 0.00020 | 0.00021 | +5.2% |
| spread=0.02 | 0.00010 | 0.00010 | +0.2% |
| spread=0.06 | 0.00020 | 0.00021 | +5.2% |
| spread=0.12 | 0.00033 | 0.00037 | +10.6% |
| spread=0.18 | 0.00045 | 0.00053 | +15.8% |
| clusters=4 | 0.00033 | 0.00034 | +2.8% |
| clusters=12 | 0.00061 | 0.00068 | +10.5% |
| clusters=32 | 0.00071 | 0.00076 | +6.9% |
| clusters=64 | 0.00087 | 0.00099 | +12.1% |
| gamut=0.4 | 0.00018 | 0.00019 | +6.2% |
| gamut=0.7 | 0.00021 | 0.00022 | +2.2% |
| gamut=1.0 | 0.00019 | 0.00020 | +3.3% |
| conc_skew=0.0 | 0.00021 | 0.00021 | +1.0% |
| conc_skew=1.0 | 0.00020 | 0.00021 | +5.2% |
| conc_skew=3.0 | 0.00019 | 0.00021 | +11.9% |

Mean improvement from population weighting: **+6.6%** — **measurably helps** → the NN should ingest per-colour populations (the index map), not palettes alone.

## 4. §8 descriptor distribution over the ensemble (16-D)

| # | component | mean | sd |
|---:|---|---:|---:|
| 0 | mean H(P_t) | 4.6859 | 0.2405 |
| 1 | sd H(P_t) | 0.0000 | 0.0000 |
| 2 | mean H_g | -3.5694 | 0.5826 |
| 3 | sd H_g | 0.4584 | 0.1411 |
| 4 | total transport | 2.5840 | 0.4461 |
| 5 | mean transport | 0.0404 | 0.0070 |
| 6 | mean H(Γ) | 9.2513 | 0.4822 |
| 7 | specEnt H(P_t) | 0.0000 | 0.0000 |
| 8 | specEnt H_g | 1.1613 | 0.1848 |
| 9 | specEnt cost | 0.9402 | 0.1581 |
| 10 | entropyRate | 0.0000 | 0.0000 |
| 11 | holonomyDefect | 0.9961 | 0.0000 |
| 12 | acPow k=1 | 0.0000 | 0.0000 |
| 13 | acPow k=2 | 0.0000 | 0.0000 |
| 14 | acPow k=3 | 0.0000 | 0.0000 |
| 15 | acPow k=4 | 0.0000 | 0.0000 |

Descriptor spans ~**3.8** effective axes (participation ratio of component variances). Most-varying components across the sweep: **sd H_g**, **total transport**, **mean transport**.

## Implications for `look-nn` design

- **Fidelity floor is non-zero** (0.0001–0.0009 OKLab²): a single 256-palette cannot perfectly reproduce 64 per-frame palettes. The learned look must operate *near* this floor — its 'signature' is a controlled deviation from it, not arbitrary.
- **Colour spread is ~1.5–2.0-D**: the global palette decoder must cover a (near-)volumetric region, not a 1-D ramp — argues for a decoder that emits full 3-D OKLab points, not a 1-D curve.
- **Population/index value = +6.6%**: **measurably helps** → the NN should ingest per-colour populations (the index map), not palettes alone — directly answers the 'two inputs (palettes + index map)' question with a measured number.
- **NN input features**: the high-variance descriptor components (sd H_g, total transport) carry the most signal distinguishing GIFs; the descriptor's ~4 effective axes suggest a compact conditioning vector is enough.
- **Baseline to beat**: weighted k-means is the fidelity floor; the look-nn is justified only where a *learned, personal* deviation is worth its fidelity cost.

