# SixFour V2 ↔ Tier-0 Synthesis: The Spec Is Already the Instance, V2's Value Is the Part No Class Can Hold

## Lead finding

The production spec is **already a fully-realized discrete-geometry + ANT object**: every V2 typeclass it could instantiate (`CommutativeRing`, `RModule`, `ReversibleLift`, `Group`, `GaugeAction`) is **already saturated by a live instance** that carries the shipped behavior. Four of the five V2 fits therefore land as DUPLICATE or PARALLEL-ANALOGY: instantiating the class a second time proves nothing the existing instance did not already prove. The one genuine exception is **Eisenstein ℤ[ω]**, and even there the *ring* instance is a redundant sibling of `Gaussian`. V2's real, irreducible content is precisely the layer **no production typeclass can express**: ideal theory (the ramified prime (1−ω), F₃ reduction, the /3 byte-exact guard). That content is a **competing C₃-mod-(1−ω) byte-exactness mechanism that contradicts the live C₄ = ℤ[i]\* determinism floor**, so it must stay behind the `XYTLabDuality`/φ6 gate. Net: the cleanest thing to land buys a generalization datapoint, not a capability; the valuable thing to land is a contract change, not an additive instance.

---

## 1. The model as discrete geometry + ANT

| Typeclass | Algebraic / geometric structure | Live production instance(s) |
|---|---|---|
| `CommutativeRing r` | Ring of coefficients; unit group = exact symmetry group; norm lives *outside* the class | `Gaussian` = ℤ[i] (`GaussianChroma`): `rmul i` = exact 90° hue turn, units {1,i,−1,−i} = C₄ |
| `RModule r m` (needs `CommutativeRing r`) | Coefficient algebra of detail/colour deltas; a **module not a vector space** because byte-exactness forbids dividing by non-units of ℤ | `Triple r` (free, `RefinementSystem`); `GColourDelta` (luma ℤ + chroma ℤ[i]); detail bands of `RootLatticeDetail` |
| `ReversibleLift f` | Per-node multiresolution bijection: b-vector → (1 coarse, b−1 detail), `unliftF . liftF = id`. The structural edge of the octree | `Dyad8` (b=8 default prefix-diff), `Tern3` (b=3, off powers of two), `OctLeaf8` = **overrides `liftF` = `OctreeCell.liftOct`**, the shipped 3-D separable Haar lift |
| `Group g` | Minimal group above base `Monoid`; `gcompose`/`ginvert` | `Perm` (S_K finitely-supported), `Z2` (φ6 / swapAB involution) |
| `GaugeAction g x` | Finite group acting on configs; observable = **orbit invariant** X/G (`gobserve (gact g x) == gobserve x`) | `GaugeAction Perm PaletteConfig` (palette gauge S_256, Obs = rendered pixels, non-abelian); `GaugeAction Z2 ChannelPair` (Obs = unordered pair) |
| `FinitePerm p` | Bijections on [0..n−1] under composition; assoc + inverse laws | `Order` (slot→screen-rank authority) |
| `Cyclic` / chroma C₄ | Cyclic group on the (a,b) plane; L fixed, gray axis = SO(2) fixed point | `ChromaRotation.rotateQuarter` = C₄, bridged to ℤ[i]\* by `ChromaUnitGauge.lawUnitGroupIsoQuarterTurn` |
| `HierarchicalDelta d` (needs `Monoid d`) | Additive accumulation of detail across scales; per-band delta-pyramid carrier | `HierarchicalDelta` carrier referenced by `RootLatticeDetail` |
| `ChannelDetail c` | `channelEnergy` lens; one interface, two instances (L vs chroma) | `AnchorDiagnostic` |

Two more structural organs sit underneath these classes (not themselves typeclasses but the geometry the classes encode):

- **Root lattice A₇** (`RootLatticeDetail`): split SES `0 → A₇ → ℤ⁸ →^Σ ℤ → 0`. Coarse = rank-1 sum functional Σ (DC quotient); detail = ker Σ = mean-free A₇, the densest dim-7 packing. Band count `b−1 = rank A_{b-1}` is an algebraic identity, not coincidence. `MeanFree` = ker-Σ-membership-as-type (constructor hidden; a value is a *proof* Σ=0).
- **Ultrametric scale filtration** (`ScaleFiltration`): s-adic valuation = common-prefix depth of octant addresses; descending sublattice chain refines by index 8 per level = the 16→64→256 spine. `lawL1NotUltrametric` closes the "d6 is 2-adic" overclaim.

