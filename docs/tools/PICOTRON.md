# Picotron, Living Reference
> Status: LIVING · Last updated: 2026-06-30 · Owner: SixFour

## Purpose (one paragraph: why SixFour cares about this tool)
Picotron is the closest existing "fantasy workstation" to the desktop SixFour wants to build for its V2.0 UI: a self-contained, windowed, multi-process editing environment whose entire userland (editors, terminal, file browser) is built from a single retained-mode GUI toolkit over an indexed-palette 2D framebuffer. Three ideas make it directly load-bearing for SixFour. First, its windowing model (process-per-window desktop, workspaces, `create_gui()` + `elem:attach{}`) is a concrete minimal template for a SixFour editing desktop where the palette cloud, nudge-paint, and L/a/b bench become linked, attachable panels. Second, its POD data model ("store a Lua table = a file") and cart-as-folder packaging mirror SixFour's need to serialize octant/lattice state and bundle GIF89a assets with code. Third, its indexed color-table + selection-bit blending is philosophically adjacent to SixFour's GIF89a-as-codec / palette-as-value-head substrate, and its general `userdata` typed arrays are exactly the storage primitive a 16³/256³ voxel lattice would live in on such a machine. The caveat SixFour must keep in view: Picotron is 2D-only and caps at 64 colors, so the SixFour lattice cannot reuse a native 3D primitive and must supply its own index math and palette scale.

## What it is
Picotron is Lexaloffle's "fantasy workstation": a self-contained virtual machine and windowed desktop operating system, scripted in Lua 5.4, for making pixel-art games, tools, demos, and even its own userland applications. It is positioned as a 16-bit-era big sibling to PICO-8, where PICO-8 is a single-console fantasy console, Picotron is a full (fantasy) desktop OS whose own bundled tools are ordinary, JIT-compiled, user-patchable apps living in `/system/apps`.

## Unique toolset (bullet the distinctive editors/features)
- Code Editor, multi-file Lua source editor.
- GFX Editor, sprite/bitmap editor, up to 256 sprites per `.gfx`, `userdata`-backed.
- Map Editor, multi-layer tile/level editor (`.map`).
- SFX Editor, sound + music via a 64-node modular synthesizer.
- Terminal, a full CLI shell (`ls`/`cd`/`cp`/`load`/`save`/`run` plus custom commands).
- File Navigator / `filenav`, graphical filesystem browser with drag-and-drop.
- All bundled tools are ordinary userland apps in `/system/apps`, JIT-compiled and user-patchable.
- GUI toolkit, `create_gui()` root + `elem:attach{}` retained-mode child tree, each element carrying its own `update`/`draw`/`click`.
- Drawing API, `spr`, `sspr`, `rect`, `rectfill`, `circ`, `line`, `map`, and `tline3d` (textured lines / pseudo-3D).
- `userdata` typed arrays/matrices (u8/i16/f64, vec2/3/4) with `:get`/`:set`/`:width`/`:height` plus batch GFX ops.

## Data & file formats
- **Cartridge `.p64`**, logically a FOLDER (not a flat file) that appears as a single file on the host; unlimited size for local dev; auto-mounted at `/ram/mount` and periodically flushed.
- **`.p64.png`**, a shareable PNG-wrapped cartridge holding up to 256k of compressed ROM, postable to the Lexaloffle BBS.
- **POD (Picotron Object Data)**, every file/folder IS a single POD: an unstructured tree mirroring a Lua object. Save any table with `store('foo.pod', tbl)` and read it back with `fetch()`.
- **`.gfx`** (sprites, up to 256/file), **`.map`** (tile maps), **`.sfx`** (audio), typed asset files inside a cart.
- **Text/code files** (`.lua`, `.txt`) use `pod_format='raw'` with metadata on the first line; all files carry POD metadata (created/modified/revision, incremented per save).

## 3D / voxel model (or "2D only" with detail)
Picotron has **no native voxel or 3D model**, it is a 2D pixel framebuffer machine. The only 3D-ish primitive is `tline3d` (perspective-correct textured lines) for pseudo-3D / mode-7-style rendering. However, the `userdata` type is a general typed N-D array/matrix (u8/i16/f64, addressable via `:get(x,y)`/`:set(x,y,v)` and multi-dimensionally), so a 3D lattice would be stored as a `userdata` buffer with a user-defined index mapping (e.g. linearized `x + y*W + z*W*H`); a voxel's color would be an index into the 64-entry color table or a packed value written via `:set`.

