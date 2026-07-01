# Voxel-Pixel GIF89a Framework, Design (V-next)

> Status: DRAFT · Last updated: 2026-06-30

## 0. Purpose and thesis

SixFour already treats **GIF89a as a codec / H-JEPA substrate**: the palette (Global/Local Color Table) is the **value head**, the LZW index stream is the discrete **content head**, and the Graphic Control Extension (GCE) + multiple Image Descriptors carry the animation axis. Separately, the model owns a **self-similar octant lattice** with a `16³ → 64³ → 256³` super-resolution spine (`reconstruct256` = `octantLift` applied twice, `SixFour.Spec.SelfSimilarReconstruct`).

This document defines a framework that fuses those two facts into one object: **a GIF89a file *is* an indexed voxel volume.** The load-bearing observation is already latent in the codebase, `SixFour.Spec.Export` states the cube pack `{16, 64, 256}` holds "spatially **and in frames** (`= frame counts too`)". SixFour's capture is `64 (x) × 64 (y) × 64 (frames)`; the frame axis is already a *third spatial axis of the cube*. We make that honest: **the GIF frame stack is the Z axis of a voxel cube**, not a wall-clock playback axis.

A **voxel-pixel** is the 3D generalization of an indexed pixel:

```
v : (x, y, z) -> Slot            Slot ∈ [0, 255] = 16²
palette :   Slot -> Colour       -- VALUE head (OKLab Q16 / Eisenstein ℤ[ω]; sRGB8 on the wire)
render(x,y,z) = palette(v(x,y,z)) -- = palette ∘ index, per z-slice (the B combinator, V2Gif89aAxes)
```

---

## 1. Core mapping: GIF89a's existing structure, extended to 3D

### 1.1 What GIF89a already gives us for free

| GIF89a construct | 2D meaning | Voxel-pixel meaning (this framework) |
|---|---|---|
| Global Color Table (≤256) | frame palette | **volume value head**, one `Slot -> Colour` for the whole cube |
| Image Descriptor (one per sub-image) | one animation frame | **one Z-slice** `z = k` |
| LZW index stream per descriptor | 2D `(x,y) -> Slot` | **one XY index plane** at depth `z = k` |
| GCE `transparent color index` | transparent pixel | **empty / "air" voxel** (carved space) |
| GCE `delay time` | playback delay | **repurposed as Z ordering/stride** (playback-time is *spent* on Z) |
| GCE `disposal method` | frame compositing | **Z-compositing convention** (replace = opaque slice; leave = accumulate) |
| Local Color Table (per descriptor) | per-frame palette | **per-Z-slice palette override**, folded to the GCT by the σ_z gauge (§3.4) |

A `64`-descriptor animated GIF sharing one Global Color Table, where descriptor `k` carries the `64×64` LZW index plane at depth `k`, **is exactly a `64³` indexed voxel volume.** No new container is invented; we reinterpret the animation axis as depth.

### 1.2 Critique of the naive "frames = Z" move

The obvious extension ("stack the animation frames along Z") is correct but has three sharp edges that the framework must legislate, not gloss:

1. **The playback collision.** A voxel-GIF opened in Preview/Chrome will *animate* the Z-slices as a flipbook. This is unavoidable given a standard decoder. We treat it as an intentional feature, a free "Z-scrub preview", and pin the real semantics (`delay = Z stride`) in spec, not in the viewer.
2. **Local Color Tables fracture the single value head.** SixFour captures carry a *per-frame* 256-entry palette (`capturePerFrame`). If each Z-slice has its own Local Color Table, "one value head per volume" is false, and the union of palettes can exceed 256. This is resolved by the palette-gauge alignment normal form (§3.4) plus an explicit risk (§7).
3. **Time is now homeless.** If the animation axis is spent on Z, an *animated* voxel object (genuine time) has nowhere to live inside one file. §2 takes a position on this.

---

## 2. Reconciliation with the octant lattice and the time axis

Three candidate readings of "the 3rd dimension," and the committed position.

### 2.1 Rejected: Z = octant depth

