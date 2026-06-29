# SixFour Spec-First Roadmap: RGB-First Encoding, the Two-Form Nudge, and the 64³ Energy Tools

## 0. Reading order

This roadmap is gated. Section 1 is a hard wall. Sections 2 through 4 are the three deliverables that must pass that wall. Section 5 is the dependency-ordered build list. Section 6 is what the owner must decide. Nothing about the trainer (loop, optimizer, corpus, checkpoint, MLX graph, head wiring) is planned here, and nothing about it may be started until the unblock condition at the end of Section 5 is met.

---

## 1. The gate (lead with this)

**NO trainer work happens until the spec is proven transferable with tests and golden vectors.** This is not a guideline, it is the acceptance bar. The single source of truth is `spec/scripts/gate.sh`.

A spec module is "proven transferable" when ALL of the following are green for that module:

1. **cabal test.** The module's QuickCheck laws live in `spec/test/Properties/<Module>.hs` exporting `tests :: TestTree`, are registered in `spec.cabal` (`spec-tests` other-modules), and are appended to the group in `spec/test/Spec.hs`. `cabal test` is the gate.
2. **Map + compartment + cabal wiring.** The module is `module SixFour.Spec.<Module>` under `spec/src/SixFour/Spec/`, carries a `-- COMPARTMENT:` tag (scanned by `check-compartments.sh`), is listed in `spec.cabal` `exposed-modules`, and has exactly one line under its category in `SixFour.Spec.Map`. It imports its primitives from the real spec (one source of truth), never hand-copies them.
3. **Hermetic codegen.** A `SixFour.Codegen.<Module>` emits Swift and Python from the SAME spec constants, wired into `app/Spec.hs main`. The committed `SixFour/Generated/*` and `trainer/generated/*` byte-equal a fresh `spec-codegen` emit (`git diff --exit-code`). The emitted Swift carries `selfCheck() -> Bool`; the emitted Python carries `_self_check()`.
4. **Cross-tier golden vector.** At least one golden is emitted from the spec (integer JSON via `app/Fixtures.hs` into `trainer/out/` plus any `.bin` into `Native/src/`) and reproduced byte-exact by every consuming tier:
   - **Swift:** the `selfCheck()` in the committed `*Contract.swift` / `*Golden.swift`.
   - **Python:** a `_self_check()` run added to `gate.sh` as a `run "<Module> (Python port == Haskell golden)" "python3 ..."` line.
   - **Zig:** a `Native/src/<module>_fixture_test.zig` that `zig build test -Drequire_fixtures=true` FAILS on if the golden is absent or mismatched (never skip-if-absent).

**Golden honesty rule (mandatory).** A golden is only byte-exact if it transports as exact integers. Pin integer numerators and integer counts, never a float `mean`/`var` that divides by N and depends on summation order. Any golden that silently degrades into a float-tolerance compare is a lying-green gate and is rejected.

**Trainer-port caveat (own it, do not hide it).** `gate.sh` runs several Python ports under `trainer/` (`model_io.py`, `test_upscale256.py`, `cell_budget.py`, `gif_to_capture.py`, and others) that are byte-twins of spec boundary types. Retyping a boundary forces edits to those port files to keep the gate green. That is editing gate consumers to stay byte-exact, NOT building the training process. The creed's wall (do not build the trainer) holds; the literal phrase "zero trainer files touched" does not, and we say so up front.

---

## 2. RGB first class

### 2.1 The encoding decision

The model's colour value is **raw sRGB 8-bit RGB**. Introduce a first-class carrier:

```
PxSRGB8 = (Word8, Word8, Word8)     -- three UInt8 (Swift), three uint8 (Zig), np.uint8 triple (Python)
```

