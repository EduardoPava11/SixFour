# PICO-8: Living Reference
> Status: LIVING · Last updated: 2026-06-30 · Owner: SixFour

## Purpose
PICO-8's role in SixFour is narrow and practical: it is a **look-and-demo sketchpad**, not a codec, runtime, or architecture precedent. It has exactly two jobs. (1) **Structure the UI's 2D and 3D GIF looks**: mock up how a 2D GIF frame and a 3D voxel-GIF volume should read on screen before that presentation is built in Swift/Metal. (2) **Demonstrate the cell grid**: build a throwaway interactive demo of the `CellBudget` / Morton `16³` nudge grid so the interaction can be shown and felt without touching the shipped app. Its fixed 128x128 framebuffer and instant `_update`/`_draw` loop make it the fastest surface to sketch these. The codec role belongs to GIF89a itself, the voxel-data model to Voxatron, and the UI shell to Picotron; PICO-8 is only the visual prototyper.

## What it is
PICO-8 is Lexaloffle's virtual 8-bit-style "fantasy console": a self-contained 128x128 / 16-color Lua machine with built-in code, sprite, map, SFX and music editors. Games ship as tiny 32KB cartridges, either as `.p8` text files or as `.p8.png` steganographic label images.

## Unique toolset
- **Code editor:** Lua source with the 8192-token / 15360-byte-compressed limits enforced live.
- **Sprite editor:** edits the 128x128 sprite sheet (256 8x8 sprites; upper/lower banks shared with the map).
- **Map editor:** 128x32 tilemap (plus a 128x32 region shared with sprite sheet bank 2); one byte per tile referencing sprite indices.
- **SFX editor:** 64 sound effects of 32 notes each, with per-note pitch/instrument/volume/effect across 4 playback channels.
- **Music/tracker editor:** chains SFX patterns into songs across the 4 channels.
- **Integrated tooling:** built-in GIF/screenshot capture, a cart runner/console, and the BBS 'splore' cart browser, all inside the console.

## Data & file formats
- **`.p8`**, human-readable UTF-8 text cart with `__lua__`, `__gfx__`, `__gff__` (flags), `__map__`, `__sfx__`, and `__music__` sections.
- **`.p8.png`**, a 160x205 PNG (a cartridge-label image) storing 32,800 bytes steganographically: each cart byte is packed into the 2 least-significant bits of the A, R, G, B channels, ordered ARGB (A holds the top 2 bits).
- **`.p8.rom`**, a raw 32KB binary image of cartridge ROM.
- **Cart ROM layout**, 0x8000 (32768) bytes: mirrors base RAM 0x0000-0x42ff (gfx/map/flags/music/sfx) plus version/hash metadata. Code is stored compressed via a custom scheme (later PXA), with a limit of 15360 bytes compressed / 8192 tokens.

## 3D / voxel model
N/A, PICO-8 is a strictly 2D framebuffer console (128x128, 16 colors). There is no native 3D or voxel model; any 3D is hand-rolled in Lua by rasterizing into the flat framebuffer.

## UI / windowing model
No windowing or desktop metaphor. There is a single fullscreen 128x128 surface with a command-line console; the built-in tabbed editors (code/sprite/map/sfx/music) and the 'splore' cart browser are the only UI. Runtime programs drive the screen directly via `_init` / `_update` / `_update60` / `_draw` callbacks. Input follows a 6-button model (D-pad + O/X per player, up to the configured number of players).

## Resolution & palette
128x128 pixels, fixed 16-color palette indexed 0-15 (black, dark-blue, dark-purple, dark-green, brown, dark-gray, light-gray, white, red, orange, yellow, green, blue, indigo, pink, peach). The screen framebuffer is 8KB at 0x6000 (4 bits per pixel, 2 pixels per byte). A secondary/undocumented palette adds 16 more selectable colors via `pal`/`poke` in later versions.

## Relevance to SixFour
Two jobs only. Everything else PICO-8 could offer (codec, lattice, byte-exactness) is explicitly out of scope here.

- **Job 1, prototype the 2D and 3D GIF looks.** At 128x128 with a fixed indexed palette, PICO-8 is a fast way to decide how the UI should *present* GIFs. For the **2D look**: draw a single indexed frame and its palette strip to settle framing, palette-swatch layout, and scanline/dither feel. For the **3D voxel-GIF look**: fake the volume by drawing the Z-slice stack as a flipbook, a stacked-parallax "deck of slices", or a cheap isometric projection, so the reading of depth is chosen on screen before any Metal volume renderer exists. Output is a look, not code to keep.
- **Job 2, demonstrate the cell grid.** Render the `16³` `CellBudget` grid as Morton-ordered cells, move a cursor cell to cell, highlight the φ6 diagonal `{0,4,8}`, and show one cell governing its super-res subtree. This is a communication and design artifact for the nudge interaction, runnable and shareable, so the grid can be felt before it is reparented into the SwiftUI V2.0 shell. It mirrors `NudgePaintView` semantics without importing anything.
- **Not a precedent.** PICO-8 does not stand in for the codec (that is GIF89a), the voxel-data model (Voxatron), or the windowed UI shell (Picotron). Its fixed-point math, cart format, and steganography are interesting but not load-bearing for SixFour, do not build architecture on them.

## Open questions
- Which 3D-look fake reads best for a voxel-GIF on a small screen: flipbook Z-scrub, stacked-parallax slice deck, or cheap isometric projection? (Decide in PICO-8, then spec it for Metal.)
- Cell-grid demo scope: does the demo need the full `16³` Morton walk and the φ6 diagonal, or is a single `16²` slice enough to communicate the interaction?
- How faithfully can the 16-color palette stand in for the SixFour palette when sketching the 2D-GIF look, and where does 16 colors mislead the design?
- Cheapest way to get a real SixFour GIF frame onto the 128x128 surface for a look mockup (import path vs hand-placing indices).

## Sources
- https://www.lexaloffle.com/dl/docs/pico-8_manual.html
- https://www.lexaloffle.com/pico-8.php
- https://pico-8.fandom.com/wiki/Math
- https://pico-8.fandom.com/wiki/P8PNGFileFormat
- https://www.lexaloffle.com/bbs/?tid=2400
- http://pico8wiki.com/index.php?title=P8PNGFileFormat
- https://robertovaccari.com/blog/2021_01_03_stegano_pico8/

## Changelog
- 2026-06-30: initial draft (automated research)
- 2026-06-30: scoped PICO-8's role to look-prototyping (2D + 3D GIF looks) and demonstrating the cell grid; removed the codec / lattice / byte-exactness precedent framing (those belong to GIF89a, Voxatron, and Picotron respectively).
