# SixFour — Metal Field Render × Spec Alignment (workflow)

> Keywords: compute ownership, Zig deterministic GIF core, Metal capture quant, Metal UI field
> (NEW), Haskell spec source of truth, product vs presentation determinism, byte-exact vs tolerance
> golden, Spec.Boundary, Spec.InfluenceField, shader-portable spec, four-backend gate, CLAUDE.md
> dependency contract, spec-first migration.

**Status:** architecture + spec-alignment workflow (2026-06-09). Follows
`SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md` (which picks Metal for the field). This doc makes the change
**on-contract**: it maps WHO computes WHAT, and HOW the Haskell spec gates a new Metal UI-render
backend without disturbing the Zig GIF core. Branch `feat/metal-field-render`. Implementation is
**spec-first** (CLAUDE.md): edit `Spec.*` → `cabal test` → `spec-codegen` → port → gate.

## 0. The misconception this corrects

"Zig does the frame compute, not Metal." **Correct — and it stays that way.** The proposal does NOT
move frame compute to Metal. It moves the **decorative UI field** (the radiation ground) off the CPU
main thread onto the GPU. Three *different* jobs, three owners — the spec must reflect all three:

| Layer | Owner | What it computes | Output | Determinism class | Spec gate |
|-------|-------|------------------|--------|-------------------|-----------|
| **GIF core** | **Zig** | quantize→dither→significance→collapse→encode | the 64×64×N GIF — the PRODUCT | **byte-exact, cross-device** | `Spec.*` byte-exact golden vectors (existing) |
| **Capture quant** | **Metal** (existing) | live-preview palette (K-means / blue-noise) | preview index tiles | best-effort (preview) | spec-aligned, not byte-pinned |
| **UI influence field** | **Metal (NEW)** | the radiation ground around the widgets | screen pixels — CHROME | **presentation-only, float, per-GPU** | `Spec.InfluenceField` **TOLERANCE** golden |
| **UI structure** | **Swift / SwiftUI** | layout, widgets, gestures, the CPU reference field | views | — | mirrors `Spec.*` contracts |
| **Source of truth** | **Haskell spec** | every law + the field function + the geometry | contracts + goldens | — | `cabal test` is the gate |

The key insight for spec alignment: **the GIF is the product (byte-exact); the field is chrome
(float, decorative).** They are different determinism classes, so they get **different golden
gates**. The spec must express that distinction, not force the field to the GIF's byte-exactness.

## 1. Two determinism classes (the crux of the alignment)

- **PRODUCT determinism (the GIF).** Must be bit-identical on every device (the GIF a user ships is
  the contract). Owned by **Zig**, gated by **byte-exact** golden vectors. **Unchanged by this work.**
- **PRESENTATION determinism (the field).** A decorative GPU effect; bit-identical-across-GPUs is
  neither needed nor wise to demand (it would over-constrain a fragment shader). The spec instead
  defines the field **function** and gates conformance to a **tolerance ε** (CPU reference vs shader
  agree within a few sRGB8 levels at sampled cells). **Geometry inside it stays integer/exact** (the
  Stage mask, the 4 pt grid — those ARE byte-exact, because they are integer cell math).

So: **Stage geometry = byte-exact golden; field colour = tolerance golden.** One spec module per
concern, each with the right gate.

## 2. Spec modules to add / align

1. **`Spec.Boundary`** (the Stage — promote the hand-written `Boundary.swift`): `inside(c,r)`,
   `footprintFits`, `isOutline`, the stepped rounded-rect laws. **Byte-exact** golden = a sampled
   `inside`/`isOutline` bitmap digest. Emits `Generated/BoundaryContract.swift` (Swift) AND a
   `Generated/boundary.h`-style **Metal constants header** (insets, corner radius) so the shader's
   in-shader Stage mask reads the SAME numbers (no drift). Integer ⇒ the shader's mask is bit-equal.

2. **`Spec.InfluenceField`** (the field function): the per-cell map — source weights (dist-to-rect,
   falloff), energy `E`, balance / Voronoi seam, usage-weighted reach, edge-bleed, outward drift,
   dither, lift ramp, the per-act theme params. Laws: monotone falloff, ridge at equal weights,
   energy→0 at reach, drift continuity, movability invariance. Emits:
   - the **param contract** → `FieldTuning` (Swift) + a **Metal uniforms header** (one source for
     reach/driftPerTick/seamMute/liftDim/theme presets — shader + Swift never diverge);
   - a **CPU reference** the shipped Swift `FieldModel` conforms to (parity-tested vs spec);
   - **tolerance golden vectors**: field colour at fixed `(widgetRects, palette, usage, tick, lift)`
     sample cells, compared CPU-reference vs Metal-shader within ε.

