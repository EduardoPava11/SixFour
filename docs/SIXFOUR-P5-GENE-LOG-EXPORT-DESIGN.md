# SixFour — P5: A/B Log + Gene→GIF Mapping + Cube-Ladder Export + GeneInspector

**Status:** design (2026-06-19), from a 6-agent research+critic workflow. The A/B LOG (chunk 1)
is **built** (commit `83350e8`); the export + inspector are the follow-on. Branch
`feat/delta-preserving-genome`.

## The user ask
"A log of A vs B and the GIF's mapping" + "is the 16³ what I see, is the 256³ exported with the
64³?". Answers: what you SEE = the **64³** (64 frames × 64×64); 16³ = a 4×temporal+spatial
SUBSAMPLE (not shown); the export currently ships **only the 64³** — `ABExportFamily` (the
{16³,64³,256³} assembler + genome block) is **orphaned**, so 16³/256³ never ship and the GIF
carries no gene.

## The unifying idea: the GIF carries + surfaces its own gene
One genome identity threaded pick → log → export → inspector. The honest gene is the **3-int Q16
`centerShift`** (`IsoMove.translate`; `signs ≡ (1,1,1)`, `shift == centerShift`) — NOT a 384-DOF
σ-pair (that would fabricate data; σ-pair becomes radix=2 only when a σ-pair path feeds the look).

## Chunk 1 — A/B LOG (BUILT, 83350e8)
Reuse `AtlasDecisionLog` (replay-deterministic, additive-Optional-field, single-sourced n).
+6 Optional fields on `AtlasDecisionRecord` (abRound/abPickedA/abWinnerShift/abLoserShift/
abCenterShift/abChosenGeneHash). `pick()` appends a Compare record (fnv1a32 leaf hashes +
770-D embeddings + the gene). `GeneLogView` + a GENES toggle on Done shows the rounds.

## Chunk 2 — Gene→GIF mapping + cube-ladder export (FOLLOW-ON)
- **Spec-first** `Spec/ChosenGene.hs`: the 3-int (centerShift) gene layout, dof=3, radix=1
  ("IsoMove-translate-Q16-v1"), + a `genomeToIso` round-trip law + golden vectors. (The only
  genuinely new integer math; cite the EXISTING `Spec.Export.lawReplicatePreservesUsedSet` for
  the 256³ per-frame-brand, do NOT re-author.)
- **`ABExportFamily.encodeBundle`**: wire the orphan. Per-rung encoder:
  - **64³ hero** = `ABExport.encodeChosenLook` (base cube = engine-validated `CompleteVoxelVolume`).
  - **256³** = `GIFEncoder.encode(volume: base, perFramePalettes: chosen, upscale: 4)` — frames
    stay 64² for the brand, replicate at LZW emit; replication preserves each frame's slot-set so
    the per-frame brand HOLDS.
  - **16³** = the existing naive `subsampleSpatial` (top-left) + every-4th-frame, labelled
    "16³ preview (lossy)"; may not be K-surjective ⇒ encode via `GIFEncoder.encodeGlobal` (no
    completeness brand, the LadderExport escape). Honest `VoxelReduce.vrSubstrate` 16³ deferred.
  - Splice the SAME S4GN block into all three.
- **BLOCKER (critic):** `spliceGenome` inserts at byte 13 — that is INSIDE the 16³ rung's Global
  Color Table (bytes 13..781). Make `spliceGenome` **GCT-aware** (parse the LSD packed byte at
  offset 10; insert after the GCT) before the 16³ rung carries a gene. The existing test misses
  this (extract scans anywhere); add a real-encodeGlobal-GIF golden.
- **Map back:** stamp `Header.deviceIdHash = winner CRC` + `Header.btCompares = n` (overload the
  always-0 fields; zero schema churn) so a GIF's S4GN block ↔ its log entry. `MappingProbe.describe(url)`
  = extract + log lookup.
- **Output:** `sixfour-look-<uuid>/look-{16,64,256}.gif`; Done's ShareLink default-shares the 64³
  hero (what you see), the folder/siblings secondary. `Surface.gifURLs: [String:URL]`.

## Chunk 3 — GeneInspector (FOLLOW-ON)
A cells-only sub-view on Done (NOT a new FSM phase), GENES toggle (the log already lives here):
- LENS A — the chosen gene (`chosenGeneCoeffs`, the 3-int shift) — the gene IN the exported GIF.
- LENS B — the 770-D taste θ as a heat band (the cumulative preference).
- the log strip (built). Reuse `CellText`/`CellSprite`/`place()` + the preserved Atlas board plumbing.

## Critic corrections folded in
- Gene = 3-int centerShift (honest), not 9-int, not σ-pair 384.
- `spliceGenome` GCT blocker (above) — must fix before 16³ carries a gene.
- Hash-domain hazard: live gene hash in the DEDICATED `abChosenGeneHash`, leave winHash/loseHash
  fnv1a32-of-leaves (Atlas domain) — done in chunk 1.
- `lawReplicatePreservesUsedSet` already exists — cite, don't re-author.
- `GenomeCarrier` is in `SixFour/Palette/`, not `Encoder/`.
- Atlas board is unwired post-P4 (the "double-source n" rationale is moot; reuse is still right
  for replay-determinism + the additive-field precedent).

## Open decisions (recommendations)
- Gene dof=3 (honest centerShift) [rec] vs dof=9 (forward-headroom). | 16³ naive-first [rec] vs
  honest VoxelReduce now. | per-pick log [rec] vs final-only. | session resume from log.compareCount
  [rec] vs fresh round 1. | deviceIdHash overload [rec] vs new Header field.
