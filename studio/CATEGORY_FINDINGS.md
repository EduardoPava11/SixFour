# CATEGORY_FINDINGS — Berlin–Kay structure of the palette (synthetic, pre-NN)

_Computed by `cargo run -p category-explore`. Categories = the 11 Berlin–Kay basic terms, foci from Sturges & Whitfield (1995) resolved against the 330 World Color Survey chips (CIE Lab→OKLab, Illuminant C→D65). T=64 × K=256, 16384 candidate colours per scene; 80 scenes (10 configs × 8 seeds). A category 'fires' above 1% population. **Measurement only — the look-NN's form is not yet frozen.**_

## 1. The MEASURED complement map (pairs chosen by the L > a > b hierarchy)

Reflect each focus through the neutral axis `(L,a,b)→(L,−a,−b)`, then match the result to a category under the **LAB importance hierarchy L > a > b** (weights [4.0, 2.0, 1.0] — lightness dominates the pairing, then red–green, then yellow–blue; user decision). So a light colour pairs with a light one *by design* — the earlier 'yellow→white' is intended behaviour, not a bug.

| term | complement (measured) | distinct opponent? |
|---|---|:--:|
| red | blue | yes |
| orange | green | yes |
| yellow | white | yes |
| green | pink | yes |
| blue | red | yes |
| purple | blue | yes |
| pink | green | yes |
| brown | brown | — (self) |
| black | black | — (self) |
| white | white | — (self) |
| gray | gray | — (self) |

7/11 terms get a distinct opponent under the hierarchy; the map is NOT an involution. Lightness-dominance is the **intended** rule (light pairs with light), so *this* map — not the artist's hue-wheel — defines the pairs; the 4 neutral terms are self-complementary.

## 2. Category occupancy of uncontrolled scenes

| config | mean complexity | complement availability | modal category |
|---|---:|---:|---|
| baseline | 7.9 | 0.81 | green |
| clusters=4 | 6.8 | 0.78 | gray |
| clusters=12 | 9.4 | 0.95 | green |
| clusters=32 | 9.9 | 0.91 | green |
| clusters=64 | 10.1 | 0.93 | green |
| gamut=0.4 | 7.2 | 0.79 | gray |
| gamut=0.7 | 7.8 | 0.82 | gray |
| gamut=1.0 | 8.0 | 0.79 | green |
| spread=0.02 | 7.8 | 0.82 | green |
| spread=0.12 | 8.0 | 0.85 | green |

## 3. Scene-complexity histogram (sets the ponder-budget range)

| categories firing | scenes |
|---:|---:|
| 6 | 4 |
| 7 | 20 |
| 8 | 27 |
| 9 | 11 |
| 10 | 15 |
| 11 | 3 |

Scene complexity spans **6–11** categories (mean 8.3). This variance is the argument for adaptive compute: a fixed-depth net is wasteful at 6 and starved at 11.

## 4. Per-category occupancy frequency + effective dimensionality

| category | fires in % of scenes | mean effective dim (when present) |
|---|---:|---:|
| red | 91% | 1.77 |
| orange | 81% | 1.61 |
| yellow | 64% | 1.68 |
| green | 100% | 2.14 |
| blue | 80% | 1.58 |
| purple | 91% | 2.04 |
| pink | 81% | 1.81 |
| brown | 89% | 1.61 |
| black | 35% | 2.11 |
| white | 15% | 1.96 |
| gray | 100% | 2.21 |

## 5. Controlled complexity ramp (metric validation)

| categories seeded | complexity measured |
|---:|---:|
| 1 | 1 |
| 2 | 2 |
| 3 | 3 |
| 4 | 4 |
| 5 | 5 |
| 6 | 6 |
| 7 | 7 |
| 8 | 8 |
| 9 | 9 |
| 10 | 10 |
| 11 | 11 |

Seeded vs measured complexity match exactly — the occupancy metric tracks known category content.

## Implications for the look-NN

- **Pairing rule = L>a>b reflection**: partner = reflect anchor through neutral, match under the lightness-dominant hierarchy [4.0, 2.0, 1.0]. 7/11 terms get a distinct opponent (map NOT an involution); the symmetric-pair decoder builds on THIS, not the hue-wheel.
- **Token vocabulary**: of 11 categories, the ones that fire in >25% of scenes are the load-bearing tokens; rarely-firing categories may be merged — the table above dictates N, not a guess.
- **Ponder budget**: scene complexity 6–11 (mean 8.3) → the adaptive-compute depth should range roughly over this span; a fixed depth can't be efficient across it.
- **Complement availability ≈ 0.84**: opponent pairs are usually naturally present, so the symmetric-pair decoder mostly selects existing pairs.

