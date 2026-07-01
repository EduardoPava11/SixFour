# Voxatron, Living Reference
> Status: LIVING · Last updated: 2026-06-30 · Owner: SixFour

## Purpose (one paragraph: why SixFour cares about this tool)
Voxatron is the closest existing prior art to SixFour's core premise of a "voxel-pixel as codec cell." In Voxatron a voxel is a single 8-bit palette index into 256 possible colors, which is exactly SixFour's `256 = 16^2` palette premise and its GIF89a-as-codec, palette-indexed-cell model. Its fixed volumetric display and integer-XYZ addressing validate SixFour's discrete-lattice thinking, and its integrated modal editors, palette-encoded semantic voxels, object banks, and world-tick timeline are a directly reusable design language for a SixFour V2.0 UI port. SixFour cares about Voxatron as both a conceptual sanity check ("one palette-index per lattice site") and a concrete UX reference.

## What it is
Voxatron is a Lexaloffle "fantasy console" for making and playing volumetric (voxel) games rendered on a fixed 128x128x64 holographic voxel display. It is effectively a 3D PICO-8: its API is a superset of PICO-8 v0.1.11, and its content is created, browsed, and launched through a PICO-8-style console shell. A voxel is a colored cube, the 3D equivalent of a pixel.

## Unique toolset (bullet the distinctive editors/features)
- **Prop Editor / Voxel Designer (VOXDE):** edits a single voxel model with Build, Paint, Dropper, Stamp, Box, Select, and Fill tools.
- **Object Editor:** the central interface for editing a selected object definition (props, actors, items shown as statues).
- **Room Editor:** places and arranges object instances in a room; includes an animation/timeline lane.
- **Resource Navigator:** a hierarchical browser with five tabs (Rooms, Objects, Internal, Metadata, plus history navigation).
- **Six Voxel Object Banks (VOBs):** act like folders/pages to organize level props and objects; copy/paste moves items between the six pages.
- **Palette-encoded voxel behaviors:** gray shades at the palette bottom-right = indestructible voxels; magenta = negative voxels that subtract/carve empty space.
- **Importers for external assets:** `.p8` PICO-8 cartridges, plain 2D `.png` images, and `.qb` Qubicle Constructor scenes.
- **Metadata tab:** for editing the optional 60x32 splore label image.

## Data & file formats
- Cartridges are stored as standard `.png` image files: a label image with cart data steganographically embedded, mirroring the PICO-8 png-cart scheme.
- Carts under 256k compressed live in a single png; data beyond 256k is appended underneath, allowing up to ~1MB compressed.
- Two label images per cart: a preview screenshot for the BBS player plus an optional 60x32 splore label.
- Import formats: `.p8` (PICO-8), `.png` (2D image), `.qb` (Qubicle Constructor).
- Distribution via the Lexaloffle BBS "splore" browser, PICO-8-style.
- Voxel data is kept in a deliberately compact format: each voxel = one 8-bit value (a palette index).

## 3D / voxel model (or "2D only" with detail)
Voxatron is genuinely 3D/volumetric. A voxel is a colored cube = the 3D equivalent of a pixel. The world is rendered to a fixed 128x128x64 volumetric display buffer (3D video memory flushed to screen each frame). Each voxel is a single 8-bit value = a palette index into 256 possible colors (color maps directly to the voxel). Voxels are addressed by integer XYZ coordinates: X = right, Y = forward/into-scene, Z = up/down (Z increasing = down in the animation-offset docs). Actors/objects declare bounding/collision boxes as WIDTH, LENGTH, HEIGHT in voxels, and animation frame offsets are given in whole voxels along X/Y/Z. Rooms historically capped near 256 voxels per side / by total voxel budget for physics-scan performance; the editor map/display height was raised from 48 to 64 in v0.2.10.

## UI / windowing model
Voxatron uses a PICO-8-style fantasy-console shell: a boot/console screen plus a built-in suite of modal editors (Object/Prop/Room editors + Resource Navigator with tabbed panels) rather than a windowed desktop. Content is browsed and launched through "splore," Lexaloffle's cart browser backed by the BBS. It is not a general windowing/desktop OS (that is Lexaloffle's later Picotron); Voxatron's UI is the game runtime plus its integrated designer tabs.

