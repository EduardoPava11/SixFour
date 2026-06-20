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
Tooling executables (`spec-tui`, `spec-gif`, tests) may use `brick`/`vty`/
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
> The full pivot map is `docs/NN-STACK.generated.md`.

## Train / deploy spine
- **Train (base net):** MLX on the M1.
- **Train (on-device, per-user):** **MPSGraph** — an Apple system framework, so it satisfies
  the Tier 2 contract. Proven on the physical iPhone 17 Pro 2026-06-12
  (`SixFour/Atlas/AtlasTrainer.swift`: Bradley–Terry value training, 12.4 ms/step,
  bit-identical loss trajectory Mac↔iPhone). The never-`mlx-swift` rule stands;
  Core AI is now allowed for **L-inference only** (see the amendment above), never
  for training. MPSGraph does not execute in the simulator (gate via
  `targetEnvironment(simulator)`).
  **Orientation: `docs/NN-STACK.generated.md`** is the single canonical map. (It
  replaces the sunset plans `docs/ON-DEVICE-TRAINING.md`, `docs/COLOR-ATLAS.md`,
  and `docs/STATUS.md`, which were deleted; their essentials now live in that map
  and in the purpose-headers of `SixFour/Atlas/`.)
- **Verify:** Haskell spec (golden vectors gate every backend).
- **Deploy (L, frozen):** MLX (Mac train) → `trainer/coreai_export/` → `L.aimodel`
  → **Core AI** inference on device (`SixFour/CoreAI/`), behind the Zig
  `zero-genome == floor` short-circuit. Owned Metal kernels ride inside the asset
  via `TorchMetalKernel`. (Per the 2026-06-20 amendment above.)
- **Deploy (A/B + integer core):** hand-written Swift + Metal + Zig on the iPhone
  17 Pro (zero third-party deps).
- **Fallback:** the older PyTorch→CoreML→ANE distillation is superseded by the
  Core AI L path; the hand-written-blob forward pass remains a valid alternative.

## Palette: global vs per-frame
**MVP1 ships PER-FRAME palettes only.** The global (GIFB) path below is implemented and
golden-gated but **DEFERRED TO V2** behind `Feature.globalPaletteV2 = false` (every entry point is
guarded ⇒ unreachable in MVP1). The per-frame + A/B-genome direction is mapped in
`docs/NN-STACK.generated.md` (the migration-workflow plans it cited were sunset).

`Spec/StageA.hs` extracts a **per-frame** 256-colour palette per frame — that is
the NN *input*. The look-NN sum-pools all frames' tokens (permutation-invariant)
and *would* emit ONE **global** **384-DOF σ-pair genome** (`SIGMA_PAIR_DOF` = 3·128
generators; `Spec/SigmaPairHead.hs`, `Spec/LookNetD.hs`) for the whole 64³ GIF —
reconstructed into the 256-leaf palette. The *output* is the genome; the palette
it reconstructs lives in the **768-real flat leaf space** (256·3). Do not conflate
the two: the NN emits 384, the leaf space is 768. The form is pinned canonically in
`Spec/Net.hs slotLookDims` → `Generated/NetContract.swift` + `trainer/.../net_shape.py`.
Both NN-input and NN-output are true, at different layers.

## Build / test
```bash
cd spec && cabal build && cabal test && cabal run spec-codegen   # verify + regen contracts
cd Native && zig build test                                      # owned Zig core (31 tests)
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
