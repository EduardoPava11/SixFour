# SIXFOUR — NN spec-coverage review + gap analysis

> **Purpose.** Per signed-off NN component, report whether the locked design is actually
> covered in `spec/`: **covered** / **partial** / **gap** (nothing there) / **hollow** (named
> but `error "TODO"` / vacuous / wrong-shape). Statuses are the adversarially-verified
> `trueStatus`, not a reviewer's first pass: where verify downgraded or upgraded the review,
> this doc trusts verify.

Companion to:
- `docs/SIXFOUR-NN-STACK-RESEARCH.md` — **§1.5 LOCKED DECISIONS** (the four signed-off,
  architecture-gating choices this doc audits against).
- `docs/SIXFOUR-NN-STACK.md` — the stack design.

This doc is a **report**, not a spec. It cites real module / function / law names and, for
hollow findings, the offending `file:line`. The spec-first loop it feeds is the CLAUDE.md one:
`Spec` → `cabal test` (laws + golden gate) → `cabal run spec-codegen` → hand-port to Swift/Zig.

---

## 1. Coverage matrix

Status is the adversarially-verified `trueStatus`. "Locked-design need" is the §1.5 clause
(or its hard-must) the component must satisfy.

| Component | Locked-design need (§1.5) | Spec modules / laws | TRUE status | Note |
|---|---|---|---|---|
| **value-head-bt-mlp** | Tiny ~50–100K-param **BT MLP** value net trained on-device (CPU-linear θ kept as fallback) | `PreferenceUpdate` (linear BT SGD), `AtlasOracle.atlasValue`, `AtlasNetEval` (forward-only MLP oracle) | **partial** | LINEAR BT trainer is fully golden-gated; the MLP exists only as an abandoned forward oracle with **no BT loss / gradient / update law**. |
| **proposer-search** | Shallow MCTS **depth 2–3** over policy-sampled **genome** candidates (`GenomePair` seed), value-head ranked, SH/Gumbel | `PaletteSearch.mctsStep`/`runSearch`, `GumbelSearch.sequentialHalving`, `AtlasOracle`, `GenomePair.sampleOrthogonalPair` | **partial** | Real PUCT tree + real SH cascade + real genome seeder all exist, **never assembled**: no depth-2–3 bound, no genome-seeded root, SH not composed into the tree; substrate is a global-palette Haar search. |
| **genome-pair-generator** | Orthogonal σ-valid genome **pairs**, golden-gated, 384 DOF, extensible to ≥2 | `GenomePair` (10 laws) + `Codegen.GenomePair` + Swift twin | **covered** | Exact (`== 0`) orthogonality, σ-validity, 384 DOF, cold-start, byte-exact Swift golden — all real & gated. Only ≥2-fan-out (tournament) unaddressed at this module. |
| **sr-residual-floor-gate** | **From-scratch on-device** learned SR residual, **zero-gated to floor** (export == floor bit-exact), FiLM-conditioned, per-frame | `ExportFamily` (`NetSynth256`), vs real `Upscale256` (deterministic floor), `Layer`/`LookCore` (zero-residual idiom, genome-space) | **hollow** | The named module is **100% `error "TODO"`**, NOT in `spec.cabal`, no test gate. Identity-at-floor is vacuous. The only real 256-endgame (`Upscale256`) is deterministic AND global+per-frame hybrid (wrong shape). |
| **coldstart-prior** | Optional **frozen Reptile/federated** prior via `personalBeta = n/(n+50)`, never required | `PersonalGenome` (8 laws), `AtlasOracle.betaBlend`, `DivergenceSchedule`, `GenomeBlend` | **partial** | The `n/(n+50)` ramp + "fades to zero influence" are real (gated on `AtlasOracle`, **unenforced** on `PersonalGenome`/`GenomeBlend` — no test files). **No** Reptile/MAML/federated-aggregation init anywhere. |
| **training-loss-gradient-determinism** | On-device BT loss+grad+step deterministic; **fixed-point Q16 / integer-index** for LEARNED detail (cross-device bit-exact) | `PreferenceUpdate` (Double BT step), `GumbelSearch.q16Key`, `ColorFixed`, `Upscale256`, vs `ExportFamily` (TODO) | **partial** | Decision-determinism (`q16Key`), color path, deterministic-floor are Q16-exact & gated. BT step is pinned but **in Double only**. LEARNED-detail Q16/integer-index path is **wholly absent** (ExportFamily TODO). |
| **hard-constraint-laws** | (1) per-frame-only / no-global-collapse; (2) output = 256-cube of **picked** candidate / ladder bijectivity; (3) on-device-learning guard | `CubeLadder` (bijectivity, gated), `Upscale256`, `ABSurface.lawExportGatedOnPick`, `Collapse`, vs `ExportFamily` (TODO) | **partial** | MUST #2 **ladder bijectivity** is real & FNV-golden-gated. MUST #1 (per-frame-only) is **ABSENT** as a law (Swift `Feature` flag only). "output = 256-cube of picked genome" is **hollow** (`lawFamilyOneGenome` = TODO). MUST #3 not present here. |

