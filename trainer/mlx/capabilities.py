"""Capability-scoping framework: what can THIS machine actually train?

The training loop forwards octants ONE AT A TIME in a Python loop (train_loop._composite_terms),
so each step fires B tiny GPU dispatches and the GPU sits idle (measured: ~8 ms/octant, flat in B
= dispatch-bound, not compute-bound). This module:

  1. Implements a BATCHED forward (one (B, N, d) pass instead of B separate passes) reusing the SAME
     weights, so the speedup is real, not a different model.
  2. VERIFIES the batched forward is numerically faithful to the looped one (same raws/palette), so
     scaling does not change the math.
  3. BENCHMARKS looped vs batched throughput + peak memory across batch sizes, and PROJECTS the
     wall-clock to reach a target step count.

Run:  python3 capabilities.py            (full sweep + report)
      python3 capabilities.py --quick    (small sweep)
"""
from __future__ import annotations

import argparse
import json
import os
import time

import train_loop as T          # imports mlx in the load-bearing order
import mlx.core as mx
import mlx.nn as nn


# The BATCHED forward + faithful batched composite now live in train_loop (the single source of
# truth, used by the persistent trainer). Benchmark against those exact functions.
batched_head = T.batched_head


def verify_faithful(head, tokens_b, d6):
    """Max abs difference between the batched and looped forward over the whole batch. Must be ~0
    (float32 reorder only) or the batched path is a DIFFERENT model and the speedup is a lie."""
    _, raws_b, pal_b, _ = batched_head(head, tokens_b, d6)
    mx.eval(raws_b, pal_b)
    dr = dp = 0.0
    for i in range(tokens_b.shape[0]):
        _, r, p, _ = head(tokens_b[i], d6)
        mx.eval(r, p)
        dr = max(dr, float(mx.max(mx.abs(r - raws_b[i]))))
        dp = max(dp, float(mx.max(mx.abs(p - pal_b[i]))))
    return dr, dp


def _batched_loss(head, tokens_b, mask_idx, targets, pal_targets, d6):
    """The FAITHFUL batched composite (the same one the trainer uses), so the benchmarked backward
    is the real training cost, not a proxy."""
    band, vic, pal, idx = T._composite_terms_batched(head, tokens_b, mask_idx, targets, pal_targets, d6)
    return band + T.LAMBDA_VIC * vic + 0.1 * pal + 0.1 * idx


def _timeit(fn, n, warm=2):
    for _ in range(warm):
        mx.eval(fn())
    t0 = time.perf_counter()
    for _ in range(n):
        mx.eval(fn())
    return (time.perf_counter() - t0) / n


def _peak_gb():
    for fn in ("get_peak_memory",):
        try:
            return getattr(mx, fn)() / 1e9
        except Exception:
            pass
    try:
        return mx.metal.get_peak_memory() / 1e9
    except Exception:
        return float("nan")


def _reset_peak():
    try:
        mx.reset_peak_memory()
    except Exception:
        try:
            mx.metal.reset_peak_memory()
        except Exception:
            pass


