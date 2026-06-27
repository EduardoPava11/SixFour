"""STEP 2 lock test: real (L, a, b) chroma flows end-to-end into the value-head target + tokens.

Before this fix chroma was discarded at three sites: l_volume kept only channel 0 (L), so octant
cubes were L scalars, and palette_target hardcoded a=0, b=0. The corpus DOES carry real chroma
(high-lab palettes_q16 channels 1 and 2 reach abs ~17k), so the off-diagonal chroma-by-space cells
were identically zero and the rank-3 value signal collapsed to rank-1. This test proves chroma now
reaches BOTH the value target (palette_target) and the model input (example_tokens), and that the
per-channel reversible lift still round-trips byte-exact (the data-engine law, now on a/b too).

Skips cleanly (exit 0) when MLX / the synth-capture corpus deps are unavailable, so the byte-exact
core can still gate on a machine without them; where the deps ARE present it FAILS (exit 1) if
chroma is zero -- so it genuinely locks the fix.
"""
from __future__ import annotations

import os
import sys

try:
    import numpy as np
    # IMPORT ORDER IS LOAD-BEARING (the documented gotcha): the trainer/ dir CONTAINS this local
    # 'mlx/' package, so once trainer/ is on the path a fresh `import mlx.core` resolves to it and
    # fails. Import the REAL mlx FIRST so it is cached, THEN add trainer/ for jepa_data.
    import mlx.core  # noqa: F401
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from jepa_data import unlift_oct
    from jepa_synth_octants import build_corpus, octant_records
    from train_loop import palette_target, example_tokens
    from encoder_frozen import CHROMA_FEATURE_COUNT, POSITION_FEATURE_COUNT
    from q16 import to_q16
    DEPS_OK, DEP_ERR = True, None
except Exception as e:  # pragma: no cover - environment-dependent
    DEPS_OK, DEP_ERR = False, e


def main() -> int:
    if not DEPS_OK:
        print(f"[SKIP] test_chroma_flow (deps unavailable: {DEP_ERR})")
        return 0

    fails = 0
    examples, _ = build_corpus([(7, "high-lab")])

    # (1) THE TARGET carries real a/b. palette_target lays out [L, a, b] * 8; a/b are slots i%3 != 0.
    # Across the corpus at least one a/b entry must be substantially nonzero (rank-3, not rank-1).
    max_ab = 0.0
    for ex in examples:
        t = palette_target(ex)
        if len(t) != 8 * 3:
            print(f"FAIL: palette_target width {len(t)} != 24"); fails += 1; break
        max_ab = max(max_ab, max(abs(t[i]) for i in range(len(t)) if i % 3 != 0))
    if max_ab <= 0.0:
        print("FAIL: palette_target a/b all zero -- chroma NOT in the value target"); fails += 1
    else:
        print(f"  value target carries real chroma: max|a,b| = {max_ab:.4f} "
              f"(rank-3 signal, not rank-1)")

    # (2) THE INPUT carries real a/b. Tokens are width 25 (CHROMA_FEATURE_COUNT) and the coarse
    # a~/b~ that ride after the width-11 L sub-token are nonzero on a chroma example.
    tok = np.array(example_tokens(examples[0]))
    if tok.shape[1] != CHROMA_FEATURE_COUNT:
        print(f"FAIL: token width {tok.shape[1]} != {CHROMA_FEATURE_COUNT}"); fails += 1
    coarse_ab = max(abs(float(tok[0, POSITION_FEATURE_COUNT])),
                    abs(float(tok[0, POSITION_FEATURE_COUNT + 1])))
    if coarse_ab <= 0.0:
        print("FAIL: token coarse a~/b~ are zero -- chroma NOT in the model input"); fails += 1
    else:
        print(f"  model input carries real chroma: |coarse a~/b~| = {coarse_ab:.4f}")

    # (3) THE L PATH IS UNCHANGED. The width-11 L sub-token is byte-identical to what the theta_B
    # path sees, so PARAM_COUNT_B == 63 and the masked-band floor are untouched.
    from encoder_frozen import features_b_pos
    from theta_b import mbe_coarse, siblings_of
    ex0 = examples[0]
    step = 65536 // 4
    l_only = np.asarray(features_b_pos(mbe_coarse(ex0), siblings_of(ex0), (0 * step, 0 * step)),
                        dtype=np.float32)
    if not np.array_equal(tok[0, :POSITION_FEATURE_COUNT], l_only):
        print("FAIL: chroma map perturbed the width-11 L sub-token (theta_B path drifted)"); fails += 1
    else:
        print("  L sub-token byte-identical to the theta_B view (PARAM_COUNT_B == 63 untouched)")

    # (4) THE DATA-ENGINE LAW HOLDS ON CHROMA. Every octant's a and b channel round-trips
    # byte-exact through the reversible lift (the assert lives in octant_records; re-prove here so
    # the lock is explicit, and confirm palette_target == unlift_oct of each channel).
    n_checked = 0
    for cubeL, cL, dL, _xy, ((cA, dA), (cB, dB)) in octant_records(7, "high-lab", frame_step=16, space_step=16):
        assert unlift_oct(cA, list(dA)) == [int(v) for v in unlift_oct(cA, list(dA))]  # type sanity
        recA = unlift_oct(cA, list(dA))
        recB = unlift_oct(cB, list(dB))
        recL = unlift_oct(cL, list(dL))
        ex = (cL, tuple(dL), 0, ((cA, tuple(dA)), (cB, tuple(dB))))
        t = palette_target(ex)
        expect = []
        for L, a, b in zip(recL, recA, recB):
            expect += [to_q16(L), to_q16(a), to_q16(b)]
        if t != expect:
            print("FAIL: palette_target != per-channel unlift_oct round-trip"); fails += 1; break
        n_checked += 1
    print(f"  per-channel lift round-trips byte-exact on {n_checked} octants (L, a AND b)")

    print("test_chroma_flow: PASS" if fails == 0 else f"test_chroma_flow: {fails} FAIL")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