## Resolution & palette
- Fixed volumetric display of **128x128x64** voxels.
- Each voxel stores an **8-bit palette index = 256 possible colors**.
- The palette carries semantic slots: gray bottom-right = indestructible; magenta = negative/subtractive voxels.
- The optional splore label image is **60x32**.

## Relevance to SixFour (GIF89a-as-codec, the 16^3->256^3 voxel lattice, and the V2.0 UI port)
- **Codec-cell parallel:** a Voxatron voxel = one 8-bit palette index into 256 colors, exactly SixFour's `256 = 16^2` palette premise and its GIF89a-as-codec, palette-indexed-cell model. In SixFour terms this is the LZW index stream (discrete CONTENT head) selecting into the per-frame palette (VALUE head).
- **Lattice validation, with a caveat:** Voxatron's fixed 128x128x64 volume and integer-XYZ addressing validate SixFour's discrete-lattice thinking. But SixFour's target is the `16^3 -> 256^3` self-similar octant-lift lattice (a cube-of-cubes, `octantLift` applied twice) rather than Voxatron's single flat 128x128x64 buffer. The shared invariant is "one palette-index per lattice site" in both; the reconciliation work is mapping SixFour's self-similar spine onto (or against) a flat volumetric buffer like Voxatron's.
- **Reusable V2.0 UI design language:** the modal voxel Prop Editor with Build/Paint/Dropper/Box/Fill mirrors SixFour's NudgePaintView paint tools and CellBudget; palette-encoded semantic voxels map to SixFour's indestructible-floor vs subtractive-nudge distinction; the six object banks map to organizing cells; and the world-tick timeline animation maps to SixFour's t-axis / GCE temporal deltas.
- **Container == payload:** the png-cart-with-embedded-data format parallels SixFour's GIF-as-container-and-model idea (the asset file doubling as the codec payload), and splore-style BBS browsing suggests the gallery model for a SixFour capture corpus.
- **UI-port note:** the user's V2.0 look/feel reference is Picotron's windowed workstation, not Voxatron's modal console shell; Voxatron contributes the *voxel-editing tool semantics* and *palette/cell/timeline concepts*, while Picotron contributes the *windowing model*.

## Open questions (things still to verify)
- Exact byte layout of the embedded cart data inside the png (header, compression scheme, offset of the >256k appended region).
- Whether the palette is fixed/standard PICO-8-derived or user-remappable, and the precise index positions of the gray-indestructible and magenta-negative semantic slots.
- Full list and semantics of Prop Editor tools beyond Build/Paint/Dropper/Stamp/Box/Select/Fill, and any keyboard/modal interactions.
- Precise per-room voxel budget / physics-scan cap and how it changed across versions (only the 48->64 map-height bump in v0.2.10 is confirmed).
- How the animation/timeline lane in the Room Editor encodes frames (frame count limits, interpolation, per-object vs per-room timing).
- Coordinate convention consistency (Z-down in animation-offset docs vs Z = up/down generally) and its impact on any SixFour lattice mapping.
- Exact behavior/lossiness of the `.p8`, `.png`, and `.qb` importers (how 2D pngs and Qubicle scenes are lifted into the voxel volume).
- Runtime scripting API surface: which PICO-8 v0.1.11 functions are supported/extended for 3D.

## Sources (the consulted URLs)
- https://www.lexaloffle.com/vox_manual.html
- https://www.lexaloffle.com/bbs/?tid=1416
- https://www.lexaloffle.com/bbs/?tid=1498
- https://www.lexaloffle.com/bbs/?tid=221
- https://www.lexaloffle.com/bbs/?tid=996
- https://voxatron.fandom.com/wiki/Voxel_Designer
- https://www.lexaloffle.com/bbs/?tid=33289
- https://www.lexaloffle.com/bbs/?tid=33268

## Changelog
- 2026-06-30: initial draft (automated research)
