"""gates.py — the TRAINING GATES for the nucleus regimen.

A training run is only ACCEPTED if these gates pass. They split into:

  PRE-TRAIN (data + pipeline correctness — must hold before a single step):
    • determinism   — (class, seed) → byte-identical capture (reproducible on any M1)
    • significance  — every frame's quantise populates all K=256 slots (CompleteVoxelVolume)
    • round-trip    — gif_decode(encode) == (indices, palettes), byte-exact (SOLID GIF)
    • token-contract— gif_to_tokens → (16384,10), Σw=1, Σ-columns exactly 0 (degenerate contract)

  POST-TRAIN (quality — the variance-hardened acceptance bar):
    • beats-baseline— the trained L-NN beats the 256-level Wasserstein barycenter on a
                      held-out validation set, on EVERY class (not the average), at ≥ `frac`.

Each gate returns (ok: bool, detail: str). `run_pretrain_gates` / `run_quality_gate`
aggregate. The regimen (regimen.py) refuses to export a blob unless all gates pass.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, List, Tuple

import numpy as np

import zig_native as zn
import global_palette as gp
import synth_classes as sc

K = zn.K
FRAME_COUNT = zn.FRAME_COUNT


@dataclass
class GateResult:
    name: str
    ok: bool
    detail: str


# ── PRE-TRAIN gates (per sampled capture) ──────────────────────────────────────
def gate_determinism(cls: sc.SynthClass, seed: int) -> GateResult:
    a = sc.materialize(cls, seed)
    b = sc.materialize(cls, seed)
    ok = np.array_equal(a.oklab_q16, b.oklab_q16) and a.gif == b.gif
    return GateResult("determinism", ok, f"{cls.name}#{seed}: identical={ok}")


def gate_significance(burst: zn.Burst, min_slots: int = K) -> GateResult:
    # Every frame's quantiser must populate all K slots (the significance contract).
    worst = K
    for f in range(burst.indices.shape[0]):
        pops = int((np.bincount(burst.indices[f].astype(np.int64), minlength=K) > 0).sum())
        worst = min(worst, pops)
    ok = worst >= min_slots
    return GateResult("significance", ok, f"min populated slots/frame = {worst}/{K}")


def gate_roundtrip(burst: zn.Burst) -> GateResult:
    idx, pal, F, S, Kk = zn.gif_decode(burst.gif)
    ok = (np.array_equal(idx, burst.indices) and np.array_equal(pal, burst.palettes_rgb)
          and (F, S, Kk) == (FRAME_COUNT, zn.SIDE, K))
    return GateResult("roundtrip", ok, f"decode==encode={ok} shape=({F},{S},{Kk})")


def gate_token_contract(burst: zn.Burst) -> GateResult:
    t = zn.gif_to_tokens(burst.gif)
    shape_ok = t.shape == (FRAME_COUNT * K, zn.GMM_TOKEN_DIM)
    sigma_zero = bool(np.all(t[:, 3:9] == 0))            # GIF carries no covariance
    sumw = float(t[:, 9].sum())
    ok = shape_ok and sigma_zero and abs(sumw - 1.0) < 1e-9
    return GateResult("token-contract", ok, f"shape_ok={shape_ok} Σ=0:{sigma_zero} Σw={sumw:.6f}")


def run_pretrain_gates(specs: List[Tuple[sc.SynthClass, int]], sample: int = 7) -> List[GateResult]:
    """Run the data/correctness gates on a sample of the corpus (one per class min)."""
    # Sample one spec per class (+ a few extra) to keep it fast but cover every class.
    seen, picked = set(), []
    for cls, seed in specs:
        if cls.name not in seen:
            picked.append((cls, seed)); seen.add(cls.name)
    picked = picked[: max(sample, len(seen))]

    def tag(name: str, gr: GateResult) -> GateResult:
        return GateResult(name, gr.ok, gr.detail)

    results: List[GateResult] = []
    for cls, seed in picked:
        results.append(tag(f"determinism[{cls.name}]", gate_determinism(cls, seed)))
        b = sc.materialize(cls, seed)
        results.append(tag(f"significance[{cls.name}]", gate_significance(b)))
        results.append(tag(f"roundtrip[{cls.name}]", gate_roundtrip(b)))
        results.append(tag(f"token[{cls.name}]", gate_token_contract(b)))
    return results


# ── POST-TRAIN quality gate (per class) ─────────────────────────────────────────
def gate_beats_baseline(palette_fn: Callable[[zn.Burst], np.ndarray],
                        classes=sc.CLASSES, per_class: int = 4, seed0: int = 90000,
                        frac: float = 0.75) -> List[GateResult]:
    """For each class, materialize `per_class` HELD-OUT captures, build the L-NN global
    palette via `palette_fn(burst) -> (256,) sorted L`, and require it to beat the
    256-level barycenter on ≥ `frac` of them. The variance-hardened acceptance bar."""
    results: List[GateResult] = []
    sid = seed0
    for c in classes:
        wins = 0
        margins = []
        for _ in range(per_class):
            b = sc.materialize(c, sid); sid += 1
            learned = gp.oklab_mse(b, palette_fn(b))
            base = gp.oklab_mse(b, gp.wasserstein_l_barycenter(b, k=256))
            wins += learned < base
            margins.append(base / max(learned, 1e-12))
        ok = wins >= int(np.ceil(frac * per_class))
        results.append(GateResult(f"beats-baseline[{c.name}]", ok,
                                   f"{wins}/{per_class} wins, mean base/learned={np.mean(margins):.2f}×"))
    return results


def summarize(results: List[GateResult]) -> bool:
    allok = all(r.ok for r in results)
    for r in results:
        print(f"  [{'PASS' if r.ok else 'FAIL'}] {r.name:28s} {r.detail}")
    print(f"  → {'ALL GATES PASS ✓' if allok else 'GATES FAILED ✗'}")
    return allok


if __name__ == "__main__":
    # Smoke: run the pre-train gates on the stratified corpus (no training needed).
    specs = sc.stratified_specs(n_per_class=1, seed0=0)
    print(f"pre-train gates over {len(sc.CLASSES)} classes:")
    ok = summarize(run_pretrain_gates(specs))
    import sys
    sys.exit(0 if ok else 1)