**OKLab is deprecated entirely from the encode path.** `Spec.ColorFixed.linearToOklabQ16` / `oklabToSrgb8Q16` and `Spec.Color.srgbToOKLab` / `okLabToSRGB` are removed from encoding and kept at most as an explicitly-tagged display-only decode. The `CaptureFormat` contract text, `contractQ16NotRecoverableAcrossGif`, and the emitted Swift/Python doc-comments currently assert the inverse of the creed ("OKLab Q16 is the model's internal working space; sRGB8 is the wire artifact"). That framing is flipped: **sRGB8 + index IS the model encoding AND the artifact of record (one space, no crossing)**, behind a renamed guardrail `contractSRGB8IsModelEncoding`.

### 2.2 The first-class projection basis (NOT Lab proxies)

A new module `SixFour.Spec.RGBProjection` defines eight RGB-native integer linear functionals over `PxSRGB8`, exactly as `trainer/mlx/frame_stats.py` already computes them, lifted into the gate:

```
projR, projG, projB :: PxSRGB8 -> Int          -- identity channels
projL  (r,g,b) = r + g + b                      -- luma: the balance functional on the (1,1,1) axis
projARG  (r,g,b) = r - g                         -- opponent R-G
projBRG  (r,g,b) = r + g - 2*b                   -- opponent R+G-2B
projCr (r,g,b) = r - b                           -- Eisenstein chroma R-B
projCg (r,g,b) = g - b                           -- Eisenstein chroma G-B
```

These are **first-class RGB-native linear functionals, not an approximation of any other colour space.** The "Lab proxy" reading is forbidden everywhere; the structural proof that they are a genuine RGB basis and not a degenerate projection is `opponentBasisInvertible`: the `(L, a, b) = (R+G+B, R-G, R+G-2B)` change-of-coordinates matrix has determinant 6, hence det != 0. Because RGB's three primaries sit at 120 degrees, the chroma plane is hexagonal A2 / Eisenstein `ℤ[ω]` (six 60-degree hue rotations as the norm-1 units), which is the correct ring for RGB, as opposed to OKLab's square `ℤ[i]`.

Only two of the four contrasts are independent: `projARG = projCr - projCg` and `projBRG = projCr + projCg`. The canonical carrier is therefore `(projL, projCr, projCg)` = luma plus Eisenstein chroma, with `(projR, projG, projB)` recoverable. The chroma metric that replaces the OKLab d6 distance is `enorm a b = a*a - a*b + b*b` (squared A2 hexagonal length).

### 2.3 Invert-or-refuse

```
lumaChromaToRGB :: Int -> (Int, Int) -> Maybe PxSRGB8
```

reconstructs integer RGB only on the index-3 sublattice Λ where `(l - cr - cg) mod 3 == 0` (the `/3` byte-exact guard, since 3 is not a unit). The arithmetic is sound: `l - cr - cg = (r+g+b) - (r-b) - (g-b) = 3b`, so every real sRGB8 pixel already lies on Λ and the round trip is total on the image. Off Λ it returns `Nothing` (never a non-byte-exact RGB). The V2 source `lumaChromaToRgb` is a bare `div 3`; promotion must add the explicit `Maybe` refusal direction.

### 2.4 Keystone sRGB8 round-trip golden

`SixFour.Codegen.RGBProjection` emits `rgb_projection_golden.json` over a fixed sRGB8 fixture set (pure primaries, grey, a high-chroma triple), pinning per fixture:

1. the eight integer projection outputs `(R, G, B, L, a, b, Cr, Cg)`, and
2. the round-trip `lumaChromaToRGB (projL p) (projCr p, projCg p) == Just p` (integer-exact, no cbrt, no matrix).

Keystone laws in `test/Properties/RGBProjection.hs`:

- `lawRgbRoundTripExact` (promoted and strengthened from `V2RgbEisenstein.hs`): a QuickCheck property over `Word8^3` for the positive direction PLUS the refusal direction (off-Λ input returns `Nothing`). Not the 10-element list check it is today.
- `opponentBasisInvertible`: det of the `(L, a, b)` basis != 0.

Because all eight functionals are pure integer adds and subtracts, JSON decimal transport is byte-exact across Haskell, Swift, Python, and Zig.

