# SixFour, Look-NN + Value-Net Unification (careful-engineering design)

Status: design, 2026-06-17. Companion to STATUS.md and the state inspection
(`docs/SIXFOUR-STATE-INSPECTION-2026-06-17.md`). Spec-first: nothing here ships
before the Haskell law lands and the golden gate is green.

## 0. Thesis

The value net and the look-NN are an actor/critic pair built as two disconnected
artifacts. Merge them into ONE net: a shared, sigma-equivariant trunk feeding two
heads, an equivariant GENOME head (the look-NN output) and an invariant VALUE head
(the preference scorer).

The merge is already half-built. `trainer/atlas_net_mlx.py` shares the trunk and
implements the invariant value head, that is the architectural target. The shipped,
on-device-proven `SixFour/Atlas/AtlasTrainer.swift` is the spike that does NOT share
the trunk (it reads a `[B,4096,6]` board cube through its own per-bin encoder and
feeds RAW 128-D context into the value MLP, so it is not sigma-invariant today, see
its own docstring at `:31-35`). The work is: promote the prototype to the shipped
path, retire the spike's separate board encoder, and add the missing spec law.

Three constraints must close together or the merge is unsound:
1. **Network/frameworks**, where the trunk ends and the heads split, and which
   framework trains/deploys each.
2. **The SIMT/Metal agreement**, the numeric contract that keeps the GPU port
   byte-identical to the Zig/Haskell truth.
3. **The 64^3 -> 16^3 (A/B) per-frame/global option stack**, the substrate the
   net's input and output ride on.

## 1. Network layers and the merge seam

Sigma classes (from `Spec/Tensor.hs:446-473`): hidden 64-D = 22 achromatic
(sigma-fixed) + 21 red-green + 21 blue-yellow (42 chromatic, sigma-negated).

| Layer | Params | Computes | Sigma property | Train | Deploy | Numeric |
|---|---|---|---|---|---|---|
| L3 encoder `phi` | Linear 10->64, masked | per-token linear + sum-pool -> 64-D ctx | equivariant + permutation-invariant (`LookNetE.hs:240,249`) | MLX | hand Swift/Metal | Q16, golden |
| L4 recursion | 2x Linear 64->64 shared, x8 | `x ↦ x + W2 tanh(W1 x)` | refine equivariant; halt invariant (`LookNetR.hs:198,292`) | MLX | static unroll | Q16, golden |
| L5 decoder | 8 heads -> 384 | per-step ctx -> 384 sigma-pair coeffs | equivariant, action `diag(1,-1,-1)x128` (`LookNetD.hs:231`) | MLX | hand Swift/Metal | Q16, golden |
| L6 reconstruct | none | 384 -> 256 leaves (inverse Haar) | symmetric eigenspace by construction (`SigmaPairHead.hs:177`) | det. | det. Zig/Swift | exact |
| **genome-enc** | Linear 384->64, masked | genome -> 64, fuse with trunk ctx | equivariant (`atlas_net_mlx.py:82`) | MLX | MPSGraph + hand fw | **fp32** |
| **inv-proj** | none | `(sum achro, ‖rg‖², ‖by‖²)` -> 24-D | **INVARIANT** by construction (`atlas_net_mlx.py:104`) | MLX | MPSGraph/Swift | fp32 |
| **value MLP** | 24->32->1 | scalar V (Bradley-Terry) | **INVARIANT** (reads inv-proj only) | MLX proto / MPSGraph spike (proven on iPhone, 12.4 ms/step) | MPSGraph on-device + hand fw | **fp32, ordinal only** |

```
  per-frame palette tokens (10-D)        curation scalars (3-D, invariant)
          │                                      │
     [L3 phi mask]                       [phi_ext mask -> 22 achromatic dims only]
          └──────────── weighted sum-pool ───────┘
                            │ (B,64)
                   ┌────────┴────────┐  L4 SHARED BLOCK x8   ← TRUNK ENDS HERE
                   │  x ↦ x+W2 tanh(W1 x)   (equivariant)
                   └────────┬────────┘
                            │ per-step contexts [ctx0..ctx8]
   ┌─────────────────────────┴──────────────────────────┐
 EQUIVARIANT GENOME HEAD (L5)                    INVARIANT VALUE HEAD
 8 sigma-block-diag heads -> 384 coeffs          genome_enc(384->64) ‖ trunk ctx
 -> reconstruct -> 256-leaf palette              -> inv_proj (24-D invariant)
 (golden-gated, Q16-portable)                    -> v1(24->32) tanh -> v2(32->1)
                                                 (fp32, ordinal)
```

