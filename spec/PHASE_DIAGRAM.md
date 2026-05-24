# Trunk + Delta Phase Diagram

The hybrid GIF mode has one degree of freedom: the **trunk fraction**

  r := kT / K  with  kT + kD = K = 256.

`r ∈ [0, 1]` continuously interpolates between two existing SixFour modes:

* `r = 0` (kT=0, kD=256) ≡ the current `.perFrame` LCT mode.
* `r = 1` (kT=256, kD=0) ≡ the current `.global` GCT mode.

The hybrid is the *interior* of that interval. There is no universally
optimal `r`; the optimum depends on two scene-level scalars derived
from the input burst:

  α ∈ [0, 1]  the **temporal stability** = N_static / N_total
              (fraction of voxels whose source RGB varies by less than
              ε across all t frames)

  β ∈ [0, 1]  the **static-palette density** = C_static / K
              (fraction of slot budget the static voxels' distinct
              OKLab cluster count would consume)

These two axes carve the phase plane into four named regimes.

## ASCII phase diagram

```
                              β = C_static / 256
                              1 ┌──────────────────────────┐
                                │                          │
                                │      STONE               │
                                │      r* ≈ 0.85-0.95      │  (textured stills:
                                │      kT 220-244          │   rock, fabric,
                                │      kD  12-36           │   high-detail bg)
                              ¾ │                          │
                                │                          │
                                │      ────                │
                                │     /                    │
                                │   r*=0.75                │
                                │    (default              │
                              ½ │     today)               │
                                │                          │
                                │      FIRE                │
                                │      r* ≈ 0.30-0.50      │  (rich palette
                                │      kT  76-128          │   + heavy motion:
                                │      kD 128-180          │   degenerate;
                                │                          │   ≈ .perFrame)
                              ¼ │                          │
                                │  GLASS                   │
                                │  r* ≈ 0.85-0.95          │
                                │  kT 220-244              │  SMOKE
                                │  kD  12-36               │  r* ≈ 0.50-0.70
                                │  (clean bg,              │  kT 128-180
                                │   small accents)         │  kD  76-128
                              0 └──────────────────────────┘
                                0      ¼    ½    ¾        1   α = N_static / N_total
                              (action)                    (tripod)
```

## Marginal-benefit derivation of r*

Per-voxel distortion under a quantizer of size k against a colour
distribution with Zipf-like tail ξ scales as

  D_per_voxel(k) ∝ k^(−ξ).

For the cube, distortion decomposes:

  D_total = α · N_total · D_static(kT) + (1−α) · N_total · D_dynamic_per_frame(kD)
          ≈ α · N · kT^(−ξ_s) + (1−α) · N · kD^(−ξ_d)

The trunk covers α · N voxels with kT centroids; each delta covers
(1−α) · N / T voxels with kD centroids. Crucially the per-frame delta
is shared across T frames so its *information per slot* is T× higher
than a slot in the trunk would be, were the trunk asked to encode
dynamic content.

Setting ∂D/∂kT = ∂D/∂kD under the constraint kT + kD = K:

  α · ξ_s · kT^(−ξ_s−1)  =  ((1−α)/T) · ξ_d · kD^(−ξ_d−1)

For the symmetric case ξ_s = ξ_d = 1 (the natural-image Zipf
default), this collapses to

  **r* / (1 − r*)  =  (α · T / (1 − α))^(1/2)**

A clean closed form. T appears under the square root because the
delta's "leverage" is concentrated in one frame while the trunk's is
spread across all T — but only as √T because the marginal-benefit
slope is sub-linear in slot count.

### What r* looks like for T = 64

| α    | √(αT/(1−α)) | r*    | kT   | kD   | regime    |
| ---  | ---         | ----  | --   | --   | -------   |
| 0.95 | 34.87       | 0.972 | 249  |   7  | Stone-pure |
| 0.80 | 16.00       | 0.941 | 241  |  15  | Stone     |
| 0.50 |  8.00       | 0.889 | 228  |  28  | Stone/Glass |
| 0.20 |  4.00       | 0.800 | 205  |  51  | Glass     |
| 0.05 |  1.84       | 0.647 | 166  |  90  | Smoke     |
| 0.01 |  0.80       | 0.446 | 114  | 142  | Fire      |

**Observation.** Even at α = 0.05 (5 % of voxels static) the
optimum is r ≈ 0.65 — i.e. the trunk is still the bigger slice.
The √T factor with T = 64 means the trunk wins until α drops
below ~0.01. Below that — pure motion — the model collapses to
the `.perFrame` boundary.

## What β does