**Tally:** covered **1** · partial **5** · hollow **1** · gap **0** (the only true gap — the
learned SR residual head — is reported as *hollow* because a placeholder module, `ExportFamily`,
exists by name; see §4).


---

## 2. What's already specced (covered) — the good news

These are real, non-vacuous, golden-gated laws to **reuse** as anchors for the hollow-fills and
gap-adds. Where a component is only `partial`, the genuinely-covered *sub-parts* are listed here.

### 2.1 genome-pair-generator — **fully covered**
`spec/src/SixFour/Spec/GenomePair.hs` is the candidate seeder, total pure-integer (Q16), all
three locked guarantees are real laws and golden-gated end-to-end:
- **Exact orthogonality** (not epsilon): `lawPairOrthogonalExact` (`GenomePair.hs:288–292`)
  asserts `genomeInner bandWeights da db == 0` (`Double`, exact `0.0`) via disjoint generator
  bands; `lawBandDisjoint` (`:334–338`) independently asserts empty support intersection.
- **σ-validity:** `lawPairValidSigma` (`:306–311`) delegates to
  `LeafOverride.lawSigmaOverridePreservesSymmetry` (`LeafOverride.hs:89–93`), a real check that
  `sigmaSwapAndReflectI pal == pal` on `applySigmaOverride` output (a real `concatMap`, not a stub).
- **384 DOF:** `maxGenerators = 128` (`:149–150`) → `lookSigmaPairDOF = 384 = 3·128` in
  `SixFour/Generated/NetContract.swift:45`. `genHaarI` exercises depth-0..7 (the 128-generator case).
- **Cold-start:** `lawColdStartStillOrthogonal` forces the empty-ranking fallback and still proves
  disjoint + exact-orthogonal.
- **Gate:** `Codegen.GenomePair` (wired `app/Spec.hs:50,97` → `Generated/GenomePairGolden.swift`);
  Swift twin `GenomePairGoldenTests.swift:26–44` re-checks byte-exact deltas, `genomeInner==0`,
  disjointness, distinctness via real Swift Testing (not compile-only). All 10 laws QuickChecked,
  registered `spec/test/Spec.hs:149`.

**Reuse it as:** the seed type for the proposer-search root (the missing wiring in §5.1).

### 2.2 proposer-search — the *mechanics* are covered (only the *assembly* is not)
- **Real PUCT tree:** `PaletteSearch.mctsStep` (`PaletteSearch.hs:200–226`) is a genuine recursive
  descend/expand/backup over a persistent rose tree; `lawBackupCountsVisits` (`:336–338`) asserts
  root visits `== n` after n iterations (non-vacuous), plus `lawPuctExploitLimit`,
  `lawDeterministic`, `lawMoveRoundTrip`.
- **Real SH cascade:** `GumbelSearch.sequentialHalving` (`:78–93`) with `lawSHPicksMaxValue`,
  `lawSHWinnerHasMaxVisits`, and the Q16 cross-tier key `lawArgmaxKeyDependsOnlyOnKeys` (`:111–116`)
  — the antidote to Metal's unspecified `simd_sum` order.
