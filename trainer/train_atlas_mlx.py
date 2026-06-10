"""train_atlas_mlx.py — Color Atlas policy + value smoke trainer (MLX).

The cold-start trainer prototype per docs/COLOR-ATLAS.md §5 (T1/T2 analogue,
no human data):

  • POLICY head — cross-entropy (KL) to the deterministic oracle's top-8
    one-step-lookahead distribution over the 1,524-move vocab (expert
    iteration target stand-in; atlas_synth.policy_target).
  • VALUE head — Bradley-Terry pairwise loss on synthetic Compare moves
    (winner = higher shaped coverage value) + a 0.3·MSE anchor to the
    deterministic shapedReward (the T3 recipe's anchor term).
  • σ-equivariance gate — |V(s) − V(σs)| and the policy row-swap residual
    are checked after training (belt-and-suspenders; the architecture is
    mask-algebraic, so these should be ~0).

Smoke run (<2 min on an Apple-Silicon Mac, prints decreasing loss, saves
weights next to out/look_net_trained.s4ln):

    cd ~/SixFour/trainer && uv run python train_atlas_mlx.py

Weights land in out/atlas_net_trained.npz (raw pre-σ-mask, the .s4ln v2
payload-to-be; blob export is the Phase-F export_look_net_blob extension).
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
import numpy as np
from mlx.utils import tree_flatten

import atlas_net_mlx as an
import atlas_synth as asy


# ── corpus: synthetic curation sessions → padded training tensors ──────────
def build_corpus(n_boards: int, genomes_per_board: int, seed: int):
    """Returns padded (tokens, weights, genomes, policy targets, value labels)
    plus Compare pair indices (winner, loser) within each board."""
    rng = np.random.default_rng(seed)
    toks, gens, ptgts, vlabs, owners = [], [], [], [], []
    for b in range(n_boards):
        sess = asy.sample_session(seed * 1000 + b)
        g0 = asy.maximin_collapse(sess)                       # maximin root
        cands = [g0] + [asy.codebook_walk(g0, rng, n_moves=int(rng.integers(4, 24)))
                        for _ in range(genomes_per_board - 1)]
        for g in cands:
            toks.append(asy.tokens_of(sess.board, g))
            gens.append(g.astype(np.float32))
            la = asy.lookahead_values(sess.board, g)
            ptgts.append(asy.policy_target(la))
            vlabs.append(asy.shaped_value(sess.board, g))
            owners.append(b)
    # pad tokens to the corpus max T (weights col 9 is zero on padding)
    tmax = max(t.shape[0] for t in toks)
    n = len(toks)
    tokens = np.zeros((n, tmax, asy.ATLAS_TOKEN_DIM), dtype=np.float32)
    for i, t in enumerate(toks):
        tokens[i, : t.shape[0]] = t
    weights = tokens[:, :, 9].copy()
    # Compare pairs: all intra-board pairs, winner = higher shaped value
    owners = np.array(owners)
    vlabs = np.array(vlabs, dtype=np.float32)
    wi, li = [], []
    for b in range(n_boards):
        idx = np.flatnonzero(owners == b)
        for i in idx:
            for j in idx:
                if i < j and abs(vlabs[i] - vlabs[j]) > 1e-6:
                    w, l = (i, j) if vlabs[i] > vlabs[j] else (j, i)
                    wi.append(w)
                    li.append(l)
    return (mx.array(tokens), mx.array(weights),
            mx.array(np.stack(gens)), mx.array(np.stack(ptgts)),
            mx.array(vlabs), mx.array(np.array(wi)), mx.array(np.array(li)))


# ── losses ──────────────────────────────────────────────────────────────────
def loss_fn(model, tokens, weights, genomes, ptgt, vlab, wi, li, lam_mse):
    logits, v = model(tokens, weights, genomes)
    logp = logits - mx.logsumexp(logits, axis=1, keepdims=True)
    pol = -mx.mean(mx.sum(ptgt * logp, axis=1))               # CE to oracle dist
    bt = -mx.mean(nn.log_sigmoid(mx.take(v, wi) - mx.take(v, li)))  # Bradley-Terry
    mse = mx.mean((v - vlab) ** 2)                            # shapedReward anchor
    return pol + bt + lam_mse * mse, (pol, bt, mse)


# ── σ-equivariance gate (doc §4.2: trainer-side tripwire, not the guarantee) ─
def sigma_gate(model, tokens, weights, genomes):
    """σ on the inputs: negate token chroma dims (1,2,4,5; ext cols invariant)
    and negate the genome's (a,b) coeffs. Check V(σs)=V(s) and the delta-head
    row swap π_{2i+1}(s) = π_{2i}(σs) (node logits σ-invariant)."""
    tok_sign = np.ones(asy.ATLAS_TOKEN_DIM, dtype=np.float32)
    tok_sign[[1, 2, 4, 5]] = -1.0
    gen_sign = np.array([1.0 if not m else -1.0 for m in an.ln.SIGMA_DECODER_MASK],
                        dtype=np.float32)
    s_tok, s_gen = tokens * mx.array(tok_sign), genomes * mx.array(gen_sign)
    ctx, s_ctx = model.fuse(tokens, weights, genomes), model.fuse(s_tok, weights, s_gen)
    dv = float(mx.max(mx.abs(model.value(ctx) - model.value(s_ctx))))
    d, sd = model.delta_head(ctx), model.delta_head(s_ctx)
    swap = np.array(sd).reshape(-1, 6, 2)[:, :, ::-1].reshape(-1, 12)
    dpi = float(np.max(np.abs(np.array(d) - swap)))
    return dv, dpi


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boards", type=int, default=16)
    ap.add_argument("--genomes-per-board", type=int, default=6)
    ap.add_argument("--steps", type=int, default=400)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--lam-mse", type=float, default=0.3)   # T3 anchor weight
    ap.add_argument("--seed", type=int, default=64)
    ap.add_argument("--log-every", type=int, default=20)
    args = ap.parse_args()

    t0 = time.time()
    mx.random.seed(args.seed)
    print(f"building synthetic curation corpus: {args.boards} boards × "
          f"{args.genomes_per_board} genomes …")
    tokens, weights, genomes, ptgt, vlab, wi, li = build_corpus(
        args.boards, args.genomes_per_board, args.seed)
    n, tmax = tokens.shape[0], tokens.shape[1]
    print(f"corpus: {n} (board, genome) examples, T={tmax} tokens, "
          f"{wi.shape[0]} Compare pairs  [{time.time() - t0:.1f}s]")

    model = an.AtlasNet()
    opt = optim.Adam(learning_rate=args.lr)
    vg = nn.value_and_grad(model, loss_fn)

    first = last = None
    for step in range(args.steps):
        (total, parts), grads = vg(model, tokens, weights, genomes,
                                   ptgt, vlab, wi, li, args.lam_mse)
        grads, _ = optim.clip_grad_norm(grads, 1.0)
        opt.update(model, grads)
        mx.eval(model.parameters(), opt.state)
        if step == 0:
            first = float(total)
        last = float(total)
        if step % args.log_every == 0 or step == args.steps - 1:
            pol, bt, mse = (float(p) for p in parts)
            print(f"step {step:>4d}  loss={float(total):.4f}  "
                  f"[policy={pol:.4f} bt={bt:.4f} mse={mse:.5f}]")

    dv, dpi = sigma_gate(model, tokens, weights, genomes)
    gate = "OK" if dv < 1e-4 and dpi < 1e-3 else "FAIL"
    print(f"σ-gate: |V(s)−V(σs)|={dv:.2e}  row-swap residual={dpi:.2e}  [{gate}]")

    out = Path(__file__).resolve().parent / "out" / "atlas_net_trained.npz"
    out.parent.mkdir(parents=True, exist_ok=True)
    flat = {k: np.array(v) for k, v in tree_flatten(model.parameters())}
    np.savez(out, **flat)
    n_params = sum(int(np.prod(v.shape)) for v in flat.values())
    trend = "DECREASING ✓" if last < first else "NOT decreasing ✗"
    print(f"\nloss {first:.4f} → {last:.4f}  ({trend})")
    print(f"saved {len(flat)} tensors / {n_params} stored params → {out}")
    print(f"total wall time: {time.time() - t0:.1f}s")
    if last >= first:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
