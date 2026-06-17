# SixFour — Genome A/B Pivot: capture → A/B → export-family (UI/UX + core workflow)

> Keywords: one-surface taste camera, genome-orthogonal A/B pair, Bradley-Terry θ taste
> vector, σ-pair reversibility, band-disjoint Haar-coefficient orthogonality, genome-in-GIF
> S4GN carrier, Export Family {16³,64³,256³}, Spec.ABSurface 8-phase FSM, coordinated cut.

> **One sentence:** you shoot a burst, the app renders the deterministic native 64³ GIF (the
> reference rung) and your *own* on-device look-genome proposes **two** competing,
> genome-orthogonal, RGBT-valid 16³ candidates; you A/B-pick the one you like (a Bradley-Terry
> comparison that updates YOUR genome, no server), and one **Export Family** action emits
> {16³, 64³, 256³} rungs with your genome embedded inside a standards-compliant GIF89a block so a
> receiver can pull it out and seed their own taste.

**Status:** design + spec-first build plan (2026-06-16). Companion to `SIXFOUR-DISPLAY-FSM.md`
(the FSM `M=(Σ,ι,δ,λ,Π,κ)` whose **clock half** we import verbatim), `SIXFOUR-ACTS-WORKFLOW.md`
(the five-acts surface this *collapses*), `SIXFOUR-LOOK-LUT-WORKFLOW.md` and
`SIXFOUR-RGBT4D-REMAINING-WORKFLOW.md` (the lift/ladder primitives we compose). SixFour owns all
code; the Haskell spec is the source of truth, codegen-pinned. Nothing here is built yet — this
is the sequenced plan. Per the camera-app rule, the bar is **BUILD SUCCEEDED** + green gates;
on-device look/A/B legibility is the user's verification step.

---

## 0. North star (the one surface, restated)

SixFour becomes a **one-surface taste camera**. The whole multi-phase Surface — browse, refine,
palette explorers (cloud/tree/grid), movable widgets, voxel tools, the 5-stage render FSM —
**collapses to three moves**: capture → A/B → export.

```
   shoot burst ──▶ 64³ reference GIF (deterministic, native)
                        │  base genome g0
                        ▼
        GenomePair: TWO genome-orthogonal, RGBT-valid 16³ candidates (δ_A, δ_B)
                        │
              you tap one  ──▶  Bradley-Terry .compare  ──▶  YOUR θ updates on-device
                        ▼
        Export Family: {16³, 64³, 256³} of the chosen genome via the reversible R operator
                        │
              every exported GIF carries your genome in a GIF89a App-Extension (S4GN)
                        ▼
            a receiver extracts it and seeds/blends it into THEIR taste (one logged .compare)
```

**The keystone** is the orthogonal-yet-reversible genome PAIR. Two properties, kept strictly
apart:

- **Validity is free and unconditional.** Any displacement δ keeps σ-pair symmetry, so both
  candidates reconstruct exactly (`lawSigmaOverridePreservesSymmetry`, reused). Reversibility is
  stated *per candidate*, never coupled to orthogonality.
- **Orthogonality is by construction**, achieved by **band-DISJOINT codebook support in the
  384-D Haar-COEFFICIENT genome space** — the one space the move basis (`DeltaCodebook.Move`)
  actually edits. Disjoint support gives an **exact 0 inner product**, never a post-hoc
  Gram-Schmidt over a non-orthogonal reconstruction, never an ε on the shipped path.

These two facts are why the pivot is provable rather than hand-wavy. The rest of the doc is the
machinery that makes them ship.

---

## 1. The new loop (FSM): `Spec.ABSurface`

`Spec.ABSurface` replaces **ONLY the phase-FSM half** of `Spec.Display`. The **clock half**
(T1–T9, 20 fps κ, `projGif`/`projPalette`/`projShutter`, the `Lattice` atom) is imported
**unchanged**. We are not re-deriving the clock; we are swapping the phase graph that rides on it.

### Phases (8) and events (11)

```
Phases:  Bootstrap | Unauthorized | Live | Captured | Picked | Exporting | Done | Error
Events:  SessionReady | AuthDenied | ShutterTap | LockComplete | BurstComplete
         | PickA | PickB | ExportFamily | ExportDone | Retake | Fault
```

### δ — total, catch-all self-loop

```
 Bootstrap × SessionReady   → Live
 Bootstrap × AuthDenied     → Unauthorized
 Live      × ShutterTap     → Live            -- lock+burst are INTERNAL to Live (camera freezes),
                                                 NOT visible sub-phases (resolves the locking question)
 Live      × BurstComplete  → Captured
 Captured  × PickA          → Picked
 Captured  × PickB          → Picked
 Picked    × ExportFamily   → Exporting
 Exporting × ExportDone     → Done
 Done      × Retake         → Live
 Captured  × Retake         → Live            -- bail before picking
 Picked    × Retake         → Live            -- bail mid-A/B (allowed)
 Error     × Retake         → Bootstrap
 _         × Fault          → Error
 (every other (phase,event)) → self-loop
```

`LockComplete` exists in the alphabet but is consumed inside `Live` (the lock+burst sequence is
an internal Live affair); it never appears as its own phase. This is the deliberate resolution of
the "do we model locking as a sub-phase?" question — **no**, the camera-freeze is internal to Live.

### Golden happy path