### 2.5 Scope honesty (do not undersell)

`PxQ16` (OKLab) is load-bearing in `ModelIO`, `Upscale256`, `RGBTFeature.blend4`, `GlobalCollapseQ16` (the Zig `s4_global_collapse` reference whose maximin runs in `PxQ16` space), `SuperResPalette`, and more; on the order of 80 spec files touch the OKLab/`ColorFixed` stack. Retyping the boundary to `PxSRGB8` regenerates the floor / collapse / upscale256 / device-index goldens. Two consequences to own explicitly:

- **Blend space is a real decision, not a relabel.** `RGBTFeature.blend4` and `Upscale256.blendPalettesQ16` are weighted integer averages. Retyped to `PxSRGB8`, the identical arithmetic now averages gamma-encoded sRGB8. The roadmap states the choice up front (Section 6, Q1) rather than calling these operators "ported unchanged" when their MEANING changes.
- **`GaussianChroma` ℤ[i] is not "superseded" by deletion.** `GaussianChroma` is a built `RefinementSystem.RModule` over the order-4 `ℤ[i]` ring, consumed by seven modules (`ChromaUnitGauge`, `ChromaUnitMinimizer`, `DualCube`, `RefinementSystem`, `ChannelProduct`, `AnchorDiagnostic`, `Map`). Eisenstein `ℤ[ω]` (order 6) exists only as exploration with no production ring carrier. The clean `PxSRGB8` encoding retype is **decoupled** from the `ℤ[i]` -> `ℤ[ω]` carrier rebuild. The encoding does not need the ring at all; `ℤ[ω]` is only the chroma metric / hue-rotation knob, which is nudge and diagnostic territory. The carrier rebuild is a tracked follow-on, scoped separately, never claimed done when only `ℤ[ω]` has been added alongside.

---

## 3. The nudge as two functions

### 3.1 The two forms (both already realized, one shared operator applied twice)

`OctreeCell.lawLadderSelfSimilar` proves `levelsBetween 64 16 == levelsBetween 256 64 == 2`. The same octant operator gives both directions, and both are colour-agnostic on `Int`, so they port unchanged under `PxSRGB8`.

**DOWN (deconstruction), `f_down : 64³ -> 16³ + residuals`:**

```
f_down :: Int -> [Int] -> ([Int], [[Detail]])
f_down depth cube64 = octantDistill depth cube64       -- SixFour.Spec.OctreeCell, composed in SuccessiveRefinement.split
-- depth = levelsBetween 64 16 = 2 ; result (coarse16, residuals) ; pinned by lawOctantRoundTrips
```

**UP (reconstruction), `f_up : (64³, residuals) -> 256³`:**

```
f_up :: [Int] -> [[Detail]] -> [Int]
f_up coarse residuals = octantLift coarse residuals    -- = OctreeCell.octantSynthesize ; SelfSimilarReconstruct.octantLift
-- the SAME operator as DOWN's inverse (lawSameOperatorBothRungs)
```

The beyond-capture 256 path uses `SelfSimilarReconstruct.reconstruct256`, whose invented second step lifts 64 -> 256 from a `LatentTail` of Mac-side floats re-entered through the one sanctioned float-to-byte seam `tailToDetail = map (map reenter7) -> ByteCarrier.reenterQ16`. **Carrier note (load-bearing):** `octantDistill`'s residual is `[[Detail]]` (`Detail` is a 7-tuple of `Int`); `reconstruct256`'s invented residual is a `LatentTail`. These are two carriers. Any nudge must pick ONE and act on it; conflating them is rejected.

### 3.2 The nudge proper

A nudge is a residual-to-residual transformation inserted between the two forms, NOT a separate paint field:

```
nudge :: NudgeWord -> Residual -> Residual
nudgedReconstruct w cube64 = f_up coarse (nudge w res)   where (coarse, res) = f_down levelsPerStep cube64
```

