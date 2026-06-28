"""Gate: trainer/mlx/upscale256.py reproduces the Haskell oracle byte-exact.

Loads trainer/out/upscale256_golden.json (emitted by `cabal run spec-fixtures` from
Spec.Upscale256.upscale256) and asserts the Python port produces the identical UpscaleOutput. This
is what makes "above-floor" measurable against the REAL deterministic floor (Spec.ModelIO.buildFloor),
not a zero baseline. Run: `python3 trainer/mlx/test_upscale256.py`.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from upscale256 import upscale256  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "..", "out", "upscale256_golden.json")


def main():
    if not os.path.exists(GOLDEN):
        print(f"FAIL: golden missing ({GOLDEN}). Run `cd spec && cabal run spec-fixtures` first.")
        sys.exit(1)
    with open(GOLDEN) as f:
        g = json.load(f)

    got = upscale256(g["input"])
    want = g["output"]

    got_pals = [[list(px) for px in frame] for frame in got["palettes"]]
    want_pals = [[list(px) for px in frame] for frame in want["palettes"]]
    got_cube = [list(plane) for plane in got["cube"]]
    want_cube = [list(plane) for plane in want["cube"]]

    n_frames = len(want_pals)
    assert len(got_pals) == n_frames, f"frame count: {len(got_pals)} != {n_frames}"

    for f in range(n_frames):
        assert got_pals[f] == want_pals[f], (
            f"PALETTE drift at frame {f}:\n  got  {got_pals[f]}\n  want {want_pals[f]}")
        assert got_cube[f] == want_cube[f], (
            f"INDEX drift at frame {f}:\n  got  {got_cube[f]}\n  want {want_cube[f]}")

    n_px = len(want_cube[0]) if want_cube else 0
    print(f"upscale256: Python port reproduces the Haskell floor byte-exact "
          f"({n_frames} frames x {n_px} px, palettes + index planes) OK")


if __name__ == "__main__":
    main()
