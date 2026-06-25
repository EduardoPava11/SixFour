# SixFour H-JEPA trainer — runbook

The Mac-side trainer for the only learned object, the hierarchical-JEPA head that rides above
the proven byte-exact `theta_B` floor. Everything lives in `trainer/mlx/`, each module a
byte-exact twin of a `spec/SixFour/Spec/*` module, and the whole thing is **forced to match the
spec**: the spec emits goldens (`trainer/generated/*.json`) that the trainer must reproduce.

> The retired look-net L-NN regimen (`regimen.py`, `train_look_net_mlx.py`,
> `out/look_net_trained.s4ln`) is gone. This is its replacement.

## The CLI

`s4train` (`trainer/mlx/cli.py`, stdlib argparse, zero deps) is the front door:

```bash
./scripts/s4train --help        # all commands
./scripts/s4train gate          # run every module self-test
./scripts/s4train train --smoke # the end-to-end loop (~9s)
./scripts/s4train floor --export      # train theta_B + write the deploy blob
./scripts/s4train cube --gif          # octree compression demo + GIFs
./scripts/s4train goldens             # do the spec goldens reproduce byte-exact?
```

Each subcommand forwards to the module that owns the behavior, so the CLI never drifts from the
gated code. Everything below can also be run directly.

## Run the gate

```bash
cd trainer/mlx
python3 gate_trainer.py        # the byte-exact core + v2 head + spec-golden loaders + cube tests
```

All modules self-test; the runner reports one PASS/FAIL. MLX is optional — the byte-exact core
gates without it (only the ViT demo and the autodiff cross-check need `mlx`). Dependencies are
in `trainer/.venv` (MLX, numpy; torch/coremltools only for the dormant CoreML fallback).

## The composite objective

```
L = L_band^A + L_band^B   (jepa_loss        — masked-band I-JEPA regression)
  + latentCodingFloor     (vicreg           — VICReg collapse guard on the pre-surface latent)
  + L_cross + L_mid        (dual_loss        — cross-encoder information floors, surfaced + 32^3)
```

Every target is **data-manufactured** (from the corpus), θ-free, no EMA — collapse is
structurally impossible. The committed byte always re-enters Q16 via `q16.quantize_q16` (Python
float64 round); MLX float32 is used only for the latent ViT and the gradient, never to decide a byte.

## Module roster (`trainer/mlx/`)

| Module | Spec twin | Role |
|---|---|---|
| `q16` | `Q16` / `ByteCarrier` | the single float→byte crossing |
| `encoder_frozen` | `EncoderFrozen` | the zero-param feature map (`encoderParamCount == 0`) |
| `theta_b` | `MaskedBandPrediction` | the 63-param predictor + 77-param position head |
| `jepa_loss` | `MaskedBandPrediction` | masked-band loss + exact gradient |
| `masked_band_trainer` | `MaskedBandTrainer` | reproduces `goldenTrainedBand` (3000) byte-exact |
| `autograd_check` | — | MLX autodiff == the analytic gradient |
| `jepa_synth_octants` | `JepaData` / `SyntheticCorpus` | real 64³ synth captures → octant corpus |
| `vicreg` | `NeuronRedundancy` | the two-term collapse guard |
| `large_head` | `LargeJepaHead` | the 18.9M-param ViT + d6-ALiBi bias; depth-1 == `theta_b` |
| `per_scale` | `PerScaleWeights` | per-scale conditioning + the 16³-identity carve-out |
| `jepa_head_golden` | `Codegen.JepaHead` | forces the head trainer to the spec golden |
| `temporal_data` | `Codegen.TemporalData` | the `(t, t+1)` value/policy delta engine |
| `delta_surrogate` | `DeltaSurrogate` | the value (regression) + policy (classification) heads |
| `dual_loss` | `DualEncoderJepa` / `MidLatentCrossPrediction` | `L_cross` + `L_mid` |
| `train_loop` | — | the end-to-end MLX optimizer over the corpus |

## Standalone runs (not in the fast gate)

```bash
python3 train_loop.py --smoke          # end-to-end: descent + no-collapse + byte-commit + determinism
python3 jepa_synth_octants.py          # corpus training; generalization is smoothness-proportional
python3 test_centered_cube.py --gif    # octree compression: a 64³ cube → 16³ coarse, zero detail
python3 test_cube_learning.py          # the floor nails the flat 99.5%; theta_B learns the surface
```

## Regenerate the spec goldens

The trainer's goldens are spec-emitted. After any change to the head/data/temporal spec:

```bash
cd ../../spec
cabal build && cabal test && cabal run spec-codegen   # re-emits trainer/generated/*.json
```

The Python loaders (`jepa_head_golden.py`, `temporal_data.py`, `jepa_data.py`) then reproduce them
byte-exact, so a one-byte drift between the spec and the trainer is a gate failure.

## Deploy

The trained 63-param `theta_B` blob ships as a **hand-written Swift forward pass**
(`SixFour/Native/MaskedBandForward.swift`), verified bit-exact against the spec golden
(`SixFour/Generated/MaskedBandGolden.swift`). No Core AI, no CoreML black box — see `CLAUDE.md`.
