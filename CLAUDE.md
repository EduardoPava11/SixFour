# SixFour — project contract

SixFour is an iOS camera app: a 64-frame burst becomes a 64×64 animated GIF with
a learned global colour palette. The defining engineering principle is
**Haskell-verified, dependency-free, hand-written**.

## The dependency contract (HARD RULE)

There are three tiers. The rule that matters: **the shipped product has ZERO
third-party dependencies.**

### Tier 0 — Haskell spec (`spec/`) — Mac-side, NOT shipped
The formally-verified **source of truth**. Tensors are verified here (Naperian +
SoA channel-axis laws in `Spec/Tensor.hs`) and so are the NN layers
(σ-equivariance theorem in `Spec/LookNetCompose.hs`). The `sixfour-spec` library
is GHC-boot-only (`base`, `vector`, `containers`, `text`, `transformers`).
Tooling executables (`spec-codegen`, `spec-fixtures`, `spec-gen`, tests) may use `brick`/`vty`/
`JuicyPixels`/`QuickCheck` — they are dev tools, never shipped. The spec emits
contracts to every other tier and pins them with golden vectors so nothing
drifts; `cabal test` is the gate.

### Tier 1 — Trainer (`trainer/`) — Mac-side, NOT shipped
Mac-side ML tooling. **MLX is the primary trainer** (Apple-Silicon-native, runs
on the M1). `torch` + `coremltools` exist ONLY for the dormant CoreML/ANE
distillation fallback (`Codegen.CoreML` → `look_net_torch.py` +
`build_mlpackage.py`); they are not on the shipped path. Because the trainer is
tooling, its dependencies are acceptable.

### Tier 2 — iOS app (everything else) — the SHIPPED CORE PRODUCT
**ZERO third-party dependencies.** No SPM packages, no CocoaPods, no Carthage.
Imports are limited to Apple system frameworks (SwiftUI, UIKit, AVFoundation,
Metal, CoreImage, Accelerate, ImageIO, …) and `simd`. All compute is
hand-written Swift + Metal. This is *why* Haskell-first matters: the spec proves
the math once, and the hand-written Swift/Metal port is verified bit-for-bit
against the spec's golden vectors — so writing it by hand is safe and fast.

When on-device NN inference lands, it will be a **hand-written forward pass**
(Swift/Accelerate or Metal — chosen after benchmarking on real iPhone 17 Pro
hardware), loading MLX-trained weights from a plain binary blob, verified
against the Haskell golden vectors. **Never `mlx-swift`. Never a CoreML black
box. Never the ANE via an opaque runtime.** The model is tiny (~115K params), so
GPU/CPU latency and power are negligible — there is no performance reason to
take on a dependency.

