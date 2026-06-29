# SKI as Expand/Contract: Reconciling the Combinator Reading with the Pyramid

## 1. Header

This is a **base-only exploration note**. Nothing here is wired into `cabal`, `Map.hs`, or `gate.sh`. The referenced reducer (`spec/exploration/GifSki.hs`) is `runghc`-only and is connected to the production octree code (`octantSynthesize`, `octantDistill`, `predictDetail`) by **argument, not by code**. Treat every cross-module identification below as a claim to be discharged by a runnable law, not as a shipped fact. The build plan in Section 7 says which laws to write first. No em-dashes are used anywhere in this document.

This note exists to **correct** the prior digest, whose skeptic ruled SKI "FORCED / notation not power." That verdict attacked a weak claim (octree band-rewriting as a confluent rewrite system) and missed the strong one. The strong reading is reconstructed here, steelmanned, and then honestly graded.

---

## 2. The reconciliation (lead)

The prior digest's error was treating "S is forbidden because a bijection cannot duplicate" as a refutation of the whole SKI reading. It is not. It is the **boundary condition that makes the reading precise**.

State it plainly:

- **K = contract / pool DOWN.** `K x y = x` keeps the first argument and **discards** the second. The exact referent is `scalarCollapseLossy = ocCoarse . liftOct` (`OctreeCell.hs:235-236`): it keeps the coarse DC value and throws away the 7 detail bands. This is a literal, syntactic projection of a pair onto its first component. The ladder form is `octantDistill` (`:302-307`).
- **I = the reversible held rung.** `I x = x`. The referent is `unliftOct . liftOct == id` (`lawOctReversible`, `OctreeCell.hs:203`) and its degenerate synth `octantSynthesize (coarse, []) = coarse` (`:312`). Nothing is created, nothing is lost. The 16->64 *Held* replay (`lawWithinCaptureExact`) is this rung at pyramid scale.
- **S = expand / invent UP.** `S f g x = f x (g x)` **duplicates** `x`, feeding one input to two consumers and keeping a copy. The referent is the **Invented arm** of `reconstruct256` (`SelfSimilarReconstruct.hs:140-145`) and, at term level, `liftKeyed book coarse = octantSynthesize (coarse, [map (residualFor book) coarse])` (`PairedResidual.hs:90`), where the single `coarse` value is consumed **twice**: once as the retained anchor, once as the argument to `residualFor` that manufactures the 7 detail bands.

The key sentence the prior digest missed:

> **S is forbidden ONLY on the reversible floor, and S is exactly the INVENTION operator on the up-rung.**

This is not a dodge. It is the **substructural-logic grading**, which is textbook and load-bearing:

| Fragment | Structural rule added | Property | Pyramid layer |
|---|---|---|---|
| **BCI** (linear) | none | every input used exactly once = **bijection** | the byte-exact floor (`lawOctantLadderBijective`) |
| **BCK** (affine) | **K = weakening** (may discard) | non-injective downward | the pool-down (`scalarCollapseLossy`) |
| full **SKI** | **S = contraction** (may duplicate) | non-injective upward, creates information | the super-res surplus (`lawBeyondCaptureInvented`) |

Linearity **equals** reversibility is a theorem, not an analogy. The floor terms `liftOct` / `unliftOct` use each of their eight inputs exactly once (verified at the variable level: `liftQuad`, `sLift` neither duplicate nor drop a variable). A term that uses each hypothesis exactly once lies in BCI, and BCI **excludes** both weakening and contraction. So "S is barred on the floor" is **derived** from "the floor is a bijection," not asserted by fiat. The two non-injectivities point in opposite directions: K loses going down, S creates going up, and the structural-rule grading is precisely what distinguishes them. A pure-notation mapping could not do that.

`DetailSource` (`SelfSimilarReconstruct.hs:79-89`) types this seam directly in the existing code: `Held` = linear replay (I, no information), `Invented` = contraction (S, information created). The reconciliation is already half-typed in the repo.

---

## 3. The expand-then-contract pyramid as a combinator term

The owner's chain is `64^3 -> 32^3 (latent) -> 16^3 (real GIF) + residuals`. The code spine is its mirror, `16^3 -> 64^3 -> 256^3` going up. These are the **same ladder read in two directions**: the owner's `64 -> 32 -> 16` is the **contract/K leg** (capture, pool down to the real GIF, retaining residuals in a side channel); the code's `16 -> 64 -> 256` is the **expand/S leg** (replay then invent).