```
events: [SessionReady, ShutterTap, BurstComplete, PickA, ExportFamily, ExportDone, Retake]
trace : [Bootstrap, Live, Live, Captured, Picked, Exporting, Done, Live]
```

(`scanl abStep Bootstrap goldenABHappyPath == goldenABPhaseTrace`.)

### The Captured A/B screen (one committed coordinate set)

On the 100×218 4 pt lattice, `Captured` is a **static 3-pane** configuration, fed once through
`Spec.GridLayout`'s contention proof (`lawABCellGrid`):

| Region | Cells | Cols | Notes |
|---|---|---|---|
| 64³ reference **HERO** | 64×64 | 18–81, top band | rendered through the **BASE genome g0 GLOBAL table** (NOT per-frame palettes) so preview ≡ ship |
| candidate **A** tile | 16×16 | 16–31 | `PickA` |
| candidate **B** tile | 16×16 | 68–83 | `PickB` |

A and B are symmetric about centre col 50 with a 36-col gutter. **Tapping a tile IS the pick**
(`PickA`/`PickB` → logged BT `.compare`). In `Picked`, a ≥11-cell `CellActionButton` "Export
Family" fires `ExportFamily`. All regions are disjoint cell rectangles.

### The gauge discipline (unchanged law)

Out-of-band Σ carries `indexCube`, `palettesForDisplay`, `candidateA`/`candidateB` genomes,
`renderProgress`. **The event alphabet never carries genome bytes** — so the BT winner is
recoverable from the event token (`PickA`/`PickB`) alone. This is what keeps `abStep` a small
total function and keeps the local ordered log replayable.

**`Spec.ABSurface` laws:** `lawABPhaseTotal`, `lawABNoOrphan`, `lawABReachable` (BOTH `PickA`
and `PickB` are live edges out of `Captured`, both land in `Picked`), `lawExportGatedOnPick`
(`Exporting` entered ONLY from `Picked` via `ExportFamily`), `lawDoneExplicit` (`Done` only via
`ExportDone`), `lawABCellGrid`, `lawABGoldenTrace`.

---

## 2. The spec layer (Haskell source of truth, codegen-pinned)

Six modules. **`Spec.GenomePair` is the keystone**; everything else is orchestration over
already-verified primitives.

### 2.1 `SixFour.Spec.GenomePair` — KEYSTONE

Two distinct, genome-orthogonal, RGBT-valid σ-pair displacements `(δ_A, δ_B)` from a capture's
base genome `g0`. Validity is free; orthogonality is by band-disjoint support in the 384-D Haar
coefficient space — the space the move basis edits — giving exact 0 inner product.

Key types:
```haskell
type GenomeDisplacement = SigmaOverride            -- generator-space, Q16, σ-locked (reused)
type GenomePair         = (GenomeDisplacement, GenomeDisplacement)
type BandWeights        = [Double]                 -- per-Haar-level, ALL STRICTLY > 0
type SubBandSupport     = Set Int                  -- Haar coeff levels each δ occupies (PALETTE space only)

genomeInner :: BandWeights -> GenomeDisplacement -> GenomeDisplacement -> Double
  -- defined on the 384-D flattenHaar COEFFICIENT vector — same space as the move basis

sampleOrthogonalPair :: HaarPaletteI -> Ranking -> GenomePair
  -- δ_A = highest-ranked move on band-set S_A; δ_B = highest-ranked move on DISJOINT band-set S_B
```

`SubBandSupport` is **palette-space only** — there is NO claimed correspondence to spatial RGBT
LL/LH/HL/HH (see decision ledger §4, Q3).

Laws:
- `lawWeightsPositiveDefinite` — all `w_band > 0`, **golden-pinned constant (NOT a tunable)** ⇒
  `genomeInner` is a true inner product.
- `lawPairOrthogonalExact` — `genomeInner w δ_A δ_B == 0` **EXACTLY** (band-disjoint support, exact
  Q16) — A and B are a genuine orthogonal choice.
- `lawPairDistinct` — each `‖δ‖_W ≥ minGenomeStep` AND `δ_A ≠ δ_B`.
- `lawPairValidSigma` — `applySigmaOverride δ_X g0` is σ-fixed for `X ∈ {A,B}` (reuses
  `lawSigmaOverridePreservesSymmetry`; validity is unconditional).
- `lawPairReversible` — `reconstructPairedFixed ∘ analyzePairedFixed = id` EXACTLY (Q16) on each
  candidate — stated **per-candidate**, not coupled to orthogonality.
- `lawPairDeterministic` — `sampleOrthogonalPair` is pure ⇒ identical `(δ_A,δ_B)` cross-device.
- `lawBandDisjoint` — `support(δ_A) ∩ support(δ_B) = ∅` (the construction that makes orthogonality
  exact).

Codegen: Swift `GenomePair` generator wired into `AtlasState.choose` (replaces
`perturb()`/`maximin`); Zig byte-exact via `BranchedPalette.projectQ16` override path (already
`SIMD3<Int32>`); `GenomePairGolden.swift` pinning `δ_A`/`δ_B` for a known `g0` plus the fixed
`w_band` constants.

### 2.2 `SixFour.Spec.PersonalGenome`

Per-device taste lifecycle over the **770-D Bradley-Terry θ** (linear utility over
`atlasEmbedding`). **The personal genome = the θ taste/ranking vector**, NOT the 384-DOF generator
weights. Thin orchestration over the verified `PreferenceUpdate` primitives; θ ranks candidates
and biases proposal. The `AtlasTrainer` MPSGraph MLP is retained only as an optional large-n head.