Honest boundary carried throughout: the floored lift is a **set-bijection of ℤ^b, not a ℤ-module homomorphism** (additivity fails under flooring). The A₇/ker-Σ algebra is the idealized-linear skeleton; the shipped lift only realizes the set-bijection face.

---

## 2. How the V2 abstraction fits (skeptic-confirmed)

| Fit | Verdict (CONFIRMED) | One-line reason |
|---|---|---|
| **Eisenstein ℤ[ω] as `CommutativeRing`/`RModule`** | **INSTANTIATES + EXTENDS** (but ring leg is REDUNDANT) | Genuine new ring instance (C₆ units, hexagonal A₂); but `Gaussian` already discharges the same proposition, so the ring leg adds a parallel sibling, not a capability. The real content (ramification, ideal (1−ω), F₃) is *definitionally outside* the class. |
| **Reversible SKI word as `Group`/`TransportGroup`/`ReversibleLift`** | **PARALLEL-ANALOGY** | The *action* (Swap ⊂ Sym ⋉ Rot C₃ ⋉ Shift ℤ) is a genuine group; the word `[Gen]` is a **free monoid**, not a group. NOT a `GaugeAction` (it MOVES the observable, would fail orbit-invariance). NOT a `ReversibleLift` (Frame→Frame, no coarse/detail split). No single-class fit. |
| **Haar uncertainty budget as `ReversibleLift`/A₇/filtration** | **PARALLEL-ANALOGY** ("class-conformant redundant sibling") | `haar8` round-trips like `ReversibleLift`, but `haar8 ≠ liftOct` (1-D Mallat pyramid vs 3-D separable). The class slot is already saturated by `OctLeaf8` carrying the shipped lift. Every positive law re-states `OctreeCell`/`RootLatticeDetail`/`Dimensions`. A₇ is count-only (no `MeanFree`). |
| **16²=256 + S/K/I path as palette gauge / scale spine / PonderNet** | **DUPLICATES** (16²=256) **/ PARALLEL-ANALOGY** (S/K/I-ponder) | Instantiates **zero** typeclasses. `CoarseIsPalette.coarseEqPalette :: PaletteCells :~: 256 = Refl` is the same identity, stronger (compile-time). `Op = S\|K\|I` is the scale monoid on `Int` (K truncates, not invertible), not a combinator algebra. Welding word-length to `PonderHaltDistribution` is forced. |
| **SKI-native + homomorphism as construction encoder / EBM search** | **PARALLEL-ANALOGY** (one re-derivation inside, zero instances) | `renderAt = fPal . fIdx` faithfully re-states `ConstructionEncoder.buildPixels = palette∘index` (already `lawConstructionExecutesToPixels`) in sRGB888 with Lab dropped (a regression). `lawSIsNativeInvention` is definitionally circular; the invention metric (distinct-colour count) diverges from production `bandEnergy`. |

**Name-match honesty:** fits 4 and 5 instantiate no typeclass at all (concept-level only). Fit 3 is class-conformant in principle but declares no instance and is redundant with `OctLeaf8`. Fit 2 is a three-algebra assembly with no single-class home. Only fit 1 is a genuine declared-instance candidate.

---

## 3. The single cleanest fit and the single forced one

**Cleanest (most genuine instantiation): Eisenstein ℤ[ω] as `CommutativeRing`.** It is the only V2 piece where every class method has a real, type-correct realizer (`radd=eadd`, `rmul=emul` = the true ℤ[ω] product `(ac−bd, ad+bc−bd)`, `rneg`, `rzero/rone`, `units` = the six C₆ elements closed under `emul`, `unitInverse` = the verified C₆ table where ω·ω²=1). `Triple Eisen` becomes an `RModule` for free. The instance is total and axiom-true, not an analogy. **Caveat that keeps it honest:** the ring instance alone is *redundant* with `Gaussian` (same kind of witness, C₆ vs C₄, consumed by no production carrier). Its value is entirely the EXTENDS layer (ideal theory) that the class cannot hold.

