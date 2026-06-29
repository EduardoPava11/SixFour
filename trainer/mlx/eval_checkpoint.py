"""Offline verdict for a persistent-training checkpoint — the live dashboard is hidden in buffered
stdout, so this loads head.safetensors and prints the held-out verdict + margins on demand.

Usage:  python3 mlx/eval_checkpoint.py [--ckpt out/scene5h/head.safetensors]
                                       [--kinds scene-gradient,scene-blob,scene-edge,scene-waves,scene-mixed]
                                       [--seed 0] [--octants 96]

The PRIMARY number is the cell margin (mean field, saturates fast). The FRONTIER is the `detail` margin
(within-octant super-res invention) — watch it climb toward and past 0% over a long run on the scene corpus.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mlx.core as mx
import numpy as np

import large_head
from large_head import N_TOKENS, octant_lattice_d6
import train_loop as T


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", default="out/scene5h/head.safetensors")
    ap.add_argument("--kinds", default="scene-gradient,scene-blob,scene-edge,scene-waves,scene-mixed")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--octants", type=int, default=96)
    a = ap.parse_args()
    kinds = [k.strip() for k in a.kinds.split(",") if k.strip()]

    step = "?"
    meta = a.ckpt + ".meta.json"
    if os.path.exists(meta):
        import json
        step = json.load(open(meta)).get("step", "?")

    d6 = mx.array(octant_lattice_d6(N_TOKENS), dtype=mx.float32); mx.eval(d6)
    mx.random.seed(a.seed); np.random.seed(a.seed)
    _mx, vit, _d, _p = large_head._build_vit()
    head = T.JepaHead(vit)
    head.readout.weight = head.readout.weight * 0.3
    head.readout.bias = head.readout.bias + 0.4
    mx.eval(head.parameters())
    head.load_weights(a.ckpt)
    mx.eval(head.parameters())

    args = argparse.Namespace(seed=a.seed, mask=None)
    held_ex = T._heldout_corpus(args, kinds, a.octants)
    h_tb, h_masks, h_tg, h_pl = T._build_batch(held_ex, d6)
    held = (h_tb, mx.array(h_masks, dtype=mx.int32), h_tg, h_pl)
    ev = T._held_eval(head, held, d6, 1.0, 0.1)
    fl = T._floor_baseline(held)
    verdict, _vm, _bm, collapsed, maxvic = T.dashboard_verdict(ev, fl)

    def pct(f, h):
        return (f - h) / f * 100 if f > 0 else 0.0

    print(f"=== checkpoint eval :: step {step} :: {len(held_ex)} held-out octants ({','.join(kinds)}) ===")
    print(f"  VERDICT: {verdict}")
    print(f"  cell   held {ev['cell']:.6f}  floor {fl['cell']:.6f}   margin {pct(fl['cell'], ev['cell']):+.1f}%   (PRIMARY: mean field)")
    print(f"  detail held {ev['detail']:.6f}  floor {fl['detail']:.6f}   margin {pct(fl['detail'], ev['detail']):+.1f}%   (FRONTIER: within-octant detail)")
    print(f"  value  held {ev['pal']:.6f}  floor {fl['value']:.6f}   margin {pct(fl['value'], ev['pal']):+.1f}%   (colour reconstruction)")
    print(f"  band   held {ev['band']:.6f}  floor {fl['band']:.6f}   margin {pct(fl['band'], ev['band']):+.1f}%   (diagnostic)")
    print(f"  collapse-guard(VICReg) {ev['vic']:.4f} / {maxvic:.1f}  [{'ok' if not collapsed else 'TRIPPED'}]")


if __name__ == "__main__":
    main()
