# spec/archive — superseded spec notes (lineage)

Not authoritative; kept for lineage. The executable truth is the `Spec.*.hs` modules + golden
vectors. Archived 2026-06-05.

| Archived doc | Why |
|---|---|
| `PHASE_DIAGRAM.md` | Specs the retired hybrid trunk+delta mode (`.global` removed); interior hypothetical. |
| `COMPETITION.md` | Self-labelled SUPERSEDED (2026-05-27) by the continuous pivot / `Spec.Preference`. |

Note: the duplicate root-level `spec/ANALYSIS.md` was removed (byte-identical to
`spec/analysis/ANALYSIS.md`, which remains canonical).

## Archived 2026-07-13 (cleanup pass)

| Archived file | Why |
|---|---|
| `BEAUTY_FINDINGS.md`, `BLEED_LOOP.md`, `GRAM_MAPPING.md`, `LOOK_NN.md`, `LOOKNET_LAYERS.md`, `MATH.md`, `NN_SPACE_NOTES.md` | Look-net-era design notes (the MLX look-net was abandoned 2026-06-17; its global-palette path is V2-deferred). Were loose in `spec/` root. |
| `ModelAlgebra.hs` | Orphan exploration module — never wired into `spec.cabal`, no importers. |
| `CubeLadderEntropyExperiments.hs` | Orphan experiment (was `spec/experiments/`, the directory's only file) — never compiled by any target since 2026-06-16. |