```haskell
data PersonalGenome = PersonalGenome { pgTheta :: [Double]   -- 770
                                     , pgCompares :: Int
                                     , pgVersion  :: Int }
type Pick = (Embedding, Embedding)                 -- ordered (winner, loser), both 770-D

coldStartTheta  :: PersonalGenome                  -- θ=0, n=0 ⇒ pure deterministic shapedReward floor
applyPick       :: PersonalGenome -> Pick -> PersonalGenome     -- one btUpdate, η=0.05, λ=1e-3
replay          :: PersonalGenome -> [Pick] -> PersonalGenome   -- foldl', order-dependent
scoreCandidate  :: PersonalGenome -> Embedding -> Double        -- linearUtility
personalBeta    :: Int -> Double                                -- betaBlend, reused n/(n+50)
```

Laws:
- `lawColdStartIsDeterministicFloor` — `n=0 ⇒ personalBeta=0 ⇒ value = pure shapedReward`.
- `lawThetaBounded` — `‖θ‖∞ ≤ max(‖θ₀‖∞, dmax/λ)` (reused; **NOTE the ball is large = 1000·dmax —
  bounded, not small**).
- `lawRegularizedObjectiveDecreases` — one informative pick decreases the **regularized** objective
  (BT NLL + ½λ‖θ‖²) for small η — restated for the shipped λ≠0 (the raw-loss
  `lawStepDecreasesLoss` is λ=0-only).
- `lawPickMovesPreferredDirection` — stated on the regularized-objective gap, not raw utility.
- `lawReplayDeterministic` — replay from coldStart over the LOCAL ordered log + checkpoints == θ
  (θ is a memoized fold, NOT spliced foreign state).
- `lawReplayFromCheckpoint` — replay from a checkpoint θ over the retained tail == full replay
  (enables pruning without breaking exact replay).
- `lawBetaMonotoneRamp` — `personalBeta` non-decreasing in n. **NO "convergence" claim** — SGD on
  an order-dependent non-stationary stream has no fixed point; only boundedness + local decrease.

Codegen: Swift `PersonalGenomeStore` (pure Swift/Accelerate CPU SGD — **no MPSGraph** for the
linear spine); `PreferenceGolden` pins one `btUpdate` step bit-exact vs Haskell; `DecisionLog`
extended to persist full 770-D winner/loser embeddings per `Compare` (retires
`pseudoGenome`/`.synthetic`) + checkpoint-θ-at-prune.

### 2.3 `SixFour.Spec.GenomeCarrier`

Byte codec for the genome-in-GIF **S4GN** payload: serialize the 384-DOF σ-pair genome in
`flattenHaar` order as **Int32 LE Q16** (NOT int16 — the shipped genome is `SIMD3<Int32>` with
`|L|≤65536, |a|,|b|≤26214`, which int16 overflows) + a 24-byte versioned header + CRC32, into a
GIF89a Application-Extension (`0x21 0xFF`) block. Codegen-MANDATORY into both encoders.

```haskell
data S4GNHeader = S4GNHeader
  { major :: Word8, minor :: Word8, flags :: Word16
  , dof :: Word16            -- read from header, DERIVED from NetContract.lookSigmaPairDOF, never literal
  , radix :: Word8, deviceIdHash :: Word32   -- per-install salt, optional via flags
  , btCompares :: Word32 }
type GenomePayload = (S4GNHeader, [Int32])     -- header ++ 384 × Int32 LE Q16 = 1536 bytes

encodeGenomeBlock  :: GenomePayload -> [Word8]
  -- 0x21 0xFF, 0x0B size byte, EXACTLY-11-byte id 'SIXFOUR1'+'G10', ≤255 sub-blocks, 0x00 terminator
extractGenomeBlock :: [Word8] -> Either CarrierError GenomePayload
data CarrierError = NoBlock | Corrupt | VersionMismatch    -- NoBlock distinct from Corrupt
```

Laws:
- `lawEmbedExtractRoundTrip` — `extract ∘ encode == Right id` on Int32 Q16 payloads.
- `lawGif89aValidity` — ≤255-byte sub-blocks, single `0x21 0xFF` introducer, `0x0B` before the
  11-byte id, `0x00` terminator.
- `lawCapacityFits` — `24 + 1536 + 4 = 1564` bytes → **7 sub-blocks** (6×255 + 34), bounded under
  any LSD / per-frame budget.
- `lawQ16RoundTripExact` — identity on the Int32 Q16 lattice (gated by a typed precondition that
  the chosen-genome boundary IS Q16).
- `lawCRCRejectsCorruption` — any single payload-byte flip changes crc32; covers
  `header‖payload-of-declared-length` (forward-compat appended fields live in their own
  length-tagged region or bump major).
- `lawVersionTolerance` — equal **MAJOR** + same `dof`/`radix` ⇒ yields the coeffs; mismatched
  magic/dof/CRC ⇒ `Left`, never partial.

Codegen: Zig `s4_gif_assemble` S4GN block writer + `s4_gif_extract_genome` **probe** (at the
`kernels.zig` extension-skip site, reuses `gifReadSubBlocks`, never decodes LZW frames); Swift —
either a `GIFEncoder` twin **OR (preferred) retire the Swift encoder and consolidate on Zig** so
there is a single source; golden pins exact S4GN block bytes + a full small GIF
(header+NETSCAPE+S4GN+1 frame) byte-for-byte across Swift/Zig, **and re-pins every existing
full-file golden in the SAME commit**.