The seam is the pooled L4 context (`atlas_net_mlx.py:96`). Trunk = L3 + L4. The
value head is a parallel branch off the shared context, NOT in series with the
genome path, that is why it cannot break the upstream equivariance theorem.

### Input-plumbing refactor (the real cost)
The shipped spike (`AtlasTrainer.swift:197-227`) reads a `[B,4096,6]` board cube
through a standalone `Linear(6->64)` + mean-pool, plus a separate genome encoder,
and feeds RAW 128-D context into the value MLP (`:236`). To merge:
1. Replace the standalone board encoder with the L3 `phi`/`phi_ext` path feeding
   L4. Curation enters as 3 invariant token-extension scalars on achromatic dims
   only (`_EXT_MASK`, `atlas_net_mlx.py:53`), not a 6-channel cube.
2. Feed the value MLP the 24-D invariant projection, not raw ctx. This is the
   change that makes `V(sigma s) = V(s)`.
3. Keep the genome encoder, but it now scores the SHARED decoder's own output.
4. On-device, the MPSGraph value subgraph shares trunk variables with the look-NN
   forward; genome-enc + value-MLP stay per-user trainable, trunk stays frozen.

## 2. The SIMT/Metal agreement

Today the "Zig == Swift == Haskell byte-exact" agreement does NOT extend to Metal.
Every GPU path is float and display/extraction-only, "verified" only by tolerance
or by Swift re-transcription (`ColorSpaceDecodeParityTests` tests a Swift copy of
the shader, not the shader). The integer kernel that COULD be gated exactly,
`s4_cube_lift_level`, has no Metal port and no caller. The docstring claim that the
tiling is "pinned" against Metal is one-sided: it is a Zig/Haskell pin with a
comment anticipating Metal.

### The byte-exactness verdict (which layers can be GPU-float)
| Path | Byte-exact across devices? | Why |
|---|---|---|
| Metal compute, integer/Q16 | YES, if floor-div is hand-coded | integer ops exact; only trap is `/` |
| Metal compute, float | NO | reassociation, FMA contraction, fast-math vary by GPU family |
| MPS/MPSGraph (float) | NO, and not in simulator | opaque per-device kernels; barred for a shipped forward pass by CLAUDE.md |
| Accelerate/BNNS (float) | NO | FMA, vendor-tuned |
| hand Swift+simd, integer | YES | matches integer Zig/Metal |

**The contract for the merged net:**
- Trunk + genome head + reconstruct + look-transfer stay **integer/Q16, golden-gated,
  exact across devices**. These are where cross-device GIF determinism is required
  AND achievable (`GenomeFixedGolden` is already "no tolerance").
- The float NN arithmetic (the dense matmul trunk and the value head) is GPU-eligible
  and **tolerance-gated only** (`GoldenForward.hs` already compares at 1e-9 and pins
  the transport format bit-exactly via `hexDouble`).
- Quantize to Q16 **at the boundary** where output re-enters the palette pipeline.
  The value head is fp32 ordinal-only forever, Bradley-Terry compares `V_w - V_l`
  (`AtlasTrainer.swift:249`), so absolute scale and bit-exactness are meaningless,
  do NOT golden-gate or quantize it.

### THE #1 silent divergence: floor-div
Zig uses `@divFloor` throughout the lift (`kernels.zig:641-650`), correct for the
negative Q16 values the lift produces. **Metal integer `/` truncates toward zero.**
`(-3)/2 = -1` in Metal but `@divFloor(-3,2) = -2` in Zig. Any Metal lift kernel MUST
implement floor-div explicitly. This is unguarded today because no Metal lift exists.