**Most forced (analogy-only, do not weld): `lawSearchDepthIsPonder`, S/K/I word-length == PonderNet read-depth.** `PonderHaltDistribution` is a geometric halting distribution (`p_n = λ_n Π(1−λ_j)`, `expectedSteps = Σ n·p_n`, KL pull to a geometric prior, coupled to the `CellNudge` budget via `lawLowerHaltRefinesMore`). V2's law is `minimum [length p] == 2` plus length-variety. They share the word "depth" and nothing structural: no halt probability, no distribution, no expectation, no budget coupling. The genuine read-depth lives on the `ScaleFiltration`/`RungPivot` ultrametric, itself distinct from `expectedSteps`. Runner-up forced move: `Op = S|K|I` as a "combinator algebra" (it is integer arithmetic on a side length, with no application/substitution, and K is not even invertible).

---

## 4. Ordered promotion path

Dependency-ordered. Each step names its keystone law. The split is **decision-free now** vs **gated behind `XYTLabDuality`/φ6**.

**Stage 0, land now, decision-free, additive (generalization witnesses):**

1. **`instance CommutativeRing Eisen`** in `RefinementSystem.hs`, beside `Gaussian`. Keystone: `lawUnitGroupClosed` + `lawUnitInverseConsistent` at C₆ (the six norm-1 units closed under `emul`, inverse table verified). `Triple Eisen` becomes `RModule` automatically; parameterize the existing `Properties.RefinementSystem` QuickCheck props over the new type. *Honest label: a third-ring generalization datapoint, not a new capability.*

2. **`Spec.SearchWord`** (or a "word = presentation" layer folded into `TransportGroup`), giving the reversible word a real `instance Group` over **existing C₄ generators** (Swap = `TransportGroup.Transport`, Rot = `ChromaUnitGauge` C₄ over ℤ[i] *not* the Eisenstein C₃, Shift = `ColourDelta`/`RModule` additive luma). Two keystones:
   - `lawSearchWordActsByBijection`: `applyWord (invWord w) . applyWord w == id` (group/reversibility, phrased over the **action**, with `[Gen]` named as the free-monoid presentation layer).
   - `lawSearchWordMovesObservable` (NEGATIVE tooth): some word changes the rendered frame, proving it is **not** a `GaugeAction` so the search-word is never conflated with the palette/chroma gauge.

**Stage 0, documentation-only (no code earns the gate):**

3. Cross-ref note in `SelfSimilarReconstruct` header: `Held`/`Invented` under the one shared `octantLift` is the I/S substructural reading (identity vs contraction), `octantDistill`/RungDir Down is K. `lawSameOperatorBothRungs` is the production form of "I and S differ only in where detail comes from."
4. `palettesAt s == s` ("palettes = frames = side") to `ScaleIndexedCorrespondence` **only** as a labelled **dimensional identity** (`lawPaletteCountEqualsSide`), never as a behavioural/learning theorem. This is the sole V2PaletteScaling statement with no exact production law.

**Stage 1, GATED behind `XYTLabDuality`/φ6 survival (contract change, keep in exploration until then):**

5. **`Spec.EisensteinIdeal`** (a `EuclideanDomain` subclass with `ediv`/`enorm`, plus `divisibleByOneMinusW`, `phiF3`, the split/inert trichotomy). Keystones: `lawEuclideanDivision` (with the tight 4N(r)≤3N(y) closest-point bound), `lawThreeRamifies` (3 = u·(1−ω)²), `lawIndexThreeSublatticeIsIdealOneMinusW`, `lawByteExactCongruenceIsF3Reduction`. **Carry verbatim the one soft spot:** `(1−ω)|z ⇔ a+b≡0 (mod 3)` is sample-verified over a finite box, **not a closed theorem**, do not upgrade it to a proved law.
6. Only if 5 wins its gate: replace `ChromaUnitGauge`'s C₄ = ℤ[i]\* with C₆ = ℤ[ω]\*, splitting the byte-exact group into the C₃ subgroup (units ≡1 mod (1−ω)), and promote `ChromaRotation.rotateQuarter` (90°) to 60° detents. This is a determinism-floor change, not additive.

