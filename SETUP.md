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
exactly 64 frames at 20 fps and renders a 64×64 global-palette GIF saved to the app's
Documents directory. Use the share button to AirDrop the GIF out.

## Mac trainer

The current path is the **L-NN nucleus regimen** — one command builds the classified synthetic
corpus, runs the gates, trains, and exports the deploy blob (synthetic-only; no Haskell needed).
See `trainer/TRAINING.md` for the authoritative runbook.

```bash
cd ~/SixFour/trainer
uv run python regimen.py --smoke    # fast structure check (~1 min)
uv run python regimen.py            # full run (Apple Silicon / M1, ~minutes)
```

The blob exporter is `export_look_net_blob.py` (byte-exact, parsed on-device by
`s4_load_look_net`). The older `train_metric.py` / `export_organ.py` "gene library" scripts are
the pre-look-NN-trainer path and are retained only for reference.

## Layout

- `SixFour/` — the iOS app sources, picked up by xcodegen via `project.yml`
- `trainer/` — Mac-side MLX training scripts, ignored by the iOS build
- `~/.claude/plans/quizzical-sleeping-pebble.md` — the approved architecture plan
