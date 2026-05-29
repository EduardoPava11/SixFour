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
        "heads": [tensor(h) for h in W["heads"]],  # 9 × (d,64)
    }
    cases = [
        {
            "name": c["name"],
            "tokens": tensor(c["tokens"]),                       # (n,10)
            "output": np.array([h2d(s) for s in c["output"]]),   # (768,)
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
        diffs.append((c["name"], float(np.max(np.abs(out - c["output"])))))
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
