# SixFour Haskell Bloat Remediation Plan

> Generated 2026-06-14. Scope: the `spec/` Haskell tree (library `sixfour-spec` + 5 executables + `spec-tests`).
> Methodology: **conservative, safest-first, gate-after-each-tier.** Never delete anything in the
> [Contested / KEEP](#contested--keep) list — every module there has a verified live consumer.

---

## Summary

| Metric | Value |
| --- | --- |
| Haskell footprint (whole `spec/` tree, prompt-stated) | ~231 files / ~35K LOC |
| Haskell footprint (`spec/{src,test,app}` *.hs, measured) | 202 files / 32,111 LOC |
| Modules recommended for **DELETE** (Tier 1–3) | **7 src modules** (+ their 7 Properties tests) |
| Modules recommended for **CONSOLIDATE** (Tier 4) | 0 (no live Fixed/float twin found to be safely mergeable; see Tier 4) |
| Contested modules **spared / KEEP** | 6 |
| **Source LOC reclaimable (src `.hs` only)** | **1,240 LOC** across 7 src modules |
| Plus their Properties tests (deleted in lockstep) | 7 test files |

> **EXECUTION STATUS (2026-06-15):** branch `cleanup/haskell-bloat`. Only **`Spec.AddressPicker`
> (191 LOC) was deleted** — gate green (777→772 tests, build + doc-claims pass). The remaining
> candidates were re-verified and split into KEEP (core/north-star) and JUDGMENT-CALL (active design
> directions); see the per-tier notes. The "1,240 LOC" headline below is the *pre-review* figure and is
> superseded by this status block.
>
> **CORRECTION 1 (post-review):** `SixFour.Spec.LookNetCompose` (214 LOC) — **moved to
> [Contested / KEEP](#contested--keep)**. Home of the σ-equivariance theorem of the NN core, cited **by
> name in `CLAUDE.md`**, referenced in the generated `look_net_{mlx,torch}.py` contracts.
>
> **CORRECTION 2 (post-review):** `SixFour.Spec.LookCategory` (190 LOC) — **moved to KEEP**. Its header
> declares it "the north-star foundation — a named look taxonomy + per-user push-pull learning"; it is
> the verified source of truth for the on-device Bradley–Terry SGD step (`btGradStep`/`trainPairs`) and
> cites `CLAUDE.md` Tier 2. TEST_ONLY here means *spec written ahead of its Swift port* — the repo's
> stated methodology — not bloat.
>
> **ROOT-CAUSE:** the audit equated "no importer" with "bloat", but this is a spec-ahead-of-
> implementation repo: importer-less modules are frequently intentional (a proven invariant or a
> north-star seed awaiting its Swift port). Honest reclaimable bloat is far below 1,240 LOC.

**Reclaimable src LOC by module** (Properties tests removed alongside, not counted here):

| Module | src LOC |
| --- | ---: |
| SixFour.Spec.WidgetDescriptor | 197 |
| SixFour.Spec.AddressPicker | 191 |
| SixFour.Spec.LookCategory | 190 |
| SixFour.Spec.PaletteGesture | 166 |
| SixFour.Spec.QuartetDelta | 158 |
| SixFour.Spec.Scale | 148 |
| SixFour.Spec.Dither | 90 |
| **Total** | **1,240** |

All 7 are **TEST_ONLY** (proven-but-undeployed): the only LIVE importer of each is its own
`Properties.*` test (Dither's chain additionally pulls in `Scale` + the `spec-gif` viz exe — see Tier 3).
None emits Swift/Zig/Python/golden artifacts; none is referenced by any gate file.

---

## Safety floor

Every step in this plan MUST preserve the green baseline. Re-run the full gate after each tier:

- **Build:** `cabal build all` succeeds — library plus all 5 executables (`spec-tui`, `spec-gif`,
  `spec-gen`, `spec-fixtures`, `spec-codegen`) compile and link. The `ld: warning: -single_module is
  obsolete` note is cosmetic and pre-existing; it is NOT a regression.
- **Tests:** `cabal test` → `spec-tests` passes. Baseline = **777 tests passed**, 1 of 1 suite.
- **Doc-claims gate:** `bash scripts/verify-doc-claims.sh` ends with `All load-bearing facts verified.`
- **Branch hygiene:** start from `master` (clean except untracked `scripts/wf-haskell-bloat-audit.js`).
- **Pre-existing failures:** none. If any step turns a check red, STOP and revert that step.

Deletions only ever drop a module + its test; the **test-count will go DOWN, never a test should start
failing.** A failing test after a delete means a hidden consumer was missed — revert immediately.

---

## Remediation (tiered, safest-first)

### Tier 1 — ORPHANS (zero importers, delete outright)

**None.** Every removable module has at least one importer — its own `Properties.*` test (and, for
`Dither`, additionally `Scale` + `app/Gif.hs`). There is no module in this audit whose deletion needs
**zero** downstream edits, so nothing qualifies as a pure orphan. All removable items live in Tier 3.

### Tier 2 — SUPERSEDED (docs/git confirm retired)

**None proposed as a distinct tier.** Two Tier-3 modules are *design-retired* per docs and may be
annotated as such while deleting (`WidgetDescriptor` → "user decision pending / retired" in
`docs/SIXFOUR-WIDGET-DESCRIPTOR-WORKFLOW.md`; `LookCategory` is described as an OPEN/missing spec gap in
`README.md:216` and `docs/SIXFOUR-DEBT-CLEANUP-REPORT.md:333`). They are handled mechanically as Tier-3
TEST_ONLY deletions; no separate procedure is needed.

### Tier 3 — TEST_ONLY (proven-but-undeployed: delete module + its Properties test)

For each: remove the cabal exposed-module line, remove the cabal test-suite `other-modules` line, delete
the two `.hs` files, and remove the `import` + `.tests` entry in `test/Spec.hs`. Map.hs index edits are
**required** (lint expects module↔Map consistency in the FORWARD direction; a removed module that is
absent from cabal AND Map is clean). Confirmed cabal line numbers below were verified on `master`
(2026-06-14) — re-check before editing as line numbers drift as you delete upward.

> **EDIT ORDER (critical):** delete cabal lines **bottom-to-top** within a single edit session, or
> re-grep after each removal, because removing an earlier line shifts all later line numbers.

---

#### 3a. SixFour.Spec.Dither  (+ SixFour.Spec.Scale)  — 90 + 148 = 238 src LOC

> **Bundled removal.** `Dither` cannot be removed alone: its only *library* importer is `Scale.hs`
> (`lawDitherMeanRecoversP`), and `Scale` is itself dead off the shipped/codegen path. Both are also
> imported by `app/Gif.hs` (the `spec-gif` dev-viz exe), which MUST be re-worked. Verified importers:
> `Scale` ← {`app/Gif.hs`, its own test}; `Dither` ← {`Scale.hs`, `app/Gif.hs`, its own test}.
> **`SpatialDither`, `STBN3D`, and all Swift/Zig dither code are SEPARATE modules and UNAFFECTED.**

- **spec.cabal — exposed-modules:** remove line **74** (`SixFour.Spec.Dither`) and line **78**
  (`SixFour.Spec.Scale`).
- **spec.cabal — test-suite other-modules:** remove line **327** (`Properties.Dither`) and line **332**
  (`Properties.Scale`).
- **Delete files:** `spec/src/SixFour/Spec/Dither.hs`, `spec/src/SixFour/Spec/Scale.hs`,
  `spec/test/Properties/Dither.hs`, `spec/test/Properties/Scale.hs`.
- **test/Spec.hs:** remove the `Properties.Dither` import (~line 56) and `Properties.Scale` import
  (~line 61), plus both `.tests` entries in the test tree.
- **app/Gif.hs (spec-gif viz exe — REQUIRED re-work):** drop the `Dither` import
  (`binomialVariance`/`realize`) and the `Scale` import block
  (`synthLookInput`/`randomResidual`/`layerLawReport`/`scaleT`/`H`/`W`/`K`) and the viz panes that use
  them. This exe must still compile under `cabal build all`. If the viz panes are load-bearing for dev,
  prefer **inlining the few helpers** into `Gif.hs` instead of deleting them — but the *modules* go away.
- **Map.hs:** remove the `SixFour.Spec.Dither` token (line 71) and the `SixFour.Spec.Scale` mention
  (line 24).
- **Optional/cosmetic:** prune `Scale`/`Layer`/`Dither` name strings from
  `scripts/wf-haskell-bloat-audit.js`.
- **Risk note:** this is the ONLY Tier-3 item that touches a shipped executable (`spec-gif`). Do it
  **first in its own commit** so a build break is isolated.

---

#### 3b. ~~SixFour.Spec.LookNetCompose~~ — WITHDRAWN, see [Contested / KEEP](#contested--keep)

**Do NOT delete.** Originally the proposed #1 win, withdrawn on review: it proves the NN core's
σ-equivariance theorem (`lookNetSigmaTheorem`), is cited by name in `CLAUDE.md`, and is referenced by
the generated `look_net_{mlx,torch}.py` contracts. A core proof module is load-bearing in a
Haskell-verified repo regardless of runtime importers. Moved to Contested / KEEP.

---

#### 3c. ~~SixFour.Spec.LookCategory~~ — WITHDRAWN, see [Contested / KEEP](#contested--keep)

**Do NOT delete.** It is the **north-star foundation** module (`Description: "The north-star foundation
— a named look taxonomy + per-user push-pull learning"`): the verified source of truth for the
on-device Bradley–Terry SGD step (`btGradStep`/`trainPairs`), citing `CLAUDE.md` Tier 2. Its single
importer being its own test reflects spec-ahead-of-port, the repo's methodology — not bloat.

---

#### 3d. SixFour.Spec.PaletteGesture — 166 src LOC

- **spec.cabal:** remove exposed-module line **45**; remove test-suite other-module line **295**.
- **Delete files:** `spec/src/SixFour/Spec/PaletteGesture.hs`,
  `spec/test/Properties/PaletteGesture.hs`.
- **test/Spec.hs:** remove import (~line 24) and `PaletteGesture.tests` entry (~line 117).
- **Map.hs §4:** delete the `SixFour.Spec.PaletteGesture` token (~line 62).
- Only importer is its own test. No codegen/Swift/Zig/Python/golden consumer. Plain
  `deriving (Eq,Ord,Show,Enum,Bounded)` only — no orphan/standalone instances.

---

#### 3e. SixFour.Spec.QuartetDelta — 158 src LOC

- **spec.cabal:** remove exposed-module line **36**; remove test-suite other-module line **325**.
- **Delete files:** `spec/src/SixFour/Spec/QuartetDelta.hs`,
  `spec/test/Properties/QuartetDelta.hs`.
- **test/Spec.hs:** remove import (~line 53) and the `, QuartetDelta.tests` entry (~line 147).
- **Map.hs:65 (REQUIRED):** remove the `"SixFour.Spec.QuartetDelta" (Act II, 4⁴ quartet core)` index
  entry. (`spec-docs.sh` step-0 lint fails if a cabal module has NO Map entry, but does NOT fail if a
  removed module is absent from Map — drop both together for a clean state.)
- **Cosmetic:** `HaarRibbon.hs:13` doc-prose references `QuartetDelta.coreColors` → reword to avoid a
  dangling Haddock link (CLAUDE.md treats Haddock warnings like build warnings). Prune
  `wf-haskell-bloat-audit.js:35`.
- **Caution — HaarRibbon is KEPT (Contested):** `HaarRibbon.hs` only mentions `QuartetDelta` in a PROSE
  Haddock comment; its real imports are `Color` + `SplitTree`. Removing `QuartetDelta` does NOT break
  `HaarRibbon`'s compile, only its doc-comment. Do the reword in the same commit.
- `docs/STATUS.md:226` records this as the `quartetdelta-orphan` debt item; its 2026-06-10 "resolution"
  was writing the test purely to satisfy the `spec-docs.sh` lint — i.e. it never became live.

---

#### 3f. SixFour.Spec.WidgetDescriptor — 197 src LOC

- **spec.cabal:** remove exposed-module line **63**; remove test-suite other-module line **312**.
- **Delete files:** `spec/src/SixFour/Spec/WidgetDescriptor.hs`,
  `spec/test/Properties/WidgetDescriptor.hs`.
- **test/Spec.hs:** remove import (~line 41) and `WidgetDescriptor.tests` entry (~line 134).
- **Map.hs:78 §7 index:** delete the `SixFour.Spec.WidgetDescriptor` doc string.
- **Optional:** mark the design retired in `docs/SIXFOUR-WIDGET-DESCRIPTOR-WORKFLOW.md`.
- Only importer is its own test (4 internal laws). No `emitWidgetDescriptorContract` exists (codegen was
  a never-built PLAN). Swift/Zig/Python "widget" grep hits are filename coincidences
  (`MovableColorWidget.swift` etc.) — unrelated. Zero instances/classes.

---

#### 3g. SixFour.Spec.AddressPicker — 191 src LOC ✅ DONE (commit on `cleanup/haskell-bloat`)

Executed 2026-06-15. Gate green: build all OK, 777→772 tests, doc-claims pass. Steps that were applied:

- **spec.cabal:** remove exposed-module line **71**; remove test-suite other-module line **320**.
- **Delete files:** `spec/src/SixFour/Spec/AddressPicker.hs`,
  `spec/test/Properties/AddressPicker.hs`.
- **test/Spec.hs:** remove import (~line 49) and `AddressPicker.tests` entry (~line 142).
- **Optional/cosmetic:** drop the name from the `Map.hs:62` doc-map and the category array in
  `scripts/wf-haskell-bloat-audit.js:43`.
- Only importers are the test suite. Codegen entrypoint `app/Spec.hs` does NOT import it; no
  `SixFour.Codegen.*` imports it. The Swift `PlaybackClock.swift:43` mention is a doc COMMENT naming a
  hypothetical `AddressPickerView` that does not exist; the live Swift view uses its own
  `SplitTree.leafIndexForAddress`. Not gated.

---

### Tier 4 — DUPLICATE (consolidate Fixed/float twins)

**No safe consolidation found in this audit's evidence set.** The classic duplicate pattern (a `*Fixed`
fixed-point module shadowing a float twin) does NOT apply to any removable module here:

- The float `Spec.Dither` is **not** a redundant twin of `Spec.SpatialDither` / Swift `Dither.swift` /
  Zig `s4_dither_frame`; those are a separate cross-language dither family that route through
  `SpatialDither` (`Fixtures.hs:35`). `Spec.Dither` is simply dead, so it is handled in **Tier 3a**, not
  consolidated.
- `QuantFixed.hs` documents itself as the fixed-point mirror of `StageA.lloydStep`, but **`StageA` is
  KEPT** (it is a live compile-time consumer via `Laws.hs` + `Properties/Wu.hs`). Do NOT attempt to fold
  `StageA` into `QuantFixed` — that is a separate, riskier refactor outside this bloat sweep.
- `buresBarycenterCov` (Rust golden) and `Spec.Look` (Rust mirror) are deliberately KEPT twins per the
  "Haskell = verified source of truth, Rust mirrors it" methodology.

**Recommendation:** leave Tier 4 empty. Any Fixed/float consolidation should be its own spec-first
workflow with golden-vector parity proof, not bundled into a deletion sweep.

---

## Verification recipe

After **each** tier (and ideally after each module within a tier), run the full gate from `spec/`:

```bash
cabal build all && cabal test && bash scripts/verify-doc-claims.sh
```

All three must stay green:

- `cabal build all` — library + all 5 exes link (the `-single_module` linker note is expected/benign).
- `cabal test` — `spec-tests` passes; **test count DROPS by the number of `*.tests` aggregations
  removed** (each deleted module removes one `Properties.X.tests` group → the printed total falls below
  777). It must never report a FAILURE — only a smaller passing count.
- `verify-doc-claims.sh` — must still print `All load-bearing facts verified.` If a deletion stales a
  doc claim (e.g. a property count in `README.md`), update the doc/gate fixture in the **same commit**.

**Expected test-count direction per tier:**

| Tier | Modules deleted | Direction |
| --- | --- | --- |
| 3a (Dither+Scale) | 2 | total ↓ (and `spec-gif` must still link) |
| 3c–3g (one per module) | 5 | total ↓ by each module's law count (3b withdrawn → KEEP) |

If `cabal test` ever goes from "passed" to "failed" after a delete, a hidden consumer exists →
**revert that single commit** and re-investigate before proceeding.

---

## Contested / KEEP

**Do NOT touch any of these.** Each has a verified live consumer that the skeptic confirmed; removing
any would break `cabal build` and/or `cabal test` (the gate), or a live cross-language port.

| Module | Saved by (live consumer — DO NOT REMOVE) |
| --- | --- |
| **SixFour.Spec.Gauge** | `Significance.hs:94` (imports `Permutation`/`permuteVector`, used in EXPORTED `lawSigGaugeInvariant`) and `Laws.hs:34` (unqualified import, uses `permuteVector` + `lawGaugeIdentity`). Both are **library exposed-modules** → removal breaks the lib build. Plus `Properties/Gauge.hs`, `Properties/Significance.hs`, `Properties/Cyclic.hs`. |
| **SixFour.Spec.StageA** | `Laws.hs` (exposed lib module) imports `StageA(StageA, Frame(..), runStageA)` and uses all three in EXPORTED `lawWuShapesOut`; `Laws.hs` is imported by live tests `Cyclic.hs`/`Color.hs`/`Gauge.hs`. Also `Properties/Wu.hs` exercises `runStageA` + `varianceCutReference`. |
| **SixFour.Spec.Laws** | Consumed by three LIVE gate tests: `Properties/Color.hs` (`lawOKLabRoundTrip`), `Properties/Gauge.hs` (`lawGaugeIdentity`), `Properties/Cyclic.hs` (5 laws). `cabal test` is THE gate. |
| **SixFour.Spec.Look** | `studio/analysis-core/src/look.rs` is a 1:1 Rust mirror (re-exported in `lib.rs:24`, consumed by `viz`/`explore`/`look-nn-baseline`). Per "Haskell = source of truth, Rust mirrors it", `Spec.Look` is the law oracle backing the live Rust port. |
| **SixFour.Spec.HaarRibbon** | Act III `.browsing` is ALIVE (`docs/STATUS.md:95-96`); the project already adjudicated this exact removal on **2026-06-10** and chose to KEEP it (wrote `Properties/HaarRibbon.hs`, un-orphaned it). `spec-docs.sh §0b` lint requires its `Properties.HaarRibbon` test to exist. |
| **SixFour.Spec.LookNetCompose** | **Withdrawn from Tier 3 on review.** Proves the NN core's end-to-end σ-equivariance theorem (`lookNetSigmaTheorem`, `src/SixFour/Spec/LookNetCompose.hs:33-63`). Cited **by name in `CLAUDE.md`** ("σ-equivariance theorem in `Spec/LookNetCompose.hs`") and referenced in the emitted contracts `Codegen/MLX.hs:58,212` + `Codegen/CoreML.hs:134,323` → `trainer/generated/look_net_{mlx,torch}.py`. In a Haskell-verified repo a proven core theorem is load-bearing even with no runtime importer; "TEST_ONLY" misclassifies it. |
| **SixFour.Spec.LookCategory** | **Withdrawn from Tier 3 on review.** The north-star foundation module (`Description:` "The north-star foundation — a named look taxonomy + per-user push-pull learning"); verified source of truth for the on-device Bradley–Terry SGD step (`btGradStep`/`trainPairs`), cites `CLAUDE.md` Tier 2. Spec-ahead-of-port, not bloat. |
| *WidgetDescriptor / PaletteGesture / QuartetDelta / Scale+Dither* | **JUDGMENT CALL — awaiting user decision.** Not auto-deleted: each backs an active design direction (widgets / gesture invariant / Act II motion) or a working dev exe (`spec-gif`). Only the user can declare these directions abandoned. |

> Reminder for **Tier 3e**: `HaarRibbon` only references `QuartetDelta` in a doc-comment, so deleting
> `QuartetDelta` does not break the KEPT `HaarRibbon` compile — but reword the comment to avoid a
> dangling Haddock link.

---

## Suggested execution

Run this as a **worktree-isolated follow-up workflow**, one branch per tier, gate after each. This keeps
`master` green and makes each tier independently revertable.

1. **Create an isolated worktree** off `master` (do not work in the primary checkout):
   ```bash
   git worktree add ../SixFour-bloat-t3 -b cleanup/haskell-bloat-tier3 master
   ```
2. **Tier 3a first, in its own commit** (it is the only item touching a shipped exe, `spec-gif`):
   delete `Dither`+`Scale`, re-work `app/Gif.hs`, then run the full gate. If `spec-gif` won't link,
   inline the helpers rather than expanding scope.
3. **Tiers 3b–3g**, one commit per module, gate after each. Stop on the first red gate and revert that
   single commit.
4. **Update doc/gate fixtures in the same commit** as the deletion that stales them (e.g. `README.md`
   property count for `LookCategory`), so `verify-doc-claims.sh` never goes red across a commit
   boundary.
5. **One PR per branch** (or one PR for all of Tier 3 with a commit per module). Title the PR with the
   reclaimed LOC; body lists each module, its LOC, and the green gate output.
6. **Tier 4 is intentionally empty** — do not bundle any Fixed/float consolidation here. If desired
   later, spin a separate spec-first branch with golden-vector parity proof.
7. **Never touch the Contested / KEEP list.** If a deletion appears to require editing any KEEP module's
   imports, that is the signal to STOP — the module is not dead.

After the workflow: `cabal build all && cabal test && bash scripts/verify-doc-claims.sh` green on the
merged result, with the test total reduced by the removed law groups and ~1,454 fewer src LOC.
