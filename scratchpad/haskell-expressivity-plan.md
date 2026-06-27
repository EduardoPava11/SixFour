# SixFour Haskell Expressivity Plan — the reversible lift as a (demoted) metamorphism over a Nat-branching module functor

Lead-architect synthesis of four design approaches against the live spec, keeping only what survived adversarial skeptic vetting. **PLANNING ONLY.**

## 0. Verdict-driven framing (read this first)

All four proposals were returned by their skeptics as **forced-jargon** or **partial-win that does not survive** as a refactor. The grand-unification headlines were each falsified:

- **"`apo` makes byte-exactness STRUCTURAL not tested" is FALSE and HARMFUL.** `ana . cata = id` is *not* a free theorem; it needs the carrier-level band-replay plumbing (coarse-concat order, `zipWith` alignment, coarsest-first band order) proven anyway. Replacing the tested `lawOctantLadderBijective :: Bool` with "structural by construction" *deletes a real regression guard* — the same class of guard that caught the shipped ReleaseFast `d=x-y` silent-overflow bug. **Do not retire any byte-exact `law :: Bool` in favour of a universal-property claim.**
- **"Euclidean domain apex" is unearned jargon and a byte-exactness break.** No SixFour op does Euclidean division; `quotRem'` over ℤ[i] secretly divides by the norm (a non-unit). Kill `euclNorm`/`quotRem'`.
- **The type-indexed general-`b` theorems do NOT compile boot-only.** Empirically, `predSucc (SS n) = Refl` and the `Vec (n+1) → Vec n` haar fail under ghc-9.2.8's built-in Nat solver (no `natnormalise`, which is forbidden). Only *user-defined promoted Peano* compiles, and that cannot host the literal 16/64/256 corners.
- **Most of the "unification" is ALREADY DONE.** `RefinementSystem.ReversibleLift` already abstracts branching `b` with `Dyad8`/`Tern3` instances and proves `lawLiftFRoundTrips` + `b−1 = rank` at both b=8 and b=3. `GaugeAction` already has two `Group` instances. `MetricLattice` already has the ℓ¹/ℓ^∞ knob. `ScaleFiltration` already checks the ultrametric and `lawL1NotUltrametric`. The flat-laws-into-class-laws win is a *description of the existing architecture*, not a deliverable.

**So this plan is deliberately small.** It commits only to the concrete, compile-verified salvages, names the metamorphism vocabulary as *documentation not theorem*, and adds exactly the new data that is genuinely net-new and checkable.

## 1. Central thesis (committed scope, honestly demoted)

> The reversible multiresolution lift is **named** a metamorphism (a `cata` capture followed by an `ana` reconstruct, Gibbons-style) over a branching node-functor whose carrier is a **module over a non-field ring R** (`CommutativeRing` with no `recip`; R = ℤ today, ℤ[i] for Gaussian chroma). This naming is *earned at the README/Map level* because the pieces it names already exist and already pass their laws. It is **NOT** promoted to a free theorem: reversibility stays a TESTED bijection law, not a universal-property gift.

What we actually *build* on top of that framing is three small, surgical wins (Section 3) plus one tiny shared `Spec.Recursion` home so `Fix/cata/ana/hylo/meta` stop being privately re-declared inside `OctreeCell`.

What we explicitly **do not build**: `BranchF (b::Nat)` replacing `V8` (downgrades the arity-8 *type* invariant to a runtime `length` check — a regression against byte-exactness); `apo`/`para`/`histo`/`futu` (one call site each = one-off dressed as generalization; `histo` is also the wrong direction — it carries finer children, while "read at depth n" needs coarser ancestors that `ScaleFiltration.valuation` already gives); the general-`b` type-level SES; the Euclidean-domain apex.

## 2. The ONE new boot-only foundation module: `Spec.Recursion`

Boot-only is legal (deps are `base/vector/containers/text/transformers`; no `recursion-schemes`/`free`/`comonad`). The module is ~30 lines and contains ONLY the schemes that already have ≥2 honest consumers (`cata`, `ana`) plus the *naming* combinators `hylo` and `meta` that describe pairs already shipped. No `apo/para/histo/futu` — they are admitted only if a second real consumer ever appears.

