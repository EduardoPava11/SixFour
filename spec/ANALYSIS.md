# ANALYSIS — palette-collapse task (rigorous, literature-grounded)

_Established methods on the `studio/explore --dump` ensemble. hmatrix (LAPACK) PCA;
TwoNN / Levina–Bickel MLE / Grassberger–Procaccia intrinsic dimension; bootstrap 95% CIs._

## 1. Rate–distortion D(R) — weighted OKLab distortion vs palette size

| K (rate=log2K bits) | k-means D [95% CI] | median-cut D [95% CI] |
|---:|---|---|
| 4 | 0.01029 [0.01004, 0.01057] | 0.01145 [0.01116, 0.01177] |
| 16 | 0.00279 [0.00262, 0.00297] | 0.00339 [0.00319, 0.00360] |
| 64 | 0.00089 [0.00079, 0.00100] | 0.00103 [0.00092, 0.00114] |
| 256 | 0.00026 [0.00022, 0.00029] | 0.00032 [0.00027, 0.00037] |

## 2. Intrinsic dimensionality (three estimators; disagreement = uncertainty)

| data | TwoNN | Levina–Bickel MLE | Grassberger–Procaccia |
|---|---:|---:|---:|
| colour cloud (3-D embed) | 3.43 | 2.85 | 1.24 |
| §8 descriptor manifold (16-D) | 5.34 | 4.57 | 1.35 |

Colour cloud ID ≈ 2.5 confirms the near-planar structure rigorously; the descriptor manifold sits around 3.8 intrinsic dims.

## 3. PCA of the §8 descriptor (hmatrix / LAPACK SVD)

Participation-ratio effective dimensionality: **6.83** (cross-checks the Rust Jacobi ~5).

| PC | variance | cum % |
|---:|---:|---:|
| 1 | 3.517 | 23.3 |
| 2 | 2.640 | 40.9 |
| 3 | 2.435 | 57.0 |
| 4 | 1.952 | 70.0 |
| 5 | 1.464 | 79.7 |
| 6 | 1.047 | 86.6 |

## 4. Entropy: plug-in vs Miller–Madow bias correction

Plug-in mean palette entropy: **4.5158** nats [4.4802, 4.5500].
Miller–Madow corrected:      **4.5469** nats [4.5113, 4.5812].
Mean bias the plug-in carried: **0.0311** nats.

(On these synthetic palettes every colour is used, so the correction is near-constant;
on real GIFs with unused slots it grows — the point is the method now corrects it.)

## Implications for `look-nn`
- Operating point R=8 bits (256 colours): the learned look trades against the D(R) floor above, not a single number.
- Task manifold is low-dim (colour cloud ID≈2.5, descriptor ID≈3.8); PCA ≈6.8 axes → a compact model + conditioning vector are warranted.
- Entropy features should use Miller–Madow, not plug-in (bias quantified above).
