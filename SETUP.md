# SixFour — setup

## iPhone app

```bash
cd ~/SixFour
./scripts/regenerate.sh         # xcodegen + post-fix for the STBN .bin tile

# Verify it builds for simulator
xcodebuild -project SixFour.xcodeproj -scheme SixFour \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build

# Install on tethered iPhone 17 Pro:
open SixFour.xcodeproj          # then in Xcode: select your device, Run (⌘R)
```

The first launch will prompt for camera permission. On accept, the shutter button captures
exactly 64 frames at 20 fps and renders a 64×64 per-frame-palette GIF saved to the app's
Documents directory. Use the share button to AirDrop the GIF out.

## Mac trainer

The Mac-side trainer is the **H-JEPA trainer** in `trainer/mlx/`, a hand-written MLX/numpy
realization gated byte-exact against the Haskell spec. See `trainer/TRAINING.md` for the runbook.

```bash
cd ~/SixFour/trainer/mlx
python3 gate_trainer.py            # the full trainer gate (byte-exact core + head + spec goldens)
python3 train_loop.py --smoke      # the end-to-end MLX optimizer (Apple Silicon / M1)
```

Dependencies live in `trainer/.venv` (MLX + numpy; torch/coremltools only for the dormant CoreML
fallback). The retired look-net regimen (`regimen.py`, `train_look_net_mlx.py`,
`export_look_net_blob.py`) is gone; `train_metric.py` / `export_organ.py` are dormant pre-look-NN
scripts retained for reference only.

## Layout

- `SixFour/` — the iOS app sources, picked up by xcodegen via `project.yml`
- `trainer/mlx/` — the Mac-side H-JEPA trainer (MLX/numpy), ignored by the iOS build
- `spec/` — the Haskell spec: the source of truth, gated by `cabal test`, emits the contracts
- `CLAUDE.md` — the project contract / canon (tier rules, train+deploy spine)
