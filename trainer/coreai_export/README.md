# `coreai_export/` — the L-channel deploy bridge (Mac-side)

**PURPOSE.** This is the one new seam of the 2026-06-20 pivot: it converts the
**frozen L (grayscale) net** — trained by MLX/PyTorch on the Mac — into a Core AI
`.aimodel` asset that the iPhone loads for *inference*. See CLAUDE.md
(the 2026-06-20 amendment) for the pivot contract.

**SCOPE — read before adding code here.**
- ✅ L channel only. L is frozen at deploy time, so inference-only Core AI is the
  right tool.
- ❌ **No training.** Core AI / `coreai-torch` are export+inference only. The
  A and B chroma channels learn **on-device with MPSGraph** (`SixFour/Atlas/`) and
  never pass through this directory.
- ❌ Not shipped. This is Tier-1 Mac tooling (deps allowed); the *runtime* deps in
  the iOS app stay zero (only `CoreAI.framework`, an Apple system framework).

**Determinism.** Core AI float output is *not* cross-device bit-exact. The asset
produced here is only ever consumed behind the `zero-genome == floor`
short-circuit into the Zig Q16 core, so float noise never reaches the GIF bytes.

## Install (Apple-Silicon Mac, Python 3.11/3.12)

```bash
# Core AI runtime is developer-beta (coreai-core==1.0.0b1, GA ~Sept 2026);
# macOS wheels are arm64 + cp311/cp312 only.
uv pip install coreai-torch        # pulls coreai-core
```

## Run

```bash
uv run python export_l_coreai.py --weights ../out/look_net_trained.s4ln \
                                 --out ../out/L.aimodel
# device-side AOT compile (run with Xcode 27 toolchain):
xcrun coreai-build compile ../out/L.aimodel --platform iOS
```

The `.aimodel` is delivered to the app via Background Assets and loaded by
`SixFour/CoreAI/CoreAILInference.swift`.

## Owned kernels stay owned

`coreai-torch` lets SixFour ship its **own** Metal kernels *inside* the asset via
`TorchMetalKernel` + `converter.register_custom_kernels([...])`, instead of
handing the math to an opaque op set. This is how the cube-ladder collapse stays
SixFour's code while riding Core AI's runtime. See `export_l_coreai.py`.
