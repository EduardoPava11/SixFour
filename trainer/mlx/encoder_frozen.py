"""The FROZEN, zero-parameter encoder, the twin of spec/SixFour/Spec/EncoderFrozen.hs
and the feature map of MaskedBandPrediction.hs.

The encoder is a composition of two FIXED stages with nothing learned:
    GIF voxel -> liftOct (exact integer bijection) -> featuresB (fixed 9-D basis).

This module realizes the feature map (`featuresB` / `featuresBPos`); the lift is the
already-gated reversible Zig op upstream. The whole point is the invariant:

    ENCODER_PARAM_COUNT == 0          (EncoderFrozen.hs:100-101)

There is nothing to pre-train. The ONLY learned object is the 63-param theta_B
predictor that rides ABOVE this embedding (see theta_b.py).

    featuresB v sibs    = [1, v~, v~^2] ++ map toQ16 sibs      (width 9)
    featuresBPos v s xy = featuresB v sibs ++ [x~, y~]         (width 11)
where v~ = toQ16 v. The encoder threads no theta argument at all - that signature
(no theta) is what forbids a learned encoder by construction.
"""
from __future__ import annotations

from q16 import to_q16

# --- shape (MaskedBandPrediction.hs:114-135) ---
NUM_BANDS = 7              # octant detail bands
COARSE_FEATURE_COUNT = 3  # [1, v~, v~^2]
SIBLING_COUNT = NUM_BANDS - 1            # one band masked, six visible
FEATURE_COUNT_B = COARSE_FEATURE_COUNT + SIBLING_COUNT   # 3 + 6 = 9
POSITION_FEATURE_COUNT = FEATURE_COUNT_B + 2             # + (x~, y~) = 11

# The encoder owns ZERO learnable parameters. This is not a config knob; it is the
# architectural keystone (lawEmbeddingFeatureMapIsParameterFree). A learned projection
# inserted here would have to give this a nonzero value, which the trainer asserts against.
ENCODER_PARAM_COUNT = 0


def features_b(v: int, sibs: list[int]) -> list[float]:
    """The widened feature map phi_B(v, sibs) = [1, v~, v~^2] ++ map toQ16 sibs.

    Siblings are padded/trimmed to exactly SIBLING_COUNT (=6). Always FEATURE_COUNT_B wide.
    Threads no theta: the embedding depends only on its input.
    """
    vq = to_q16(v)
    sib = [to_q16(s) for s in sibs][:SIBLING_COUNT]
    sib += [0.0] * (SIBLING_COUNT - len(sib))
    return [1.0, vq, vq * vq] + sib


def features_b_pos(v: int, sibs: list[int], xy: tuple[int, int]) -> list[float]:
    """Position-conditioned map: featuresB ++ [x~, y~] (the I-JEPA mask-token position).

    The carriers {L, t} are deliberately NOT included; only the (x, y) search position.
    """
    x, y = xy
    return features_b(v, sibs) + [to_q16(x), to_q16(y)]


if __name__ == "__main__":
    fails = 0

    # lawEmbeddingFeatureMapIsParameterFree: width is the 9-D phi_B, encoder is param-free.
    emb = features_b(20000, [0, 0, 0, 0, 0, 0])
    if len(emb) != FEATURE_COUNT_B:
        print(f"FAIL: features_b width {len(emb)} != {FEATURE_COUNT_B}"); fails += 1
    if ENCODER_PARAM_COUNT != 0:
        print("FAIL: encoder is not parameter-free"); fails += 1

    # phi_B0 is the constant-1 bias; v~ = 20000/65536; v~^2 follows.
    if emb[0] != 1.0:
        print("FAIL: phi_B0 (bias) != 1"); fails += 1
    if abs(emb[1] - 20000 / 65536) > 1e-15:
        print("FAIL: v~ wrong"); fails += 1
    if abs(emb[2] - (20000 / 65536) ** 2) > 1e-15:
        print("FAIL: v~^2 wrong"); fails += 1

    # siblings ride the tail; a nonzero sibling shows up Q16-normalised at slot 3.
    emb2 = features_b(20000, [32768, 0, 0, 0, 0, 0])
    if abs(emb2[3] - 0.5) > 1e-15:
        print("FAIL: sibling 32768 did not normalise to 0.5"); fails += 1

    # position-conditioned width = 11, position token appended last.
    embp = features_b_pos(20000, [0] * 6, (32768, 0))
    if len(embp) != POSITION_FEATURE_COUNT:
        print(f"FAIL: features_b_pos width {len(embp)} != {POSITION_FEATURE_COUNT}"); fails += 1
    if abs(embp[FEATURE_COUNT_B] - 0.5) > 1e-15:
        print("FAIL: x~ token wrong"); fails += 1

    print("encoder_frozen: PASS" if fails == 0 else f"encoder_frozen: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