The keystone is the **neutral nudge**: the empty word is the identity on the residual, so `nudgedReconstruct [] cube64` equals the byte-exact floor (`lawNeutralNudgeIsFloor`, composing the empty-word identity with `SelfSimilarReconstruct.lawZeroTailIsFloor`). Painted residual moves the output off the floor; the coarse cube is invariant under the nudge (the nudge only reallocates the residual, mirroring `V2UncertaintyBudget.lawResidualEditPreservesCoarse`). Reversibility: every nudge keeps `f_up . f_down` reconstructible, so the user can always return to the original 64³.

### 3.3 Hard correction (carrier type-mismatch, must fix before any golden)

The tempting identification `nudge w = applyWord w` (from `V2SkiResidualOrder.hs`) **does not typecheck against `[[Detail]]`.** `applyWord :: [Gen] -> Frame -> Frame` operates on `Frame = [RGB]` (point-indexed pixels); its generators `Rot i / Shift i / Swap i j` are not defined on the 7-tuple `Detail`, and every V2 reversibility law (`lawWordReversible`, `lawReversibleBecauseANT`) is proven over `Frame`, not over the residual carrier. As written, the SKI-word nudge is a frame paint operator relabeled, which is exactly the "separate paint field in disguise" the creed forbids. The minimum to make the nudge sound:

1. Choose ONE residual carrier (`[[Detail]]` for the within-capture rung, or `LatentTail` for the invented 256 rung) and **define the generator action on THAT carrier**.
2. Re-prove `lawWordReversible` and the floor keystone on that carrier (not on `Frame`).
3. Exhibit the genuine `64³ + residuals -> 256³` UP form, not the within-capture `16 <-> 64` round trip the V2 sketch actually realizes.

### 3.4 Scope discipline for the nudge pass

`ModelForward.forwardOctant` and `CellNudge` already have green laws (`lawZeroNudgeForwardIsFloor`, `lawNudgeMovesOutput`, `lawResidualStaysInA7`, `lawForwardCommitIsQ16`) over a continuous A7-legal Q16-committed residual. **Do not rewrite them in the nudge-promotion pass.** Swapping that residual for a discrete word changes the model's output type and re-opens green laws, which is model re-architecture and is deferred behind the gate. Land `NudgeWord` purely additively. `NudgeStep.hs` (the `Gesture -> LatentCube -> project` latent-gesture nudge) does not factor through `f_down`/`f_up`; it is documented as the demoted, non-canonical path. `OctreeCell`, `SuccessiveRefinement`, and `SelfSimilarReconstruct` stay untouched (the two forms already exist; the nudge only inserts between them).

---

## 4. The user 64³ energy tools

### 4.1 What this layer is

A **read-only diagnostics layer** that turns a real 64³ GIF89a capture into a per-frame energy and entropy view. It informs the user's nudge; it never re-enters the encode path and imports no trainer model module. A real 64³ capture is exactly a length-64 list `frames = [(palette_srgb8, index64x64)]`. The math already exists in `trainer/mlx/frame_energy.py` and `trainer/mlx/frame_stats.py` and is sRGB-native:

- `frame_energy.frame_series(frames)` -> a 64-point series of `(energy_norm, entropy, luma_e, chroma_e)`. Energy is deviation-from-the-frame's-own-mean (the averaging-machine residual, 0 iff flat); `energy_luma_chroma` splits luma = var(R+G+B) and chroma = mean A2 norm `enorm(ca, cb)` with `ca = R-B, cb = G-B`. Entropy is normalized Shannon entropy of slot usage in [0, 1].
- `frame_energy.plot_energy_time(series)` -> a PNG of the per-frame energy LEVEL across the 64 frames, coloured by entropy. This IS the user's 64³ energy-levels view.
- `frame_stats.facet_tensor(frames)` -> per-frame x 8-projection x 3-statistic table over `R, G, B, L=R+G+B, a=R-G, b=R+G-2B, Cr=R-B, Cg=G-B`, plus temporal `delta_energy` per projection and the cyclic loop-seam energy frame[63] -> frame[0].