The octant ladder (`16³→64³→256³`) is a **scale / epistemic** ladder, not a Euclidean extent. Its steps carry the `DetailSource` split (`Held` exact detail within capture vs `Invented` latent-tail detail beyond capture, `SelfSimilarReconstruct`), a `4³` subdivision, and `lawLadderSelfSimilar`. Making Z the octant depth would:

- break `lawLadderSelfSimilar`, which requires **all three** of x, y, z to scale together (each rung is `N×N×N`); and
- conflate a resolution pyramid with a spatial coordinate, poisoning `reconstruct256`.

**Octant depth is orthogonal to (x, y, z): it is a pyramid *over* the cube, not an axis *of* it.**

### 2.2 Committed: Z = the frame stack = the third equal spatial axis

The cube pack `{16, 64, 256}` is, in SixFour's own words, frame counts too. So the frame axis already scales lockstep with x and y under the ladder. We name this:

- **Capture volume:** `64³` = `wireFrames (64)` Z-slices × `wireSide` mapped by `replicate2D` in XY only. `lawTimeAxisUnscaledAtWire` (frames never scaled at the wire) becomes **`lawFrameAxisIsSpatialZ`**: the wire's 64-frame axis is the volume's Z axis, unscaled by the spatial `replicate2D`.
- **Model floor output:** `upscale256` (space **and** frame, `64³→256³`) super-resolves the full cube including Z. This is the *output* floor, never the wire, the existing `replicate2D`-vs-`upscale256` keystone is preserved verbatim.

### 2.3 Where time goes: a T-indexed sequence of volumes (canonical)

Since one GIF's frame axis is spent on Z, **genuine time is promoted out of the single container into a T-indexed *sequence* of voxel-GIF volumes**, a project is a folder of GIFs, one per time step. This is the canonical form because:

- each volume is an independently valid, byte-exact GIF89a;
- it matches Picotron's `.p64`-as-folder / POD model (§5) directly;
- the existing **GCE inter-frame delta** semantics (`ColourDelta` value / `IndexDelta` policy) simply move up one level: they now measure the delta *between consecutive volumes in T*, exactly preserving the temporal H-JEPA supervision that already exists.

A crucial dividend: the *same* delta machinery becomes reusable **within** a volume as a spatial `∂/∂z` gradient (slice-to-slice coherence), and **between** volumes as `∂/∂t`. One `ColourDelta`/`IndexDelta` algebra, two applications.

Alternative (noted, non-canonical): pack `N_z · N_t` descriptors into one GIF with a disposal-method stride encoding (Z) vs delay-marker (T). Rejected as canonical because disposal-stride conventions are fragile across decoders and defeat the "each file is a valid volume" invariant.

**Summary of the axis budget**

| Axis | Carrier | Scaling |
|---|---|---|
| x, y | XY index plane per descriptor | `replicate2D` / `decimate2D` (wire), `octantLift` (ladder) |
| z | GIF frame stack (Image Descriptors) | unscaled at wire; `octantLift` in the ladder (`lawFrameAxisIsSpatialZ`) |
| octant depth | resolution pyramid | `16³→64³→256³`, `reconstruct256`; NOT an axis |
| t (time) | sequence of GIF volumes (folder) | inter-volume `ColourDelta`/`IndexDelta` |

---

## 3. Voxel-pixel data model

### 3.1 Coordinate space

- Right-handed integer lattice, **X = right, Y = down (image-row order), Z = slice-forward** (Z-increasing = later descriptor). We adopt image-row Y (matches the LZW plane) and reconcile with Voxatron's Z-up in §4 via an explicit transpose at the importer boundary.
- Address is `(x, y, z) ∈ [0,S)³`, `S ∈ {16, 64, 256}`.
- **Morton (Z-order) linearization** for the `16³` control grid is already the convention in `NudgePaintView` (4 bits/axis); the voxel volume reuses it for cell addressing so paint cells map to `cellSubtreeLeaves = 4096` output voxels (`lawCellGovernsSuperResSubtree`).

### 3.2 The two heads

- **Content head (index):** `index_z : (x,y) -> Slot`, one per Z-slice, an LZW-coded plane. Domain is ℤ; addressing is exact.
- **Value head (palette):** `palette : Slot -> Colour`. Internal working space is **OKLab Q16** (or Eisenstein `ℤ[ω]` with `R↦1, G↦ω, B↦ω²`, `1+ω+ω²=0`, gray = kernel). On the wire it is **sRGB8** (`captureColorDepthBits`), because GIF89a cannot store >8 bits/channel: `contractQ16NotRecoverableAcrossGif` holds unchanged, the round trip is exact only at (index plane + sRGB8 palette); Q16 is deterministically re-derived on import.

