# SixFour — The A/B Game: User Story, Full-Stack Export, Saved Learnings

> **Status:** WORKFLOW (2026-06-18). The product, as a user story, and the three open builds it
> needs. Grounded in a reachability map of the taste loop, the export ladder, persistence, and the
> phase FSM. Companion to `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` (the per-frame
> direction) — this doc is the *experience* + the *export* + the *memory*.

---

## 0. The user story (the acts, uprooted)

```
Open ───► Capture ───► A | B ───► (pick · pick · pick … "play the game") ───► Export ───► Saved
 live      burst       two 16×16        each pick moves θ + proposes a            full       learnings
 screen    (64³)       candidates       NEW, narrower orthogonal pair             stack      persist
```

1. **Open.** The app is live (camera).
2. **Capture.** One shutter tap → a 64-frame burst → the deterministic per-frame 64³ GIF (the
   reference). MVP1 is per-frame only (`Feature.globalPaletteV2 = false`).
3. **A | B.** Two **16×16** candidate looks, A and B — the orthogonal `GenomePair` pair
   (`GenomePair.sampleOrthogonalPair`, EXACT ⟂, CI-proven). Rendered through the cell grid.
4. **Play the game.** Tapping a tile IS the pick. Each pick: folds θ by `btUpdate` (the Bradley–Terry
   taste vector), persists it, and proposes the NEXT pair from the θ-tinted base — **closer to taste,
   and narrower** (`DivergenceSchedule`: the policy:value gap `Δ` shrinks). The user keeps picking
   until satisfied.
5. **Export.** When satisfied, the user exports the **full cube ladder {16³, 64³, 256³}** carrying
   the chosen genome.
6. **Saved.** The learnings persist: θ (already), and the chosen genome into a local **gene archive**
   (the RAG store) so next session warm-starts from the user's taste.

---

## 1. What is BUILT vs the three GAPS

### Taste loop — **BUILT** (just needs the per-frame picker wired to it)
- `PersonalTaste.btUpdate` / `embedding(leaves:)` / `leafTint(_:theta:)` — the 770-D Bradley–Terry
  step, the palette→embedding, the leaf-space tint. All golden-gated against
  `Spec.PreferenceUpdate`.
- `PersonalTasteStore` — θ persists as JSON in Application Support (per-device, never cloud).
- `AtlasState.choose` is the *recipe* (pick → embed → btUpdate → save → tint → log) but it is
  **global-coupled** (publishes to `AtlasPaletteStore.curatedLeavesQ16`, the V2-deferred render
  seam) and builds MAXIMIN/PERTURB candidates, not the orthogonal pair.
- **Wiring (this workflow):** the per-frame `CandidatePickView.onPick` calls the `PersonalTaste`
  primitives DIRECTLY (skip the global-coupled `AtlasState`), and re-derives the next orthogonal
  pair. → §2.