A **rung is the operator applied twice**: `levelsPerStep = levelsBetween 64 16 = 2` octree levels (`SelfSimilarReconstruct.hs:149-150`, `lawLadderSelfSimilar`). Each octree level is x2 linear / x8 volume via `liftOct`/`unliftOct`; a rung is x4 linear. **Twiceness = two levels of abstraction**: one rung composes two single-level steps, and `lawLadderSelfSimilar` proves `levelsBetween 64 16 == levelsBetween 256 64 == 2`, so **one** octant operator covers both rung steps (`16:64 :: 64:256`), differing only in `DetailSource`.

The whole pipeline is the hylomorphism named in `OctreeCell.lawOctantBuildFlattenIsHylo`:

```
pyramid  =  ana(S-step) . cata(K-step)              -- contract DOWN, then invent UP
K-step (down, one octree level) = octantStep = unzip [ (ocCoarse b, ocDetail b) ]   -- :296-297
S-step (up,   one octree level) = \co de -> unliftOct (OctBand co de)                -- inside octantSynthesize, :315
rung   = step . step                                -- twiceness, levelsPerStep = 2
```

`octantDistill d` is `K-step` iterated `d` times; `octantSynthesize` is `S-step` iterated back. The owner's `+ residuals` is exactly the `[[Detail]]` side channel that `octantDistill` retains. That side channel is what upgrades a **lossy K** (`scalarCollapseLossy`, genuine weakening) into a **reversible K-with-a-receipt** (`octantDistill`, pools but keeps the discarded part). Canonical choice: **the lossy `scalarCollapseLossy` is "the" K** (true weakening); `octantDistill` is "K-with-a-receipt" (affine made reversible by carrying the discarded detail).

The role assignment per layer:

| Layer transition | Direction | Operator | Combinator | Information |
|---|---|---|---|---|
| 64^3 -> 32^3 -> 16^3 | down (capture/pool) | `octantDistill` (K-with-receipt) / `scalarCollapseLossy` (pure K) | **K** | retained in side channel / discarded |
| 16^3 -> 64^3 | up, Held replay | `octantLift cube16 heldDetail` | **I** | none created (`lawWithinCaptureExact`) |
| 64^3 -> 256^3 | up, Invented | `octantLift cube64 (tailToDetail tail)` | **S** | net-new surplus (`lawBeyondCaptureInvented`) |

---

## 4. SKI-as-compute = train-long

The forward pass is `reconstruct256 r = octantLift (refine d (base16 r)) (tailToDetail tail)`, which is literally `f (g x)` = the **B combinator**, already built and proven in `GifSki.hs`:

```
b = S # (K # S) # K            -- B f g x = f (g x), GifSki.hs:109
lawComposition                 -- nf (b#f#g#x) == nf (f#(g#x)), GifSki.hs:167  (GREEN)
```

So `reconstruct256 == B refineInvented refineHeld base16` as a **denotational** reading. Expanding `B f g x` to `f (g x)` is four `step` reductions; one *ponder* step is one rung's redex firing.

**Halting = reduction depth.** `ScalePonder.applyPonder (refineAll n)` keeps every band and round-trips to the exact cube (`lawRefineAllIsLossless`): **full reduction to normal form = the byte-exact floor.** A halted scale replaces its band with `zero7` (leaves a redex **unfired**), a budgeted cutoff short of normal form. `PonderHaltDistribution.expectedSteps = sum n*p_n` is then literally expected reduction length, with `p_n = lambda_n * prod_{j<n}(1-lambda_j)` (a proper distribution, `lawHaltIsProperDistribution`), and `lawLowerHaltRefinesMore` says more painted budget = lower lambda = more steps. `lawPonderExceedsScalarHalt` proves the per-scale mask reaches shapes (`[True,False,True]`) no single stop-depth can reach. The variable-length forward pass has a real witness.

**Fixpoint / recursion.** `Recursion.hs` supplies `Fix`/`cata`/`ana`/`hylo`; the lift is an `ana`, the collapse a `cata`, the round-trip codec a `hylo` (`lawOctantBuildFlattenIsHylo`, `lawHyloFusesCataAna`, both GREEN, depth-bounded). The refinement spine is `iterate octantLift`, and `octantLift` is the **same** function at every rung (source-agnostic, `lawSameOperatorBothRungs`).

**Honest accounting of gain vs re-description:**