```haskell
-- COMPARTMENT: PURE-SPEC-WALL | tag:none
module SixFour.Spec.Recursion
  ( Fix(..), cata, ana, hylo, meta ) where

newtype Fix f = Fix { unFix :: f (Fix f) }

cata :: Functor f => (f b -> b) -> Fix f -> b
cata alg = alg . fmap (cata alg) . unFix

ana :: Functor f => (a -> f a) -> a -> Fix f
ana coalg = Fix . fmap (ana coalg) . coalg

-- | hylomorphism: ana then cata fused, no intermediate Fix.
hylo :: Functor f => (f b -> b) -> (a -> f a) -> a -> b
hylo alg coalg = alg . fmap (hylo alg coalg) . coalg

-- | metamorphism (Gibbons): a cata that FULLY COMPLETES, then an ana.
--   Names the capture→reconstruct PAIR as one object. Documentation only;
--   it asserts NOTHING about mutual-inverseness (that stays a tested law).
meta :: (Functor f, Functor g) => (f b -> b) -> (b -> g b) -> Fix f -> Fix g
meta alg coalg = ana coalg . cata alg
```

The shipped octree functor and its two morphisms **already live in `OctreeCell.hs`** and stay exactly as written (the fixed arity-8 product `V8` is the byte-exact type invariant — keep it):

```haskell
data V8 a   = V8 a a a a a a a a            deriving (Eq, Show, Functor)
data OctF l a = Leaf l | Node (V8 a)        deriving (Eq, Show, Functor)

-- the catamorphism that captures a cube into bands (UNCHANGED):
octantDistill   :: Fix (OctF Int) -> [OctBand]      -- coarsest-first
-- the anamorphism that reconstructs (UNCHANGED):
octantSynthesize :: [OctBand] -> Fix (OctF Int)

-- the TESTED bijection — stays a Bool, never "structural":
lawOctantLadderBijective :: V8 Int -> Bool
```

The only change to `OctreeCell` is: **import `Fix/cata/ana` from `Spec.Recursion` instead of declaring them locally**, and name the capture/reconstruct pair with `meta` in a doc-comment. No law changes, no plumbing changes. `V8` stays; there is **no `apo` octree coalgebra** in this plan — the example signature the brief asked for is deliberately *rejected* because the skeptic showed it tests nothing about `liftOct` while deleting the regression guard.

## 3. The three real expressivity wins (the actual payload)

These are the only items every skeptic *salvaged*. Each is small, boot-only, and either retires a law honestly or removes a real partiality wart.

### Win A — `units` / `unitInverse` on `CommutativeRing` (the one genuinely net-new datum)
Turn the prose "the absence of `recip` IS the structural claim" into a *checkable enumerated list*, and connect it to the already-green Gaussian order-4 unit laws.

```haskell
class CommutativeRing r where
  rzero, rone :: r
  radd, rmul  :: r -> r -> r
  rneg        :: r -> r
  units       :: [r]            -- NET-NEW: the finite enumerated unit group
  unitInverse :: r -> Maybe r   -- partial recip, DEFINED ONLY on units

instance CommutativeRing Integer  where units = [1, -1]; ...
instance CommutativeRing Gaussian where units = [1, i, -1, -i]; ...   -- {±1, ±i}
```
**Payoff:** makes "not a field, finite units" a *theorem with teeth* (`lawUnitInverseOnlyOnUnits`, `lawUnitsClosedUnderMul`), and ties `GaussianChroma`'s `lawChromaQuarterTurnOrderFour` to the ring: the four quarter-turns ARE `units :: [Gaussian]`. **Drop `euclNorm`/`quotRem'`** — they import the forbidden non-unit division.

### Win B — total `OctLeaf8` conversion (the single most concrete correctness win)
`RefinementCarriers.OctLeaf8.fromVec` currently has a silent partial fallback:
```haskell
fromVec xs = case map fromIntegral (take 8 (xs ++ repeat 0)) of
  (a:b:c:d:e:f:g:h:_) -> OctLeaf8 (V8 a b c d e f g h)
  _                   -> OctLeaf8 (V8 0 0 0 0 0 0 0 0)   -- swallows ragged input