### Export the full stack {16³, 64³, 256³} — **PARTIAL** (per-frame deterministic available; learned 256³ + assembly are GAPs)
| Rung | Per-frame deterministic | Status |
|---|---|---|
| **16³** | subsample frames+palettes to 16 (`LadderGIF.workingCopy`) | BUILT (today via the global path; needs a per-frame variant) |
| **64³** | the committed per-frame GIFA | **BUILT** (it's the reference itself) |
| **256³ floor** | `SixFourExport.replicate4x` (index 4× replication, per-frame palette untouched) | **BUILT, per-frame-capable** |
| **256³ learned** | `NetSynth256` / `Spec.Upscale256` (genome-driven detail above the floor) | **STUB** (`error "TODO"`) |
| **assemble all 3 + carry genome** | `Spec.ExportFamily` | **STUB** (100% `error "TODO"`) |
- The `.global64`/`.working16` rungs in `LadderExport` collapse to a GLOBAL palette → V2-deferred.
- **The per-frame export of all three rungs is available DETERMINISTICALLY today** (16³ subsample,
  64³ committed, 256³ replicate4x) — it is just **not assembled**. The learned 256³ is future. → §3.

### Saved learnings — **PARTIAL** (θ persists; the gene archive is a GAP)
- θ persists (JSON). The decision log (DECN v2) persists frozen embeddings for deterministic replay.
- **GAP:** `Spec.GenomeCarrier` (the S4GN genome-in-GIF codec, Int32 Q16) and `Spec.GenomeBlend`
  (federated adopt) have **zero Swift consumer**; no genome is ever extracted or stored. The Phase 7/8
  vector-RAG **gene archive** does not exist. → §4.

### The acts FSM — current vs target
- **Current device FSM** (`Surface.swift`): live → capturing → browsing(pick-4) → rendering(5 stages)
  → review. 13 phases; works; per-frame.
- **Target A/B FSM** (`Spec.ABSurface`, 8 phases: Live → Captured → Picked → Exporting → Done): the
  spec is **100% stub** (`abStep = error "TODO"`).
- **Uproot plan:** MVP1 surfaces the A/B game *inside* the existing `review` phase behind
  `Feature.abCandidatePicker` (already wired); the clean FSM (implement `ABSurface`, add a `captured`
  phase) is the V2 structural step. → §5.

---

## 2. Wiring the game loop (the build this session starts)

The pick→learn→re-propose loop, reusing the BUILT `PersonalTaste` primitives, following the cell grid:

1. **State** (in the review surface, behind `Feature.abCandidatePicker`): `θ = PersonalTasteStore.load()`,
   `pickCount = 0`.
2. **Propose:** `ABCandidates.fromPalette(capturedPalette, theta: θ)` → two candidate looks (sRGB tiles
   + their Q16 leaves). The generators are tinted by θ (`leafTint`) before `sampleOrthogonalPair`, so
   the pair tracks the user's taste; the pair is EXACTLY orthogonal regardless.
3. **Render:** `CandidatePickView` — two **16×16 `CellSprite`** tiles (the cell grid; the 16×16
   `ColorIdentity.palette16` movable-widget upgrade is §5).
4. **Pick:** tap A or B → `winner/loser` Q16 leaves → `θ ← btUpdate(θ, embedding(winner),
   embedding(loser))` → `PersonalTasteStore.save(θ)` → `pickCount += 1`. The computed candidates
   re-derive from the new θ → the NEXT, taste-shifted pair appears. **The loop is the re-render.**
5. **Converge:** `DivergenceSchedule.divergence(pickCount)` scales the proposal spread (future: feed
   it into the override magnitude so A and B narrow as the user settles).
6. **Export affordance:** an Export control (cell-grid) ends the game → §3.

*This session: steps 1–4 + 6-as-hook, compile-checked. Step 5 (Δ→override magnitude) is the next refinement.*

---

## 3. Full-stack export {16³, 64³, 256³} — the design

**Decision: ship the PER-FRAME DETERMINISTIC family now; the learned 256³ is a gated enhancement later.**

`ExportFamily` (port the Haskell stub to a per-frame Swift `ABExportFamily`):
- **64³** = the committed per-frame GIFA (already on disk), re-encoded with the chosen genome applied
  per-frame (`leafOverride` the picked δ into each frame's palette).
- **16³** = `VoxelReduce`-distil the 64³ to the 16³ substrate (Phase 1, owned + 4-lang gated) →
  per-frame palettes of the substrate → GIFA-encode. (This is the *honest* 16³: the lossless
  reduction, not a global collapse.)
- **256³ floor** = `SixFourExport.replicate4x` on the 64³ index cube (per-frame palette untouched).
- **256³ learned** = `NetSynth256` detail above the floor — GATED (`Feature` flag), bit-exact-equal
  to the floor at zero genome (Phase 6 of the migration; stub today).
- **Genome carried in every rung** = embed the chosen 384-DOF genome as the S4GN block (§4) so each
  exported GIF is self-describing and shareable.

Build order: (a) per-frame `ABExportFamily` assembling {16³ via VoxelReduce, 64³ committed, 256³
replicate4x} carrying the genome; (b) the learned 256³ behind its flag; (c) a single "Export Family"
action in the picker. No dependency on the V2-deferred global path.

---

## 4. Saved learnings — the gene archive (RAG)

θ already persists. The NEW build is the **gene store** (the Phase 7/8 object, unified with
CVT-MAP-Elites):

1. **Port `GenomeCarrier` to Swift** — embed/extract the 384-DOF genome as an Int32 LE Q16 S4GN block
   in the exported GIF89a (the wire format is already chosen *because* float/JSON truncates).
2. **On export:** write the chosen genome into the family GIFs (self-describing).
3. **On capture/import:** extract any S4GN block; `GenomeBlend.adoptForeign` folds it as ONE gated
   Compare (never a splice).
4. **The archive:** an on-device store of accepted genomes (Q16 vectors), the CVT-MAP-Elites cells,
   with `genomeInner` (the orthogonality metric, reused) as the similarity. Retrieval seeds the
   next session's base genome `g0` near the user's taste — warm start, not cold. **No JSON on the
   hot path; binary Q16 vectors on a SIMT substrate.**

This is the migration workflow's Phase 7+8 (merged) — see its §9 RAG analysis. The smallest first
step is the `GenomeCarrier` Swift codec (embed on export), which §3 needs anyway.

---

## 5. Uproot the acts (the FSM + the 16×16 widget)

- **MVP1 (now):** the A/B game lives in `review` behind `Feature.abCandidatePicker`. No FSM surgery.
- **V2 (clean):** implement `Spec.ABSurface.abStep` (the 8-phase δ — currently `error "TODO"`), add a
  `captured` phase + `pickA`/`pickB` events to `Surface.swift`, route to a `CapturedPhaseField`. Gate
  the device FSM trace against the spec.
- **The 16×16 widget:** the candidate tiles should become first-class movable widgets — add
  `ColorIdentity.candidateA` / `.candidateB` to `Spec.MovableLayout` (→ `MoveContract` codegen), each
  a 16×16 footprint, rendered through the same cell grid the live `palette16` uses. Then A and B
  inherit the lift→drag→snap placement law for free. (This session uses `CellSprite(16,16)` directly —
  the same primitive — and defers the movable-widget identities to here.)

---

## 6. The build sequence (each gated; per-frame, no global dependency)

- **G1 — Game loop. ✅ DONE.** `CandidatePickView.onPick` → `PersonalTaste` (θ update + save) +
  re-propose from θ-tinted base; export affordance hook. iOS BUILD + GRID lint green.
- **G2 — Δ surfaced. ✅ DONE (display).** `DivergenceSchedule` ported to Swift; the picker shows
  "ROUND n · Δ X.XX" narrowing. *G2b (feed Δ into the override magnitude) needs a spec step-scale —
  remaining.*
- **G3 — Per-frame ExportFamily. ✅ DONE.** `ABExportFamily` assembles {16³ subsample, 64³ committed,
  256³ replicate4x} carrying the genome (S4GN spliced). Rung-dim + genome-round-trip tests. *(16³ via
  the lossless VoxelReduce needs the retained OKLab cube; the subsample is the honest interim.)*
- **G4 — GenomeCarrier Swift codec. ✅ DONE.** Embed/extract the S4GN block; golden vs the spec
  (6 carrier laws now gated in CI).
- **G5 — Gene archive. ✅ DONE (flat first version).** On-device Q16 gene store + nearest warm-start.
  *Full CVT-MAP-Elites + `genomeInner`-on-SIMT index = future (migration §9).*
- **G6 — Learned 256³. ⚠️ SCAFFOLD.** `NetSynth256` is the gated no-op (== floor at zero genome). The
  learned weights need the on-device trainer — NOT a port; this is the drop-in seam.
- **G7 — ABSurface FSM ✅ DONE / movable A/B widgets ⏳ REMAINING.** The 8-phase δ is implemented +
  7 laws gated (was an orphan stub). The candidates render through the cell grid (`CellSprite` 16×16,
  GRID-conformant) + are tappable. Promoting them to movable `ColorIdentity.candidateA/B` widgets
  touches the codegen `MoveContract` + the disjoint-defaults golden — deferred (needs the move-golden
  regenerated + verified on a runnable target, not blind).

---

## 7. Cross-references
- `docs/SIXFOUR-PER-FRAME-GENOME-AB-MIGRATION-WORKFLOW.md` — the per-frame direction (Pillars,
  Phase 1 VoxelReduce done, Phase 3 GenomePair port done, Phase 7/8 RAG analysis §9).
- `docs/SIXFOUR-GLOBAL-PALETTE-RETIREMENT-WORKFLOW.md` — why MVP1 is per-frame only.
- `docs/SIXFOUR-ACTS-WORKFLOW.md` — the original five-acts design.
- Built primitives: `PersonalTaste` (θ loop), `GenomePair`/`ABCandidates` (the pair),
  `VoxelReduce` (16³), `SixFourExport.replicate4x` (256³ floor).