- **Genuine architectural gain (NOT just PonderNet):** weight-tying. `lawSameOperatorBothRungs` proves `octantLift coarse (Held det) == octantLift coarse (Invented det)` is the identical function. One operator covers both rungs, so **parameter count is depth-independent**: a longer run trains one operator against deeper targets (a curriculum), and you can add `256^3 -> 1024^3` with **zero new parameters**. A fixed-depth net does not have this. The fixpoint/`iterate` reading is what *names* why depth is free.
- **Re-description (no gain over PonderNet):** mapping `expectedSteps` onto "reduction length" adds nothing PonderNet does not already have. `haltDist` is contract-only (consumed only by `Map.hs`). The phrase "SKI is Turing-complete so train arbitrarily long" is **FALSE as stated**: `Recursion.hs` deliberately omits `fix`/`Y` (anti-jargon header), depth is bounded (`d <= 5`), and `Ponder` is a finite `[Bool]`. The realised object is **bounded adaptive depth with a shared operator**, not an open-ended fixpoint. Scope the claim there and drop the Y-combinator framing.
- **Provenance gap:** the 5h +59.6% surplus is `DetailPredictor` improving. It shows "train long helps," not that the **cause** is weight-sharing rather than ordinary SGD on one head. The tied-vs-untied ablation (Section 7) is the discriminating test.

---

## 5. The SKI <-> (R,G,B,x,y,t) dictionary

The substrate is already 3+3-typed: `P6{p6L,p6A,p6B,p6X,p6Y,p6T}` (`RelationalResidual.hs:35-38`), with `phi6` the involution `L<->t, a<->x, b<->y` (`lawPhi6Involution`), pinned as the colour-axis <-> position-axis binding by `lawPhi6PairsColourWithPosition`. The render term is a real combinator: `render = b # paletteK # indexI`, and per voxel:

```
render position
  = B palette index position
  = palette (index position)     -- lawComposition (GREEN)
  = palette position             -- index = I
  = colour                       -- paletteK = K colour, lawRenderLooksUpColour (GREEN)
```

The honest 6-row table. The load-bearing structure is **NOT** R/G/B <-> S/K/I one-to-one. It is **three phi6 pairs <-> {one distinguished carrier (I) + two symmetric search lanes}**:

| axis | phi6 partner | carrier/search (`isUniversal`) | combinator role | earns it? |
|---|---|---|---|---|
| luma / (1,1,1) balance axis (L-slot) | t | carrier (held DC lane) | **I** (reversible held value) | **YES** (triple-agreement below) |
| t (render/time term) | L | carrier | **I** (rides with its carrier) | YES, as carrier's partner |
| chroma-1 (a-slot, Eisenstein Re) | x | search (emitted residual) | S-lane (invention lives here) | partial |
| x | chroma-1 | search | argument distributed in S | partial |
| chroma-2 (b-slot, Eisenstein Im) | y | search (emitted residual) | S-lane | partial |
| y | chroma-2 | search | argument distributed in S | partial |

**Is 3-colour/3-primitive structural or coincidence?** Mostly coincidence at the one-to-one level, but with **one genuinely structural agreement**:

- **REAL (the single best find): the luma = kernel = carrier = I triple-agreement.** Three independent derivations land on the same `(1,1,1)` axis. (a) The Eisenstein map R->1, G->omega, B->omega^2 has the syzygy `1+omega+omega^2 = 0`, so gray `(1,1,1)` is the **kernel** of the chroma map (V2-PLAN, skeptic-confirmed). (b) `lawCarriersAreLandT` pins `{L,t}` as the held-out DC carrier. (c) The byte-exact floor `octantSynthesize(coarse,[]) = coarse` is the identity passthrough = the I role (`lawIisSKK`: I = SKK). Three different algebraic facts, one axis. That convergence is structural.
- **REAL: the value/argument asymmetry.** `lawPositionDistinguishesSameColour` (`RelationalMemory.hs:134`) proves two voxels with equal `(L,a,b)` but different `(x,y,t)` are invisible to `dColour` yet distinct under `d6`. Position carries information colour cannot. That directionality is exactly what S and K presuppose, and it is a theorem.
- **FORCED (drop these):** R->S, G->K, B->I one-to-one (no axiom forces Red to duplicate or Green to discard); the `(a,x)` = S vs `(b,y)` = K split (the two search pairs have identical `isSearch` status, nothing breaks their symmetry); and phi6-as-render-symmetry **dies** under the V2 Eisenstein rebase (square Z[i] is D4 order 8, hexagonal A2 is D6 order 12, not isometric, so phi6 survives only as a bookkeeping set-involution, not an automorphism of render). A literal R,G,B-in-slots rebase also **mis-seats the carrier** on Red instead of luma. The rebase only works in a **luma + 2 chroma** Eisenstein basis.
- **SUGGESTIVE: the "2 generators + 1 dependent" rhyme.** SKI = {S,K} with I = SKK; Eisenstein = {1, omega} with omega^2 = -1-omega. Same rank-2 shape, but I=SKK is a reduction/derivation while 1+omega+omega^2=0 is an additive syzygy. A rhyme, not an isomorphism.