β shifts r* against the prediction above. When the static palette
needs more than kT slots to cover faithfully (β > kT/K = r), the
trunk *underflows* and its distortion spikes. The corrective term
makes r at least β:

  r_adjusted  =  max(r*, β · safety)

with `safety ≈ 1.1` to leave headroom. So β acts as a **floor**
on r — never push the trunk below the count of distinct static
colors plus 10 %.

In the phase plot:

  * **Glass**: α high, β low → r* dominates; thin trunk OK if
    background is one or two pastel surfaces, but the √T leverage
    still wants r ≈ 0.85. Default kT = 192 is *too low* for Glass.

  * **Stone**: α high, β high → both forces push the same way:
    big trunk (kT 220–244). Default kT = 192 is *near-correct*
    for Stone.

  * **Smoke**: α low, β low → r* = 0.5–0.7; kT 128–180. Default
    kT = 192 is *too high* for Smoke; trunk wastes slots on
    transient colours that disagree across frames.

  * **Fire**: α low, β high → degenerate; r* < 0.5 means a trunk
    is barely worth shipping. Fall back to `.perFrame` (which is
    what `r = 0` already provides).

## Phase boundaries

Three knees matter operationally:

1. **The Glass↔Stone knee** (β crosses ~ 0.5, α stays high).
   Below it, the trunk is over-provisioned and the codec wastes
   bytes; above it, the trunk is under-provisioned and `D` jumps
   sharply. The transition is *sharp* because each unused trunk
   slot is a constant 3-byte file cost AND a Sinkhorn rebalancing
   cost.

2. **The Stone↔Smoke knee** (α drops past ~ 0.5).
   Below it, the trunk is shared by fewer voxels, lowering its
   leverage; above it, the trunk amortises across most of the
   cube. The transition is *smooth* — D and F move continuously.

3. **The Smoke↔Fire knee** (β crosses ~ 0.8 with α low).
   At extreme color complexity AND low stability, the spec
   recommends falling all the way to `r = 0` (i.e. just emit
   `.perFrame`); the hybrid offers nothing the simpler mode does
   not, and the trunk-extraction Sinkhorn pass is wasted CPU.

## Recommended presets

For SixFour, ship three named presets in addition to the existing
`.global` and `.perFrame`:

| Preset name | (kT, kD) | r    | α target | β target | Use when                              |
| ----------- | -------- | ---- | -------- | -------- | ------------------------------------- |
| `.hybridGlass`  | (240,  16) | 0.94 | ≥ 0.7    | ≤ 0.4    | Tripod, clean backgrounds, small subject |
| `.hybridStone`  | (216,  40) | 0.84 | ≥ 0.5    | 0.4–0.8  | Tripod, textured backgrounds (current default territory; tighter than today's kT=192) |
| `.hybridSmoke`  | (160,  96) | 0.625| 0.1–0.5  | ≤ 0.6    | Hand-held, flowing motion (foliage, water, smoke) |

The previously-discussed default of `(kT=192, kD=64)` sits at
r = 0.75, *between* Stone and Smoke. That's a defensible "safe
middle" but the math says capture-aware preset selection beats
a one-size-fits-all default by 1–2 dB perceived distortion in
each named regime.

## Operationalising α and β

To pick a preset *adaptively* per burst, estimate (α, β) cheaply:

* **α** ≈ (number of voxels whose per-channel OKLab range across
  the 64 frames is below 0.02) / 262,144. Computable in a single
  Metal compute pass; ~ 1 ms on A19.

* **β** ≈ (number of distinct OKLab clusters at ΔE = 0.02 among
  the static voxels) / 256. Single-linkage in a per-burst Sinkhorn
  pre-pass; ~ 5 ms.

Then look up the matching preset in the table above. If α < 0.01
fall through to `.perFrame`; if β > 0.95 fall through to `.global`
(the trunk-only mode genuinely is optimal then).

## Open questions (next iteration)

1. The Zipf index ξ is treated as a per-pipeline constant. Is it
   actually shape-stable across natural-image bursts, or does it
   vary by lighting / subject in a way that nudges the curves?

2. The √T leverage factor assumes deltas are temporally
   *independent*. If consecutive deltas drift smoothly (which is
   what they should, on a real scene), the effective leverage may
   be smaller than √T because nearby deltas are correlated. Open
   measurement: estimate the inter-frame delta autocorrelation in
   real bursts and recompute r*.

3. STBN3D is only applied to trunk-routed voxels in the spec
   reference. If we extended it to *route* voxels stochastically
   (mask threshold decides trunk-vs-delta) we might recover a
   ~ 6 dB perceived noise reduction at the cost of softer
   boundaries. Open measurement: A/B vs deterministic margin.
