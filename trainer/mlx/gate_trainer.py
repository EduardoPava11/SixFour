"""Run every trainer self-test in dependency order and report one PASS/FAIL.

Each module is an independently testable byte-exact twin of its spec module; this
runner executes them as subprocesses (so a SystemExit in one cannot abort the rest)
and exits nonzero if any fails. The MLX autograd check is optional: if MLX is not
importable the runner reports it SKIPPED rather than failing, so the byte-exact core
gates even on a machine without MLX.
"""
from __future__ import annotations

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# (module, required) - byte-exact core + v2 contract laws are required; MLX autodiff is optional.
# v1.5 corpus training (jepa_synth_octants.py) is run separately: it is slower (~11s) and needs
# synth_capture, so it is not part of this fast deterministic gate.
MODULES = [
    # v1 floor (byte-exact)
    ("q16.py", True),
    ("cell_loss.py", True),   # STEP 3: Spec.MatrixTarget.cellLoss byte-exact (the held-out objective)
    ("encoder_frozen.py", True),
    ("theta_b.py", True),
    ("jepa_loss.py", True),
    ("masked_band_trainer.py", True),
    # v2 wide head + collapse guard (contract laws run without MLX; the ViT demo needs it)
    ("vicreg.py", True),
    ("per_scale.py", True),
    ("large_head.py", True),
    # v3 spec-emitted goldens (the spec is the authority for the trainer)
    ("jepa_head_golden.py", True),
    ("test_learnability.py", True),  # the LEARNABILITY THEOREM ported byte-exact (Spec.LearnabilityTheorem)
    ("temporal_data.py", True),
    ("test_motion_floor.py", True),   # TimeRung prerequisite: corpus has inter-frame motion (MotionFloorCorpus)
    ("temporal_rung.py", True),        # TimeRung: a learned model beats PERSISTENCE on held-out (learns motion)
    ("test_detail_reachable.py", True),  # ScaleRung detail is LEARNABLE (oracle beats flat-mean floor; masking ok)
    ("test_learnability_behavior.py", True),  # the REAL trainer behaves as the theorem predicts (blind/sees/descent)
    ("delta_surrogate.py", True),
    ("gaussian_chroma.py", True),
    ("dual_loss.py", True),
    ("test_centered_cube.py", True),
    ("test_cube_learning.py", True),
    ("test_dashboard_verdict.py", True),
    ("test_cell_loss.py", True),   # STEP 3: trained+judged cell-aggregate objective lock
    # STEP 2 chroma flow (skips cleanly if MLX/synth-capture deps are absent; locks the fix otherwise)
    ("test_chroma_flow.py", True),
    ("test_anti_overfit.py", True),   # STEP 4: lr NaN-trap fix + weight decay + non-declining margin
    # FULL-MATRIX boundary (Spec.ModelIO alignment): the floor, the paint surface, the held corpus,
    # the floor-aligned loss, and the acceptance harness. No training; byte-exact / law twins.
    ("test_upscale256.py", True),     # buildFloor = upscale256, byte-exact vs the Haskell golden
    ("cell_budget.py", True),         # CellBudget = Spec.CellNudge laws
    ("model_io.py", True),            # ModelInput->buildFloor, nudge-invariant
    ("heldout_corpus.py", True),      # held-WHOLE (scale+time) corpus + motion floor
    ("full_matrix_loss.py", True),    # cell loss vs the REAL floor + float<->byte cross-check
    ("above_floor_margin.py", True),  # the acceptance number harness (survivesCommit + mean-dominance guard)
    ("full_matrix_model.py", True),   # ModelInput->ModelOutput forward wired to Spec.ModelIO (untrained smoke)
    ("full_matrix_train.py", True),   # nudge-conditioned invention + end-to-end train (beats floor on synthetic held detail)
    ("full_matrix_train_loop.py", True),  # the REAL training run: trains a held-out predictor, MEASURES the margin (honest verdict)
    # MLX autodiff cross-check (optional)
    ("autograd_check.py", False),
]


def _mlx_available() -> bool:
    try:
        import mlx.core  # noqa: F401
        return True
    except Exception:
        return False


def main() -> int:
    have_mlx = _mlx_available()
    failures = 0
    print("=== SixFour H-JEPA trainer gate (v1 floor + v2 head) ===")
    for mod, required in MODULES:
        if mod == "autograd_check.py" and not have_mlx:
            print(f"[SKIP] {mod} (MLX not importable; byte-exact core does not need it)")
            continue
        rc = subprocess.run([sys.executable, os.path.join(HERE, mod)], cwd=HERE).returncode
        if rc != 0:
            print(f"[FAIL] {mod} (exit {rc})")
            if required:
                failures += 1
        else:
            print(f"[ ok ] {mod}")
    print("=== GATE: all green ===" if failures == 0 else f"=== GATE: {failures} module(s) FAILED ===")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