---

## 6. Honest verdicts

**Thesis 1 (S=expand / K=contract = the pyramid): REAL, with one SUGGESTIVE arm to promote.**
- I = `unliftOct . liftOct` bijection: **REAL** (`lawOctantLadderBijective`, syntactically variable-linear, stronger than the prose).
- K = `scalarCollapseLossy` weakening: **REAL** (literally drops `ocDetail`).
- Linearity = reversibility, so S barred on the floor by structure not fiat: **REAL** (BCI excludes contraction; the floor terms are BCI-shaped at the variable level).
- The genuine `S f g x` duplication: **REAL, but located in `liftKeyed`/`pairedLift`** (`PairedResidual.hs:90`), where `coarse` is the sole input appearing twice, **NOT** in `octantLift cube det` (which is linear in two independent inputs). **Promotion condition:** re-point the keystone's S arm from `octantLift` to `liftKeyed book coarse`.

**Thesis 2 (SKI-as-compute = train-long): GO-WITH-CONDITION.**
- B-composition of the two rungs, refineHeld = I, refineInvented = S, full reduction = floor: all **REAL** (`lawComposition`, `lawWithinCaptureExact`, `lawBeyondCaptureInvented`, `lawRefineAllIsLossless`).
- "Same operator twice, weight-tied across both spine rungs": **SUGGESTIVE.** The spine as built uses `refine` for step1 and `octantLift` for step2 (two different wrappers); the shared body is `octantSynthesize`, one level below where the claim is stated. **Promotion condition:** prove `lawRefineFactorsThroughOctantLift` (that `refine` factors through `octantLift`). Until then "same operator" is a near-miss, and the builder's own draft keystone clause `octantLift cube16 heldBands == refine ...` will NOT hold as written. Fix the lemma before the keystone.
- "Unbounded reduction / Turing-complete": **FORCED as stated**, correctly self-demoted. Scope to bounded adaptive depth.
- "+59.6% proves weight-sharing is why": **SUGGESTIVE.** Needs the tied-vs-untied ablation.

**Thesis 3 (SKI <-> 6-axis dictionary): GO-WITH-CONDITION.**
- render = B(palette,index), value/argument asymmetry, luma=kernel=carrier=I triple-agreement: **REAL** (the spine survives).
- R/G/B <-> S/K/I one-to-one, (a,x)-vs-(b,y) split, phi6-as-render-symmetry under V2: **FORCED**, drop them. The honest shape is "three phi6 pairs, one carrier (I) + two symmetric search lanes."
- The proposed `lawRenderAsymmetry`: **BROKEN as written.** Conjunct (4) `nf(render # colour) /= nf(render # position)` evaluates to **False**, because `paletteK = K colour` is constant and discards its argument, so both sides reduce to `K K`. The K-flatness conjunct (2) destroys the asymmetry conjunct (4). **Promotion condition:** rebuild with a genuine 2-entry palette + non-trivial index (a Church-pair selector `tbl = \slot -> slot c0 c1`) so render is position-sensitive: then conjunct (4) is True (asymmetry positive) while phi6-non-automorphism stays negative. The single palette cell stays K (locally constant), but global render is not constant in position.

---

## 7. Build plan (runnable exploration files, sequenced)

All files are `spec/exploration/`, base-only, `runghc`, NOT in cabal/Map/gate until promotion is decided.

**File 1 (write FIRST): `spec/exploration/V2SkiExpandContract.hs`, the structural trichotomy.**
Keystone `lawStructuralTrichotomy`: a fan-out census separating the three structural classes.
- I (linear/BCI): `unliftOct (liftOct v8) == v8` (each input used once).
- K (weakening/BCK): two distinct octants with the same coarse collapse equal under `scalarCollapseLossy` while the inputs differ (info discarded).
- S (contraction/full SKI): drive `liftKeyed book coarse` where `det = map (residualFor book) coarse` (the literal `g x`), assert (a) `coarse` feeds both the synthesize slot and `residualFor`, and (b) fan-out >= 2 children move AND output /= floor.
This is the **corrected** keystone: the S arm tests `liftKeyed` (real duplication), not `octantLift` (linear in two inputs). It bears teeth: fails if the floor stops being a bijection, if `scalarCollapseLossy` became injective, or if invention had fan-out < 1. Delegates to existing `OctreeCell` + `SelfSimilarReconstruct` + `PairedResidual` functions only.

