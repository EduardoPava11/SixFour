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
from upscale256 import upscale256, quantize_prior, drift_prior  # noqa: E402

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

    # DRIFT-PRIOR DECISIVE case: verify the carried exit drift actually FLIPS a quantize choice
    # (lambda=0 -> nearest slot 0, lambda=1 -> slot 1). This gates drift_prior + quantize_prior
    # byte-exact, the path the full-cube golden does not make decisive.
    pc = g["priorCase"]
    pal = [tuple(c) for c in pc["palette"]]
    m = pc["map"]
    exit_drift = {row[0]: (row[1], row[2], row[3]) for row in pc["exitDrift"]}
    tgt = tuple(pc["target"])

    def prior_fn(j):
        return drift_prior(exit_drift, m, pal, tgt, j)

    pick0 = quantize_prior(0, pal, prior_fn, tgt)
    pick1 = quantize_prior(1, pal, prior_fn, tgt)
    assert pick0 == pc["pick0"], f"priorCase lambda=0: {pick0} != {pc['pick0']}"
    assert pick1 == pc["pick1"], f"priorCase lambda=1: {pick1} != {pc['pick1']}"
    assert pick0 != pick1, "the carried exit drift must FLIP the choice (else the prior path is untested)"

    n_px = len(want_cube[0]) if want_cube else 0
    print(f"upscale256: Python port reproduces the Haskell floor byte-exact "
          f"({n_frames} frames x {n_px} px, palettes + index planes); drift-prior flips "
          f"choice {pick0}->{pick1} OK")


if __name__ == "__main__":
    main()