### 4.2 The one missing codepath

A small adapter `diagnostics/capture_frames.py`:

```
frames_from_gif(gif_bytes)    -> list[(palette_srgb8 (K,3) uint8, index64 (64,64) uint8)]
frames_from_capture(cap: dict) -> same list
```

It reuses the spec-matched byte-exact decoder (`zig_native.gif_decode` plus `generated/capture_format.decimate4x`, 256² wire -> 64², time axis never scaled) and is ~5 lines of glue: reshape `indices (F,4096) -> (F,64,64)` and zip with `palettes_srgb8[f]`. Each frame carries its own K; callers pass `k = palette.shape[0]` so entropy normalization stays honest (pin this, no caller hardcodes 256).

**Lab-leak fix (mandatory):** do NOT route through `gif_to_capture.import_app_gif`, because it unconditionally computes `srgb8_to_oklab_q16(...)`. Call the sRGB8-only decode (`gif_decode` + `decimate4x`) directly, so no OKLab kernel ever runs in the diagnostics layer.

### 4.3 Keep it separate from the encoding and the trainer

- **Framing rewords (no math change):** `frame_stats.py`'s "the training signal the model trains on" and `eisenstein.py`'s "the substrate the V2 model trains under" are reworded to "user diagnostic, read-only, separate from the model encoding."
- **Split before relocating:** `eisenstein.py` mixes the diagnostic substrate (`enorm`, `luma`, `chroma`) with a training loss (`lattice_loss`, `train_loss_rgb`, `closest_lambda`, `snap_palette_to_lambda`). Pull the diagnostic substrate out (or pin only `enorm`) before any relocation into `diagnostics/`. Do not drag training-loss code into a layer labeled read-only. Nothing in `trainer/` imports these three files today, so relocation breaks no trainer code.
- **The diagnostic is deviation-from-mean energy, not the encode-path coarse/residual split.** Label it as such. It is not the `64³ -> 16³` residual the nudge acts on; it is an independent meter that informs the nudge.

### 4.4 Golden honesty for this layer (the trap)

If this layer is promoted to the gate (Section 6, Q3 decides whether it must be), the headline "byte-exact integer golden" claim only survives if:

- **Pin integer numerators, not float means.** `var(R+G+B)` and `mean(enorm(...))` divide by N (float64, order-dependent). Pin the integer sum-of-squared-integer-deviations plus integer N; divide only for display. Otherwise the gate degrades into a float-tolerance compare (lying-green).
- **Reconcile the golden definition to the actual code.** `energy_luma_chroma` computes the A2 norm of the **deviation** from the mean, not of raw pixels. The Haskell oracle must pin the deviation quantity the code computes, not a raw-pixel quantity, or the cross-tier gate tests two different numbers.
- **Rename the keystone.** `energyVsEntropyOrthogonal` is a single witnessed pair (a flat frame can hold full slot-entropy and vice versa), not orthogonality. Call it `energyEntropyIndependentWitness`. Anti-forced-jargon.

---

## 5. Ordered promotion plan

Dependency-ordered. RGB encoding lands first. Each item is "done" only when it passes the full Section 1 gate (cabal + Map + compartment + hermetic codegen + cross-tier golden).

**M1. `SixFour.Spec.RGBProjection`** (the sRGB8 first-class encoding; promotes `V2RgbEisenstein.hs::rgbToLumaChroma`).
- Keystone golden: `rgb_projection_golden.json` (eight integer projections + sRGB8 round-trip per fixture).
- Keystone laws: `lawRgbRoundTripExact` (QuickCheck over `Word8^3`, positive + off-Λ refusal), `opponentBasisInvertible` (det = 6).
- Compartment: `PURE-SPEC-WALL | tag:rgb-opponent-algebra` (the integer functionals straddle ZIG-FLOOR when shipped on device; new Zig kernel `s4_rgb_opponent`).
- Lands **alongside** `color_golden.json` (kept as display-only decode, retagged not deleted, so `-Drequire_fixtures=true` does not fail on an absent golden). It does NOT yet retire the OKLab path: `ModelIO` / `collapse_golden` / `Upscale256` still run `PxQ16`. Calling M1 "the model encoding is now sRGB8" before those are rethreaded is an overclaim; the honest statement is "the RGB contract is added and gated; OKLab retirement from the model path is the follow-on M1b."

