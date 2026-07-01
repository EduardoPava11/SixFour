# Lexaloffle Tool References (Living Documents)

> Status: LIVING · Last updated: 2026-06-30 · Owner: SixFour

Living references for the three Lexaloffle tools we mine for SixFour's V2.0
direction. Each doc is built to be revised: it carries a status line, cited
sources, explicit open questions, and a changelog. Update the doc (and bump its
changelog) whenever a fact is verified or a decision lands.

| Tool | Role for SixFour | Doc |
|---|---|---|
| **PICO-8** | Look-and-demo sketchpad: prototype the 2D + 3D GIF looks, demonstrate the cell grid | [PICO-8.md](PICO-8.md) |
| **Voxatron** | The **voxel-pixel** design reference (1 byte/voxel = 1 palette index into 256) | [VOXATRON.md](VOXATRON.md) |
| **Picotron** | The **V2.0 UI** reference (windowed fantasy workstation, POD data model) | [PICOTRON.md](PICOTRON.md) |

## Where the framework lives

The synthesis that turns these references into a plan, feeding GIF89a as a
voxel-pixel in 3D space, is the design doc:

- [`../../spec/exploration/VOXEL-PIXEL-GIF89A-FRAMEWORK.md`](../../spec/exploration/VOXEL-PIXEL-GIF89A-FRAMEWORK.md)

## How these were produced

Authored by a research workflow (one web-research agent per tool, then a
per-tool doc author, then a framework synthesizer). Facts are sourced from the
official Lexaloffle manuals, BBS, and wikis; see each doc's Sources section.

## Changelog

- 2026-06-30: initial set (PICO-8, Voxatron, Picotron) + framework doc.
