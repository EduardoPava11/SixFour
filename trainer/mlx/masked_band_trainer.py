"""THE FIRST GREEN TRAINING STEP. Twin of spec/SixFour/Spec/MaskedBandTrainer.hs.

This is the byte-checkable training gate for the only learned object, theta_B. A
single fixed example, trained for a fixed number of steps from the floor, must take a
SPECIFIC trajectory and recover a golden committed band:

    trainerExample   = (20000, (3000, 0, 0, 0, 0, 0, 0), 0)    coarse 20000, mask band 0
    trainerSteps     = 2000
    goldenFloorBand  = 0      (the floor prediction, zero-genome == floor)
    goldenTrainedBand = 3000  (the byte the MLX-trained theta_B AND the device forward
                               pass must both reproduce, exactly, through the Q16 crossing)

Two trainers, both eta = 0.2 from the floor:
  * train_band_joint        - SUMMED gradient (the spec's trainBandJoint). The effective
                              step scales with batch size N, so a batch of many high-v~
                              examples drives eta*N*lambda past the GD stability bound and
                              the descent diverges to NaN.
  * train_band_joint_stable - MEAN gradient. Batch-size-independent, stays convergent.
    Both reproduce the single-example golden (summed == mean on one example).

Run this module to execute the gate. Run with `--export` to also write the trained
63-float blob that SixFour/Native/MaskedBandForward.swift loads.
"""
from __future__ import annotations

import json
import os
import sys

from jepa_loss import masked_band_gradient, masked_band_loss_sum
from theta_b import PARAM_COUNT_B, zero_params_b, predict_masked_band

# --- the golden fixture + its pinned trajectory endpoints ---
TRAINER_EXAMPLE = (20000, (3000, 0, 0, 0, 0, 0, 0), 0)
TRAINER_STEPS = 2000
GOLDEN_FLOOR_BAND = 0
GOLDEN_TRAINED_BAND = 3000
ETA = 0.2


def _zeros() -> list[float]:
    return [0.0] * PARAM_COUNT_B


def train_band_joint(n: int, exs) -> list[float]:
    """Full-batch joint training, SUMMED gradient, eta = 0.2, from the floor (spec twin)."""
    ps = zero_params_b()
    for _ in range(max(0, n)):
        acc = _zeros()
        for ex in exs:
            g = masked_band_gradient(ps, ex)
            for i in range(PARAM_COUNT_B):
                acc[i] += g[i]
        ps = [p - ETA * gi for p, gi in zip(ps, acc)]
    return ps


def train_band_joint_stable(n: int, exs) -> list[float]:
    """Full-batch joint training, MEAN gradient, eta = 0.2 (the batch-stable trainer)."""
    ps = zero_params_b()
    m = max(1, len(exs))
    for _ in range(max(0, n)):
        acc = _zeros()
        for ex in exs:
            g = masked_band_gradient(ps, ex)
            for i in range(PARAM_COUNT_B):
                acc[i] += g[i]
        ps = [p - ETA * (gi / m) for p, gi in zip(ps, acc)]
    return ps


def export_blob(path: str) -> None:
    """Write the trained 63-float theta_B + golden metadata for the device forward pass."""
    theta = train_band_joint(TRAINER_STEPS, [TRAINER_EXAMPLE])
    blob = {
        "param_count": PARAM_COUNT_B,
        "eta": ETA,
        "steps": TRAINER_STEPS,
        "trainer_example": TRAINER_EXAMPLE,
        "golden_floor_band": GOLDEN_FLOOR_BAND,
        "golden_trained_band": GOLDEN_TRAINED_BAND,
        "predicted_band": predict_masked_band(theta, TRAINER_EXAMPLE),
        "theta_b": theta,
    }
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(blob, f, indent=2)
    print(f"exported theta_B blob -> {path} (predicted band {blob['predicted_band']})")


def _gate() -> int:
    fails = 0
    floor = zero_params_b()

    # zero-genome == floor: the start point predicts the floor band and incurs real loss.
    if predict_masked_band(floor, TRAINER_EXAMPLE) != GOLDEN_FLOOR_BAND:
        print("FAIL: floor prediction != goldenFloorBand"); fails += 1
    floor_loss = masked_band_loss_sum(floor, [TRAINER_EXAMPLE])
    if not (floor_loss > 1e-6):
        print("FAIL: floor incurs no loss (vacuous fixture)"); fails += 1

    # THE BYTE-CHECKABLE TWIN (lawTrainedForwardIsGolden): after 2000 steps -> 3000 exactly.
    theta = train_band_joint(TRAINER_STEPS, [TRAINER_EXAMPLE])
    pred = predict_masked_band(theta, TRAINER_EXAMPLE)
    if pred != GOLDEN_TRAINED_BAND:
        print(f"FAIL: trained band {pred} != goldenTrainedBand {GOLDEN_TRAINED_BAND}"); fails += 1
    else:
        print(f"  byte-exact: trained theta_B recovers band {pred} == 3000")

    # lawTrainingDrivesLossDown: trained loss < 1e-3 of the floor loss.
    trained_loss = masked_band_loss_sum(theta, [TRAINER_EXAMPLE])
    if not (trained_loss < 1e-3 * floor_loss):
        print(f"FAIL: loss not driven down ({trained_loss} vs floor {floor_loss})"); fails += 1

    # lawTrainingDescendsMonotonically: more steps never increase the loss.
    l_2000 = masked_band_loss_sum(train_band_joint(2000, [TRAINER_EXAMPLE]), [TRAINER_EXAMPLE])
    l_100 = masked_band_loss_sum(train_band_joint(100, [TRAINER_EXAMPLE]), [TRAINER_EXAMPLE])
    if not (l_2000 <= l_100):
        print(f"FAIL: descent not monotone ({l_100} -> {l_2000})"); fails += 1

    # lawStableTrainerSurvivesBatchDivergence: summed diverges on 8 high-v~; mean stays finite.
    many = [(v, (3000, 0, 0, 0, 0, 0, 0), 0) for v in range(50000, 64001, 2000)]  # 8 examples
    loss_summed = masked_band_loss_sum(train_band_joint(5000, many), many)
    loss_stable = masked_band_loss_sum(train_band_joint_stable(5000, many), many)
    summed_diverged = (loss_summed != loss_summed) or (loss_summed == float("inf")) or (loss_summed > 1.0)
    stable_finite = (loss_stable == loss_stable) and (loss_stable != float("inf"))
    if not summed_diverged:
        print(f"FAIL: summed trainer did NOT diverge on the high-v~ batch ({loss_summed})"); fails += 1
    if not (stable_finite and loss_stable < 1e-3):
        print(f"FAIL: stable trainer did not converge on the batch ({loss_stable})"); fails += 1
    if fails == 0:
        print(f"  batch guard: summed diverged ({loss_summed:.3g}), mean converged ({loss_stable:.3g})")

    print("masked_band_trainer: PASS" if fails == 0 else f"masked_band_trainer: {fails} FAIL")
    return 1 if fails else 0


if __name__ == "__main__":
    rc = _gate()
    if "--export" in sys.argv and rc == 0:
        export_blob(os.path.join(os.path.dirname(__file__), "..", "out", "theta_b_golden.json"))
    raise SystemExit(rc)