```
Replace the ragged-`[Integer]` round-trip with a **total `V8`-direct conversion** (`V8` is already exactly eight fields — a literal `3`/`8`, no symbolic Nat arithmetic, so it compiles boot-only). This removes the dead/silent `_` branch so malformed input cannot be silently zero-corrupted on a byte-exact path. **Payoff:** make-illegal-states-unrepresentable on the production octant carrier, with zero new dependency and no Nat solver.

### Win C — `MeanFree` newtype constructed from root coordinates (NOT by subtracting a mean)
Give `HierarchicalDelta`'s zero-mean `fineBand` a typed home that retires `inA`/`lawDetailIsMeanFree`/`lawSimpleRootsAreMeanFree` *by construction*:
```haskell
newtype MeanFree = MeanFree [Integer]            -- INVARIANT: Σ = 0
mkMeanFreeFromRootCoords :: [Integer] -> MeanFree -- via fromRootCoords (always Σ=0, integer-exact)
mkMeanFreeChecked        :: [Integer] -> Maybe MeanFree  -- inA guard, Nothing if Σ≠0
```
**Payoff:** the mean-free property becomes a type invariant on the detail band. **Hard constraint:** the constructor must come from `RootLatticeDetail.fromRootCoords` or a `Maybe`-checking `inA` guard — **NEVER** a `project`/subtract-DC mechanism, because the mean = `sum/length` divides by `b` (a non-unit) and breaks byte-exactness. The `algebraic-tower` proposal's `mkMeanFree = project` is explicitly killed.

## 4. Keystone laws of the new expression + HONEST BOUNDARIES

**Keystone laws (all stay tested `:: Bool`, gated by `cabal test`):**
1. `lawOctantLadderBijective` — UNCHANGED, still tested. The metamorphism naming adds zero new guarantee here; this is the load-bearing byte-exact guard and it must never be downgraded to "structural".
2. `lawMetaIsDistillThenSynthesize` (NEW, doc-grade) — `meta liftAlg synthCoalg == octantSynthesize . octantDistill` on a sample cube. Names the pair; asserts equality of the *named* composite with the *existing* one, not mutual-inverseness.
3. `lawUnitInverseOnlyOnUnits` + `lawUnitsClosedUnderMul` (NEW, Win A) — at both ℤ and ℤ[i]; `unitInverse x = Nothing` for any non-unit (e.g. `2`, `1+i`).
4. `lawOctLeaf8FromVecTotal` (NEW, Win B) — round-trips for ALL `V8 Int`, no `_` fallback reachable.
5. `lawMeanFreeIsSigmaZero` (NEW, Win C) — every `MeanFree` has `sumFunctional = 0`; constructed only from root coords or a checked guard.

**HONEST BOUNDARIES — names NOT earned, must be avoided (respect the rejected-jargon list):**
- **"Byte-exactness is structural / by construction"** — FORBIDDEN phrasing. Reversibility is a TESTED bijection. The floored shipped `liftOct`/`sLift` is a *set bijection*, NOT a ℤ-module homomorphism (additivity fails under flooring); `RootLatticeDetail`'s honest-boundary doc stays. `meta` does not certify linearity.
- **`apo`/`para`/`histo`/`futu`** — not introduced. One consumer each = jargon-by-absence. `histo` is also a category error for "read at depth n" (it carries finer children; coarser ancestors come from `ScaleFiltration.valuation`).
- **`BranchF (b::Nat)`** — rejected: it downgrades `V8`'s arity-8 *type* invariant to a runtime `length` check. Keep `V8`. A new branching (b=27) is added as a new `ReversibleLift` *instance*, not a list functor.
- **"Euclidean domain"** — rejected: no SixFour op does Euclidean division; the only load-bearing fact is "commutative ring + finite enumerated units + no `recip`", now captured by Win A's `units`. No `quotRem'`.
- **General-`b` type-level SES / `predSucc` induction** — rejected: does not compile boot-only (needs forbidden `natnormalise`). Type-level facts limited to literal corners (`(2^4) :~: 16`) which DO compile but retire nothing important — admit only as cheap doc, not as the carrier of the SES theorem (SES exactness stays the runtime `lawRootCoordsRoundTrip`).
- **"Galois / Frobenius / GF(256) / 2-adic d6"** — already-rejected jargon; the gauge group is non-abelian S_K (invariant theory), the scale metric is s-adic ultrametric distinct from archimedean ℓ¹ (`lawL1NotUltrametric`). Unchanged.
- **Profinite (ℤ₂)³ completion** — NOT constructed; a finite ADT cannot witness it. Doc-comment stance only.

