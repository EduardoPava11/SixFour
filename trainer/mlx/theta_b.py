"""The 63-param masked-band predictor theta_B, the twin of the forward pass in
spec/SixFour/Spec/MaskedBandPrediction.hs. The ONLY learned object in the stack.

A MaskedBandExample is (coarse, detail7, masked_index):
  * coarse       - the visible coarse value v
  * detail7      - the ground-truth seven octant bands (a list/tuple of 7 ints)
  * masked_index - which band m in [0,6] is hidden and regressed

Forward:
    raw_m(v, sibs) = theta_row[m] . featuresB(v, sibs)        (a Mac-side Double)
    band_m         = quantize_q16(raw_m)                       (the one float->byte crossing)

There are NUM_BANDS rows of FEATURE_COUNT_B each => 7*9 = 63 flat params, laid out
theta_0 ++ ... ++ theta_6. zeroParamsB is the floor BY ARITHMETIC: 0 . phi = 0 and
quantize_q16(0) = 0, so the floor prediction is band 0 with no sentinel branch.
"""
from __future__ import annotations

from encoder_frozen import (
    NUM_BANDS, FEATURE_COUNT_B, SIBLING_COUNT, POSITION_FEATURE_COUNT,
    features_b, features_b_pos,
)
from q16 import quantize_q16

# 7 bands * 9 features = 63 flat params (MaskedBandPrediction.hs:133-135).
PARAM_COUNT_B = NUM_BANDS * FEATURE_COUNT_B
# Position-conditioned head: 7 bands * 11 features = 77 (MaskedBandPrediction.hs:509-510).
PARAM_COUNT_B_POS = NUM_BANDS * POSITION_FEATURE_COUNT


def zero_params_b() -> list[float]:
    """The all-zero parameter vector, the floor by arithmetic (not a sentinel)."""
    return [0.0] * PARAM_COUNT_B


# --- masked-example helpers (MaskedBandPrediction.hs:152-195) ---

def clamp_index(m: int) -> int:
    """Masked band index wrapped into [0, NUM_BANDS)."""
    return ((m % NUM_BANDS) + NUM_BANDS) % NUM_BANDS


def bands_list(detail) -> list[int]:
    """The seven detail bands as a list in canonical order."""
    return list(detail)[:NUM_BANDS]


def band_at(detail, i: int) -> int:
    """Read band i (clamped) of a detail."""
    return bands_list(detail)[clamp_index(i)]


def set_band(detail, i: int, x: int) -> list[int]:
    """Overwrite band i (clamped) of a detail with value x."""
    i2 = clamp_index(i)
    return [x if j == i2 else b for j, b in enumerate(bands_list(detail))]


def mbe_coarse(ex) -> int:
    return ex[0]


def mbe_masked(ex) -> int:
    return clamp_index(ex[2])


def siblings_of(ex) -> list[int]:
    """The six VISIBLE sibling bands: every band except the masked one, canonical order.

    This is the only detail the predictor may see; the masked band is excluded
    (lawMaskedContextExcludesTarget has teeth against a leak).
    """
    m = mbe_masked(ex)
    return [b for j, b in enumerate(bands_list(ex[1])) if j != m]


def masked_target_band(ex) -> int:
    """The masked band's true value, the regression target."""
    return band_at(ex[1], ex[2])


# --- forward (MaskedBandPrediction.hs:204-226) ---

def rows_b(ps: list[float]) -> list[list[float]]:
    """Slice the flat 63 params into 7 rows of 9."""
    return [ps[j * FEATURE_COUNT_B:(j + 1) * FEATURE_COUNT_B] for j in range(NUM_BANDS)]


def raw_masked_band(ps: list[float], ex) -> float:
    """The Mac-side RAW readout theta_m . phi_B(v, sibs), a Double before Q16 re-entry."""
    phi = features_b(mbe_coarse(ex), siblings_of(ex))
    row = rows_b(ps)[mbe_masked(ex)]
    return sum(r * p for r, p in zip(row, phi))


def predict_masked_band(ps: list[float], ex) -> int:
    """THE predictor: the raw readout re-entered to the Q16 device floor (the one crossing)."""
    return quantize_q16(raw_masked_band(ps, ex))


# --- position-conditioned forward (the 77-param theta_B-Pos; the I-JEPA mask-token position).
# A MaskedBandExamplePos is (coarse, detail7, masked_index, (x, y)). (MaskedBandPrediction.hs:516)

def zero_params_b_pos() -> list[float]:
    """The all-zero 77-param position head, the floor by arithmetic."""
    return [0.0] * PARAM_COUNT_B_POS


def rows_b_pos(ps: list[float]) -> list[list[float]]:
    """Slice the flat 77 params into 7 rows of 11."""
    return [ps[j * POSITION_FEATURE_COUNT:(j + 1) * POSITION_FEATURE_COUNT] for j in range(NUM_BANDS)]


def raw_masked_band_pos(ps: list[float], ex) -> float:
    """RAW position-conditioned readout theta_m . featuresBPos(v, sibs, (x, y))."""
    coarse, detail, mask, xy = ex
    sibs = [b for j, b in enumerate(bands_list(detail)) if j != clamp_index(mask)]
    phi = features_b_pos(coarse, sibs, xy)
    row = rows_b_pos(ps)[clamp_index(mask)]
    return sum(r * p for r, p in zip(row, phi))


def predict_masked_band_pos(ps: list[float], ex) -> int:
    """The position-conditioned prediction (Q16 byte via the single reenterQ16 crossing)."""
    return quantize_q16(raw_masked_band_pos(ps, ex))


if __name__ == "__main__":
    fails = 0
    floor = zero_params_b()
    # the golden fixture from MaskedBandTrainer.hs:53
    ex = (20000, (3000, 0, 0, 0, 0, 0, 0), 0)

    if PARAM_COUNT_B != 63:
        print(f"FAIL: PARAM_COUNT_B {PARAM_COUNT_B} != 63"); fails += 1

    # zero-genome == floor: at the floor the prediction is band 0 (== goldenFloorBand).
    if predict_masked_band(floor, ex) != 0:
        print("FAIL: floor prediction != 0"); fails += 1

    # masking: siblings exclude band 0 (the masked band) -> the six visible bands.
    if siblings_of(ex) != [0, 0, 0, 0, 0, 0]:
        print(f"FAIL: siblings_of leaked the masked band: {siblings_of(ex)}"); fails += 1
    if masked_target_band(ex) != 3000:
        print("FAIL: masked target != 3000"); fails += 1

    # NON-CONSTANT: bumping the masked row's bias param (phi_B0 = 1) moves raw by ~1.
    hh = 1e-6
    bump = floor[:]
    bump[0] += hh   # band 0's bias feature
    sens = (raw_masked_band(bump, ex) - raw_masked_band(floor, ex)) / hh
    if abs(sens - 1.0) > 1e-3:
        print(f"FAIL: bias sensitivity {sens} != phi_B0 = 1"); fails += 1

    # masking guarantee: changing ONLY the masked band leaves the prediction unchanged.
    ex_peek = (20000, set_band((3000, 0, 0, 0, 0, 0, 0), 0, 9999), 0)
    if predict_masked_band(floor, ex) != predict_masked_band(floor, ex_peek):
        print("FAIL: prediction depended on the masked band (target leak)"); fails += 1

    print("theta_b: PASS" if fails == 0 else f"theta_b: {fails} FAIL")
    raise SystemExit(1 if fails else 0)
