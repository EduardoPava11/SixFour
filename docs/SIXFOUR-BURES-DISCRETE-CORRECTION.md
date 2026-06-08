# ADR-014: Bures is a Gaussian Approximation of Discrete Palettes, Not Their Barycenter

**Status:** Accepted · **Date:** 2026-06-08 · **Slice:** sigma-bures-core, collapse-surface, downstream-consumers

> **AS-BUILT (executed 2026-06-08, branch `cleanup/bures-discrete-adr014`, 593 tests green) — read §0 first.** Direct reading of the code scoped the change down from the map-based plan below. See **§0 As-Built** for what actually shipped and why it diverges from §2–§4.

## 0. As-Built (what actually shipped, vs the plan in §1–§6)

Reading the real code revealed the map-based plan over-reached. What was executed:

- **Step 0 — orphan delete (done).** `CollapseLever.hs` was an *untracked, abandoned* module (added to `spec.cabal` in one uncommitted line, zero importers). There was **no** `Properties/CollapseLever.hs` (the plan assumed one). Removed the file + reverted the cabal line → nets to zero git diff. (−255 LOC of dead code, off-tree.)
- **Step 2 — deleted `buresBarycenter` + its 2 props (done).** This is the live category-error symbol (a Gaussian-of-Gaussians barycenter doc'd as "the parametric companion to the k-means palette barycenter"). Zero callers ⇒ "Bures barycenter" is now **unnameable** in the API.
- **KEPT `buresBarycenterCov` (deviation from §3).** It is load-bearing for the `BURES_BARY_COV` golden, which a **hand-written Rust consumer** (`studio/look-nn-baseline/src/lib.rs:225`) cross-checks — and the Rust `studio` workspace is *outside the cabal gate* (separate cargo gate). Deleting it would silently break the Rust port. Instead it was **re-doc'd as Gaussian-only** (a spread summary for the analysis oracle, explicitly NOT the discrete-palette collapse, citing arXiv:1511.05355).
- **Did NOT rename `buresDistanceSq` → `gaussianMomentDistanceSq` (deviation from §2).** On reading, `buresDistanceSq` is *correctly* named — it genuinely computes the Bures–Wasserstein distance between two Gaussians. The honesty problem was never that function; it was (a) the dead `barycenter` symbols and (b) the docs. Renaming a correct function would lose precision and risk the cross-language golden constant. Honesty was fixed via **deletion + docs** instead.
- **Did NOT add `WitnessedApprox` / create `Spec/GaussianApprox.hs` (deviation from §2).** Per the anti-bloat / Layers-0–2 canon driving this whole cleanup, adding an unused type with an admittedly-possibly-vacuous law is the very speculative ceremony we are removing. The category error is already eliminated by deletion; the module keeps the name `Bures` because it legitimately implements the Bures *distance*.
- **Docs retyped (done):** `Bures.hs` header, `buresBarycenterCov` doc, `LookCore.hs:53`, `LookNet.hs:215` — all now say "discrete maximin floor is the collapse; Gaussian Bures is a spread-aware approximation; exact discrete barycenter NP-hard."
- **Step 4 — fold `Quad4Fit` (done, commit `a2aa091`).** `Quad4Fit` was a finished negative-result capacity experiment (design-matrix/rank/residual) whose finding *drove* the `SigmaPairHead` 384-DOF pivot; only `paletteToVec` ever reached production. Moved `paletteToVec` into `Quad4`, deleted `Quad4Fit.hs` + `Properties/Quad4Fit.hs`, repointed the `SigmaPairHead` import, de-linked the historical prose refs (`LookNetD`, `SigmaPairHead`, `Pipeline`) to this ADR. ~−310 LOC; 593→585 tests; 0 codegen drift (it was never in the codegen path).

**As-built net (commits `3478426` + `a2aa091`):** ≈ **−592 LOC** (−255 orphan, −27 barycenter+props, −310 Quad4Fit), **0 codegen drift**, **0 cross-tier breakage**, 595→585 tests. Files: `Spec/Bures.hs`, `Spec/LookCore.hs`, `Spec/LookNet.hs`, `Spec/Quad4.hs`, `Spec/SigmaPairHead.hs`, `Spec/LookNetD.hs`, `Spec/Pipeline.hs`, `spec.cabal`, `test/Spec.hs`, `test/Properties/Bures.hs`; deleted `Spec/Quad4Fit.hs`, `test/Properties/Quad4Fit.hs`, `Spec/CollapseLever.hs`.

**Deferred (not done, clearly scoped):**
- **Deeper `buresBarycenterCov` + Rust-port reconciliation.** Would retype/retire the Gaussian covariance barycenter in the proprietary `studio` analysis tool; crosses into a second (cargo) gate.
- **Broader doc sweep** (`GMM.hs`, `Collapse.hs` header, `LookNetR.hs`).

The §1–§6 below is the *original debate synthesis* — preserved as the reasoning record; where it conflicts with §0, §0 is authoritative.

---

> Produced by a 4-position type-class debate workflow (map → debate → adversarial judge panel → synthesis).
> Debate ranking: **Delete-Don't-Abstract 19/25** ≈ **Witnessed-Approximation 19/25** > Two-Class 17/25 > Phantom/DataKinds 15/25.
> North star: research finding in [SIXFOUR-JEPA-VS-STATISTICAL-CELLGRID.md](SIXFOUR-JEPA-VS-STATISTICAL-CELLGRID.md) — the closed-form Bures barycenter is licensed only for absolutely-continuous/Gaussian measures and explicitly excludes discrete distributions ([arXiv:1511.05355]); exact discrete W₂ barycenter is NP-hard.
> All caller/orphan claims below independently grep-verified on disk 2026-06-08.

## 1. Decision

**Lowest-ceremony blend: deletion + one self-describing rename + one witnessed-value record + one law. No type class, no DataKinds, no kind index.**

The category error has no live value-level locus. Verified on disk: `buresBarycenter` and `buresBarycenterCov` have **zero production callers** — `buresBarycenter` appears only in `LookCore.hs:53`/`LookNet.hs:215` *prose* plus two test props (`Properties/Bures.hs:75,84`); `buresBarycenterCov` is consumed only by `Burn.hs:109` (`baryCov6`) plus props `97,98`. The **single live Bures function** is `buresDistanceSq`, reached once, from `Loss.fidelityLossLeaves:162`. `CollapseLever.hs` (255 LOC) has **zero importers**. All confirmed by grep.

Per the binding methodology canon — "type classes used sparingly; escalate ONLY on pager-on-fire; SKIP DataKinds/LiquidHaskell/Agda as ceremony" — a category error that is, after dead-code deletion, a *documentation lie* is categorically **not** pager-on-fire. Every judge converged here: the Phantom (DataKinds) and Two-Class positions both **lose to their own function-only fallbacks**, which buy identical unnameability for ~40–90 fewer LOC. The Two-Class author concedes this in writing.

So we **delete the two `barycenter` symbols** (making "Bures barycenter" *unnameable* on the Gaussian side — there is no function to express it through), **rename** the surviving distance so its name carries the arXiv:1511.05355 caveat, and ship the projection error **as a value** via Witnessed-Approximation's record — but compute the witness as the judges grafted: the **dimensionally-honest OKLab gap from the moment-matched Gaussian mean to the nearest discrete-floor leaf**, not the ill-posed `gErr <= discreteCost` scalar comparison (which the cross-exam showed compares a Bures distance against a maximin objective of different units, possibly vacuous or false).

We **reject** the SigmaPairFixed↔SigmaPairHead merge: verified disjoint substrates (`SigmaPairHead` imports `PairTree`/`OKLab`; `SigmaPairFixed` imports `PairTreeFixed`/`OKLabI`). The "112 LOC → one 1-liner" claim is unsupported; the real saving is a ~6-LOC interleave helper, not worth a module that depends on both substrates. We **also reject** deleting the `sigmaPair` LA scaffold while keeping `sigmaPairResidual`, because `sigmaPairResidual = residualFraction sigmaPairBasis (paletteToVec leaves)` transitively pulls in `sigmaPairBasis → sigmaPairDesignMatrix → paletteToVec` — confirmed on disk. The scaffold stays as-is; it's honest discrete σ-algebra and is consumed by `Properties/SigmaPairHead.hs`.

## 2. The North-Star Encoding

New module `Spec/GaussianApprox.hs` (replacing the Bures barycenter exports). Lower-case names are the disclaimer; the only door to a Gaussian distance forces the witness to exist alongside it.

```haskell
{- |
Module      : SixFour.Spec.GaussianApprox
Description : Gaussian MOMENT-SUMMARY of a discrete palette — an APPROXIMATION,
              NOT its W₂ barycenter.

A SixFour per-frame palette is a DISCRETE empirical measure (≤256 weighted OKLab
atoms). The closed-form Bures fixed point Σ̄ = Σᵢλᵢ(Σ̄^½ΣᵢΣ̄^½)^½ (Agueh–Carlier
2011) is proven ONLY for absolutely-continuous / Gaussian measures; the source
[arXiv:1511.05355] EXPLICITLY excludes discrete distributions. So moment-matching
a palette to one Gaussian and taking a Bures distance is a SPREAD-PRIOR
APPROXIMATION with a real projection error — see 'waError'. The honest discrete
floor is 'SixFour.Spec.Collapse.farthestPointCollapse' / 'globalCollapseQ16'.
See docs/SIXFOUR-JEPA-VS-STATISTICAL-CELLGRID.md.
-}
module SixFour.Spec.GaussianApprox
  ( Mat3(..), fromCov3, toCov3, matId, matMul, matTrace, sqrtPSD   -- algebra kept
  , gaussianMomentDistanceSq                                       -- renamed
  , WitnessedApprox(..), gaussianApprox                            -- the witness
  ) where

-- | Squared Bures (Gaussian W₂) distance. NOT a discrete-palette distance:
-- both inputs are moment-matched Gaussian SUMMARIES. (was 'buresDistanceSq';
-- byte-identical body ⇒ golden value unchanged.)
gaussianMomentDistanceSq :: Gaussian -> Gaussian -> Double
gaussianMomentDistanceSq (Gaussian m1 c1 _) (Gaussian m2 c2 _) = ...  -- old body

-- | A Gaussian moment-summary of a discrete palette, shipped WITH the witnessed
-- projection error to the discrete floor. The name is the assertion.
data WitnessedApprox = WitnessedApprox
  { waGaussian :: !Gaussian   -- moment-matched (μ, Σ, w)
  , waError    :: !Double      -- ‖μ − nearest discrete-floor leaf‖², always ≥ 0
  } deriving (Eq, Show)

-- | The ONLY constructor: forces the witness. 'farthestPointFloor' is the
-- gamut-closed maximin floor (reuses shipped Collapse code, no new algorithm).
gaussianApprox :: [OKLab] -> WitnessedApprox
gaussianApprox leaves =
  let g   = mixtureAsGaussian (leavesAsPointMassGMM leaves)
      flr = farthestPointFloor leaves
      err = minimum (okLabDistanceSquared (gMean g) <$> flr)
  in WitnessedApprox g err
```

`farthestPointFloor :: [OKLab] -> [OKLab]` is a 4-line wrapper exported from `Collapse.hs` over the shipped `pooledCandidates` + maximin. `mixtureAsGaussian` and `leavesAsPointMassGMM` move from `Loss.hs` exports to **internal** use here (confirmed: `mixtureAsGaussian` is called only inside `fidelityLossLeaves`), closing the silent discrete→Gaussian coercion door.

**The one new law** (`Properties/GaussianApprox.hs`) — the honest, dimensionally-sound witness the North Star names:

```haskell
lawApproxWitnessed :: [OKLab] -> Bool
lawApproxWitnessed leaves =
  let w = gaussianApprox leaves
  in waError w >= 0                                   -- moments never lie about sign
     && (allEqual leaves `implies` (waError w == 0))  -- degenerate point-mass ⇒ exact
```

`Loss.fidelityLossLeaves` keeps its **signature and numeric body** (golden stays green); it now routes through `gaussianMomentDistanceSq`:

```haskell
fidelityLossLeaves :: [OKLab] -> GMM -> Double
fidelityLossLeaves leaves inputGmm =
  gaussianMomentDistanceSq (mixtureAsGaussian (leavesAsPointMassGMM leaves))
                           (mixtureAsGaussian inputGmm)
```

There is now **no exported symbol named `barycenter`** that consumes palettes and is a Gaussian object. The error is symbol-unrepresentable without a class.

## 3. De-Bloat Ledger

| Action | Target | LOC Δ | Notes |
|---|---|---|---|
| DELETE | `Spec/CollapseLever.hs` | −255 | Zero importers (verified). |
| DELETE | `Properties/CollapseLever.hs` | ~−60 | drops with it; remove from `spec.cabal` + `test/Spec.hs`. |
| DELETE | `Bures.buresBarycenter` + doc | ~−15 | 0 production callers. |
| DELETE | `Bures.buresBarycenterCov` + doc | ~−20 | only `Burn.baryCov6` + 2 props. |
| DELETE | `Properties/Bures.hs` props 75/84/97/98 | ~−15 | barycenter props die with the functions. |
| DELETE | `Burn.hs` `baryCov6` + `BURES_BARY_COV` golden line | ~−6 | drops the dead-fn golden pin. |
| RENAME | `Spec/Bures.hs` → `Spec/GaussianApprox.hs`; `buresDistanceSq` → `gaussianMomentDistanceSq` | 0 | bodies identical; golden value `BURES_DIST_SQ` **unchanged**, constant kept (rename optional, deferred to avoid churn). |
| RENAME | doc headers: `Bures.hs` 5–22, `Collapse.hs` "Wasserstein barycenter" header, `GMM.poolGMM` doc, `LookCore.hs` 3/8/53, `LookNet.hs` 126/215, `LookNetR.hs` 12 | ~0 | prose → "Gaussian spread prior (approximation; see waError)" vs "discrete maximin floor". |
| ADD | `WitnessedApprox` + `gaussianApprox` + `farthestPointFloor` + `lawApproxWitnessed` | +~22 | the witness machinery. |
| ADD | `Burn.hs` `BURES_APPROX_ERROR` golden (witness on `buresG1`) | +~3 | swaps WHICH number is pinned. |
| FOLD | `Quad4Fit.hs` → keep only `paletteToVec`, move into `Quad4.hs`; delete design-matrix/rank/residual + `Properties/Quad4Fit.hs` | ~−240 | finished negative-result experiment; `paletteToVec` is the sole reuse (SigmaPairHead:77). |
| KEEP | `SigmaPairHead` LA scaffold, `SigmaPairFixed` as separate module | 0 | merge over-claimed (disjoint substrates); residual entanglement makes demotion self-contradictory. |

**Net: roughly −600 to −650 LOC, −2 to −3 modules** (CollapseLever, Quad4Fit, +Properties). This is the realistic figure after honestly costing out the *Fixed merge the headline −750 claim relied on.

## 4. Staged Migration (gate green at every step)

Gate after **every** step:
```
cd /Users/daniel/SixFour/spec && cabal build && cabal test && cabal run spec-codegen
```
(equivalently `scripts/s4.sh codegen && scripts/s4.sh verify`). Then the full repo gate (`xcodegen generate && xcodebuild -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`) and `scripts/verify-doc-claims.sh` at the **end of each landing-worthy step**.

**Step 0 — Delete the orphan.** Remove `CollapseLever.hs` + `Properties/CollapseLever.hs`; strip from `spec.cabal` exposed-modules and `test/Spec.hs`. Zero blast radius. Gate.

**Step 1 — Add the witness (additive, nothing breaks).** Add `farthestPointFloor` export to `Collapse.hs`; add `WitnessedApprox`/`gaussianApprox`/`lawApproxWitnessed` to `Bures.hs` (still named Bures); wire `Properties/GaussianApprox` (or extend `Properties/Bures`) into `test/Spec.hs`. No existing symbol changes. Gate.

**Step 2 — Kill the dead barycenters + swap the Burn golden.** Delete `buresBarycenter`, `buresBarycenterCov`, their props, and `baryCov6`. In `Burn.hs` replace `BURES_BARY_COV` with `BURES_APPROX_ERROR = waError (gaussianApprox <fixture leaves>)`. **`cabal run spec-codegen` regenerates `contract.rs`** — the Rust port's `bures.rs` golden must follow (drop `BURES_BARY_COV`, add `BURES_APPROX_ERROR`). `BURES_DIST_SQ` is **untouched** (body preserved). Gate. *Codegen touch-point: `Burn.hs` only; `Golden.hs` `loss_note` and `input_gmm_*` are unchanged because `fidelityLossLeaves` numerics are preserved.*

**Step 3 — Rename Bures→GaussianApprox + `buresDistanceSq`→`gaussianMomentDistanceSq`.** Update imports in `Loss.hs`, `Burn.hs`, `LookCore.hs`, `LookNet.hs`. Keep the **golden constant name** `BURES_DIST_SQ` (or rename to `GAUSSIAN_MOMENT_DIST_SQ` in the same commit as the Rust port — value identical either way). Gate.

**Step 4 — Fold Quad4Fit.** Move `paletteToVec` into `Quad4.hs`; update `SigmaPairHead.hs:77` import. Delete the rest of `Quad4Fit.hs` + `Properties/Quad4Fit.hs`; strip from `spec.cabal`/`test/Spec.hs`. **Verify `sigmaPairResidual`/`sigmaPairBasis` still compile** (they depend on `paletteToVec`, now from `Quad4`). Gate.

**Step 5 — Doc retype sweep.** Rewrite the conflating headers (`Collapse.hs`, `GMM.hs`, `LookCore.hs`, `LookNet.hs`, `LookNetR.hs`). Run `scripts/verify-doc-claims.sh`. Gate.

**Explicit contract preservation:** the **SigmaPairHead 384-DOF spine** (`SigmaPairHead → LookNetD → Net.slotLookDims → Codegen.{CoreML,MLX,Swift,Genome,GenomeFixed}`) **imports no Bures function** (verified) — every step above touches it in **zero** places. `SIGMA_PAIR_DOF=384`, `DECODER_OUT_DIM`, `GMM_TOKEN_DIM=10`, `sigmaDecoderMask`, and the `CollapseGolden.swift` Q16 contract are all unaffected.

## 5. Risks & What Could Break

- **`BURES_DIST_SQ` rename desync (Step 3).** If the Rust `bures.rs` golden isn't updated in lockstep with the Haskell constant rename, the 1e-6 cross-language gate fails. *Mitigation:* keep the constant **name** `BURES_DIST_SQ` (value-only contract; symbol rename is cosmetic and can stay deferred indefinitely).
- **`baryCov6` removal underestimated (Step 2).** `Properties/Bures.hs` props 97/98 must be deleted in the same commit or the build breaks on the missing symbol. Already in the ledger.
- **Quad4Fit fold breaks `sigmaPairResidual` (Step 4).** `sigmaPairResidual → sigmaPairBasis → paletteToVec` (verified). If `paletteToVec` isn't re-exported from `Quad4` before deleting `Quad4Fit`, `SigmaPairHead` won't compile. The step ordering (move first, delete second) handles this; the gate catches any slip.
- **Witness law could be vacuous.** `waError == 0` when `gMean` coincides with a floor leaf even for a non-Gaussian cloud (judge's fatal flaw on Position 3). This is **accepted**: the law's job is honesty about *sign* and the *degenerate case*, not a tight Gaussianity test — `SigmaDecomp.sigmaSymFraction` and `SigmaPairHead.sigmaPairResidual` remain the discrete fidelity witnesses for scene affordance. We do **not** add `slicedW2OKLab` (every judge flagged it as consumer-less new bloat; the existing Q16 maximin floor already satisfies "honest discrete base").
- **`waGaussian` is a public field** — a determined caller can pattern-match the raw Gaussian. Accepted under the canon: the conflation is *discouraged by construction* (only constructor computes the witness; `barycenter` is unnameable), not type-enforced. Type-enforcing it would require the class hierarchy the canon forbids.

---

**Files referenced (all verified on disk):** `spec/src/SixFour/Spec/Bures.hs`, `Collapse.hs`, `CollapseLever.hs`, `Quad4Fit.hs`, `SigmaPairHead.hs`, `SigmaPairFixed.hs`, `Loss.hs`; `spec/src/SixFour/Codegen/Burn.hs`; `spec/test/Properties/{Bures,SigmaPairHead}.hs`.