### 2.4 `SixFour.Spec.GenomeBlend`

Receiver-side federated transport. An extracted foreign GENOME (384-DOF, palette space) enters as
a **logged BT A/B candidate** — NEVER a silent θ overwrite. **SINGLE mechanism** (resolves the
`blendForeign`-vs-`Compare` contradiction): adoption is always one ordered
`.compare(foreignGenomeEmbedding, personalGenomeEmbedding)`, so θ stays a pure fold of the LOCAL
ordered log and `lawReplayDeterministic` survives. Optional explicit interpolation seed via
σ-locked `applySigmaOverride`.

```haskell
type ForeignGenome = HaarPaletteI                  -- extracted, lifted to 128 generators
blendSeed   :: PersonalGenome -> ForeignGenome -> SenderCompares -> ABCandidate
trustWeight :: SenderCompares -> Int -> Double     -- receiverConfidenceWeighted (NOT sender-count-only)
blendInterp :: Double -> PersonalGenome -> ForeignGenome -> Genome  -- σ-locked, explicit opt-in only
```

Laws:
- `lawBlendIsACompare` — adopting a foreign genome emits EXACTLY one logged ordered `.compare`; no
  θ splice; replay determinism preserved.
- `lawBlendStaysSigmaSymmetric` — any seeded/interpolated genome is still σ-pair (reuses
  `lawSigmaOverridePreservesSymmetry`).
- `lawZeroTrustIsIdentity` — `senderCompares=0 ⇒ trustWeight 0 ⇒ no perturbation` (an untrained
  foreign look cannot move a receiver).
- `lawHighLocalConfidenceResistsBlend` — `trustWeight → 0` as `pgCompares` grows ⇒ a trained local
  taste resists wash-out under **repeated** blends (bounds the consensus-collapse fixed point, not
  just one step).

Codegen: Swift foreign-genome adoption wired through `AtlasState.choose` as an ordinary A/B
`Compare`; golden trust-weight + σ-symmetry preservation vectors.

### 2.5 `SixFour.Spec.ABSurface`

The 8-phase FSM of §1, replacing ONLY Display's phase-FSM half; imports Display's clock half
unchanged. Types: `ABPhase`, `ABEvent`, `abStep :: ABPhase -> ABEvent -> ABPhase` (total,
catch-all), `abPhaseName`/`abEventName` (cross-language tokens), `goldenABHappyPath`,
`goldenABPhaseTrace`. Laws as listed in §1. Codegen: re-emit `DisplayContract.swift`
phases/events/`goldenHappyPathTrace` from `ABSurface`; shrink the `PhaseField` router to the 5
product cases; `Surface.abStep` replaces `surfaceStep` with the same shape.

### 2.6 `SixFour.Spec.ExportFamily` (+ `Spec.TemporalPool`, `Spec.NetSynth256`)

The G6 orchestrator: one chosen genome → one global palette → three R-views {16³,64³,256³}, each
carrying the SAME S4GN block. Composes proven `RGBTLift` + `CubeLadder`. **Genome ⊥ R for
16³/64³** (palette factor only, preserves preview≡ship + the lossless ladder); genome touches R
ONLY via `NetSynth256` above-capture detail at 256³.

```haskell
data RungTier    = Tier16 | Tier64 | Tier256
data FamilyInput = FamilyInput { genome384 :: ..., indexCube :: ..., globalTable :: ... }
data RungProduct = RungProduct { rungSide, rungFrames, rungCube, rungPalette :: ... }
exportFamily :: FamilyInput -> ExportFamily
-- TemporalPool: temporalDistill / temporalSynthesize (time-axis S-transform)
-- NetSynth256:  genomeToSynthSeed, synthDetail (degrades to synthBeyond floor)
```

Laws:
- `lawFamilyOneGenome` — all three rungs reconstruct bit-identical palette from the one genome.
- `lawLadderConsistencyDownUp` — `distill ∘ synthesize = id` on the SPATIAL floor (EXACT, reversible
  integer wavelet — the high band carries the exact difference so floor rounding is losslessly
  undone). **16³ DECISION: 64 frames at 16² spatial (temporally lossless)** — so the down-up
  bijection is FULL, not "spatially-exact temporally-coarse".
- `lawTier64IsReference` — `fam64 = R-identity`, byte-exact.
- `lawTier256FloorIsNearestNeighbour` — with NN detail zeroed, `256³ == synthBeyond == nearest-
  neighbour replicate`.
- `lawZeroGenomeIsFloor` — `synthDetail` of zero genome == `synthBeyond` floor — proven as a single
  **golden-pinned bit-exact equality** (NOT a free generalization; if `Upscale256`'s `ExitState`
  signature can't be fed degenerately, `synthBeyond` ships as the canonical 256³ floor and
  `Upscale256` is a SEPARATE gated enhancement).
- `lawTemporalReversibleOnCarriedDetail` — EXACT on the carried 64-frame object (the shipped 16³
  keeps 64 frames, so this law is non-vacuous).
- `lawFamilyDeterministic`, `lawFamilyGamutClosed`.