def bench(head, d6, B, n=3):
    """Looped vs batched full-step (forward+backward+update) timing + peak memory at batch B."""
    ex, _ = T.build_corpus([(0, "high-lab"), (1, "high-detail"), (2, "smooth-grey")],
                           frame_step=8, space_step=8)
    ex = (ex * ((B // len(ex)) + 1))[:B]
    tb, masks, targets, pal = T._build_batch(ex, d6)
    mask_idx = mx.array(masks, dtype=mx.int32)

    # LOOPED step (the current trainer)
    def comp_loop(h):
        b, v, p, i = T._composite_terms(h, tb, masks, targets, pal, d6)
        return b + 0.05 * v + 0.1 * p + 0.1 * i
    vg_loop = nn.value_and_grad(head, comp_loop)
    opt = T.optim.SGD(learning_rate=0.0)        # lr=0 so weights do not drift during benchmarking

    def step_loop():
        l, g = vg_loop(head)
        opt.update(head, g)
        return l

    # BATCHED step (the fix)
    def comp_batched(h):
        return _batched_loss(h, tb, mask_idx, targets, pal, d6)
    vg_batched = nn.value_and_grad(head, comp_batched)

    def step_batched():
        l, g = vg_batched(head)
        opt.update(head, g)
        return l

    _reset_peak()
    try:
        t_loop = _timeit(step_loop, n)
    except Exception as e:
        t_loop = float("nan")
    try:
        t_batched = _timeit(step_batched, n)
        peak = _peak_gb()
        ok = True
    except Exception as e:
        t_batched = float("nan")
        peak = float("nan")
        ok = False
    return {"B": B, "loop_ms": t_loop * 1e3, "batch_ms": t_batched * 1e3,
            "loop_sps": 1.0 / t_loop if t_loop == t_loop else 0.0,
            "batch_sps": (1.0 / t_batched) if (ok and t_batched == t_batched) else 0.0,
            "speedup": (t_loop / t_batched) if (ok and t_batched) else float("nan"),
            "peak_gb": peak, "ok": ok}


def main():
    ap = argparse.ArgumentParser(description="Scope this machine's training capabilities.")
    ap.add_argument("--quick", action="store_true", help="small sweep (8,64,256)")
    ap.add_argument("--targets", type=str, default="100000,500000",
                    help="comma step targets to project wall-clock for")
    args = ap.parse_args()

    built = T.large_head._build_vit()
    _mx, vit, _d, pc = built
    head = T.JepaHead(vit)
    mx.eval(head.parameters())
    d6 = mx.array(T.octant_lattice_d6(T.N_TOKENS), dtype=mx.float32)
    mx.eval(d6)

    print(f"=== SixFour training-capability scope ===")
    print(f"machine ViT: {pc/1e6:.1f}M params, N={T.N_TOKENS} tokens, d={T.D_MODEL}")

    # 1. Faithfulness: the batched forward must equal the looped forward.
    ex, _ = T.build_corpus([(0, "high-lab"), (1, "high-detail"), (2, "smooth-grey")],
                           frame_step=8, space_step=8)
    tb, _, _, _ = T._build_batch(ex[:16], d6)
    dr, dp = verify_faithful(head, tb, d6)
    print(f"\n[faithfulness] batched vs looped forward: max|Δraws|={dr:.2e}  max|Δpalette|={dp:.2e}  "
          f"({'FAITHFUL (same math)' if max(dr, dp) < 1e-3 else 'DIVERGENT -- do not trust speedup'})")

    sizes = [8, 64, 256] if args.quick else [8, 32, 96, 256, 512, 1024]
    targets = [int(t) for t in args.targets.split(",")]

    print(f"\n{'B':>5} {'loop ms':>9} {'batch ms':>9} {'speedup':>8} {'loop st/s':>10} "
          f"{'batch st/s':>11} {'peak GB':>8}")
    rows = []
    for B in sizes:
        r = bench(head, d6, B)
        rows.append(r)
        print(f"{r['B']:>5} {r['loop_ms']:>9.1f} {r['batch_ms']:>9.1f} {r['speedup']:>7.1f}x "
              f"{r['loop_sps']:>10.2f} {r['batch_sps']:>11.2f} {r['peak_gb']:>8.2f}")

    # Octant-throughput frontier (steps/s x batch = how many octant-updates/sec the machine sustains).
    okrows = [r for r in rows if r["ok"]]
    best = max(okrows, key=lambda r: r["batch_sps"] * r["B"])
    print(f"\n=== THROUGHPUT FRONTIER (octants/sec = steps/s x batch) ===")
    for r in okrows:
        print(f"  B={r['B']:>4}: looped {r['loop_sps']*r['B']:>6.0f} oct/s   "
              f"batched {r['batch_sps']*r['B']:>6.0f} oct/s   ({r['speedup']:.1f}x)   peak {r['peak_gb']:.1f} GB")
    print(f"  -> batched ceiling ~{best['batch_sps']*best['B']:.0f} octants/s at B={best['B']} "
          f"(peak {best['peak_gb']:.1f} GB); looped wastes the GPU on per-octant dispatch.")

    # Projection at a FIXED training batch (apples-to-apples looped vs batched on the SAME row).
    print(f"\n=== WALL-CLOCK TO TARGET (same batch, looped vs batched) ===")
    for r in okrows:
        if r["loop_sps"] <= 0 or r["batch_sps"] <= 0:
            continue
        for t in targets:
            hl = t / r["loop_sps"] / 3600
            hb = t / r["batch_sps"] / 3600
            print(f"  B={r['B']:>4}  {t:>7} steps:  looped {hl:7.1f} h   batched {hb:7.1f} h   "
                  f"({hl/max(hb,1e-9):.1f}x faster)")

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "capabilities.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump({"params": pc, "faithful_draws": dr, "faithful_dpal": dp, "rows": rows}, f, indent=2)
    print(f"\nreport: {out}")


if __name__ == "__main__":
    main()