### 3.3 Byte-exactness over ℤ[1/2]

- Index arithmetic (slice stacking, decimation, Morton walk) is over ℤ, exact by construction.
- Palette/value arithmetic (nudges, `ColourDelta`, deltas along z and t) lives in **Q16 = a ℤ[1/2]-module**: dyadic rationals only, no division by non-units. `octantLift` and all delta moves are module operations, not field operations, the existing discipline extends verbatim to the third axis.

### 3.4 Empty voxels and the palette gauge

- **Air voxel:** the GCE transparent color index decodes to *empty* (no colour, carved space). One reserved Slot is `AIR`. This is preserved under `replicate2D` by the existing opacity guarantee (`lawReplicatePreservesUsedSet`), lifted to 3D as `lawTransparentIsAir`.
- **Palette-gauge normal form:** captures may carry per-slice Local Color Tables. The slot-permutation gauge (relabel `index_z` by σ_z and `palette` by σ_z⁻¹ leaves `render` fixed, the `lawSixAxesFactor` gauge tooth, realized by `Upscale256.alignSlots`) folds all slices onto **one Global Color Table** (the volume value head) plus a residual per-slice `ColourDelta`. When the union of per-slice palettes exceeds 256, alignment is *not* byte-exact, flagged as the top risk in §7.

---

## 4. Borrowed from Voxatron (voxel design reference)

Voxatron is the closest prior art and its representation maps almost 1:1:

- **Voxel = one 8-bit palette index into 256 colours** (the color maps directly to the voxel). This is *exactly* SixFour's `Slot ∈ [0,255] = 16²`. Adopt directly: one byte per voxel, colour via the palette LUT.
- **Integer XYZ addressing, fixed volume `128×128×64`** validates SixFour's discrete-lattice stance; Voxatron *raised its Z from 48 to 64* (v0.2.10), and SixFour's Z = 64 frames matches. SixFour's volume is `64³` (capture) / `256³` (floor output) rather than a flat buffer, but the "one palette-index per lattice site" rule is identical.
- **Semantic palette slots.** Voxatron encodes behavior in palette position: *gray bottom-right = indestructible*, *magenta = negative/subtractive (carves empty space)*. Borrow both:
  - `AIR` / negative slot ≙ magenta subtractive voxel (carve, §3.4).
  - a reserved **floor slot range** ≙ indestructible: these decode to the deterministic zero-genome floor (`ModelFloor`) and **cannot be nudged below `AboveFloorMargin`**, pinned as `lawFloorSlotUnnudgeable`.
- **Compact "one 8-bit value per voxel" format** ≙ the LZW index stream (run-friendly for sparse/air-heavy volumes).
- **Six Voxel Object Banks (VOBs)** as folder/pages ≙ the T-sequence project banks / gallery organization in the UI (§5).
- **Importers (`.qb`, `.png`, `.p8`)** ≙ SixFour importers: a 2D GIF/PNG becomes a single Z-slice; an external `.vox`/`.qb` transposes into the volume (apply the Z-up→Z-forward transpose here).
- **Prop-editor tools (Build / Paint / Dropper / Stamp / Box / Select / Fill)** ≙ the `NudgePaintView` toolset (§5).

---

## 5. Picotron-inspired V2.0 UI: a windowed voxel-GIF workstation

Picotron is the **look/feel reference** (a fantasy *workstation*, not a single-surface console). We port the *shell metaphor* to SwiftUI/Metal; we do **not** port the Lua runtime.

**Tool division of labour for the UI:** Picotron supplies the *windowed shell* (this section). **PICO-8 is the throwaway look-and-demo sketchpad**: before any panel is built in SwiftUI/Metal, PICO-8 is used to (a) settle the **2D and 3D GIF looks** (how a frame, and how the Z-slice volume, should read on screen: flipbook Z-scrub vs stacked-slice deck vs cheap iso) and (b) **demonstrate the cell grid** (the `16³` `CellBudget` Morton walk + φ6 diagonal), so the interaction can be felt and shown before it lands in the shell. PICO-8 outputs a look and a demo, never shipped code. See `docs/tools/PICO-8.md`.

