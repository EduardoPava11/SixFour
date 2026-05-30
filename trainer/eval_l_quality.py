"""eval_l_quality.py — reload the trained L-NN blob and evaluate held-out quality
across several unseen captures vs the 256- and 128-level barycenter baselines.
Confirms the 'beats baseline' result generalizes (not single-seed noise)."""
from __future__ import annotations
import sys
from pathlib import Path

import mlx.core as mx
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent / "generated"))
import look_net_mlx as ln
import zig_native as zn
import global_palette as gp
import export_look_net_blob as blob
import train_look_net_mlx as T


def load_gen(path: Path) -> ln.LookNet:
    w = blob.read_blob(path)                       # name -> float32 ndarray
    g = ln.LookNet()
    g.encoder.phi.weight = mx.array(w["phi"])
    g.recursion.g.w1.weight = mx.array(w["w1"])
    g.recursion.g.w2.weight = mx.array(w["w2"])
    g.recursion.g.halt_mlp.weight = mx.array(w["halt_w"])
    g.recursion.g.halt_mlp.bias = mx.array(w["halt_b"].reshape(-1))
    for i in range(8):
        g.decoder.heads[i].weight = mx.array(w[f"head{i}"])
    mx.eval(g.parameters())
    return g


def main():
    gen = load_gen(Path(__file__).resolve().parent / "out" / "look_net_trained.s4ln")
    seeds = [999, 1000, 1001, 1002, 1003, 1234]
    wins = 0
    print(f"{'seed':>6} {'learned':>12} {'base256':>12} {'base128':>12}  verdict")
    for s in seeds:
        b = zn.synth_sample(seed=s, mode=zn.SYNTH_COLOR)
        pooled = zn.gif_to_tokens(b.gif).astype(np.float32)
        tokens = mx.array(pooled[None]); mask = mx.array(pooled[None, :, 9])
        pal_L, _, _ = T.generate_palette(gen, tokens, mask)
        pal = np.sort(np.clip(np.array(pal_L), 0.0, 1.0))
        learned = gp.oklab_mse(b, pal)
        b256 = gp.oklab_mse(b, gp.wasserstein_l_barycenter(b, k=256))
        b128 = gp.oklab_mse(b, gp.wasserstein_l_barycenter(b, k=128))
        win = learned < b256
        wins += win
        print(f"{s:>6} {learned:>12.3e} {b256:>12.3e} {b128:>12.3e}  {'✓ beats 256' if win else '✗'}")
    print(f"\nbeat the 256-level barycenter on {wins}/{len(seeds)} held-out captures")


if __name__ == "__main__":
    main()
