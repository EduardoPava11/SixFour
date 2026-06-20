# SixFour nucleus L-NN — training regimen (MacBook M1)

We do **not** train for production on the dev machine. This is the reproducible
**regimen**: `git pull`, then one command builds the classified synthetic corpus,
runs the gates, trains the L-NN nucleus, and exports the deploy blob. Synthetic-only
(no captured data); deterministic from seeds, so a run reproduces byte-for-byte on
any Apple-Silicon Mac.

## What the L-NN nucleus is

Input: any 64³ **colour** per-frame-palette GIF. Output: the highest-quality global
**grayscale** 64³ GIF (one shared 256-grey palette). It's the achromatic (σ-invariant)
core; A/B chroma nets build around it later. Architecture: σ-equivariant MoR encoder →
PonderNet-halting recursive core → **depth-8 256-distinct-L head** (the σ-pair is for
chroma; L uses full resolution), trained as a soft-OT GAN. Beats the 256-level
Wasserstein-barycenter baseline on held-out captures.

> **DIRECTION NOTE (2026-06-20 — supersedes the "global grayscale palette" framing above):**
> L is being reframed from a grayscale-palette nucleus to a **white-balance +
> dynamic-range BALANCE network** — a learned **spatio-temporal LUT** that applies
> the reversible `(2×2)×(2×2)↔1` collapse/lift over the 64³ LAB cube. It is **NOT a
> global colour palette** (the global-output line above is the debt being retired).
> Training becomes **self-supervised on random colours** (learn the operator, no
> labels). Game role (homeostasis): A/B picks DESTABILIZE colours; L RE-BALANCES
> (white point + dynamic range). Canon home = `CLAUDE.md`; design search in progress.

## Prerequisites (M1)

- **Zig 0.16** (`brew install zig`) — builds the native core `libsixfour_native.dylib`.
- **uv** (`brew install uv`) — Python env from the pinned `uv.lock` (MLX trainer).
- *(optional)* **GHC 9.2.8 + cabal** via ghcup — only to *regenerate* the committed
  resources (`srgb_linear_lut.bin`, `axisnet_golden.json`, golden vectors). Running the
  regimen does **not** need Haskell; the committed resources suffice.

## Run it

```bash
# 1. Build the native core (synth + GIF codec + blob loader) → host dylib for ctypes.
cd Native && zig build && zig build test      # tests should be 22 pass / 1 skip
cd ..

# 2. Python env (pinned).
cd trainer && uv sync

# 3. The regimen.
uv run python regimen.py --smoke               # fast structure check (~1 min)
uv run python regimen.py                        # full run (M1, ~minutes)
```

## What the regimen does (and gates)

1. **PRE-TRAIN gates** (`gates.run_pretrain_gates`) — over every `SynthClass`:
   `determinism` (seed→bytes), `significance` (256/256 slots/frame), `roundtrip`
   (decode∘encode == identity), `token-contract` (16384×10, Σw=1, Σ=0). Abort if any fail.
2. **TRAIN** (`train_look_net_mlx.train`) — ε-annealed soft-OT GAN + halting on the
   **stratified classified corpus** (`synth_classes.CLASSES`, equal captures per class).
3. **QUALITY gate** (`gates.gate_beats_baseline`) — the L-NN must beat the 256-level
   barycenter on held-out captures of **every class** (≥75%) — variance-hardened, not averaged.
4. **EXPORT** → `out/look_net_trained.s4ln` (loads via the Zig `s4_load_look_net`).
   The run is **ACCEPTED** only if the quality gate passes.

## Classification (`synth_classes.py`)

The corpus is stratified across named regions of the input envelope so training and
gating cover the whole space (not just easy captures):
`wide_color`, `wide_gray`, `mid_color`, `narrow`, `lowkey`, `highkey`, `highchroma`
— each a (L-dynamic-range × chroma × key) preset. Add a class = add a `SynthClass`.

## Regenerating committed resources (optional, needs Haskell)

```bash
cd spec && cabal run spec-fixtures   # → Native/src/{gamma_lut,srgb_linear_lut}.bin
cabal run spec-codegen               # → trainer/generated/*, axisnet_golden.json
cabal test                           # 320 spec + 10 gen tests (the spec gate)
```
