#!/usr/bin/env python3
"""s4train — the SixFour H-JEPA trainer CLI.

A single stdlib-argparse front door over the trainer modules. It owns no training logic: each
subcommand forwards to the module that already implements it (so the CLI can never drift from the
gated behavior). Zero third-party deps — `argparse` is stdlib, consistent with the trainer staying
on stdlib + numpy + mlx.

    python3 trainer/mlx/cli.py <command> [flags]      # from the repo root
    python3 cli.py <command> [flags]                  # from trainer/mlx/
    ./scripts/s4train <command> [flags]               # shell shim

Commands:
    gate         run the full trainer gate (every module self-test; the CI-style check)
    train        the end-to-end MLX optimizer loop over the corpus
    floor        the byte-exact theta_B floor trainer (+ --export the deploy blob)
    corpus       train on real synth-capture octants; smoothness-proportional generalization
    cube         octree compression: a 64^3 cube -> 16^3 coarse, zero detail (+ --gif)
    cube-learn   compression vs prediction: floor nails the flat 99.5%, theta_B learns the surface
    goldens      verify the trainer reproduces the spec-emitted goldens byte-exact
    regen        regenerate the spec goldens (cabal run spec-codegen)
    autograd     MLX autodiff == the analytic gradient cross-check
    report       training-observability bundle (loss/VICReg charts + input GIF + 16/64/256 spine)

Every command exits 0 on success and nonzero on failure, so it composes in scripts and CI.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TRAINER = os.path.dirname(HERE)                 # trainer/
SPEC = os.path.abspath(os.path.join(HERE, "..", "..", "spec"))
PY = sys.executable


def _run(script: str, *args: str, cwd: str = HERE) -> int:
    """Run a trainer module as a subprocess; return its exit code."""
    return subprocess.run([PY, os.path.join(cwd, script), *args], cwd=cwd).returncode


def _all(*codes: int) -> int:
    """0 iff every step succeeded."""
    return 0 if all(c == 0 for c in codes) else 1


# --- command handlers (each forwards to the module that owns the behavior) ---

def cmd_gate(a) -> int:
    return _run("gate_trainer.py")


def cmd_train(a) -> int:
    fwd = []
    if a.smoke:
        fwd.append("--smoke")
    fwd += ["--seed", str(a.seed), "--lr", str(a.lr)]
    if a.steps is not None:
        fwd += ["--steps", str(a.steps)]
    if a.octants is not None:
        fwd += ["--octants", str(a.octants)]
    if a.mask is not None:
        fwd += ["--mask", str(a.mask)]
    if a.w_value is not None:
        fwd += ["--w-value", str(a.w_value)]
    if a.w_policy is not None:
        fwd += ["--w-policy", str(a.w_policy)]
    return _run("train_loop.py", *fwd)


def cmd_sweep(a) -> int:
    return _run("train_sweep.py")


def cmd_floor(a) -> int:
    return _run("masked_band_trainer.py", *(["--export"] if a.export else []))


def cmd_corpus(a) -> int:
    return _run("jepa_synth_octants.py")


def cmd_cube(a) -> int:
    return _run("test_centered_cube.py", *(["--gif"] if a.gif else []))


def cmd_cube_learn(a) -> int:
    return _run("test_cube_learning.py")


def cmd_goldens(a) -> int:
    # the head + temporal goldens live next to the loaders; the data golden loader is one dir up.
    return _all(
        _run("jepa_head_golden.py"),
        _run("temporal_data.py"),
        _run("jepa_data.py", cwd=TRAINER),
    )


def cmd_regen(a) -> int:
    if not os.path.isdir(SPEC):
        print(f"spec dir not found: {SPEC}", file=sys.stderr)
        return 1
    return subprocess.run(["cabal", "run", "spec-codegen"], cwd=SPEC).returncode


def cmd_autograd(a) -> int:
    return _run("autograd_check.py")


def cmd_quantize(a) -> int:
    fwd = ["--seed", str(a.seed), "--kind", a.kind, "--frame", str(a.frame), "--k", str(a.k)]
    if a.selftest:
        fwd.append("--selftest")
    return _run("frame_palette.py", *fwd)


def cmd_superres(a) -> int:
    return _run("superres.py")


def cmd_report(a) -> int:
    fwd = []
    if a.smoke:
        fwd.append("--smoke")
    fwd += ["--seed", str(a.seed)]
    if a.steps is not None:
        fwd += ["--steps", str(a.steps)]
    return _run("train_viz.py", *fwd)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="s4train",
        description="SixFour H-JEPA trainer CLI.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="examples:\n"
               "  s4train gate                 # run every module self-test\n"
               "  s4train train --smoke        # quick end-to-end loop (~9s)\n"
               "  s4train train --steps 200 --seed 3\n"
               "  s4train floor --export       # train theta_B + write the deploy blob\n"
               "  s4train cube --gif           # compression demo + GIFs\n"
               "  s4train goldens              # spec goldens reproduce byte-exact?\n",
    )
    sub = p.add_subparsers(dest="command", metavar="<command>")

    sub.add_parser("gate", help="run the full trainer gate (every module self-test)").set_defaults(fn=cmd_gate)

    t = sub.add_parser("train", help="the end-to-end MLX optimizer loop over the corpus")
    t.add_argument("--smoke", action="store_true", help="quick mode: 8 octants, 30 steps, ~9s")
    t.add_argument("--seed", type=int, default=0, help="determinism seed (default 0)")
    t.add_argument("--steps", type=int, default=None, help="override the step count")
    t.add_argument("--lr", type=float, default=8e-3, help="learning rate (default 8e-3)")
    t.add_argument("--octants", type=int, default=None,
                   help="FULL: octants to train on, strided across all captures (default 24; corpus has 1536)")
    t.add_argument("--mask", type=int, default=None,
                   help="train a per-band specialist on this encoded band (0..6); default cycles all 7")
    t.add_argument("--w-value", dest="w_value", type=float, default=None,
                   help="weight on the GIF89a palette VALUE head (0=inert/bit-identical; >0 trains it)")
    t.add_argument("--w-policy", dest="w_policy", type=float, default=None,
                   help="weight on the GIF89a discrete INDEX head (straight-through; 0=inert; >0 trains it)")
    t.set_defaults(fn=cmd_train)

    f = sub.add_parser("floor", help="the byte-exact theta_B floor trainer")
    f.add_argument("--export", action="store_true", help="write the trained 63-float deploy blob")
    f.set_defaults(fn=cmd_floor)

    sub.add_parser("corpus", help="train on real synth-capture octants (generalization)").set_defaults(fn=cmd_corpus)
    sub.add_parser("sweep", help="one specialist run per encoded band x scene kind (3x7 matrix)").set_defaults(fn=cmd_sweep)

    q = sub.add_parser("quantize", help="frame-level GIF89a palette + index learned on REAL chroma")
    q.add_argument("--seed", type=int, default=7)
    q.add_argument("--kind", type=str, default="high-lab")
    q.add_argument("--frame", type=int, default=0)
    q.add_argument("--k", type=int, default=32, help="learned palette size (real GIF K=256)")
    q.add_argument("--selftest", action="store_true", help="run the descent/raster/determinism self-test")
    q.set_defaults(fn=cmd_quantize)

    c = sub.add_parser("cube", help="octree compression sanity test (centered cube)")
    c.add_argument("--gif", action="store_true", help="also write input + coarse GIFs + montage")
    c.set_defaults(fn=cmd_cube)

    sub.add_parser("cube-learn", help="compression vs prediction division of labour").set_defaults(fn=cmd_cube_learn)
    sub.add_parser("goldens", help="verify the trainer reproduces the spec goldens byte-exact").set_defaults(fn=cmd_goldens)
    sub.add_parser("regen", help="regenerate the spec goldens (cabal run spec-codegen)").set_defaults(fn=cmd_regen)
    sub.add_parser("autograd", help="MLX autodiff == analytic gradient cross-check").set_defaults(fn=cmd_autograd)
    sub.add_parser("superres", help="up-rung super-res: invent 256³ detail (floor vs trained energy + consistency)").set_defaults(fn=cmd_superres)

    r = sub.add_parser("report", help="training-observability bundle (charts + input GIF + scale spine)")
    r.add_argument("--smoke", action="store_true", help="ONE real run + ONE lr=0 control, ~ a few seconds")
    r.add_argument("--seed", type=int, default=7, help="determinism seed (default 7, the smoke capture)")
    r.add_argument("--steps", type=int, default=None, help="override the step count")
    r.set_defaults(fn=cmd_report)
    return p


def main(argv=None) -> int:
    p = build_parser()
    a = p.parse_args(argv)
    if not getattr(a, "command", None):
        p.print_help()
        return 0
    return a.fn(a)


if __name__ == "__main__":
    raise SystemExit(main())