- **Real oracle:** `AtlasOracle.atlasPolicy` (top-k=8, `:179–191`), `atlasValue` (β-blend, `:199–207`);
  `lawWidthLeqEight`, `lawPriorsSumOne`, `lawZeroWeightsIsReference` all golden-gated.

**Reuse them as:** the three components to *compose* (§5.1) — none needs rewriting, only wiring.

### 2.3 Q16 determinism + deterministic floor — covered (training-loss & hard-constraint components)
- **Decision determinism:** `GumbelSearch.q16Key` (`:50`) quantizes float value → Q16 integer key;
  the argmax/pick decides only on that key (`lawArgmaxKeyDependsOnlyOnKeys`). Honest claim: the
  float value head may wobble, the pick cannot flip.
- **Color path:** `ColorFixed` (`linearToOklabQ16`/`oklabToSrgb8Q16`, integer cbrt/sqrt, embedded
  gamma LUT) is byte-exact vs the Zig core, gated by `Properties.ColorFixed`.
- **Deterministic 256 floor:** `Upscale256.upscale256` (`:221`) recomputes the 4× endgame
  (`blendPalettesQ16`/`quantizePrior`/`applyAnchors`, all exact `Int` + arithmetic shift);
  `lawK0PaletteExact`, `lawIntegerClosed`, `lawAnchorsVerbatim` + an FNV-1a-64 `outputChecksum`
  golden, gated by `Properties.Upscale256`. **Notably preserves per-frame palettes** (operates on
  `upPalettes` per-frame).