### Minimal parity gate (do this first, it is small)
Plain Metal compute DOES run on the iOS-26 simulator (the k-means tests already
dispatch shaders there), only MPSGraph cannot. So a compute-shader parity gate is
CI-runnable now:
1. Add integer-only `cubeLiftLevel`/`rgbtLiftQuad` to a new `Cube.metal`, with an
   explicit floor-div helper.
2. Emit a Haskell golden into `Generated/` (reuse the `GenomeFixedGolden` pattern
   and `RGBTLift.hs:40`'s vector plus a negative-bearing Q16 batch).
3. `MetalCubeLiftParityTests.swift`: dispatch, read back, assert exact `Int32`
   equality against the golden AND against `SixFourNative.s4_cube_lift_level`. One
   test closes Metal == Zig == Haskell. No MPSGraph dependency.

This is the first concrete step that makes "NN tensors honor the Metal agreement"
true rather than aspirational, even before the net merge.

## 3. The 64^3 -> 16^3 (A/B) per-frame/global option stack

### Disambiguation (pin this or everything muddles)
Two orthogonal decompositions, the code keeps them separate:
- **Spatial Haar ladder** (coarse vs detail): 64^3 -> 32^3 -> 16^3 via the reversible
  RGBT lift. Sub-bands R=coarse/DC, G=LH, B=HL, T=HH. **Lossless.**
- **Palette axis** (per-frame vs global): this is where "cube A / cube B" is named,
  and this is the `paletteScope` toggle. **Lossy** (collapse + quantize).

### A and B, grounded in code
- **Per-frame cube** = 64 distinct per-frame 256-leaf palettes + index planes
  (`Upscale256.hs:194` `upPalettes`/`upCubeB`), the diversity-maximal cube, produced
  by `StageA.hs`. This is the NN INPUT.
- **Global cube** = one curated 256-leaf palette + global index planes
  (`upGlobal`/`upCubeA`), produced by collapsing per-frame via `s4_global_collapse`
  (maximin). This is the NN OUTPUT (the 384-DOF genome reconstructs it).

**Label-collision warning (unreconciled in code):** `Upscale256.hs:7-8` calls the
global cube "cube A", but the shipped `LadderExport.swift:11-16` and the 2026-06-12
doc amendments call the per-frame product "A / GIFA" and the global product
"B / GIFB". For the LIVE app, trust LadderExport: A = per-frame (GIFA), B = global
(GIFB). For the merged net the robust, label-free statement is:

> **per-frame = NN input = diversity-max cube; global = NN output = one-genome collapse.**
> The NN is the learned replacement for `s4_global_collapse`.

### Reversibility ledger
| Transition | Reversible? | Law |
|---|---|---|
| 64^3 <-> 16^3 spatial Haar (coarse + detail) | LOSSLESS, bijective | `lawLadderBijective` (`CubeLadder.hs:122`), `lawLiftUnliftExact` (`RGBTLift.hs:137`) |
| per-frame capture -> per-frame palette (StageA) | lossy (4096 px -> 256) | quantize, `s4_quantize_frame` |
| per-frame -> global collapse (B -> A) | lossy, irreversible | maximin pick + nearest re-index |
| 64^3 -> 256^3 synth-beyond | lossy (zeroed detail = NN must invent) | `lawSynthBeyondIsNearestNeighbour` (`CubeLadder.hs:139`) |

A + B do NOT reconstruct 64^3 losslessly. Only the spatial Haar {16^3 coarse +
detail} <-> 64^3 is lossless, and it operates on whatever measure substrate is fed
in. The dormant `rgbt4dEnabled` path (`AppSettings.swift:175`, OFF, zero callers) is
the lossless Haar machinery; the shipped 64->16 today is the lossy palette collapse.

### The option stack the user actually toggles
- `paletteScope` (`AppSettings.swift:129`, default `.perFrame`): per-frame -> render
  cube B (the hero GIFA); global -> collapse to cube A (GIFB via `s4_global_collapse`).
  In `.global` mode Review still shows per-frame ("per-frame shown, global on export").
- `paletteBranching` (`AppSettings.swift:123`, 16^2 / 4^4 / 2^8): the radix / tree
  factorization of the 256 leaves. `CaptureViewModel.swift:692` calls this "the radix
  = the NN genome". This is the genome factorization the merged net emits.
- Cut LEVEL (collapse depth): designed, slider NOT built (`COLLAPSE-LEVER-UIUX.md`).
- `rgbt4dEnabled`, `colorAtlasEnabled`: both OFF, dormant.

There is per-frame/global scope at the PALETTE rung only, no per-channel or per-level
scope toggle. The spatial Haar lift is unconditional and not user-exposed.

## 4. Spec laws to add (the gate before any code)

New module `Spec.AtlasValueHead` (or extend `AtlasOracle`):
1. **`lawValueSigmaInvariance`** (keystone): `value(sigmaTrunk ctx, sigmaDecoder g)
   == value(ctx, g)`, asserted with `==` (exact, like `lawHaltingSigmaInvariance`),
   because inv-proj squares the chromatic blocks so the sign flip vanishes.
2. **`lawValuePreservesLookNetTheorem`**: the trunk -> genome path is byte-identical
   to the standalone look-NN, the value head adds no operator to the equivariant
   path. This lets us add the value head WITHOUT re-proving `lookNetSigmaTheorem`.
3. **`lawExtMaskHonoursSigma`**: curation scalars (invariant) feed only the 22
   achromatic hidden dims (mirrors `lawPlacementMapHonoursSigma`, `LookNetE.hs:280`).
4. **`lawGenomeEncMaskHonoursSigma`**: genome encoder is equivariant 384->64
   (transposed decoder mask), then inv-proj collapses to invariant.

Template already exists: the halting head is "a reader of the trunk through an
invariant projection", the value head is the same shape, the merge is sound iff it
reads through that same invariant projection.

## 5. Phased plan

- **P0 (small, do now):** the Metal cube-lift parity gate (Section 2). Makes the
  Metal agreement real, independent of the merge. Also lights the integer path the
  net's deterministic stages will reuse.
- **P1 (spec):** `Spec.AtlasValueHead` with the 4 laws + a golden. Gate green before
  any Swift change. This is where the spike's "not actually invariant" debt is paid.
- **P2 (codegen):** make `atlas_net_mlx.py` spec-emitted (it is hand-written today,
  `:3-5`), so the prototype cannot drift from the spec.
- **P3 (deploy):** rebuild the MPSGraph value subgraph in `AtlasTrainer.swift` to
  share trunk variables, feed inv-proj into the value MLP, retire `wBoard`.
  Re-measure on-device perf (the 12.4 ms/step was the separate-board variant).
- **P4 (wire):** the deterministic 64^3 stages stay Q16/golden, quantize the float
  trunk output at the Q16 boundary, gate the boundary.

## 6. Honest risks

1. The merge REPLACES the proven on-device path with an unproven shared-trunk path.
   The 12.4 ms/step result was the separate-board spike, the shared-trunk variant's
   on-device backprop and latency are unmeasured.
2. The shipped spike is NOT sigma-invariant (`AtlasTrainer.swift:32-34,236`), so
   `lawValueSigmaInvariance` FAILS on current code. Satisfying it is real work.
3. No `Spec.AtlasValueHead` exists, the neural value head is off-contract until the
   spec module lands (only the linear `Preference.linearUtility` is spec'd).
4. The numeric-contract split is load-bearing: fp32 value math must never leak into
   the genome path, the genome path must never be tolerance-only. The seam (inv-proj)
   is exactly where fp32 begins and Q16 ends.
5. `Spec.Upscale256` (the 64->256 endgame) is unported, the A/B label collision is
   unreconciled in code, and the "palette is motion" displacement residual is
   doc-theory only. None of these block the merge, but they block 256^3.

## 7. Open decisions for the user

1. Scope: ship the merge against the per-frame/global stack as-is (genome replaces
   `s4_global_collapse`), or wait until the lossless Haar path (`rgbt4dEnabled`) is
   wired so the net rides the bijective ladder instead of the lossy collapse?
2. Value-head training: keep MPSGraph on-device per-user (proven), or also train it
   on the Mac with MLX and ship frozen for v1?
3. Do P0 (Metal parity gate) now as a standalone hardening win, before the merge?
