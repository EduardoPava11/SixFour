"""regimen.py — the nucleus L-NN TRAINING REGIMEN (run this on a MacBook M1).

We do NOT train for production here; this is the reproducible protocol you `git pull`
and run on an M1. One command: build the classified synthetic corpus → run the
PRE-TRAIN gates → train the L-NN → run the POST-TRAIN per-class quality gate → export
the deploy blob. The run is ACCEPTED only if all gates pass.

    cd trainer && uv run python regimen.py            # full regimen
    cd trainer && uv run python regimen.py --smoke     # fast structure check (few steps)

Stages:
  0. Native dylib build (zig build) is the caller's responsibility / auto by zig_native.
  1. PRE-TRAIN gates  (gates.run_pretrain_gates)  — data + pipeline correctness.
  2. TRAIN            (train_look_net_mlx.train)  — ε-annealed GAN + halting, stratified corpus.
  3. QUALITY gate     (gates.gate_beats_baseline) — beats the 256-barycenter on EVERY class.
  4. EXPORT           → out/look_net_trained.s4ln  (loads via the Zig s4_load_look_net).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from types import SimpleNamespace

import gates
import synth_classes as sc
import train_look_net_mlx as T


def train_args(smoke: bool) -> SimpleNamespace:
    # The regimen's pinned hyper-parameters (the protocol, not ad-hoc flags).
    if smoke:
        return SimpleNamespace(steps=24, per_class=1, frames_per_step=4, glr=1e-3, dlr=4e-4,
                               eps_start=2e-2, eps_end=1.5e-4, lam_adv=1.0, lam_recon=200.0,
                               lam_bures=5.0, lam_halt=0.02, lam_p=0.2, log_every=12)
    return SimpleNamespace(steps=1400, per_class=7, frames_per_step=8, glr=1e-3, dlr=4e-4,
                           eps_start=2e-2, eps_end=1.5e-4, lam_adv=1.0, lam_recon=200.0,
                           lam_bures=5.0, lam_halt=0.02, lam_p=0.2, log_every=200)


def main():
    ap = argparse.ArgumentParser(description="SixFour nucleus L-NN training regimen (M1)")
    ap.add_argument("--smoke", action="store_true", help="fast structure check (few steps; quality gate may not pass)")
    args = ap.parse_args()
    out_dir = Path(__file__).resolve().parent / "out"
    out_dir.mkdir(parents=True, exist_ok=True)

    print("══ Stage 1: PRE-TRAIN gates (data + pipeline correctness) ══")
    specs = sc.stratified_specs(n_per_class=1, seed0=0)
    if not gates.summarize(gates.run_pretrain_gates(specs)):
        print("REGIMEN ABORTED: pre-train gates failed (fix data/pipeline before training).")
        sys.exit(1)

    print("\n══ Stage 2: TRAIN (ε-annealed GAN + halting, stratified classified corpus) ══")
    gen = T.train(train_args(args.smoke))

    print("\n══ Stage 3: QUALITY gate (per-class beats-256-barycenter, held-out) ══")
    per_class = 2 if args.smoke else 4
    quality = gates.gate_beats_baseline(lambda b: T.palette_of(gen, b),
                                        per_class=per_class, frac=0.75)
    quality_ok = gates.summarize(quality)

    print("\n══ Stage 4: EXPORT deploy blob ══")
    nbytes = T.export_blob(gen, out_dir / "look_net_trained.s4ln")
    print(f"  wrote out/look_net_trained.s4ln ({nbytes} bytes) — loads via Zig s4_load_look_net")

    if args.smoke:
        print("\nSMOKE complete (structure verified; run without --smoke on an M1 for the real quality gate).")
        sys.exit(0)
    print(f"\nREGIMEN {'ACCEPTED ✓' if quality_ok else 'REJECTED ✗ (quality gate failed — do not ship these weights)'}")
    sys.exit(0 if quality_ok else 2)


if __name__ == "__main__":
    main()
