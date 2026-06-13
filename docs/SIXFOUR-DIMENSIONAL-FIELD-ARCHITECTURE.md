# SixFour — The Dimensional Field: 16×16 ⇄ 64×64 as base/fiber, and the unified surface (deep review)

> Keywords: fiber bundle, base 64×64 ⇄ fiber 16×16, value axis = 16² radix + OKLab³, the index
> section I:(x,y,t)→Z₂₅₆, three coordinate systems, one unified GPU surface, per-phase CAMetalLayer
> glitch, κ-gated draw, three-separate-paths → one Metal pass, base↔fiber projection field.

**Status:** ARCHITECTURE review + plan (2026-06-09). Steps back from the patch-level fluidity work
to answer "what IS the 16×16 ⇄ 64×64 relationship?" and re-plan the render architecture around the
answer. Companion to `SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md` (why CPU baking is wrong),
`SIXFOUR-METAL-FIELD-SPEC-ALIGNMENT.md` (the spec contract, S1 done), `SIXFOUR-HIGHDIM-UIUX.md` /
`docs/archive/SIXFOUR-REPRESENTATION-UNIFICATION.md` / `SIXFOUR-VISION.md` (the "one cube, projected honestly"
vision this formalises). Branch `feat/metal-field-render`.

---

## 1. The dimensional truth (the answer)

The GIF is **one tensor + one palette**, i.e. a section of a fiber bundle:

```
  I : (x, y, t) → Z₂₅₆            -- the index map (the "section"): which colour at each voxel
  P_t : Z₂₅₆ → OKLab³            -- the per-frame palette (the "fibre embedding")
```
`Surface.indexCube` IS `I` (layout `t·4096 + y·64 + x`); `palettesPerFrame` IS `P_t`. (Confirmed.)

There are **three coordinate systems**, and they are NOT peers:

| Axis | What | The 2D face the UI shows | Internal structure |
|------|------|--------------------------|--------------------|
| **SPACE** `(x,y)` | where in the frame | **the 64×64 preview** (the BASE) | a flat 64×64 grid |
| **TIME** `t` | which of 64 frames | the cursor / scrub | Z₆₄ cycle |
| **VALUE / COLOUR** | which of 256 colours | **the 16×16 palette** (the FIBER's address) | **2D: 16² radix** AND **3D: OKLab** |

**The 16×16 ⇄ 64×64 relationship is base ⇄ fiber.** The 64×64 is the BASE space (positions); over
each base point sits a **fiber** = the colour, and that fiber is itself a 2-D object (the 16×16 radix
address, `index = py·16 + px`) AND a 3-D object (its OKLab/​sRGB coordinates). The index map `I`
is the *section* that picks one fiber point per base point.

**Why "deeper than x/y":** `x` and `y` are two directions of the SAME (spatial) axis. `(x,y)` vs
`(px,py)` are two *different* axes — position vs value — linked only through `I`. The value axis
carries its own 2-D (radix) and 3-D (OKLab) geometry, so the 16×16 is a *face* of a richer space, not
a second copy of the image plane. "Seeing the influence of the 16×16 on the 64×64" = visualising the
**base↔fiber projection**: every preview pixel *is* a fiber point; the palette is the value-space the
preview's positions map into.

> The code already half-encodes this: the field's `.arrangement` source = the BASE (bleeds the
> `tile`/`indexCube`), the `.set` source = the FIBER (radiates the palette by radix rank). That split
> is the seam to build on — but today base and fiber are rendered as *separate* paths, not faces of
> one tensor. The architecture should make them ONE.

---

## 2. Review of the current implementation (as-built)

**What's right.** Dimensions are clean and fiber-aware: `indexCube` (base), `palettesPerFrame`
(fiber), the `.arrangement`/`.set` source kinds, the spec-pinned Stage + field params + byte-exact
dither (S1 done). The GPU field (S2/S3) renders the *ground* off the main thread (you confirmed it
"looks smoother").

**What's structurally wrong (the glitch + the debt) — three separate paths for one tensor:**

| Element | Path today | Problem |
|---|---|---|
| Field ground (100×218) | GPU `FieldMetalView`→`CAMetalLayer` (or CPU `InfluenceField`) | **A NEW `CAMetalLayer` per PHASE** — `Live`/`Capturing`/`Rendering` each own a `StageGround`→`FieldMetalView`, distinct SwiftUI identities, so `.live→.locking` tears down + rebuilds the layer → a transition flash. (The "persists" comment is aspirational.) **Prime glitch.** |
| Preview hero (64×64 = base face) | CPU `CellSprite`→`CellBitmap` (un-cached) | Re-bakes 4096 cells on EVERY body eval — both the κ reverse-cursor AND each bursty `capturedFrames` change → **two main-thread bakes per frame mid-burst**. |
| Palette (16×16 = fiber face) | CPU `CellSprite`→`CellBitmap` (un-cached) | Re-bakes on every palette change; same data the field already has. |

Plus, even on the GPU path: the draw is **not κ-gated** (any σ mutation re-fires `updateUIView`→
`nextDrawable`, several/zero per tick); **no `maximumDrawableCount`/triple-buffer**; `nextDrawable`
runs **synchronously on main**; a **fresh tile `MTLBuffer` is allocated every draw** + full CPU array
prep (palette/usage/tile/histogram) every tick. The 64×64 data is prepared **twice** per tick (once
for the GPU field, once for the CPU hero).