**M1b (follow-on, scoped separately, not part of M1).** Rethread `ModelIO` / `Upscale256` / `RGBTFeature.blend4` / `GlobalCollapseQ16` off `PxQ16` onto `PxSRGB8`, decide the blend space (Section 6, Q1), and regenerate the floor / collapse / upscale256 / device-index goldens plus the gate-run trainer ports (`model_io.py`, `test_upscale256.py`, `cell_budget.py`). Only after M1b is OKLab actually deprecated from the encode path.

**M2. `SixFour.Spec.Eisenstein`** (the A2 chroma substrate; promotes `V2A2ClosestPoint.hs` + `eisenstein.py` parity).
- Consumes `RGBProjection` chroma `(ca, cb) = (projCr, projCg)`. Ring over `ℤ[ω]`, `enorm a b = a*a - a*b + b*b`, six norm-1 units = six 60-degree hue rotations.
- Keystone golden `eisenstein_norm_golden.json`; laws `lawHueRotationIsNormIsometry`, `lawGrayCollapsesToKernel`.
- Compartment: `ZIG-FLOOR` (new kernel `s4_eisenstein_norm`).
- This is the ring carrier introduced **alongside** `GaussianChroma`'s `ℤ[i]`. It does NOT replace it: the seven `ℤ[i]` consumers are untouched and tracked as a separate rewire. Say "introduces `ℤ[ω]`," never "replaces `ℤ[i]`," until those consumers move.

**M3. `SixFour.Spec.EisensteinIdeal`** (the gated ideal theory; promotes `V2TrainingLattice.hs` + `V2EisensteinPrime.hs`).
- The index-3 sublattice Λ, `lumaChromaToRGB` invert-or-refuse, `closestLambda` nearest-point snapper.
- Keystone golden `eisenstein_ideal_golden.json`; laws `lawByteExactTargetsAreOnLambda` (`l - ca - cb = 3b`), `lawInvertOrRefuse` (off-Λ returns `Nothing`).
- Compartment: `PURE-SPEC-WALL`.
- **Strip trainer scope:** do NOT promote `latticeLoss` / `trainingTarget` / `trainLoss` (these are trainer scope and import training intent ahead of the gate). Keep only the byte-exact pieces (`lumaChromaToRGB`, `closestLambda`, the `mod 3` membership). Pin `closestLambda` OUTPUTS byte-exact; soften the prose from "provably the nearest point" to a pinned-output claim unless the candidate-set completeness is itself a checked tooth.

**M4 (optional, gated by Section 6 Q3). `SixFour.Spec.FrameEnergy`** (the 64³ diagnostic oracle).
- New `diagnostics/capture_frames.py` reader (sRGB8-only decode, no `import_app_gif`).
- Keystone golden `frame_energy_golden.json` over a fixed 2-frame 64x64 fixture, pinning integer numerators + integer N (not float `var`/`mean`), with the deviation-based `chromaE` reconciled to the code.
- Keystone laws: `energyEntropyIndependentWitness` (renamed), `opponentBasisInvertible`.
- This discharges the standing gap that `eisenstein.py` asserts spec parity only in a docstring.

**M5 (the nudge, last; gated by the Section 3.3 carrier fix). `SixFour.Spec.NudgeWord`** (promotes `V2SkiResidualOrder.hs`).
- Blocked until the generator action is defined on the chosen residual carrier and `lawWordReversible` is re-proven on THAT carrier (not `Frame`). Keystone laws `lawNeutralNudgeIsFloor`, `lawNudgeReconstructible`; golden `nudge_word_golden.json`.
- Lands additively. Does NOT touch `ModelForward` / `CellNudge` (that is M-later, behind the gate).