> **REDIRECT 2026-06-22 (Core AI is to be TRAINED, as the I-JEPA large head).** The
> relational-residual encoding (the 6D point `P6 (L,a,b,x,y,t)` + `safeNudge` domain guard
> live in `Spec.RelationalResidual` (Zig-floor substrate); the `d6` metric, the `phi6`
> pairing `a<->x,b<->y,L<->t`, and the 14-int position residual live in `Spec.RelationalMemory`
> (MLX-model, split out by the compartment pivot))
> is the I-JEPA POSITION-CONDITIONING: it lets the predictor be conditioned on
> WHERE it predicts (`lawPositionDistinguishesSameColour` proves position carries info
> colour cannot). DIRECTION: grow the learned predictor into a genuinely LARGE
> position-conditioned I-JEPA head and TRAIN it (MLX on the Mac) -> `coreai-torch` ->
> `L.aimodel` -> **Core AI inference** on device. This MEETS the documented Core AI flip
> condition, so Core AI is UN-RETIRED as a roadmap. ARCHITECTURE = ASYMMETRIC I-JEPA: the
> frozen reversible lift stays the TOKENIZER (and manufactures the collapse-proof target,
> so `EncoderFrozen` is NOT reversed and no settled law breaks); the LARGE learned object
> rides on top. The hand-written-forward rule still governs anything small (`theta_B` stays
> `MaskedBandForward.swift`); zero-third-party shipped core stands; Core AI float still
> re-enters the Zig Q16 floor. A full learned EMA TARGET encoder (symmetric I-JEPA) is NOT
> adopted (it reintroduces the collapse problem) without explicit go. Below: the 2026-06-22
> retirement note, now scoped to "tiny theta_B did not need Core AI" rather than "no learned
> head ever will".
>
> **SUPERSEDED 2026-06-22 (encoder needs no learned L).** The JEPA encoder is the
> frozen reversible lift (zero params) plus the 63-param `theta_B`, which ships
> HAND-WRITTEN in `SixFour/Native/MaskedBandForward.swift` (golden-gated, no Core AI).
> The frozen grayscale-L net this amendment served was the MLX look-net abandoned
> 2026-06-17 (its global-palette path is V2-deferred, `Feature.globalPaletteV2 = false`).
> Core AI is RETIRED from the spine; the orphaned seam (`SixFour/CoreAI/`,
> `trainer/coreai_export/`) was DELETED 2026-06-26 in the L-anchor pivot cleanup (it was
> audit-only and unreferenced; git history is the record). Resurrect from scratch ONLY if a
> genuinely LARGE on-device generative-L head is roadmapped with a real trainer + weights. The Tier-2
> rule stands unchanged: on-device NN inference is a hand-written forward pass, never a
> CoreML black box, never an opaque ANE runtime. The amendment below is the historical
> record of why Core AI was considered.
>
> **AMENDMENT 2026-06-20 — Core AI for L-inference only.** `CoreAI.framework` is
> an Apple *system* framework (it satisfies the zero-third-party rule), and it is
> adopted for **exactly one job**: running the **frozen L (grayscale) net** for
> *inference* on device (`SixFour/CoreAI/`, asset built by
> `trainer/coreai_export/`). Scope and guards:
> - **L inference only.** Core AI cannot train. **A/B chroma learning stays on
>   MPSGraph** (`SixFour/Atlas/`). The "never `mlx-swift`" and zero-third-party
>   rules are **unchanged**.
> - **Determinism floor.** Core AI float output is *not* cross-device bit-exact,
>   so it MUST re-enter the Zig Q16 core via the `zero-genome == floor`
>   short-circuit before reaching the GIF bytes. The integer floor stays the only
>   bit-exact substrate.
> - **Guarded.** Core AI is absent from the iOS Simulator SDK (issue #49) and is
>   developer-beta (GA ~Sept 2026); every use sits behind `#if canImport(CoreAI)`
>   and is verifiable only on a real device.
>
> This contract is the canon; the pivot is the amendment above.

## Train / deploy spine
- **Train (base net):** MLX on the M1.
- **Train (on-device, per-user):** two paths under `SixFour/Train/` (PATH CORRECTION
  2026-07-03: `SixFour/Atlas/` was deleted with the A/B retirement, commit `1e0837b`;
  the historical AtlasTrainer proof — Bradley–Terry value training, 12.4 ms/step,
  bit-identical loss trajectory Mac↔iPhone, physical iPhone 17 Pro 2026-06-12 —
  established that MPSGraph training on device works; git history is the record).
  Today: `Train/RungDispatch.swift` (plain Metal fused kernel — runs in the simulator
  too) is the LIVE per-capture θ_up trainer; `Train/DeviceTrainer.swift` (MPSGraph)
  is the golden-parity harness, exercised by `DeviceTrainGoldenTests` only. MPSGraph
  satisfies the Tier 2 contract (Apple system framework); the never-`mlx-swift` rule
  stands; Core AI is allowed for **L-inference only** (see the amendment above),
  never for training. MPSGraph does not execute in the simulator (gate via
  `targetEnvironment(simulator)`).
  **Orientation:** this contract (the amendment above) is the canon. The sunset
  plans `docs/ON-DEVICE-TRAINING.md` / `docs/COLOR-ATLAS.md` / `docs/STATUS.md`
  were deleted; their essentials live in these rules and the purpose-headers in
  `SixFour/Train/`.
- **Verify:** Haskell spec (golden vectors gate every backend).
- **Deploy (theta_B, the only learned object):** MLX-trained 63-param blob →
  HAND-WRITTEN Swift forward in `SixFour/Native/MaskedBandForward.swift`,
  golden-gated (`MaskedBandGolden`) and byte-exact on device. NO Core AI.
  (SUPERSEDES the 2026-06-22-retired "Deploy L via Core AI" line; see the amendment
  block above. The `trainer/coreai_export/` → `L.aimodel` → Core AI path was DELETED 2026-06-26.)
- **Deploy (A/B + integer core):** hand-written Swift + Metal + Zig on the iPhone
  17 Pro (zero third-party deps).
- **Fallback:** the older PyTorch→CoreML→ANE distillation is superseded by the
  Core AI L path; the hand-written-blob forward pass remains a valid alternative.

## Palette: global vs per-frame
**MVP1 ships PER-FRAME palettes only.** The global (GIFB) path below is implemented and
golden-gated but **DEFERRED TO V2** behind `Feature.globalPaletteV2 = false` (every entry point is
guarded ⇒ unreachable in MVP1). The per-frame + A/B-genome direction lives in the
spec (`Spec/StageA.hs`, `Spec.Proposer`, `Spec.GenomePair`); its earlier
migration-workflow docs were sunset.

`Spec/StageA.hs` extracts a **per-frame** 256-colour palette per frame — that is
the NN *input*. The look-NN sum-pools all frames' tokens (permutation-invariant)
and *would* emit ONE **global** **384-DOF σ-pair genome** (`SIGMA_PAIR_DOF` = 3·128
generators; `Spec/SigmaPairHead.hs`, `Spec/LookNetD.hs`) for the whole 64³ GIF —
reconstructed into the 256-leaf palette. The *output* is the genome; the palette
it reconstructs lives in the **768-real flat leaf space** (256·3). Do not conflate
the two: the NN emits 384, the leaf space is 768. The form is pinned canonically in
`Spec/Net.hs slotLookDims` → `Generated/NetContract.swift` + `trainer/.../net_shape.py`.
Both NN-input and NN-output are true, at different layers.


## The GIF89a color head (the 16/32/64 ladder)

The camera's COLOR HEAD and its exact-arithmetic learning gates (landed 2026-07-03/04):

- **`Native/src/palette16.zig`** (zero imports): 16×16 bin → 768-byte GCT. u64 block-SUMS are the
  transitive pyramid carrier (rounded means do not compose — teeth-tested); the GCT is a final
  rounding realization. `s4_ladder_delay_cs` = THE TIME LAW: GIF89a's centisecond GCE delay forces
  the isotropic ladder 64@20fps / 32@10 / 16@5 (delays 5/10/20 cs) and caps it at 64 (side | 320).
  Inverse-EOTF LUTs (literal goldens, sRGB + HLG BT.2100) give the radiometric path; the capture
  contract (10-bit `x420`, Swift does Y'CbCr→R'G'B' + range expansion BEFORE the LUT) is recorded
  in the file header. `s4_pool_sums_bgra8` pools straight from CVPixelBuffer 32BGRA (stride-aware,
  center-crop in-kernel).
- **`Native/src/kinematic.zig`** (zero imports): `s4_certified_order` / `s4_newton_predict` /
  `s4_residual_loss` — the exact on-device observables of `Spec.KinematicLadder` +
  `Spec.KinematicHaltPrior` (certified kinematic order = the PonderNet halting-prior floor; short
  windows REFUSE rather than vacuously certify).
- **`SixFour/Metal/PaletteLadder.metal`**: GPU pooling, one thread per bin, sequential integer
  accumulation over raw bytes (no texture/unorm-float) — byte-identical to the Zig floor by
  construction; the Zig kernel is the authority, parity gated in `ColorHeadTests`.
- **`SixFour/Capture/ColorHead.swift`**: the per-tick circuit — poolSums64 → ingest derives the
  32/16 rungs by exact u64 adds at the GIF-exact cadences → GCT + 256 particle L-streams →
  `haltFloor()` per-slot certified order. AVFoundation-free. WIRED into CaptureSession (2026-07-04):
  constructed per burst when `Feature.yinYangBands` (`CaptureSession.finishBurst` gate), fed per tick
  via `poolSums64(fromX420:)` + `ingest`, drained at burst end into the `BandHeadTrainer`. Telemetry
  /learning only — no GIF byte depends on it. NOTE: the live x420 path sets `lastCropArea = 0`, so
  `latestGCT` stays nil on device (GCT realization is the 32BGRA `poolSums64` path, not the camera's).
- **Spec gates**: `Spec.OctantViews` (2×2×2 grading 1+3+3+1 = Walsh–Hadamard; latents = mixed
  derivatives), `Spec.PaletteKinetics` (256 particles; entropy as exact microstate counts W),
  `Spec.KinematicLadder` (Δ^k coarsens by Pascal row k+1; Newton = Mahler basis; budget law),
  `Spec.KinematicHaltPrior` (cheapest zero-loss halt == certified order), `Spec.TriScaleTraining`
  (transitions train disjoint bits; info-per-compute rung-invariant; all three scales = 9/8 the
  finest alone). Tests: spec suite + `zig build test` + `SixFourTests/ColorHeadTests` (Metal↔Zig
  parity) + `PaintGateTests`.

## Build / test
```bash
cd spec && cabal build && cabal test && cabal run spec-codegen   # verify + regen contracts
cd Native && zig build test                                      # owned Zig core (100 tests; runner may report 'failed command' — run the cached test binary in .zig-cache/o/*/test directly for truth)
cd .. && xcodegen generate                                       # regen .xcodeproj (after ANY new .swift)
xcodebuild -scheme SixFour -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
**Headless / no-simulator-installed machines** (compile-check only — there is no camera, so the
bar is BUILD SUCCEEDED, the user runs on device): the prebuilt Native lib is **arm64-only**, so a
generic destination that also wants x86_64 fails at LINK (not a Zig/codegen bug). Restrict to arm64:
```bash
xcodegen generate
xcodebuild -scheme SixFour -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 build-for-testing
```
The build auto-stamps `SixFour/Generated/BuildStamp.swift` (gitSHA + time) — `git checkout` it
before committing so the stamp is not committed as noise.
Never hand-edit generated files (`SixFour/Generated/`, `trainer/generated/`,
`studio/look-nn-baseline/src/generated/`) — change `spec/src/SixFour/Codegen/`
and regenerate.

## The spec is browsable — use it, keep it that way

The Haskell spec is the source of truth AND a browsable reference. Its module
doc-comments (`{- | … -}`) and per-function `-- |` comments ARE the spec pages.
Tooling: **Haddock** (hyperlinked HTML + quickjump search), **Hoogle** (name/type
search), **ghcid** (live typecheck), **graphviz** (module import graph). One
driver: `spec/scripts/spec-docs.sh` (`--serve` for Hoogle on :8080).

**Start any spec exploration at module `SixFour.Spec.Map`** — the categorised
index (NN design is the ★ core category). Browse before grepping.

**Maintenance contract (every session):**
- Adding a `Spec.*`/`Codegen.*` module → (1) wire it in `spec.cabal`
  `exposed-modules`, (2) give it a `{- | Module / Description / … -}` header,
  (3) add ONE line in `SixFour.Spec.Map` under its category. A module with no
  `Map` entry is the lint failure.
- Every exported function gets a `-- |` doc — no blank Haddock rows.
- The iterate loop after any spec change: `ghcid` (live) → `cabal test`
  (laws + golden gate) → `cabal run spec-codegen` (regen app contracts) →
  `spec/scripts/spec-docs.sh` (regen Haddock + Hoogle + import graph).
- `cabal haddock sixfour-spec` must stay warning-clean (missing docs surface
  there). Treat a Haddock warning like a build warning.
