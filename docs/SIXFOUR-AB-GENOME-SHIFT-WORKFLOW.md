# SixFour — A/B-Genome Shift Workflow

**Status:** canonical direction as of 2026-06-18. Supersedes the manual
capture→browse→pick-4→render→review flow (incl. the picks-drive-render decouple
on branch `feat/per-frame-flow-decouple`). Authored from a 9-agent codebase review
(`ab-genome-shift-review` workflow).

## The shift (user's words)

> "I do not need the user's input anymore. On a frame-by-frame basis everything
> should be done automatically and the user should only really choose GIF A or
> GIF B" … "the orthogonal paths that make the 64³ → 16³ A/B" … "the picking of
> A/B is an infinite game" … "focus this app on the linked neural networks and
> surface their genes. RGBT staggered and the loop of GIF is also related."

Cut all manual frame-by-frame input. Capture → everything automatic → the user
picks **GIF A or GIF B** (two orthogonal genome candidates) → repeat (infinite
game) → export. Refocus on the linked NNs and surface their genes.

## The four rulings (2026-06-18)

1. **A/B semantics = two genomes, ONE collapse.** A and B are the two orthogonal
   palette GENOMES (`GenomePair` δ_A, δ_B) applied over ONE shared reversible
   `VoxelReduce` 64³→16³ substrate. NOT two distinct collapse operators (those do
   not exist and were not chosen). The spec explicitly decouples palette-genome
   orthogonality from the spatial collapse (`GenomePair.hs:36-54`); this ruling
   keeps the collapse side as wiring, not new math.
2. **NN-proposed genes is a HARD V1 requirement.** The linked look-NN must
   PROPOSE the base genome on device. Today there is NO on-device forward pass
   (only the `s4_load_look_net` blob parser). V1 therefore includes a net-new
   hand-written forward kernel (Swift/Metal, zero-dep) + trained-weight deploy.
3. **Infinite game is FORWARD-ONLY for now.** θ keeps learning each pick; no
   past-A/past-B rewind this pass. Do not box it out (keep the FSM/storage
   choices rewind-friendly), but build nothing for redo yet.
4. **"Surface the genes" = BOTH, two lenses.** A `GeneInspector` showing the
   384-DOF per-candidate σ-pair displacement (what makes THIS A vs B) AND the
   770-DOF per-user Bradley-Terry taste θ (the learned-about-you genome).

## What is PROVEN vs WIRED (the honest floor)

REAL + verified (golden-gated, mostly on-device):
- `Spec/GenomePair.hs` — the orthogonal A/B generator. Orthogonality is EXACT
  (`lawPairOrthogonalExact`, ==0 on the Q16 lattice via disjoint-band support, no
  ε). Cold-start-safe (`captureMeasureRanking`, needs no trained NN). Ported
  byte-exact to `GenomePair.swift` + `GenomePairGoldenTests`.
- `Spec/ABSurface.hs` — the 8-phase target FSM (no browse/pick-4; `PickA/PickB`
  self-loop = the infinite game). Total, no-orphan, export-gated, golden-traced.
- `Spec/VoxelReduce.hs` — reversible 64³→16³, already ported to Swift.
- `Spec/DivergenceSchedule.hs` — start-wide-then-converge Δ(n) knob (proven).
- PersonalGenome θ (770-DOF Bradley-Terry) + on-device MPSGraph trainer (live).

ASPIRATIONAL (the gaps to close):
- `ABSurface` has ZERO Swift consumers / no codegen emitter (app runs old Display FSM).
- Live A/B = `AtlasState.perturb` STUB (±chroma), not the orthogonal pair; the
  real pair is gated off (`Feature.abCandidatePicker = false`).
- Render is provably genome-INDEPENDENT (`CaptureViewModel:687`) → today A/B = two
  swatches over ONE GIF. **Genome→bytes is the load-bearing net-new build.**
- No on-device look-NN forward pass (only a blob parser).
- `onExport` is an empty stub; `ABExportFamily` golden-tested but zero callers.
- No redo/history substrate (θ overwritten in place; `GeneArchive` has no callers).

## KEEP / CUT / REPURPOSE / BUILD