**V2 files that STAY exploration (base-only runghc, no golden):**
- `V2UncertaintyBudget.hs` (haar8 1+7 DOWN/UP) duplicates the production `OctreeCell.octantDistill` / `octantSynthesize`, already golden-pinned via `upscale256_golden.json` and `s4_octant_lift`. No new transferable content.
- `V2SkiResidualOrder.hs` stays the design source for M5 but its frame-level `applyWord` does not promote unchanged (carrier fix required).
- The remaining V2 analogy files stay base-only runghc.

### Trainer-unblock condition (explicit)

The trainer stays out of scope until **M1, M2, and M3 are green cross-tier** (cabal test + hermetic codegen git-diff clean + Swift `selfCheck()` + Python `_self_check()` gate line + Zig `-Drequire_fixtures=true` fixture test, for each). That is: the RGB sRGB8 encoding contract and the gated Eisenstein ideal theory are proven transferable end to end. Only then may trainer planning begin. M1b, M4, and M5 are independent follow-ons and are not part of the minimal unblock set, though M1b (OKLab actually retired from the model path) is required before any claim that the trainer trains on RGB rather than OKLab.

---

## 6. Open questions and contradictions for the owner

1. **Blend space (M1b).** When `RGBTFeature.blend4` / `Upscale256.blendPalettesQ16` retype to `PxSRGB8`, the same integer averaging now happens in gamma-encoded sRGB8. Is the model floor blend (a) sRGB8-gamma directly (simplest, owns a wrong-gamma blend), or (b) linearized before blending and re-encoded (adds a linearize step, not OKLab)? This decision regenerates every floor/collapse/upscale256 golden and must be made before M1b.

2. **`ℤ[i]` vs `ℤ[ω]` carrier (M2 vs `GaussianChroma`).** `GaussianChroma` is a built `RModule` over order-4 `ℤ[i]` with seven consumers; V2-FITS flags the `ℤ[ω]` C3-mod-(1-ω) byte-exactness mechanism as CONTRADICTING the live C4 = `ℤ[i]` determinism floor (additive, not a drop-in replace). Does the owner want (a) two chroma rings coexisting indefinitely (`ℤ[ω]` for RGB chroma metric/hue, `ℤ[i]` retained for the existing refinement carriers), or (b) a full rewire of the seven `ℤ[i]` consumers onto `ℤ[ω]` as a tracked epic?

3. **Does the 64³ energy layer (M4) get a real `Spec.*` + golden, or is it exempt as a Mac-side diagnostic that never reaches device?** If gated, the integer-numerator + deviation-reconciliation fixes are mandatory. If exempt, it ships as read-only Python only, outside the gate.

4. **Luma vs Rec.709.** `projL = R+G+B` is the balance functional on (1,1,1), about 39.8 degrees off Rec.709 luminance. Is that an accepted give-up under RGB-first, or does the owner want a weighted luma (which would break the integer-exact, ring-clean story)?

5. **Residual carrier for the nudge (M5).** The within-capture rung uses `[[Detail]]`; the invented 64 -> 256 rung uses `LatentTail` (Q16 floats re-entered via `reenterQ16`). The nudge generators must be defined on ONE. Which carrier is canonical for the user-facing nudge, given the user steers the invented 256 output but the byte-exact reversibility laws are cleanest on the integer `[[Detail]]` rung?

6. **Two nudge notions.** The creed selects the residual-transform nudge (`f_up . nudge w . f_down`) as canonical and demotes `NudgeStep`'s latent-gesture nudge. Confirm `NudgeStep` stays in spec as documented-but-demoted, rather than being retired.

7. **OKLab goldens at deprecation (M1b).** When OKLab leaves the encode path, do `color_golden.json` / `ColorFixed.goldenLinearInputsQ16` / the d6 metric retire entirely, or persist as a clearly-tagged display-only decode (the recommendation, so `-Drequire_fixtures=true` never fails on an absent golden)?