3. (Existing, unchanged) the Zig `Spec.*` byte-exact goldens for the GIF core.

## 3. The verification ladder (four backends, one truth)

```
Haskell Spec.InfluenceField / Spec.Boundary        ← THE TRUTH (laws + goldens)
        │ codegen (constants/params)
        ├──► Swift  FieldTuning + FieldModel (CPU reference)  — parity-tested == spec golden
        ├──► Metal  field.metal (hand-written shader)         — verified == golden within ε (debug self-check)
        └──► Metal  Stage mask (from boundary header)         — bit-equal (integer)

Haskell Spec.* (GIF)  ──► Zig kernels                         — byte-exact golden (UNCHANGED)
```

- The shipped Swift `FieldModel` becomes the **spec-pinned CPU reference** — the thing the shader is
  checked against (it already encodes the field math).
- A **debug self-check** (like `Surface.assertSpecParity`) renders N sample cells through the shader
  and asserts they match the `FieldModel`/golden within ε — the live Swift↔Metal↔Haskell pin.
- The Metal shader BODY is hand-written (math); only its **constants** are codegen'd — same
  discipline as the hand-written Swift/Metal GIF path verified against Haskell goldens.

## 4. CLAUDE.md dependency-contract check

Tier 2 (shipped iOS) permits **hand-written Metal + system frameworks, zero third-party deps**. A
hand-written field fragment shader in a `CAMetalLayer` (`MetalKit`/`QuartzCore` are system
frameworks) is **on-contract** — identical in spirit to the existing `SixFour/Metal/*` capture
shaders and the hand-written Swift/Metal GIF path. No `mlx-swift`, no CoreML, no SPM. The Haskell
golden gating the shader is exactly the "spec proves the math once, the hand-written port is verified
bit-/tolerance-for-tolerance" rule. **The architecture change does not change the dependency tiers.**

## 5. Spec-first migration sequence (gated by `scripts/s4.sh all`)

| Step | Work | Gate |
|------|------|------|
| **S1** | `Spec.Boundary` + `Spec.InfluenceField` (laws + goldens) → `spec-codegen` emits `BoundaryContract.swift`, `FieldTuning`, the Metal constants header; re-fold the shipped `FieldModel` as the spec reference | `cabal test` (laws + goldens) + `s4 verify` + `s4 build` |
| **S2** | Write `field.metal` (fragment shader) against the generated constants; debug self-check vs `FieldModel`/golden within ε | `s4 build` + on-device self-check passes |
| **S3** | `FieldMetalView` (`UIViewRepresentable` + `CAMetalLayer`) replaces the CPU `StageField` bake for the FIELD; widgets stay SwiftUI on top; delete the per-tick CPU bake | `s4 build` + **on-device** smoothness + ms/tick |
| **S4** | Capture **texture ring** (systems doc M2): burst frames → GPU texture, reverse-cursor indexes it at steady κ | `s4 build` + **on-device** (camera) |

S1 is pure Haskell+codegen (testable by `cabal test`); S2–S4 are on-device. **Order matters:** the
spec is verified BEFORE the shader exists, so the shader is built against a proven contract.

## 6. What does NOT change (so the spec stays coherent)

- The **Zig GIF core** + its byte-exact goldens — the product's determinism is untouched.
- The **20 fps content cadence**, the **cell-field law** (discrete 4 pt), the **one clock**, the FSM.
- The **field math** itself — `Spec.InfluenceField` simply *formalizes the already-shipped*
  `FieldModel`; CPU→GPU is a backend move, not a math change.

## 7. Open decisions (for the user)

- **Tolerance ε** for the field golden (e.g. ±2 sRGB8 levels) — how strict should the shader match
  the CPU reference? (Loose = GPU freedom; tight = WYSIWYG vs the spec.)
- **Codegen the Metal constants header**, or hand-mirror it with a lint? (Codegen = zero drift,
  matches the Zig/Swift contract discipline — recommended.)
- **Does the field need ANY cross-device consistency?** (Likely no — it's chrome; tolerance golden is
  about matching the SPEC, not matching device-to-device. Confirm.)
- **Capture ring (S4) format:** one shared burst palette (kills shimmer, simpler ring) vs per-frame
  palettes in a parallel texture? (Leaning shared.)