KEEP: `ABSurface.hs`, `GenomePair` (spec+swift), `VoxelReduce`, `DivergenceSchedule`,
`CanonicalPhase`, PersonalGenome θ + `PersonalTaste.btUpdate` + `DecisionLog`, the
64-frame Z₆₄ loop.

CUT (from the live flow; tag-not-delete where it's a green regression ref):
`BrowsingPhaseField` (scrub/pick-4 UI), `.picked4`/`.selectFrame` + `Surface.picks`/
`togglePick`/`scrubCursor`, `AtlasState.perturb` candidate-B, the global-palette
collapse path (`s4_global_collapse`/`globalPaletteV2`), Review Refine tools
(Depth/Motion/Groups/cut-lever) + Color-Atlas manual curation + GroupRGBT PICK-GROUPS.

REPURPOSE: `Feature.abCandidatePicker` (flip on, fold into auto-flow), the 5-stage
`.rendering` banner (demote to a brief auto-reveal), `ABExportFamily` (rebuild its
16³ rung on `VoxelReduce.vrSubstrate`, wire `onExport`), `GeneArchive` (later redo
substrate), `AtlasTrainer` value net (repurpose V(A)/V(B) to actually RANK), the
dormant RGBT4D spatial lift (wire as the automatic collapse leg, NOT an A/B axis).

BUILD (net-new, V1):
- B1. Swift codegen emitter for `ABSurface` + `Surface.swift` FSM swap.
- B2. **Genome→render-bytes** so δ_A/δ_B produce two genuinely different GIF cubes
  over the shared `VoxelReduce` 16³ substrate. (The load-bearing build.)
- B3. **On-device look-NN forward kernel** (hand-written, zero-dep) + weight deploy
  → the NN proposes the base genome. (Hard V1 per ruling 2.)
- B4. `GeneInspector` UI (both lenses: 384-DOF displacement + 770-DOF θ).
- B5. Smooth Live→Capture (fold lock+burst into Live per `ABSurface`; pre-warm AE/AWB).

## Dependency-sequenced phases

- **P1 — Port the target FSM (the spine).** Add `emitABSurfaceContract` to
  `Codegen/Swift.hs` → `Generated/ABSurfaceContract.swift` (8 phases, 11 events,
  golden trace). Port `abStep` into `Surface.swift` (new `ABPhase`/`ABEvent`),
  re-point `assertSpecParity`, regenerate the golden happy-path trace. Keep the
  clock/Lattice/projection half of `Display` unchanged. Keep `Display.hs`
  compiled as a deprecated reference until `ABSurface` is proven live.
- **P2 — Make A/B real + auto.** Flip `Feature.abCandidatePicker`; route
  `ABCandidates.fromPalette` (`GenomePair.sampleOrthogonalPair`) as the live
  producer; delete `AtlasState.perturb`. Promote `CandidatePickView` to the
  primary `Captured` surface. θ-fold per pick = the infinite-game loop.
- **P3 — Genome shapes the bytes.** Build B2: δ_A/δ_B drive two distinct rendered
  cubes over the shared `VoxelReduce` substrate. Wire `onExport → ABExportFamily`;
  rebuild its 16³ rung on `vrSubstrate`.
- **P4 — Delete the cut flow + fix the handoff.** Remove the CUT list from the live
  flow; demote the render banner; smooth Live→Capture (B5).
- **P5 — Surface the genes.** Build `GeneInspector` (B4, both lenses), reusing
  Atlas board widget plumbing.
- **P6 — Linked-NN refocus (hard V1, ruling 2).** Build B3: the on-device look-NN
  forward kernel + weight deploy so the NN proposes the genome; repurpose the
  Atlas value net to RANK A/B; port `RGBTFeature` as the per-frame feature
  substrate with a real weight source. `NetSynth256` 256³ super-res last.

Spec-first per `CLAUDE.md`: any new integer math → Haskell `Spec.*` + golden
vectors → `cabal test` → `cabal run spec-codegen` → port. Each phase ends BUILD
SUCCEEDED (arm64) + green gates.

## Open (deferred, not blocking V1)
- Redo / past-A/past-B history (ruling 3 = later; keep FSM rewind-friendly).
- `DivergenceSchedule` driving generation (today cosmetic; wire so A/B truly converge).
- Genome scope across all 64 frames (RGBT-staggered / loop-of-GIF) vs frame-0 only.
- Gene SHARING (AirDrop a genome).