- **Ladder bijectivity (MUST #2):** `CubeLadder.lawLadderBijective` (`:122–127`) proves
  `synthesize . distill = id` over fully-implemented integer Haar (sides 2/4/8, levels 0–3) with
  **3 FNV-1a-64 golden pins** (`test/Properties/CubeLadder.hs:32–58`).

### 2.4 BT training math (linear) — covered
`PreferenceUpdate` pins `btPairLoss` (`:67`), the exact `btPairGradient` (`:78`), the `btUpdate`
SGD+L2 step (`:86`), with `lawGradientFiniteDiff` (gradient vs central differences),
`lawStepDecreasesLoss`, `lawSwapAntisymmetry`, `lawThetaBounded` — all real, non-vacuous, gated by
`Properties.PreferenceUpdate`. **Caveat:** this is the **linear** θ model (a dot product over
`[Double]`), the kept fallback — not the locked MLP value head (§4 / §5).

### 2.5 Cold-start ramp — the formula is covered (gated on one path)
`personalBeta = n/(n+blendHalfLife=50)` and "cold-start contributes nothing" are real:
`lawColdStartIsDeterministicFloor` (`PersonalGenome.hs:207–211`) asserts `personalBeta
coldStartGenome == 0` AND `scoreCandidate coldStartGenome == 0`. The **identical ratio** is
test-gated as `AtlasOracle.betaBlend` (`:84–85`, asserts `betaBlend 0==0`, `<1`, monotone in
`Properties.AtlasOracle`) and mirrored by `DivergenceSchedule` (6 gated laws). **Caveat:** on the
`PersonalGenome`/`GenomeBlend` path the laws have real bodies but **no test file** — see §4.


---

## 3. Hollow laws (exist by name, do not actually constrain)

The dangerous middle: a reader scanning `spec/` sees these names and believes the design is
covered. They are not. Each is `error "TODO"` / vacuous / unwired, with the offending `file:line`
and what it must become.

### 3.1 `ExportFamily` — the entire `NetSynth256` learned-SR surface is `error "TODO"`
**`spec/src/SixFour/Spec/ExportFamily.hs` is the only module in the whole spec with TODO stubs,
AND it is not registered in `spec.cabal` exposed-modules, AND it has no `Properties.ExportFamily`
test module.** So even the names that look like laws **run in no test suite and emit no golden** —
nothing is enforced even before considering that the bodies are empty. (The only text reference is
a docstring `"via ExportFamily"` on the *unrelated* `lawExportGatedOnPick` in
`test/Properties/ABSurface.hs:13` — a different law in another module.)

Functions, all `= error "TODO"`:
- `exportFamily` (`:83`), `temporalDistill` (`:87`), `temporalSynthesize` (`:91`),
  `genomeToSynthSeed` (`:95`), `synthDetail` (`:99`), `synthBeyond256` (`:103`).

Laws, all `= error "TODO"` (and thus vacuous because their dependencies are also TODO):
- **`lawZeroGenomeIsFloor` (`:128`)** — THE identity-at-floor guarantee the locked SR design
  hinges on (export == deterministic floor bit-exact at zero genome). Vacuous: body is `error`,
  dependency `synthDetail` (`:99`) is `error`. **This is the single most load-bearing hollow law
  in the audit.**
- `lawFamilyOneGenome` (`:111`) — "output = 256-cube of the ONE picked genome" (hard MUST #2
  content half). Vacuous; orchestrator `exportFamily` (`:83`) is `error`.
- `lawTier256FloorIsNearestNeighbour` (`:124`), `lawTier64IsReference` (`:120`),
  `lawLadderConsistencyDownUp` (`:116`), `lawTemporalReversibleOnCarriedDetail` (`:133`),
  `lawFamilyDeterministic` (`:137`), `lawFamilyGamutClosed` (`:141`) — all `error "TODO"`.

**What it must become.** A real `NetSynth256` spec for the learned SR residual:
1. `synthDetail` = a real **zero-init-gated** residual body (`floor ⊕ s·tanh(residual)` shape,
   borrowing the proven idiom from `Layer.lawLayerNeutralResidualIsFloor` / `LookCore.lookFloor`,
   but in **pixel/index space**, not 384-DOF genome space), with **FiLM** genome-conditioning made
   explicit and a **pixel-shuffle** body.
2. `lawZeroGenomeIsFloor` = a real proof that zero genome ⇒ `exportFamily == upscale256` floor
   **bit-exact** (the floor is `Upscale256`, already real — reuse it as the oracle).
3. `lawFamilyOneGenome` = all three rungs {16,64,256} reconstruct from the ONE picked genome.
4. Register `ExportFamily` + `Properties.ExportFamily` in `spec.cabal`; wire `Codegen.ExportFamily`
   + an FNV golden. Per the CLAUDE.md maintenance contract, also add a `Spec.Map` entry.

> This single module is simultaneously the **hollow** finding for `sr-residual-floor-gate`, the
> **hollow** content-half of `hard-constraint-laws` MUST #2, and the **gap** for the learned-detail
> Q16 path in `training-loss-gradient-determinism`. Filling it closes the most surface at once.

### 3.2 `AtlasNetEval` MLP — real *forward* oracle, but **no training law** (value-head-bt-mlp)
Not a TODO body — a **wrong-shape / abandoned-provenance** hollow. `AtlasNetEval.hs:143–146` is a
24-32-1 MLP (`aV1` 32×24, `aV2` 1×32) with a real forward (`:255–257`), but:
- Its weights are a **placeholder fill**: `deterministicAtlasWeights` is `0.1*sin` (`:152`).
- The module header (`:22–24`) says **v1 REPLACES this MLP with the linear utility**.
- Its gate `Properties/AtlasNetEval.hs:55–88` checks only shape / finiteness / σ-symmetry —
  **no BT loss, no gradient, no training step over the MLP.**

So the locked "~50–100K-param BT MLP value net, trained on-device" has **no loss/gradient/update
law**: the only such laws (`PreferenceUpdate`) are over `linearUtility`, a dot product.
**What it must become:** a `PreferenceUpdate`-style trainer whose forward is the MLP, not the
linear θ — i.e. `btPairGradient`/`btUpdate` lifted to backprop through `aV1`/`aV2` (§5.2).

### 3.3 `PersonalGenome` + `GenomeBlend` laws — real bodies, **unenforced** (coldstart-prior)
Not vacuous, but **gated by nothing** — a hollow-by-non-execution:
- ALL 8 `PersonalGenome` laws (`lawColdStartIsDeterministicFloor:207`, `lawBetaMonotoneRamp:233`,
  `lawReplayDeterministic:216`, `lawApplyPickBounded:243`, `lawRegularizedObjectiveDecreases:257`,
  `lawGateRejectsRegression:269`, `lawGatedPromotion:279`, `lawReplayFromCheckpoint:224`) have
  **no `Properties.PersonalGenome` file**, not imported in `test/Spec.hs`. The module's own
  doc-comment admits it: *"test wiring pending — this module lands at build step 3"*
  (`PersonalGenome.hs:47`).
- ALL 6 `GenomeBlend` laws (`lawBlendIsACompare:137` … `lawBlendStaysSigmaSymmetric:173`) —
  no `Properties.GenomeBlend` file, doc says *"build step 7"* (`GenomeBlend.hs:41`).

So `personalBeta = n/(n+50)` and "cold-start is floor" are **exported predicates that nothing
runs** on the genome path. **What it must become:** add `Properties.PersonalGenome` +
`Properties.GenomeBlend`, register in `test/Spec.hs`. Cheap, high-leverage (§6).

### 3.4 Depth + composition gaps in proposer-search (real laws, wrong scope)
These laws are real and non-vacuous but do **not** constrain the locked architecture:
- `PaletteSearch.runSearch` (`:244–253`) halts only on `HaltOnVisits`/`HaltOnValue` **budget**;
  no depth parameter, no law pins **depth to 2–3**. `mctsStep` recurses to arbitrary depth.
- `AtlasGame.terminal` (`:124–125`) = `gsTerminal` flag only; `lawTerminalHasNoMoves` (`:169`)
  tests only that clause. The design's `plyBudget`/anchor terminal predicate
  (`ALPHAZERO-COLLAPSE-DESIGN.md:51` calls it "the missing piece") is **not implemented**.
- `GumbelSearch.sequentialHalving` ranges over anonymous `[Double] → [Double]` arms; it is
  **never composed** with `mctsStep`, and `sampleOrthogonalPair` (`GenomePair.hs:270`) has **no
  call site** in `mctsStep`/`childrenFromPolicy`/`runSearch` (its only consumers are
  `Codegen.GenomePair` + its own laws). The search root is seeded by `AtlasOracle.codebookPolicy`
  (Haar offsets), not genome candidates — and `SearchState = HaarPalette` flattens to ONE 768-D
  **global** palette (`PaletteSearch.hs:115`, `paletteEmbedding:266–268`), a different substrate
  than the per-frame genome the design wants.

**What they must become:** §5.1.


---

## 4. Gaps (nothing there) — gap analysis

No component is a *pure* gap (every one has at least a placeholder or a covered sub-part). These
are the design clauses with **zero real spec content** — they need new modules/laws/codegen added.
Each is sized (small / medium / large) and placed beside the existing spec it should sit next to.

### 4.1 GAP — learned SR residual head (the suspected gap) — **LARGE**
**Where it sits:** beside `Upscale256` (the deterministic floor = the bit-exact oracle) and
`Layer`/`LookCore` (the proven zero-residual idiom to lift into pixel space). Module to fill is the
existing-but-empty `ExportFamily` (so this is *technically* hollow, but the **content** is a true
gap — see §3.1 for the exact `error "TODO"` lines and the fill spec). Add: `NetSynth256`
architecture, FiLM conditioning, pixel-shuffle body, zero-init gate, `lawZeroGenomeIsFloor`
(bit-exact vs `Upscale256`), `lawFamilyOneGenome`, `Properties.ExportFamily`, `Codegen.ExportFamily`
+ FNV golden, `spec.cabal` + `Spec.Map` registration. **Large** because it is a from-scratch net
spec plus its determinism contract plus the integer/Q16 index path for cross-device exactness.

### 4.2 GAP — BT **MLP** value-net training law — **MEDIUM**
**Where it sits:** beside `PreferenceUpdate` (reuse `btPairLoss`/`btPairGradient`/`btUpdate`
structure and all four laws) and `AtlasNetEval` (reuse the `aV1`/`aV2` forward, replace the
`0.1*sin` placeholder weights with trained ones). Add: a loss+gradient+update law where the BT
utility is the **MLP forward**, not `linearUtility`; `lawStepDecreasesLoss`/`lawGradientFiniteDiff`
lifted to the 2-layer net; a golden trajectory. **Medium** — the BT scaffolding already exists, the
work is backprop through 2 layers + a finite-diff gradient check. (Linear θ stays the gated fallback.)

### 4.3 GAP — depth-2–3 bound + plyBudget terminal — **SMALL/MEDIUM**
**Where it sits:** inside `PaletteSearch.runSearch` + `AtlasGame.terminal`. Add: a `depthBudget`
(or `plyBudget`) parameter threaded through `mctsStep`, a `terminal` clause that fires at depth ≥ 3
(plus `allAnchorsMet`/`noKilledLeaves` per `ALPHAZERO-COLLAPSE-DESIGN.md:51`), and a law
`lawDepthBounded` asserting no node exceeds depth 3. **Small** if it is purely a counter on the
existing tree; **medium** if the terminal predicate must also fold anchor/leaf state.

### 4.4 GAP — assemble SH-over-genome-candidates **inside** the tree — **MEDIUM**
**Where it sits:** a new composition module (e.g. `Spec.Proposer`) over `GumbelSearch`,
`PaletteSearch`/`AtlasOracle`, and `GenomePair`. Add: seed `mctsStep`'s root children from
`sampleOrthogonalPair` (and a ≥2 fan-out generalization of `chooseDisjointBands` if the design
wants >2 children per node — see §4.6), run `sequentialHalving` over those genome arms, rank by the
value head, and a golden that gates the **composed** proposer (no Codegen module currently emits the
assembled tree-search loop). **Medium** — all three pieces exist; this is wiring + one new law + one
golden. *Depends on 4.3 (depth) and ideally 4.2 (MLP value rank).*

### 4.5 GAP — per-frame-only / no-global-collapse invariant (hard MUST #1) — **SMALL**
**Where it sits:** beside `Collapse` (`Collapse.hs:102–106` confirms `globalCollapseQ16` is merely
V2-deferred behind Swift `Feature.globalPaletteV2`, **not forbidden by any law**) and the export
pipeline. Add: a spec-level invariant that the MVP1 export path never calls `globalCollapseQ16`
(e.g. a law over the FSM/pipeline that asserts the per-frame palette count is preserved through
export, or that the global path is statically unreachable from `Exporting`). **Small** — it is one
guard law, but it needs a representation of "the export pipeline" to range over (currently only
`ABSurface.lawExportGatedOnPick` gates the *entry*, not the *content*). Also fixes the substrate
note in §3.4 (the proposer's `SearchState` is a global 768-D palette).

### 4.6 GAP — ≥2 / tournament fan-out from the genome generator — **SMALL**
**Where it sits:** inside `GenomePair` (otherwise fully covered). The generator is hardwired to
exactly TWO candidates (`chooseDisjointBands` does a 2-way rank-parity split; `sampleOrthogonalPair`
returns a 2-tuple). Add: an n-way disjoint-band partition + a list-of-candidates form, with the
orthogonality/σ-validity laws generalized to pairwise-over-the-list. **Small** — generalize the
existing proven 2-way split. Only needed if §4.4's tree expands >2 seeded children per node.

### 4.7 GAP — cross-device bit-exact BT **training trajectory** + Reptile/federated init — **MEDIUM**
**Where it sits:** beside `PreferenceUpdate` (training trajectory) and `PersonalGenome`/`GenomeBlend`
(prior). Two missing things:
1. **No golden pins a cross-device-identical weight trajectory.** `PreferenceUpdate` is Double
   throughout; `btFit` is documented order-dependent. CLAUDE.md asserts a "bit-identical loss
   trajectory Mac↔iPhone" was *measured*, but the spec does not *constrain* it. Add a Q16 (or
   fixed-order-reduction) twin of the update + a golden trajectory vector. **Medium.**
2. **No Reptile/MAML/federated-aggregation init exists anywhere** (`grep` for
   `reptile|maml|meta.learn|federat|aggregat` finds nothing relevant). The §1.5 "optional frozen
   Reptile/federated prior" has only (a) the blend *ratio* and (b) receiver-side single-genome
   adoption-as-Compare (`GenomeBlend.adoptForeign`). The "never required / fades to zero" half **is**
   encoded; the meta-learned/aggregated INIT half is a true gap. Add a `Spec.MetaPrior` (frozen θ₀
   blended via `personalBeta`, with a law tying prior weight `50/(n+50)` to fade-out, applied to
   value/policy+genome **but NOT the SR head** per §1.5). **Medium** (and the §1.5 note marks it
   *optional*, so it is the lowest-priority gap).


---

## 5. Recommended spec-work order

Sequenced by **leverage** (surface closed per unit work) and **dependency** (cheapest enabling work
first), following the CLAUDE.md spec-first loop for each item:
`Spec` → `cabal test` → `cabal run spec-codegen` → hand-port to Swift/Zig.

| # | Item | Size | Kind | Why first / depends on |
|---|---|---|---|---|
| **1** | **Wire `Properties.PersonalGenome` + `Properties.GenomeBlend`** into `test/Spec.hs` (§3.3, 4.7) | small | hollow-fill | Pure leverage: the laws already have real bodies; this just makes 14 cold-start laws actually *run*. Zero new design. Unblocks trusting the `personalBeta` ramp. |
| **2** | **Per-frame-only invariant** (§4.5) | small | gap-add | A hard MUST currently enforced only by a Swift compile flag. One guard law beside `Collapse`. Cheap, and it de-risks every downstream export/proposer spec from silently reintroducing global collapse. |
| **3** | **depth-2–3 bound + plyBudget terminal** (§3.4, 4.3) | small/med | gap-add | Enables the proposer assembly (#5). Self-contained counter/predicate on the existing real `mctsStep`/`AtlasGame`. |
| **4** | **≥2 fan-out in `GenomePair`** (§4.6) | small | gap-add | Generalize the proven 2-way split; needed only if #5 expands >2 children. Do before #5. |
| **5** | **Assemble `Spec.Proposer`** — SH over genome candidates inside the depth-bounded tree (§3.4, 4.4) | medium | gap-add | The headline architecture. All three pieces (PUCT tree, SH cascade, genome seeder) are already real (§2.2); this is wiring + one composed golden. **Depends on #3, #4.** |
| **6** | **Fill `ExportFamily` / `NetSynth256`** — learned SR residual, zero-init gate, FiLM, pixel-shuffle, `lawZeroGenomeIsFloor` bit-exact vs `Upscale256`, register module + `Properties` + `Codegen` (§3.1, 4.1) | **large** | hollow-fill + gap | Highest *total* surface (closes the hollow for `sr-residual-floor-gate`, the content-half of MUST #2, and the learned-detail Q16 path). But it is large and carries the §1.5 "on-device SR training is UNPROVEN" feasibility risk — do it after the cheap wins land, and spike the feasibility separately. Reuse `Upscale256` as the oracle and the `Layer`/`LookCore` zero-residual idiom. |
| **7** | **BT MLP value-net training law** (§3.2, 4.2) | medium | hollow-fill + gap | Replace `AtlasNetEval`'s `0.1*sin` placeholder + lift `PreferenceUpdate`'s BT loss/gradient/step to the MLP forward. Improves #5's ranking but #5 works with the linear fallback meanwhile, so this is not a blocker. |
| **8** | **Cross-device BT training-trajectory golden + optional `Spec.MetaPrior`** (§4.7) | medium | gap-add | Lowest priority: the trajectory golden hardens an already-asserted property; the Reptile/federated prior is explicitly *optional* in §1.5. Do last. |

**Critical path to the locked architecture:** #1 → #2 → #3 → #4 → #5 gets a real, gated,
depth-2–3 SH-over-genome proposer for cheap. #6 (the learned SR head) is the big rock and the real
feasibility risk; #7–#8 are quality/optionality.