Codegen: Zig — compose `s4_cube_lift_level`/`unlift` into `s4_cube_distill`/`synthesize`/
`synth_beyond` C-ABI; Swift — un-gate `RGBT4DLift` (drop `rgbt4dEnabled`); `GenomeExportFamily`
extends `LadderExport.Rung` to 3 genome-driven rungs; golden — extend `RGBT4DGolden` with
`ExportFamily`/`TemporalPool`/`NetSynth256` vectors.

---

## 3. Sequenced build order (spec-first, gate per step)

Each step ends green before the next begins. The single hardest hinge is **step 5**, the
coordinated cut — it is the one atomic change that must be fully sequenced (`s4 codegen → verify`
proven before any Swift delete).

**Step 1 — Extract `Quad4.paletteToVec`.** Move it into a neutral module (`SixFour.Spec.Palette`
or `LinAlg`) and migrate the 8 importers (`SigmaPairHead`, `LinAlg`, `Pipeline`, `SigmaPairFixed`,
`LookNetD`, `Bottleneck16`, `AxisNet`, `CloudProjection`). **Do NOT delete `Quad4.hs` yet.** This
unblocks every later genome-fixing cut.
*Reuses:* `Quad4.paletteToVec` (called by `SigmaPairHead` at lines 191, 207), all 8 importers.
*Gate:* `s4 codegen` + `s4 verify` green; `spec.cabal` exposed-modules + `Map.hs` updated; no
importer references the moved symbol's old path.

**Step 2 — `Spec.GenomePair` (keystone).** `genomeInner` on the 384-D Haar-COEFFICIENT vector
(same space as `DeltaCodebook` moves); band-DISJOINT codebook support as the PRIMARY orthogonal
constructor (exact 0 by support); `w_band` strictly positive, golden-pinned constant. Codegen
`GenomePairGolden.swift`; wire `sampleOrthogonalPair` into `AtlasState.choose` replacing
`perturb()`/`maximin`.
*Reuses:* `SigmaPairHead`, `SigmaPairFixed` (`reconstructPairedFixed` exact Q16),
`LeafOverride.applySigmaOverride`, `DeltaCodebook.moveVocab`, `BranchedPalette.projectQ16`
override path (`SIMD3<Int32>`).
*Gate:* `lawPairOrthogonalExact` + `lawPairValidSigma` + `lawPairReversible` +
`lawWeightsPositiveDefinite` green in GHCi; `GenomePairGolden` byte-exact Swift↔Haskell; iOS BUILD
SUCCEEDED (compile-only).

**Step 3 — `Spec.PersonalGenome`.** Wrap `PreferenceUpdate` into
`init`/`applyPick`/`replay`/`scoreCandidate`/checkpoint. Codegen pure-Swift `PersonalGenomeStore`
(no MPSGraph for the linear spine). Extend `DecisionLog` to persist full 770-D embeddings per
`Compare`; add checkpoint-θ-at-prune. Restate monotonicity on the regularized objective; drop
"convergence" language.
*Reuses:* `PreferenceUpdate.btUpdate`/`btPairGradient` (η=0.05, λ=1e-3),
`AtlasState.atlasEmbedding` (770), `AtlasOracle.betaBlend`, `AtlasState.choose` seam,
`AtlasTrainingSession` flywheel (run cheap CPU `applyPick` off-main).
*Gate:* `lawColdStartIsDeterministicFloor` + `lawReplayDeterministic` + `lawReplayFromCheckpoint` +
`lawRegularizedObjectiveDecreases` green; `PreferenceGolden` one-step bit-exact; iOS build green.

**Step 4 — `Spec.ABSurface`.** New module importing Display's clock half. Trim `Display.hs` export
list to clock-only. Regenerate `DisplayContract.swift`. Shrink the `PhaseField` router to 5 cases;
`abStep` replaces `surfaceStep`.
*Reuses:* `Display.hs` clock half (T1–T9, κ, `Lattice`), `Surface.assertSpecParity` discipline,
`LivePhaseField` (kept verbatim), `AtlasGalleryView` (promoted to `Captured` A/B primitive),
`CellSprite`/`CellSlider`/`CellActionButton`/`CellText`.
*Gate:* `lawABPhaseTotal`/`NoOrphan`/`Reachable`/`ExportGatedOnPick`/`DoneExplicit`/`CellGrid`/
`GoldenTrace` green; `DisplayContract` regen (never hand-edited); `Surface.assertSpecParity`
passes; `spec.cabal` + `Map.hs` consistent.