## UI / windowing model
A true windowed desktop environment (unlike PICO-8's single-console model): multiple resizable/movable windows, a wallpaper/desktop, and multiple "workspaces" (virtual desktops) that default to `/desktop` in desktop mode. Each window is a process; system tools run as concurrent userland processes. The UI is built with the retained-mode GUI toolkit, `create_gui()` returns a root element and `elem:attach{...}` nests child widgets (buttons, etc.), each carrying its own `update`/`draw`/`click` callbacks; the window manager routes events down the element tree. Inter-process communication and caching flow through the `/ram` drive.

## Resolution & palette
Three display modes: **480×270** (default), **240×135**, and **160×90**. Color: **64 total definable colors** (32 default system colors). Four color tables live at `0x8000`, `0x9000`, `0xa000`, and `0xb000`, enabling per-pixel effects, overlapping shadows, fog, tinting, additive blending, and clipping via color-table + selection-bit tricks.

## Relevance to SixFour (GIF89a-as-codec, the 16³→256³ voxel lattice, and the V2.0 UI port)
1. **Windowing (V2.0 UI port).** Picotron's process-per-window desktop + workspaces + `create_gui`/`elem:attach` retained-mode tree is a concrete, minimal model for a SixFour editing desktop: multiple linked panels, palette cloud, nudge paint, the L/a/b bench, realized as attachable child elements, each with its own `update`/`draw`/`click`. The window manager's event routing down the element tree is the pattern SixFour's SwiftUI host (`NudgePaintView` / `PaletteCloudView`) can mirror.
2. **Data model (POD ↔ serialized lattice).** POD ("store a Lua table = a file") closely mirrors SixFour's need to serialize octant/lattice state, and `.p64`-as-folder maps to bundling GIF89a assets + code together as one project.
3. **Voxel lattice.** The `userdata` typed-array (u8/i16/f64) with explicit index math is exactly how a 16³ or 256³ SixFour voxel buffer would be held on such a machine, coloring each voxel through a 64-entry palette table, directly analogous to GIF89a's indexed palette, and the natural on-machine home for the self-similar octant lattice (the `octantLift`-twice 16³→256³ spine plus time axis) that already exists in SixFour.
4. **GIF89a-as-codec parallel.** Picotron's indexed color-table + selection-bit blending is philosophically close to treating an indexed-palette bitmap format as the substrate; its 64-color definable table is a scaled-down cousin of SixFour's palette-as-VALUE-head idea (per-frame palette = value head, LZW index stream = discrete content head).
5. **Caveat.** Picotron is 2D-only (no built-in voxel addressing) and caps at 64 colors, so a SixFour 256³ / full-color lattice would need a custom `userdata` layout and cannot reuse a native 3D primitive beyond `tline3d`. The 3rd dimension must be reconciled with SixFour's existing lattice + time axis, not invented fresh.

## Open questions (things still to verify)
- Exact `userdata` maximum dimensionality and per-buffer size limits (can it hold a 256³ buffer directly, or only via chunking?).
- Whether `tline3d` alone is sufficient for any usable pseudo-3D lattice preview, or whether a full software rasterizer in Lua is required.
- Precise per-element GUI event/callback contract (full signature of `update`/`draw`/`click`, hit-testing rules, z-order) needed to faithfully re-implement the panel model.
- How the four color tables (`0x8000`/`0x9000`/`0xa000`/`0xb000`) and selection bits combine mechanically, the exact blending/clipping math, for mapping to SixFour's palette=value-head semantics.
- POD binary layout / versioning guarantees (is POD byte-stable across Picotron versions for long-term SixFour serialization?).
- Whether `.p64` folder mounting semantics (`/ram/mount`, flush timing) are safe for bundling large GIF89a asset sets.
- Licensing / whether any of this is directly reusable vs. reference-only for SixFour.

## Sources (the consulted URLs)
- https://www.lexaloffle.com/dl/docs/picotron_manual.html
- https://www.lexaloffle.com/dl/docs/picotron_filesystem.html
- https://www.lexaloffle.com/picotron.php
- https://www.lexaloffle.com/picotron.php?page=faq
- https://en.wikipedia.org/wiki/Picotron
- https://github.com/jesstelford/picotron-man
- https://www.lexaloffle.com/bbs/?pid=pgui
- https://github.com/srsergiorodriguez/pgui

## Changelog
- 2026-06-30: initial draft (automated research)