**Stays exploration permanently (no Tier-0 home, would be forced or vacuous):**

- `V2PaletteScaling` (16²=256 is already `Refl`; S/K/I is the scale monoid; PonderNet weld is forced).
- `V2SkiNativeGif` / `V2SkiHomomorphism` (render=B already pinned; homomorphism true by construction, `lawSIsNativeInvention` circular; a `Spec.Combinator` typeclass over `DetailSource` cannot fire the gate non-vacuously).
- `V2UncertaintyBudget` (`haar8` is a redundant fourth `ReversibleLift` sibling; conservation narrative belongs in `V2-PLAN.md` tying `Dimensions.lawDimConserved` + `RootLatticeDetail` + `OctreeCell`; `lawHaarHasNoStrongHeisenberg` worth *citing* as the reason the uncertainty framing stays exploration-only).
- Any Eisenstein/C₃ content in `V2SkiResidualOrder` (`latticeUnits`, "3 ramifies, C₃ = u ≡ 1 mod (1−ω)") rides on Stage 1's gate.

---

## 5. Open questions / contradictions for the owner

1. **Gaussian vs Eisenstein, the one real decision (everything gated hangs on it).** Production byte-exactness is the **whole C₄** (all four ℤ[i] units permute integer coords exactly, no congruence guard). V2 byte-exactness is the **C₃ of six ℤ[ω] units that are ≡1 mod (1−ω)** plus an invert-or-refuse /3 guard. Which is the right inductive bias for hue: 4 exact quarter-turns (square lattice) or 3-exact-of-6 sixth-turns (hexagonal A₂)? Adopting Eisen imports a *second, competing* byte-exactness mechanism into Tier-0 while the live `ChromaUnitGauge.lawUnitGroupIsoQuarterTurn` floor is unchanged. Does C₆ survive `XYTLabDuality`/φ6 (the memory's stated gate)?

2. **Does promoting one detent ring (C₆) from float-guidance to bit-exact change the determinism-floor contract `DetentNudge` depends on?** Today `ChromaRotation`'s 30/45/60 detents re-enter Q16 and are *not* a group; C₆ would make 60° a genuine group element.

3. **Three lattices, orthogonal or composable?** Colour A₂ (V2 Eisenstein / hexagonal chroma) vs detail A₇ (`RootLatticeDetail` ker Σ) vs the descending octant scale filtration. `ScaleFiltration` explicitly *declines* the profinite completion to (ℤ₂)³. Are these ever meant to compose, or are they three independent geometries?

4. **Does the 9-channel rank-3 cell-aggregate survive an Eisenstein RGB lens?** `NudgeRankTheorem`/`CellNudge` (A = Σ colour⊗space, rank-3, det=1, with the φ6 Z⁶-module value-split gauge) has **no V2 expression**. If V2's RGB-Eisenstein replaces the (L,a,b)/(x,y,t) φ6 split, does the colour-by-space outer product still type-check, or must it be re-derived over ℤ[ω]?

5. **Promote the Held/Invented + Down/Up dichotomy to an explicit S/K/I combinator algebra, or keep the homomorphism V2-only?** The honest production analogues already exist (`DetailSource` Held≈I / Invented≈S, RungDir Down≈K). A `Spec.Combinator` typeclass would import substructural vocabulary but no load-bearing math beyond the existing split, and its homomorphism is true by construction (vacuous gate). Land it *only* if the EBM search is ever genuinely reformulated as SKI-word reduction with a real proposer ranked by `bandEnergy` (today the proposer is `ScalePonder`'s halt-mask, not a word-reducer).

6. **Is the floored-lift honesty stated once or duplicated?** `ReversibleLift`'s "set-bijection, not ℤ-module hom" and `V2UncertaintyBudget`'s "no strong Heisenberg" are the same register. Should one law state "the lattice STRUCTURE (which bands) is exact but per-element additivity is not" once, instead of duplicated across `RootLatticeDetail` and the carrier?

7. **Search-family vs the two gauges.** The palette gauge is S_256 (non-abelian); the reversible word MOVES the observable. Is the search family (reversible word = norm-1 unit) compatible with the S_256 orbit-invariant, or do the index gauge and hue gauge need to be quotiented *jointly* before the search is well-defined?