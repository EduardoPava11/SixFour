"""check_golden.py — the look-NN forward correctness gate.

Loads trainer/generated/look_net_golden.json (emitted by the Haskell spec via
Codegen.Golden), decodes the IEEE-754 hex weights/inputs BIT-EXACTLY, loads them
into BOTH the MLX (primary) and PyTorch (dormant fallback) LookNet models, runs
each golden case, and asserts every output matches the Haskell oracle within the
JSON's `meta.tolerance` (1e-6). Cross-language matmul summation order differs at
the ULP level, so the gate is a tolerance, not bit-equality — but the WEIGHTS and
INPUTS are transported bit-exact (hex), so any mismatch is a real forward bug.

Run:  .venv/bin/python check_golden.py
Exit 0 iff both backends reproduce all cases; non-zero otherwise.
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np

GOLDEN = Path(__file__).parent / "generated" / "look_net_golden.json"
sys.path.insert(0, str(Path(__file__).parent / "generated"))


def h2d(s: str) -> float:
    """16-hex-digit IEEE-754 bit pattern -> float64 (bit-exact, no decimal parse)."""
    return struct.unpack(">d", int(s, 16).to_bytes(8, "big"))[0]


def tensor(obj: dict) -> np.ndarray:
    """{'shape':[...], 'hex':[...]} -> float64 ndarray of that shape."""
    flat = np.array([h2d(s) for s in obj["hex"]], dtype=np.float64)
    return flat.reshape(obj["shape"])


def load_golden() -> dict:
    g = json.loads(GOLDEN.read_text())
    W = g["weights"]
    weights = {
        "phi": tensor(W["phi"]),                 # (64,10)
        "w1": tensor(W["w1"]),                   # (64,64)
        "w2": tensor(W["w2"]),                   # (64,64)
        "halt_w": tensor(W["halt_w"]),           # (1,2)
        "halt_b": tensor(W["halt_b"]),           # (1,)
        "heads": [tensor(h) for h in W["heads"]],  # 8 × (d,64)
    }
    cases = [
        {
            "name": c["name"],
            "tokens": tensor(c["tokens"]),                       # (n,10)
            "output": np.array([h2d(s) for s in c["output"]]),   # (384,)
            # loss reference (emitted by Codegen.Golden); absent in older goldens.
            "input_gmm_mean": np.array([h2d(s) for s in c["input_gmm_mean"]])
                              if "input_gmm_mean" in c else None,
            "input_gmm_cov": np.array([h2d(s) for s in c["input_gmm_cov"]])
                             if "input_gmm_cov" in c else None,
            "halts": [h2d(s) for s in c["halts"]] if "halts" in c else None,
            "loss": {k: h2d(v) for k, v in c["loss"].items()}
                    if "loss" in c else None,
        }
        for c in g["cases"]
    ]
    return {"meta": g["meta"], "weights": weights, "cases": cases}


def pad_tokens(tokens: np.ndarray, max_tokens: int):
    n = tokens.shape[0]
    padded = np.zeros((1, max_tokens, tokens.shape[1]), dtype=np.float32)
    padded[0, :n, :] = tokens
    mask = np.zeros((1, max_tokens), dtype=np.float32)
    mask[0, :n] = 1.0
    return padded, mask


# ---------------------------------------------------------------------------
# torch backend
# ---------------------------------------------------------------------------
def run_torch(weights: dict, cases: list) -> list:
    import torch
    import look_net_torch as m

    net = m.LookNet().eval()
    with torch.no_grad():
        net.encoder.phi.weight.copy_(torch.tensor(weights["phi"], dtype=torch.float32))
        net.recursion.g.w1.weight.copy_(torch.tensor(weights["w1"], dtype=torch.float32))
        net.recursion.g.w2.weight.copy_(torch.tensor(weights["w2"], dtype=torch.float32))
        net.recursion.g.halt_mlp.weight.copy_(torch.tensor(weights["halt_w"], dtype=torch.float32))
        net.recursion.g.halt_mlp.bias.copy_(torch.tensor(weights["halt_b"], dtype=torch.float32))
        for k, hw in enumerate(weights["heads"]):
            net.decoder.heads[k].weight.copy_(torch.tensor(hw, dtype=torch.float32))

        diffs = []
        for c in cases:
            tok, mask = pad_tokens(c["tokens"], m.MAX_TOKENS)
            out = net(torch.tensor(tok), token_mask=torch.tensor(mask)).numpy().reshape(-1)
            # non-finite guard: an all-NaN/Inf forward must FAIL, not slip the gate
            # (np.max of a NaN array yields NaN, and `NaN <= tol` is False, so the
            # gate would silently pass — surface it explicitly as +inf instead).
            if not np.all(np.isfinite(out)):
                diffs.append((c["name"] + ":nonfinite", float("inf")))
                continue
            diffs.append((c["name"], float(np.max(np.abs(out - c["output"])))))
    return diffs


# ---------------------------------------------------------------------------
# mlx backend
# ---------------------------------------------------------------------------
def run_mlx(weights: dict, cases: list) -> list:
    import mlx.core as mx
    import look_net_mlx as m

    net = m.LookNet()
    net.encoder.phi.weight = mx.array(weights["phi"].astype(np.float32))
    net.recursion.g.w1.weight = mx.array(weights["w1"].astype(np.float32))
    net.recursion.g.w2.weight = mx.array(weights["w2"].astype(np.float32))
    net.recursion.g.halt_mlp.weight = mx.array(weights["halt_w"].astype(np.float32))
    net.recursion.g.halt_mlp.bias = mx.array(weights["halt_b"].astype(np.float32))
    for k, hw in enumerate(weights["heads"]):
        net.decoder.heads[k].weight = mx.array(hw.astype(np.float32))
    mx.eval(net.parameters())

    diffs = []
    for c in cases:
        tok, mask = pad_tokens(c["tokens"], m.MAX_TOKENS)
        out = net(mx.array(tok), token_mask=mx.array(mask))
        mx.eval(out)
        out = np.array(out).reshape(-1)
        # non-finite guard (see run_torch): all-NaN/Inf forward must FAIL fast.
        if not np.all(np.isfinite(out)):
            diffs.append((c["name"] + ":nonfinite", float("inf")))
            continue
        diffs.append((c["name"], float(np.max(np.abs(out - c["output"])))))
    return diffs


# ---------------------------------------------------------------------------
# mlx loss gate — verifies look_net_loss_mlx (the Spec.Loss port) against the
# loss reference cases emitted by Codegen.Golden. Each case's forward OUTPUT
# (the 384 SigmaPairTree coeffs) is fed to the MLX loss with the case's input
# GMM moments; the three component losses + total must match the Haskell oracle.
# ---------------------------------------------------------------------------
def run_mlx_loss(cases: list) -> list:
    import mlx.core as mx
    import look_net_loss_mlx as loss

    diffs = []
    for c in cases:
        if c.get("loss") is None:
            continue
        # high_precision: float64-CPU reduction so the loss gate holds the same
        # 1e-6 contract as the forward gate. The beauty sum reaches magnitude ~127,
        # where float32 ULP (~7.6e-6) alone exceeds 1e-6; float64 matches the
        # Haskell Spec.Loss oracle to ~1e-14. (Training uses float32-GPU.)
        coeffs = mx.array(c["output"])            # float64 (decoded from hex)
        mean = mx.array(c["input_gmm_mean"])
        cov = mx.array(c["input_gmm_cov"])
        total, parts = loss.look_net_loss(coeffs, mean, cov, high_precision=True)
        mx.eval(total, *parts.values())
        # non-finite guard: an all-NaN loss must NOT silently pass the gate.
        vals = {k: float(np.array(v)) for k, v in parts.items()}
        if not all(np.isfinite(list(vals.values()))):
            diffs.append((c["name"] + ":nonfinite", float("inf")))
            continue
        worst = max(abs(vals[k] - c["loss"][k]) for k in ("fidelity", "coverage", "beauty", "total"))
        # PonderNet halting loss — mirrors Spec.Loss.haltingLoss over the per-level
        # halt λ's (the "halts" field), KL to the geometric prior. Verified here
        # so the trained-λ_ℓ regulariser stays bit-faithful to the spec.
        if c.get("halts") is not None and "halting" in c["loss"]:
            h_mlx = loss.halting_loss(c["halts"])
            if not np.isfinite(h_mlx):
                diffs.append((c["name"] + ":halting-nonfinite", float("inf")))
                continue
            worst = max(worst, abs(h_mlx - c["loss"]["halting"]))
        diffs.append((c["name"], worst))
    return diffs


def report(label: str, diffs: list, tol: float) -> bool:
    ok = True
    for name, d in diffs:
        status = "OK " if d <= tol else "FAIL"
        if d > tol:
            ok = False
        print(f"  [{label}] case {name:8s}  max|Δ| = {d:.3e}   {status} (tol {tol:.0e})")
    return ok


def main() -> None:
    g = load_golden()
    tol = float(g["meta"]["tolerance"])
    print(f"look-NN golden gate — {len(g['cases'])} cases, tolerance {tol:.0e}")
    print(f"weights/inputs transported bit-exact (IEEE-754 hex); outputs gated within tolerance.\n")

    ok = True
    for label, runner in (("mlx", run_mlx), ("torch", run_torch)):
        try:
            ok &= report(label, runner(g["weights"], g["cases"]), tol)
        except Exception as e:  # noqa: BLE001
            print(f"  [{label}] SKIPPED/ERROR: {e}")
            ok = False

    # loss gate: the MLX Spec.Loss port reproduces the loss reference cases.
    if any(c.get("loss") is not None for c in g["cases"]):
        print(f"\nlook-NN LOSS gate — Spec.Loss (fidelity Bures-W + coverage + Ou-Luo beauty), tol {tol:.0e}")
        try:
            ok &= report("mlx-loss", run_mlx_loss(g["cases"]), tol)
        except Exception as e:  # noqa: BLE001
            print(f"  [mlx-loss] SKIPPED/ERROR: {e}")
            ok = False

    # Sanity: corrupting one weight must make the gate FAIL (prove it bites).
    print("\nsanity: corrupting w1[0,0] by +1.0 must FAIL the gate...")
    g["weights"]["w1"][0, 0] += 1.0
    corrupt = run_torch(g["weights"], g["cases"])
    bites = any(d > tol for _, d in corrupt)
    print(f"  corrupted max|Δ| = {max(d for _, d in corrupt):.3e}  ->  {'gate BITES ✓' if bites else 'gate did NOT bite ✗'}")
    ok &= bites

    print("\n" + ("ALL GOLDEN CHECKS PASSED ✓" if ok else "GOLDEN CHECKS FAILED ✗"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
