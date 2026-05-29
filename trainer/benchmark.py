"""benchmark.py — forward-latency benchmark for the SixFour look-NN.

Informs the deferred on-device inference-mechanism decision (hand-written Metal
vs Swift/Accelerate on the iPhone 17 Pro) by characterising the model's compute
profile on this Mac:

  * MLX (Apple-Silicon GPU, Metal-backed)   — proxy for a hand-written Metal path.
  * PyTorch CPU (BLAS / Accelerate-backed)  — proxy for a hand-written Swift+Accelerate path.
  * PyTorch MPS (if available)              — Metal-via-translation reference.

The model is tiny (~58K params, ~21 MFLOP/forward dominated by L3's per-token
projection), so the headline question is whether ARITHMETIC or DISPATCH OVERHEAD
dominates. These are Mac numbers, NOT iPhone numbers — they inform direction.

Usage:  .venv/bin/python benchmark.py [--tokens 16384 4096 1024 256] [--iters 50]
"""
from __future__ import annotations

import argparse
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "generated"))


def _stats(samples_ms: list) -> str:
    md = statistics.median(samples_ms)
    p10 = min(samples_ms)
    return f"median {md:8.3f} ms   best {p10:8.3f} ms"


def bench_torch(device: str, token_counts: list, iters: int) -> None:
    import torch
    import look_net_torch as m

    dev = torch.device(device)
    net = m.LookNet().to(dev).eval()
    n_params = sum(p.numel() for p in net.parameters())
    print(f"\n[torch/{device}]  params={n_params}")
    for n in token_counts:
        tok = torch.randn(1, m.MAX_TOKENS, m.GMM_TOKEN_DIM, device=dev)
        mask = torch.zeros(1, m.MAX_TOKENS, device=dev)
        mask[:, :n] = 1.0  # only n tokens "present"
        with torch.no_grad():
            for _ in range(5):  # warmup
                _ = net(tok, token_mask=mask)
            if device == "mps":
                torch.mps.synchronize()
            samples = []
            for _ in range(iters):
                t0 = time.perf_counter()
                out = net(tok, token_mask=mask)
                if device == "mps":
                    torch.mps.synchronize()
                else:
                    _ = out.sum().item()  # force materialization on CPU
                samples.append((time.perf_counter() - t0) * 1e3)
        print(f"  tokens={n:6d}   {_stats(samples)}")


def bench_mlx(token_counts: list, iters: int) -> None:
    import mlx.core as mx
    import look_net_mlx as m
    from mlx.utils import tree_flatten

    net = m.LookNet()
    mx.eval(net.parameters())
    n_params = sum(v.size for _, v in tree_flatten(net.parameters()))
    print(f"\n[mlx/gpu]  params={n_params}")
    for n in token_counts:
        tok = mx.random.normal((1, m.MAX_TOKENS, m.GMM_TOKEN_DIM))
        mask = mx.concatenate(
            [mx.ones((1, n)), mx.zeros((1, m.MAX_TOKENS - n))], axis=1
        )
        for _ in range(5):  # warmup
            mx.eval(net(tok, token_mask=mask))
        samples = []
        for _ in range(iters):
            t0 = time.perf_counter()
            out = net(tok, token_mask=mask)
            mx.eval(out)
            samples.append((time.perf_counter() - t0) * 1e3)
        print(f"  tokens={n:6d}   {_stats(samples)}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tokens", type=int, nargs="+", default=[16384, 4096, 1024, 256])
    ap.add_argument("--iters", type=int, default=50)
    args = ap.parse_args()

    print(f"SixFour look-NN forward benchmark — {args.iters} iters, batch=1")
    print("(Mac M-series numbers; proxy for the iPhone inference-path decision.)")

    try:
        bench_mlx(args.tokens, args.iters)
    except Exception as e:  # noqa: BLE001
        print(f"\n[mlx/gpu]  SKIPPED: {e}")

    try:
        bench_torch("cpu", args.tokens, args.iters)
    except Exception as e:  # noqa: BLE001
        print(f"\n[torch/cpu]  SKIPPED: {e}")

    try:
        import torch
        if torch.backends.mps.is_available():
            bench_torch("mps", args.tokens, args.iters)
        else:
            print("\n[torch/mps]  SKIPPED: MPS not available")
    except Exception as e:  # noqa: BLE001
        print(f"\n[torch/mps]  SKIPPED: {e}")


if __name__ == "__main__":
    main()