**File 2: extend `spec/exploration/GifSki.hs`, the corrected render asymmetry.**
Keystone `lawRenderAsymmetry'` (rebuilt): 2-entry palette `tbl = \slot -> slot c0 c1`, non-trivial `index` sending `position` and `colour` to different slots. Assert: (1) `render # position == c0`, (2) a single palette cell is K (constant in slot), (3) carrier = I (`S#K#K#colour == colour`), (4) **TEETH** `nf(render # colour) /= nf(render # position)` now genuinely True. Witnesses the value/argument asymmetry positively and phi6-non-automorphism negatively in one law.

**File 3: `Properties.SelfSimilarReconstruct` lemma `lawRefineFactorsThroughOctantLift`.**
Prove `refine d sp == octantLift (coarse-of sp) (held-bands-of sp)`. This converts step1 and step2 of the spine into the **literal same operator**, making weight-tying (depth-independent params, add-a-rung-free) a theorem rather than a near-miss. ONLY after this is green, write the forward-pass keystone `lawForwardPassIsSharedOperatorComposition` on top of it. This is the **decisive next step** for Thesis 2; the builder's draft keystone fails without it.

**File 4 (experiment, trainer-side): tied-vs-untied ablation on `DetailPredictor`.**
Tied = one `octantLift`/`predictDetail` body weight-shared across `16->64` and `64->256`. Untied = two independent bodies (double params). Run both to 5h. Keystone metric: `surplus_tied(5h) >= surplus_untied(5h)` at half params. If tied loses, demote the fixpoint/weight-sharing framing to "suggestive" alongside the decorative palette=K/index=S story. Targets `trainer/` against `DetailPredictor.predictDetail`/`predictorUpdate`.

**Promotion to Tier-0:** File 3 (`lawRefineFactorsThroughOctantLift`) is the only one that **should** promote to Tier-0 if green: it is a genuine statement about the production spine (weight-tying), not about the decorative reducer. Files 1 and 2 stay exploration (they prove the substructural reading but rest on `GifSki`'s unwired `Comb`/`step`). File 4 is a measurement, not a law. Do not promote any combinator-naming law that depends on the unwired reducer until a typed homomorphism from `Comb` into the operator algebra exists.

---

## 8. Open questions for the owner

1. **Canonical K referent.** Lock the lossy `scalarCollapseLossy` (genuine weakening, matches `K x y = x` exactly) as "the" K, with `octantDistill` named "K-with-a-receipt" (reversible affine pool)? The substructural story needs the lossy one; the reversible pipeline uses the lossless one. Confirm the split.

2. **Which "S"?** There are three S candidates in one neighbourhood: the Haar lift `sLift`/`sUnlift` (the only thing literally named an S-transform, but reversible hence BCI), the dimensional `unliftOct` (1->8, linear), and the super-res invention (`liftKeyed` duplication + the Invented arm). The honest thesis wants **S = contraction = invention** (`liftKeyed` + Invented arm), NOT the Haar lift and NOT `octantSynthesize` as a whole. Bless this, or specify otherwise.

3. **Split the overloaded S.** Should we formally separate `S_dup` (reversible channel-duplication, the `f x (g x)` retained anchor in `liftKeyed`) from `S_inv` (non-reversible scale-invention, `lawBeyondCaptureInvented`)? They are two operators wearing one S. Only `S_inv` may sit on the search lanes, never on the carrier.

4. **Direction of the pyramid.** The prompt frames `64 -> 32 -> 16` (down/contract); the code spine is `16 -> 64 -> 256` (up/expand), rung = 2 octree levels, with `32^3`/`128^3` as single-level mid-rungs. Confirm that "down = K = capture/pool, up = S/I = replay+invent" is the intended reading, and that the owner's `32^3` latent is the mid-rung of the contract leg.

5. **V2 carrier seat.** Under the V2 (R,G,B,x,y,t) rebase, the universal/I carrier must be **luma = the (1,1,1) balance axis**, which is no single primary. Confirm we synthesize a luma carrier slot (Eisenstein basis: luma + 2 chroma) rather than seating I on Red. The phi6 ring-exchange does NOT survive Eisenstein (D4 vs D6), so phi6 is bookkeeping only; confirm we keep it only as a set-involution label.

6. **"Train long" scope.** Accept the honest scope "bounded adaptive depth with a shared operator, contraction-count as the depth metric," and drop the Y-combinator / unbounded-reduction framing? Or is building a real `fix` whose reduction length is provably the refinement count worth the effort?

7. **Wire or stay decorative?** Should `GifSki`'s `Comb`/`step`/`nf` reducer be wired (prove `liftKeyed` is the image of the S-term under a typed homomorphism into the operator algebra), or left explicitly decorative with the substructural claims standing on their own (which they do, since they do not depend on the reducer)?