**Step 5 — COORDINATED CUT (one atomic commit).** Delete `Browsing`/`Rendering`/`Capturing`
`PhaseField`s + Review Refine drawer + movable-widget + influence-field stack + 5-stage
`RenderStage`. In the **same commit**: remove deleted modules' goldens from `assertSpecParity`,
drop the `surfaceStep` golden fold, remove modules from `spec.cabal` exposed-modules + `Map.hs`,
AND edit `scripts/verify-doc-claims.sh` (remove `ReviewPhaseField`/`MovableColorWidget`/
`MoveContract` grep targets + dependent checks, replacing each invariant anchor with its A/B
equivalent per the gate's **D2 rule**), update `docs/STATUS.md`.
*Reuses:* `Spec.GridLayout` contention proof for the committed `Captured` rectangles (hero cols
18–81, A cols 16–31, B cols 68–83).
*Gate:* `s4 all` green (the **doc gate is 2nd in gate-order — MUST pass**); `assertSpecParity`
passes; no orphaned cabal/Map entries; `DisplayContract` regen.

**Step 6 — `Spec.GenomeCarrier`.** Int32 LE Q16 (NOT int16), 1564-byte / 7-sub-block S4GN
Application-Extension. Codegen-MANDATORY block writer into Zig `s4_gif_assemble`; add
`s4_gif_extract_genome` probe; retire OR codegen-pin the Swift `GIFEncoder` twin. Re-pin every
full-file golden in the same commit. Edit `verify-doc-claims.sh` if any genome/comment-string
check is touched.
*Reuses:* `s4_gif_assemble` comment path + ≤255 chunker, `gifReadSubBlocks`, `s4_gif_decode`
extension-skip site, S4LN / `export_look_net_blob.py` container discipline, `flattenHaar` order,
`NetContract.lookSigmaPairDOF`.
*Gate:* `lawEmbedExtractRoundTrip` + `lawGif89aValidity` + `lawCapacityFits(1564)` +
`lawCRCRejectsCorruption` + `lawVersionTolerance(major.minor)` green; exact S4GN block bytes +
full-small-GIF golden byte-for-byte Swift↔Zig; existing goldens re-pinned.

**Step 7 — `Spec.GenomeBlend`.** SINGLE mechanism: extracted foreign genome → ONE logged BT
`Compare` (never θ splice). Receiver-confidence-weighted trust. Explicit "pull sender's look"
action surfaces extraction (no auto-scan). `NoBlock` vs `Corrupt` UX distinction.
*Reuses:* `GenomeCarrier.extractGenomeBlock`, `AtlasOracle.betaBlend`,
`LeafOverride.applySigmaOverride`, `AtlasState.choose`/`DecisionLog .compare`, `fed_sim` policy
(FedAvg core + β-blend cold-start).
*Gate:* `lawBlendIsACompare` + `lawBlendStaysSigmaSymmetric` + `lawZeroTrustIsIdentity` +
`lawHighLocalConfidenceResistsBlend` green; iOS build green.

**Step 8 — `Spec.ExportFamily` + `TemporalPool` + `NetSynth256`.** Compose Zig per-level lift
primitives into `s4_cube_distill`/`synthesize`/`synth_beyond`; un-gate `RGBT4DLift`. Ship 16³+64³
synchronous (lossless, 16³ = 64 frames at 16² spatial); 256³ as an explicit progress-gated/tiled
follow-on defaulting to the `synthBeyond` floor. `GenomeExportFamily` extends `LadderExport.Rung`;
all three rungs carry the S4GN block.
*Reuses:* `CubeLadder` (`distill`/`synthesize`/`synthBeyond`, `lawLadderBijective`), `RGBTLift`
(`lawLiftUnliftExact`), `RGBT4DLift` Swift port, `s4_cube_lift_level`/`unlift` Zig primitives,
`LadderExport`/`LadderGIF.encodeGlobalGIF`, `BranchedPalette.projectQ16(.b2)` seam, `Upscale256`
(gated enhancement only).
*Gate:* `lawFamilyOneGenome` + `lawLadderConsistencyDownUp` + `lawTier256FloorIsNearestNeighbour`
+ `lawZeroGenomeIsFloor` (golden-pinned equality) + `lawTemporalReversibleOnCarriedDetail` green;
`RGBT4DGolden` extended byte-exact; iOS build green.

---

## 4. What to DELETE

Deletions are **gated on the step that makes them safe** — most are dead only after the genome
spine replaces them. Two FILES (`Quad4.hs`, `Quad4Fixed.hs`) are NOT deleted even though their
radix BRANCH is, because `SigmaPairHead` still calls `Quad4.paletteToVec` and they are grep
targets in `verify-doc-claims.sh`.

| What | When safe |
|---|---|
| Quad4 4⁴/513-DOF radix BRANCH + `Quad4Nav`/`Quad4DrillView` UI + 3-way `PaletteBranching` selector + `.b16` Flat-identity branch (`BranchedPalette.swift`) | after step 1 extracts `paletteToVec` — **files `Quad4.hs`/`Quad4Fixed.hs` stay** |
| `AtlasState.perturb` (fixed ±0.04 a-axis candidate B) | after step 2 — replaced by `sampleOrthogonalPair`'s band-disjoint δ_B |
| `AtlasTrainingSession` `pseudoGenome` + `.synthetic` teacher path + saliency sweep | after step 3 persists real per-Compare embeddings |
| `DecisionLog` hash-only Compare records (FNV-1a32 `winHash`/`loseHash`) | after step 3 — replaced by full-embedding records |
| `spec/src/SixFour/Spec/Preference.hs` DPP gallery (`rbfKernel`/`greedyGallery`/`qualityGram`/`dppLogDet`) | after step 2 — A/B is exactly-2-candidate, not an N-gallery |
| `spec/src/SixFour/Spec/PaletteGesture.hs` | gesture-driven manual genome editing outside the A/B loop |
| `BrowsingPhaseField.swift` + `.selectFrame`/`.picked4` events + `surface.picks`/`togglePick`/`scrubCursor` + Continue-exactly-4 gate | **COORDINATED step 5** — replaced by Captured A/B |
| `RenderingPhaseField.swift` + `CapturingPhaseField` serpentine sweep + `SurfacePhase.RenderStage` + `stageDone:*` events | **step 5** — collapse to one Exporting phase |
| `ReviewPhaseField.swift` Refine drawer (cut-lever/`BranchingSelector`, motion/`QuartetDelta`, group-pick, LUT-in-refine, Atlas button, ~400 LOC) — keep only Ship/export + Retake spine | **COORDINATED step 5** (grep target — gate must be edited) |
| Movable-widget + influence-field stack (`MovableColorWidget.swift`, `MoveContract.swift`, `Spec.MovableLayout`, `InfluenceField`/`StageField`/`FieldMetalView`, `InfluenceFieldGolden`, `FieldTuningContract`) | **COORDINATED step 5** (`MovableColorWidget.swift` + `MoveContract.swift` are grep targets; goldens in `assertSpecParity`) |
| Orphaned palette explorers (`PaletteCloudView`, `PaletteTreeView`, `PaletteGridView`, `ContestedCellGridView`, `PixelGrid`, `CellOwnershipOverlay`) + dead chrome (`GlassControls`, `HaarShutterView`, `GridlineField`, `DemoScene`) | **step 5** — zero live-path callers |
| `SettingsPhaseField` sampler drawer + Settings phase + `openSettings`/`closeSettings` — drop or shrink to a tiny inline menu after auditing load-bearing toggles (e.g. `useDeterministicCore`) | **step 5** |
| `LadderGIF.workingCopy`/`spatialDownsample`/`temporalSubsample` (naive 64→16) + `SixFourExport.replicate(factor:4)` 256² + stale 5-rung doc-claim | **step 8** — superseded by lossless distill + ExportFamily |
| `AppSettings.rgbt4dEnabled` flag gate | **step 8** — `RGBT4DLift` becomes a live consumer |

---

## 5. Decision ledger (owner-call flags ⚑)

Each row is a settled recommendation; the ⚑ ones are owner-call decisions that change the math or
the blast radius. The recommendations below are what this plan builds against.

**Q1 — In WHICH space are the two A/B candidates orthogonal?** ⚑ KEYSTONE
*Recommendation:* the 384-D Haar-COEFFICIENT genome vector (`flattenHaar` order) — the SAME space
`DeltaCodebook.Move` edits — using band-DISJOINT support, **not** Gram-Schmidt over reconstructed
generators.
*Why:* `genomeInner`-on-reconstructed-generators and the codebook-move-basis live in DIFFERENT
vector spaces related by a non-orthogonal, per-level-scaled Haar reconstruction, so orthogonality
in one is not orthogonality in the other and `lawPairOrthogonal` is not type-correct. Defining the
metric on the coefficient vector makes metric and move basis share one space; σ-validity is
automatic there too.

**Q2 — How is exact orthogonality achieved given Q16 lattice snapping?** ⚑
*Recommendation:* band-DISJOINT codebook support as the PRIMARY constructor (exact 0 dot,
deterministic). Gram-Schmidt is a non-shipped diagnostic only.
*Why:* snapping a GS-orthogonalized δ_B to the coarse codebook lattice generically destroys the
zero dot product. The two recipes are mutually exclusive at exact-zero. Band-disjointness gives
exact orthogonality by construction with no GS, no ε.

**Q3 — Do the 4 "sub-band axes LL/LH/HL/HH" couple the genome to the spatial RGBT lift?** ⚑
*Recommendation:* **NO.** "Respect the 4 sub-band axes" means band-disjoint support in the 1-D
PALETTE Haar ONLY. The genome is the palette factor; R/RGBT-spatial-lift is the index factor; they
are orthogonal (`lawExportLiftUntouched` is right).
*Why:* there is no isomorphism between a 1-D palette Haar (1 detail family/level) and a 2-D spatial
Haar (3 detail families/level); the `bandOf` map would be an arbitrary relabel with zero RGBT
content. Only decoupling is provable.

**Q4 — What IS the trained personal genome?** ⚑
*Recommendation:* the 770-D Bradley-Terry θ taste/ranking vector over σ-pair leaf embeddings.
`AtlasTrainer`'s MPSGraph MLP is retained as an OPTIONAL large-n value head only. Do NOT on-device
fine-tune the 384-DOF generator weights.
*Why:* θ is the only learned per-user state with a VERIFIED update step (`PreferenceUpdate`), is
~3 KB and trainable with dependency-free CPU SGD, and directly ranks/biases proposal. Training the
generator weights is a heavier object with no verified step.

**Q5 — Federated transport: blend foreign θ (convex) or adopt foreign genome (logged Compare)?** ⚑
*Recommendation:* SINGLE mechanism — the GIF carries the GENOME (384-DOF palette space); adoption
is ALWAYS one ordered logged BT `.compare`. Delete `blendForeign`-as-θ-convex-blend.
*Why:* a convex θ splice makes θ un-reproducible from coldStart + local ordered log (violates
`lawReplayDeterministic`); and blending θ (770-D) vs genome (384-DOF) under one name blends
different objects. Compare-over-genome keeps θ a pure fold.

**Q6 — GIF carrier element type: int16 or Int32 Q16?** ⚑
*Recommendation:* Int32 LE Q16, 1536-byte payload, 1564 total, 7 sub-blocks. Re-derive
`lawCapacityFits`.
*Why:* the shipped genome is `SIMD3<Int32>` with `|L|≤65536, |a|,|b|≤26214`, generators ~74k —
int16 (max 32767) silently truncates and breaks `lawEmbedExtractRoundTrip`/`lawQ16RoundTripExact`.
Every golden and the round-trip law bake in a broken type until fixed.

**Q7 — Carrier channel: Application Extension or Comment?**
*Recommendation:* GIF89a Application Extension (`0x21 0xFF`), EXACTLY 11-byte identifier (8+3, e.g.
`'SIXFOUR1'`+`'G10'`), with the `0x0B` size byte before it; codegen-MANDATORY into both encoders;
CRC32 footer; `major.minor` version; `NoBlock` vs `Corrupt` extraction errors.
*Why:* App-ext is the standards-intended private channel, unambiguous reader, marginally more
durable; honest file-level transport. Codegen-mandatory prevents dual-encoder golden drift.
`major.minor` resolves the forward-compat-vs-CRC tension.

**Q8 — 16³ rung: 16 frames (lossy in time) or 64 frames at 16² spatial?** ⚑
*Recommendation:* 64 frames at 16² spatial — temporally lossless, so `lawLadderConsistencyDownUp`
is a FULL bijection and `lawTemporalReversibleOnCarriedDetail` is non-vacuous.
*Why:* the integer-wavelet down-up=id holds only when detail is carried. A 16-frame discard breaks
the time-axis bijection and makes the lossless-temporal law vacuous.

**Q9 — 256³ engine: synthBeyond floor or Upscale256?** ⚑
*Recommendation:* `synthBeyond` nearest-neighbour floor is the canonical, always-correct 256³
baseline; `Upscale256`/`NetSynth256` is a SEPARATE golden-gated enhancement that must be PROVEN
bit-exact-equal to the floor at zero genome. Ship 16³+64³ synchronously; 256³ is a progress-gated/
tiled follow-on.
*Why:* `Upscale256` consumes a richer input (cube A+B+`ExitState`) than the single-genome export
has; framing it as a "generalization of the floor" is unearned across mismatched signatures. The
floor is cheap, lossless-above-capture, and de-risks the spine.

**Q10 — Captured 64³ hero colour basis?** ⚑
*Recommendation:* render the hero through the BASE genome g0 GLOBAL table (no δ), the same basis as
the candidates — NOT per-frame palettes.
*Why:* a per-frame-palette hero puts the on-screen reference on a different colour basis than the
candidates it is judged against, and preview≠ship for the exported 64³. Add a law: Captured hero ==
`fam64` of g0.

**Q11 — Settings/movable-widgets survive?** ⚑
*Recommendation:* retire the movable-widget + influence-field stack and the Settings sampler
drawer; shrink to a tiny inline menu only for audited load-bearing toggles (e.g.
`useDeterministicCore`).
*Why:* a static 3-pane (64³|A|B) layout doesn't justify the Metal radiation ground or
long-press-drag-snap; most Settings state is local `@State` orthogonal to capture→A/B→export. High
value, but COORDINATED with `assertSpecParity` + cabal/Map + `verify-doc-claims` edits.

---

## 6. Open risks

- **Candidate-proposal cold start.** `AtlasTrainer` is a VALUE head that RANKS, not a generator.
  Day-1 (n < 8 Compares) `sampleOrthogonalPair` needs a deterministic non-learned ranking (e.g.
  capture-measure per-band variance) or the "NN proposes two" requirement degrades to a fixed
  heuristic until enough Compares accrue. The band-disjoint construction is deterministic and valid
  regardless, but WHICH two band-sets rank highest is θ-dependent only once trained.
- **θ ranks but does not generate.** θ ranks/biases but does not by itself GENERATE the orthogonal
  RGBT-valid candidates; `GenomePair` (the proposer) is a hard dependency of the A/B screen. If
  `GenomePair` isn't ready, `Captured` has no real candidates (today's `perturb`/`maximin`
  stand-ins).