**Root cause (same as the original disjointedness, one level up):** the surface is built as
**separate views each doing their own per-tick CPU/GPU work**, recreated per phase — instead of **one
persistent render of one tensor**. Patching individual paths can't fix a structural mismatch.

---

## 3. The architecture change — ONE unified dimensional surface

Render the whole thing as **one persistent GPU surface that draws the tensor's faces**, hoisted
ABOVE the phase router, phase passed as a uniform. The base, the fiber, and the field stop being
three paths and become **regions/projections of one Metal pass**.

**A. One persistent surface (fixes the prime glitch).** Hoist a SINGLE `FieldMetalView`/`CAMetalLayer`
to `SurfaceView` (above `PhaseField`), so it is created ONCE and lives across every phase; the phase
is a uniform, not a new view identity. No teardown/rebuild at `.live→.locking` → no transition flash.

**B. One Metal pass renders every face (folds the three paths into one).** The shader already has the
base (`indexCube`/`previewTile`) and the fiber (the palette). Give it the widget rects as uniforms and
let ONE fragment shader paint:
- the **field** where no widget is (the base↔fiber radiation, as now);
- the **64×64 hero** inside Field64's rect = the BASE face: sample `I` at `(x−rect.x, y−rect.y, t)`
  through the fiber `P_t` (this is exactly `gifCell`, on the GPU);
- the **16×16 palette** inside Palette16's rect = the FIBER face: the 256 colours by radix address.
The hero + palette CPU `CellSprite` bakes are **deleted** — they were the base/fiber faces all along.
One pass, one read of the tensor, no double-prep, no main-thread baking.

**C. κ-gate + harden (perf).** Drive the single draw from the ONE clock (a `CADisplayLink` tick inside
the persistent view, or an explicit `tick`-gated `setNeedsDisplay`), not from arbitrary σ changes; set
`maximumDrawableCount = 3`; pool the index/palette buffers (update only on data change, not per tick);
keep `nextDrawable` off the critical path. Result: a steady 20 fps GPU surface that can't be starved
by the burst on the main thread — the actual cure for "glitchy."

**D. The dimensional honesty (the payoff).** Because the one shader holds the base `I`, the fiber `P`,
and the section, it can render ANY projection between them — so the influence field becomes the literal
**base↔fiber map**: an empty cell can show *which fiber address* (palette colour) the nearby base
region maps to, and the palette can show *where in the base* each colour is used. "See the influence
of the 16×16 on the 64×64" stops being a metaphor and becomes the rendered projection. This is the
`SIXFOUR-VISION.md` "one cube, projected honestly" made real, and the substrate future widgets (other
faces/projections) are born onto.

---

## 4. Migration plan (continues the S-series; spec-first where it touches the contract)

| Step | Work | Fixes | Verify |
|------|------|-------|--------|
| **S5** | Hoist ONE persistent `FieldMetalView`/`CAMetalLayer` to `SurfaceView`; phase + widget rects as uniforms; remove the per-phase `StageGround`s | the **prime glitch** (per-phase layer recreation) | on-device: no transition flash |
| **S6** | κ-gate the draw (one clock) + `maximumDrawableCount=3` + buffer pooling (update on data change, not per tick) | the per-tick alloc / un-gated `nextDrawable` jank | on-device ms/tick |
| **S7** | Fold the **64×64 hero** (base face) into the shader — sample `indexCube`/`previewTile` through the fiber in Field64's rect; delete the CPU hero `CellSprite` | the two-bakes-per-frame hero jank | on-device |
| **S8** | Fold the **16×16 palette** (fiber face) into the shader; delete the CPU palette `CellSprite` | last CPU bake on the hot path | on-device |
| **S9** | The **base↔fiber projection** field (the dimensional influence — palette-address-of-nearby-base, base-usage-of-each-colour) | makes the relationship visible | on-device + spec |
| **spec** | Pin the value-axis addressing (16² radix ⇄ index ⇄ OKLab) as `Spec.Address` (or reuse `Spec.AddressPicker`/radix work) so the shader's base/fiber mapping is golden | drift | `cabal test` |

S5/S6 are the glitch cure and should land first; S7/S8 are the unification (and a big perf win);
S9 is the dimensional payoff.

## 5. What does NOT change
Zig still owns the byte-exact GIF; 20 fps content cadence; one clock; discrete cells; the spec is the
source of truth; zero deps. This is a *render-architecture* change (three paths → one tensor surface),
not a change to the GIF math or the data model — `indexCube`/`palettesPerFrame` already ARE the
base/fiber.

## 6. Open decisions (for the user)
- **Hoist the surface to `SurfaceView` (S5) now** as the glitch fix, or first prototype the unified
  shader (S7/S8) on the live screen? (Rec: S5 first — it's the glitch.)
- **One pass vs a thin split:** render hero+palette+field in one fragment shader (max unification), or
  keep the hero a separate GPU draw for clarity? (Rec: one pass — it's the dimensional point.)
- **The projection field (S9):** which base↔fiber visualisation — palette-address tint of the nearby
  base, base-usage glow of each fiber colour, or both? (A design choice to mock first.)
- **Spec scope:** golden-pin the radix addressing now (`Spec.Address`), or after the shader settles?