### 5.1 Shell

- A **windowed desktop** with workspaces, wallpaper, and a retained-mode widget tree (Picotron's `create_gui()` + `elem:attach{}` with per-element `update/draw/click`). In SwiftUI this is a host `ZStack` desktop with draggable/resizable panel windows, each an `ObservableObject`-backed pane; event routing mirrors the retained tree. Display-mode ladder (`480×270 / 240×135 / 160×90`) informs a pixel-art chrome scale.
- **Caveat (must design around):** SwiftUI has no cheap process-per-window and no native voxel primitive; Picotron's own 3D is only `tline3d` pseudo-3D and it caps at 64 colours. The volume renderer is a **custom Metal slice/raymarch pass** over the 256-entry palette LUT, not a reused primitive.

### 5.2 Panels (each a window)

| Panel | Role | Existing SixFour surface |
|---|---|---|
| **Palette Cloud** | edit the value head in OKLab/Eisenstein 3-space | `PaletteCloudView`, the L,a,b nudge design language |
| **Nudge Paint** | paint content into the `16³ × 9` control grid (Chroma{A,B,L}×Axis{X,Y,T}), φ6 diagonal `{0,4,8}` | `NudgePaintView` (`CellBudget`, Morton cells, `miGauge`) |
| **L,a,b Bench** | `SwatchVector` (ColourDelta slide) + `TransportRibbon` (IndexDelta transport chain) | the tri-scale linked-delta bench |
| **Z-Scrubber / Volume View** | scrub Z-slices; Metal volume preview | new (renders `render(x,y,z)`) |
| **T-Timeline** | step across the folder-of-volumes (time) | new (drives inter-volume deltas) |
| **Terminal + Filenav** | project ops, byte-golden checks | new, POD-style |

### 5.3 Data model borrowings

- **POD ("store a Lua table = a file")** ≙ SixFour project serialization: a voxel-GIF volume + its `CellBudget` nudge state + aligned palette bundle serialize as one POD-like record; `revision`-on-save maps to a golden-hash bump.
- **`.p64`-as-folder** ≙ the canonical **project = folder of voxel-GIFs** (the T-sequence, §2.3). This is why the folder model, not an interleaved single file, is canonical.
- **`userdata` typed arrays** ≙ the on-device buffers: `u8` for the dense index volume (Morton-linearized), `i16`/`f64` for the Q16 palette. Explicit index math (`x + y·S + z·S²` or Morton) mirrors Picotron's manual layout.

---

## 6. Build roadmap (SixFour discipline)

Order is fixed: **Haskell spec + runghc laws → Zig fixtures → Metal parity → SwiftUI V2.0.** Nothing crosses a tier until its laws are green in `gate.sh`.

### 6.1 Tier 0, Haskell spec, laws FIRST

New module `SixFour.Spec.VoxelVolume` (COMPARTMENT: SWIFT-COREAI | tag:DisplaySide), additive, no golden touched:

- `VoxelVolume` type; `voxel :: (Int,Int,Int) -> Slot`; `sliceZ`, `stackZ`.
- **`lawVoxelPlanesRoundTrip`**, `stackZ ∘ sliceZ == id` and `sliceZ ∘ stackZ == id`: the volume ⇄ indexed-plane isomorphism (round-trip voxel ↔ indexed-planes).
- **`lawZSliceReversible`**, Z-slice extraction is an exact left inverse of stacking, and commutes with `replicate2D`/`decimate2D` on the XY plane.
- **`lawPaletteGaugeInvariance`**, `render` invariant under σ_z on `(LCT_z, index_z)`; extends the `lawSixAxesFactor` gauge tooth; defines the single-GCT normal form.
- **`lawTransparentIsAir`**, transparency-index voxels decode to empty and are preserved under `replicate2D` (lift of `lawReplicatePreservesUsedSet`).
- **`lawFrameAxisIsSpatialZ`**, the wire's 64-frame axis is the volume Z axis, unscaled by spatial `replicate2D` (extends `lawTimeAxisUnscaledAtWire`).
- **`lawCubeLadderScalesZ`**, `octantLift` scales z lockstep with x,y; delegates `lawLadderSelfSimilar` (frame counts `[16,64,256]`).
- **`lawTimeIsSequenceNotFrames`**, time = T-indexed sequence of volumes; within-volume slice delta is `∂/∂z`, inter-volume delta is `∂/∂t` (same `ColourDelta`/`IndexDelta` algebra).
- **`lawFloorSlotUnnudgeable`**, reserved floor slots stay ≥ `AboveFloorMargin` (Voxatron indestructible borrow).
- Reuse **`lawRenderIsBComposition`** (voxel `render = palette ∘ index` per slice) and **`contractQ16NotRecoverableAcrossGif`** (sRGB8 wire).

All exported as predicates, QuickCheck'd in `Properties.VoxelVolume`, wired into `spec/scripts/gate.sh`.

### 6.2 Tier 1, Zig fixtures (byte-golden vs Haskell)

Extend `gif_assemble_fixture_test` / `s4_octant_lift`:

- `s4_voxel_stack` / `s4_voxel_slice` (stack ⇄ slice, byte-golden to `lawVoxelPlanesRoundTrip`).
- `s4_z_delta` (slice-to-slice `IndexDelta`/`ColourDelta`).
- `s4_palette_align_z` (σ_z gauge fold to single GCT; must reproduce Haskell σ exactly).
- A dense `64³` GIF-assemble fixture: encode 64 descriptors + one GCT, decode, assert byte-identical index volume.

### 6.3 Tier 2, Metal parity / golden

- Volume slice/raymarch renderer with the 256-entry palette LUT; golden vs the Zig-decoded volume.
- `octantLift` z-scaling parity for the `64³→256³` floor path.

### 6.4 Tier 3, SwiftUI V2.0 UI

The windowed workstation (§5): Z-scrubber and T-timeline panels first (they exercise the new axis), then reparent `NudgePaintView` / `PaletteCloudView` / L,a,b bench into the desktop shell; project-as-folder POD serialization last.

---

## 7. Open questions and risks

1. **Palette union > 256 (top risk).** If per-slice Local Color Tables collectively use >256 distinct colours, σ_z alignment to a single Global Color Table is **not** byte-exact. Mitigations: (a) enforce one GCT at capture; (b) allow LCTs but carry residual `ColourDelta` per slice and accept lossy alignment at the value head; (c) split the volume. Needs a decision before Tier 1.
2. **Playback-vs-Z collision.** Standard viewers animate Z-slices as a flipbook. Feature or spec violation? Proposal: accept it as a free Z-preview; pin `delay = Z stride` in spec and never rely on decoder timing.
3. **Interleaved N_z·N_t packing.** Is the folder-of-volumes always preferable, or is a single-file `N_z·N_t` layout needed for the trainer's I/O? Disposal-stride fragility vs one-file convenience.
4. **256³ floor output as GIF.** `upscale256` scales Z 64→256; a `256×256×256` GIF is enormous and re-raises per-slice palette drift. Is the floor output ever *serialized* as a voxel-GIF, or only rendered?
5. **Stranding temporal H-JEPA supervision.** Promoting t→z moves temporal deltas to the inter-volume level; the existing temporal training corpus is frame-indexed. Does the trainer need re-plumbing to the folder-sequence, and does within-volume `∂/∂z` want its own supervised head?
6. **Handedness lock.** Image-row Y-down vs Voxatron Z-up; the importer transpose must be a single pinned law, or `.qb`/`.vox` imports mirror silently.
7. **Value head on the wire.** OKLab Q16 vs Eisenstein `ℤ[ω]` both collapse to sRGB8 at the GIF boundary, the choice is internal, but the two produce different `ColourDelta` metrics along z and t; which is canonical for the delta algebra?
8. **Sparse/air-heavy volumes.** Dense planes + LZW handle runs, but a mostly-air cube may want an octree/Morton sparse representation; when does dense-plane storage stop paying?
9. **SwiftUI shell fidelity.** No process-per-window and no native voxel primitive; the retained-mode-over-SwiftUI port and custom Metal volume renderer are unproven at the target frame budget.