- **θ bound is large.** `dmax/λ = 1000·dmax` is bounded but not small; if embeddings are O(1), θ can
  reach O(1000) before L2 catches it. Consider embedding normalization or larger λ if tight bounds
  matter (affects practical magnitude, not correctness).
- **NetSynth256 floor reduction rides on unproven signature compatibility** between `Upscale256`
  (needs `ExitState`/cube A+B) and the single-genome export; if it can't be golden-pinned as a
  bit-exact equality, 256³ ships as the floor only and `NetSynth256`'s genome→detail map stays
  unexercised.
- **256³ on-device perf/memory.** 256²×256 frames = 64× the 64³ data; no tiling path is spec'd. The
  export-family 256³ tap likely needs a progress/tiling path, not a synchronous call.
- **Re-save survival is FILE-LEVEL only.** gifsicle / ImageMagick / Photoshop / Messages-transcode
  drop the S4GN block; there is no signal to the user that a received GIF lost its genome beyond the
  `NoBlock` extraction variant. Portability must be documented honestly, not over-promised.
- **Coordinated-cut blast radius (step 5).** Deleting guarded files touches `verify-doc-claims.sh`
  `GREP_TARGETS` + checks, `Surface.assertSpecParity` golden folds, `spec.cabal` exposed-modules,
  and `Map.hs` simultaneously. A miss in any one aborts `s4 all` at the doc gate (2nd in gate-order)
  before build runs. Must be one atomic, fully-sequenced change with `s4 codegen → verify` proven
  before any Swift delete.
- **Repeated federated blends still risk consensus collapse** despite
  `lawHighLocalConfidenceResistsBlend`; the multi-sender aggregation policy is sim-validated
  (`fed_sim`) but not yet fully spec'd as a law beyond the single-step trust weight.
