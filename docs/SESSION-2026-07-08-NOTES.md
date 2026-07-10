# Session notes — 2026-07-08 (perf → independence → UX instrument → THE SCROLL)

> Handoff notes, not a status ledger. Branch: `perf/thermal-budget-round1`, six commits ahead of
> `master` (land with `git merge --ff-only perf/thermal-budget-round1`). Every commit passed the
> full gates at landing time: cabal spec suite + simulator test suite + GRID lint +
> verify-doc-claims. Nothing here is device-validated yet except the pre-session baseline.

## The six commits (oldest first)

1. **`2d738d3` Perf: hot-path round 1** — SIMD16 pre-scan + chroma-pair hoist on the per-tick
   x420 pool; poolV21Counts off the shutter seam (new `v21CountsCallback`); v21 hist buffer
   u16 = **384 MiB (was 768)** with a scale>63 guard; pyramid bake caching; `s4_set_log_gate`;
   texture pool + `BandHeadTrainer.shared`; LUT export deprecated (`Feature.lutExport=false`);
   Batch-0 excludes (8 mechanically-verified zero-ref files); troubleshoot logs (aggregate,
   never per-tick): `[perf] yin-yang tick CPU`, `[tick] LATE frame`, pool-miss counter,
   hist-buffer MiB. Map: `docs/PERF-MAP.md`.
2. **`948d2c4` The Loom's independent rungs** — Daniel's direction: the three resolutions must
   be INDEPENDENT data signals (derived pooling teaches the model the pooling operator).
   `Spec.RungTelemetry` (13 laws), CaptureRecord v2 (`c64/c32/c16` + zigzag signed `ev` + `tel`;
   v1 bytes unchanged), `BurstWeaveDriver` (16-tick super-cycle, owned 24/12/4, real weave word
   into the `.s4cr`), `liveScene` rung/system grid regions + `RungTelemetryField`. Ladder mode
   (`Feature.multiScaleLadder`, still OFF) gates off v21 hist + ColorHead per burst BY DESIGN.
3. **`fca6522` Live glow tracks the pyramid** — `field64/32/16` pyramid-band regions in
   liveScene; influence-ground sources re-anchored (CPU + GPU twins).
4. **`057db09` UI/UX reorg + charter** — function-first `UI/{Lattice,Cells,Ground,Machine,
   Scenes/*,Widgets}` (51 pure renames); `docs/UI-FORM-FOLLOWS-FUNCTION.md` = the charter
   (five device-review debts + THE INSTRUMENT FRAMING: color as energy, waves moving — every
   visualization surfaces a real spec quantity).
5. **`53e8bb4` THE POUR** — the synthesized design (4-way competition): coarse rungs are TRUE
   temporal integrals (acc32/acc16, honest cadences 20/10/5 Hz); **capture-freeze root-caused
   and fixed** (non-quantized publish branch starved the pyramid); the 16² is the banked weave
   ledger (4 cells/frame, 64×4=256 by law); ControlFace algebra (lint-policed) + shutter
   BRACKETS beating at the mod-4 realize; flux bar (paletteW1); palette widget DELETED from
   Live; ground's named function = capture energy; Decide rebuilt around ACCEPT/AGAIN with the
   advanced fold. `Spec.ColorTimeDisplay` (9 laws) pins all display cadence to the one tick.
6. **`5b43a88` THE SCROLL** — Jeandel–Rao 11-tile aperiodic Wang tiling as the SKI state
   machine: `Spec.WangTiling` (tiles verified against Labbé's slabbe package; O(1) toral oracle
   in exact ℤ[φ]; NOTE the citation: toral coding = arXiv:1903.06137, substitution fallback =
   arXiv:1808.07768; the oracle emits the MINIMAL subshift — a feature, positive recurrence).
   THE COUNT: 11 ops = {I} ∪ {K_x,K_y,K_t} ∪ {S_x,S_y,S_t} ∪ {S_xy,S_xt,S_yt} ∪ {S_xyt} —
   the axis-graded SKI algebra is exactly eleven. Gene = attention (`lawAttentionModulatesNot
   Mutates`, mutation-tested). `SixFour/Tube/` + `Scenes/Scroll/` (`Feature.scrollTube`) +
   BOOT RESOLVE on Live (16²→32²→64² at the pour boundaries, display-only).

## Device validation queue (nothing validated yet)

`docs/LOOM-RUNGS-DEVICE-CHECKLIST.md` has the full script. Highlights: boot crystallization;
burst is alive (ledger fills, no freeze) + `[perf] yin-yang tick CPU` line in Console; rung
flank meters + `=4F/=2F` labels; Decide ACCEPT/AGAIN + fold; the scroll tube (aperiodic
novelty, refine-on-linger, gene swap changes look not sequence); Phase B = flip
`multiScaleLadder` for the independent-exposure bring-up.

## Open ledger (next session's menu)

- **Scroll round 2**: the RAG retrieval index (capture/gene descriptors → nearest-neighbor tube
  seeding) was designed but NOT built; AnytimeDecode repair still pending (the lazy-expansion
  law exists only at tube granularity); mmap'd tube store upgrade path documented, not built.
- **Perf medium tier**: fold v21 hist into the box-average GPU pass; H1 deep cut (fuse x420
  convert+pool, spec golden first); shorten the flow-encode buffer hold (384 MiB × ~19 s).
- **Ring re-map Batches 1–3** (PERF-MAP §3.5): file splits → Attic moves → HotPath/Shutter/
  Render moves. Batch 0 landed; the rest needs the test-target-sources pattern for
  golden-test-referenced files.
- **Scenes not yet passed**: Review (V21 widgets → debug gate?), Curate, Bootstrap.
- **Watch items**: one unreproducible QuickCheck flake (identity unknown, suite green ×2 after);
  the loom workflow's hot-path verify lens died (its territory was partially covered by the
  other lenses — a fresh hot-path audit post-THE-POUR would close it); `docs/APP-MAP.md`
  predates the UI reorg (stale paths).

## Standing decisions made this session (also in Claude's memory)

Rung independence is canon; destructive UI changes authorized under commit-first discipline;
the instrument framing (color as energy) outranks style; THE POUR's 4-into-1 vocabulary is the
app-wide quantum (capture, boot, scroll); tiling = syntax / gene = semantics / attention = the
gene's weighting; 11 is the theorem-minimal tile count (Jeandel–Rao) and the repo's own op count.
