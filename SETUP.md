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

```bash
cd ~/SixFour/trainer
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

# Drop reference GIFs into trainer/data/reference_gifs/, then:
python train_metric.py --steps 2000 --out out/metric.json
python export_organ.py --slot metric --input out/metric.json --name "warm-look"
```

Then copy the resulting `out/genes/metric/<hash>.json` + `index.json` to the device's
SixFour gene library (via Files app or future AirDrop bundle support).

## Layout

- `SixFour/` — the iOS app sources, picked up by xcodegen via `project.yml`
- `trainer/` — Mac-side MLX training scripts, ignored by the iOS build
- `~/.claude/plans/quizzical-sleeping-pebble.md` — the approved architecture plan
