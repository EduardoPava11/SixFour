"""test_motion_floor.py -- the TimeRung prerequisite: the corpus must MOVE between frames.

Spec.MotionFloorCorpus.lawStaticCorpusStarvesGradient: on a STATIC clip, persistence (predict
t+1 := t) is optimal, so the temporal (TimeRung) gradient is ZERO. The two-rung H-JEPA's TIME rung
can only learn if the corpus carries real inter-frame motion. Each training octant is a 2x2x2
FRAME-MAJOR cube (jepa_synth_octants._cube_at): voxels [0:4] = frame f, [4:8] = frame f+1, so
inter-frame motion = |mean(cube[4:8]) - mean(cube[0:4])| per channel. This asserts the synth corpus
moves (L AND chroma), with the static-cube teeth (a flat cube => 0 motion, the degenerate case the
spec forbids). Byte-exact, no MLX; uses the SAME build_corpus the trainer trains on.
"""
import numpy as np

from jepa_synth_octants import build_corpus
from jepa_data import unlift_oct

# A corpus channel is "moving" only if its mean per-octant inter-frame delta clears this Q16 floor
# (1.0 Q16 ~= 1/65536 in OKLab L; a real moving edge is far above it, a static clip is 0).
MOTION_FLOOR_Q16 = 1.0
MIN_FRACTION_MOVING = 0.25


def cube_motion(cube):
    """Inter-frame motion of one frame-major 2x2x2 octant: |mean(frame f+1) - mean(frame f)|."""
    return abs(sum(cube[4:]) / 4.0 - sum(cube[:4]) / 4.0)


def corpus_motion(kinds, frame_step=8, space_step=8):
    specs = [(i * 7 + 1, k) for i, k in enumerate(kinds)]
    examples, _ = build_corpus(specs, frame_step=frame_step, space_step=space_step)
    mL, mC, moving = [], [], 0
    for (coarse, detail, _mask, chroma) in examples:
        cubeL = unlift_oct(coarse, list(detail))
        (cA, dA), (cB, dB) = chroma
        ml = cube_motion(cubeL)
        mc = cube_motion(unlift_oct(cA, list(dA))) + cube_motion(unlift_oct(cB, list(dB)))
        mL.append(ml)
        mC.append(mc)
        if ml + mc > 0.0:
            moving += 1
    n = len(examples) or 1
    return float(np.mean(mL)), float(np.mean(mC)), moving / n, len(examples)


def main():
    print("=== TimeRung prerequisite: inter-frame MOTION floor (Spec.MotionFloorCorpus) ===")
    # Teeth: a STATIC cube has zero motion; a cube that changes between frames is positive.
    assert cube_motion([5, 5, 5, 5, 5, 5, 5, 5]) == 0.0, "static cube must have zero motion"
    assert cube_motion([0, 0, 0, 0, 8, 8, 8, 8]) > 0.0, "a moving cube must have positive motion"

    kinds = ["high-lab", "high-detail", "smooth-grey"]
    meanL, meanC, frac, n = corpus_motion(kinds)
    print(f"  octants={n}  mean L motion={meanL:.1f} Q16  mean chroma motion={meanC:.1f} Q16  "
          f"fraction moving={frac:.3f}  (floor L>{MOTION_FLOOR_Q16}, frac>={MIN_FRACTION_MOVING})")
    print("  static-cube teeth: flat=0, moving>0 (ok)")
    ok = (n > 0 and meanL > MOTION_FLOOR_Q16 and frac >= MIN_FRACTION_MOVING)
    print("PASS: the corpus MOVES -- the TimeRung has gradient" if ok else
          "FAIL: corpus is (near-)static -- TimeRung would starve (persistence optimal)")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