## 5. Phased build sequence (each phase gateable with `cabal test`)

Follow the mechanical add-a-module pattern: (1) `spec.cabal` `exposed-modules`, (2) module `{- | Module / Description / … -}` header, (3) ONE line in `SixFour.Spec.Map` under its category, (4) wire laws into `Spec.hs` test group, (5) `cabal run spec-codegen` (no codegen impact expected here — all pure-spec). Run `ghcid → cabal test → cabal haddock` after each.

**Phase 0 — `Spec.Recursion` foundation (additive, zero behaviour change).**
Add the module (Section 2). Add `lawMetaIsDistillThenSynthesize` as a sample-cube Bool. Map category: "NN design ★ / refinement core". Gate: `cabal test` green, Haddock warning-clean. *No existing module touched yet.*

**Phase 1 — re-home `OctreeCell` onto `Spec.Recursion`.**
Delete the local `Fix/cata/ana` decls in `OctreeCell.hs`; import from `Spec.Recursion`. Keep `V8`, `OctF`, `liftOct`, `octantDistill/Synthesize`, and `lawOctantLadderBijective` byte-for-byte. Add a doc-comment naming the pair `meta`. Gate: `cabal test` (the bijection law is the regression guard — it must stay green and stay a Bool).

**Phase 2 — Win A: `units`/`unitInverse` on `CommutativeRing`.**
Extend the class + both instances (ℤ, ℤ[i]); drop nothing else from `RefinementSystem`. Add `lawUnitInverseOnlyOnUnits`, `lawUnitsClosedUnderMul` tested at both rings. Cross-link to `GaussianChroma.lawChromaQuarterTurnOrderFour` in the doc. Gate: `cabal test` at Integer AND Gaussian.

**Phase 3 — Win B: total `OctLeaf8` conversion in `RefinementCarriers`.**
Replace the ragged `fromVec`/`toVec` with a total `V8`-direct conversion; remove the silent `_` fallback. Add `lawOctLeaf8FromVecTotal`. Confirm `lawOctLeafLiftIsLiftOct` + `lawOctLeafOverridesDefault` still green (the carrier still genuinely overrides the prefix-difference default). Gate: `cabal test`.

**Phase 4 — Win C: `MeanFree` newtype in (or beside) `RootLatticeDetail`.**
Add `MeanFree`, `mkMeanFreeFromRootCoords` (via `fromRootCoords`), `mkMeanFreeChecked` (via `inA`). Give `HierarchicalDelta.fineBand` (ColourDelta value carrier) a `MeanFree`-typed surface. Add `lawMeanFreeIsSigmaZero`. **Audit:** grep the diff for any `div`/`/`/`sum … length` mean-subtraction — there must be NONE. Optionally retire `lawDetailIsMeanFree`/`lawSimpleRootsAreMeanFree` *only if* fully subsumed by construction; otherwise keep them. Gate: `cabal test`.

**Phase 5 — `Spec.Map` taxonomy doc (no code).**
Write the faithful README-level structure map (apex = ring with enumerated finite units; cross-cut by archimedean `LatticeNorm` vs non-archimedean `Ultrametric`; capped by `Group ⇒ GaugeAction`) as documentation in `Spec.Map`, citing the existing modules. This is the only honest form of the "algebraic tower" — a citation map, not a refactor. Gate: Haddock warning-clean, `Map` lint passes (every module has its one line).

**Stop conditions / non-goals:** no `BranchF`, no `apo/para/histo/futu`, no Euclidean apex, no type-level general-`b`, no profinite type. If a second honest consumer for any unused scheme appears later, revisit — until then they stay out.
