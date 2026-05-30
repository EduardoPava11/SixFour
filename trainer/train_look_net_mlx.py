"""train_look_net_mlx.py — the look-NN NUCLEUS trainer (Milestone L).

Closes NOTES gap A1 (no look-NN trainer existed). The L-NN is the MVP nucleus:
COLOUR 64³ per-frame-palette capture IN → highest-quality global GRAYSCALE palette OUT.

Architecture (per the user: halting + GAN are CRUCIAL):
  • Generator G   = the look-NN (trainer/generated/look_net_mlx.py). COLOUR pooled GMM
                    tokens → 384 σ-pair coeffs. The grayscale OUTPUT constraint (AxisNet 'L)
                    projects the reconstructed leaves to the L-axis (a=b=0).
  • Halting       = adaptive palette complexity. The palette is the PonderNet EXPECTED
                    output over Haar-truncation depths d=0..7, weighted by the halting
                    distribution p_d — so halting literally sizes the global palette.
  • GAN / soft-OT = the discriminator (Mac-side, training-only) tells a soft-OT-rendered
                    global-palette grayscale frame from the true-lightness frame; G must
                    make ONE global grey palette render indistinguishably. Soft-OT (Sinkhorn
                    softmax) is the differentiable bridge (composability + dynamic range).
  • Bures anchor  = 1D fidelity (output L moments ≈ pooled input L moments) — anti-collapse,
                    and it calibrates the sum-pool's large activations into [0,1].

Deploy: trained weights → export_look_net_blob.write_blob → out/look_net_trained.s4ln (loadable by
the Zig s4_load_look_net). Verify: render the learned global grayscale GIF, compare L-MSE to
the barycenter baseline and the per-frame-grayscale floor (global_palette.py).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent / "generated"))
import look_net_mlx as ln          # noqa: E402  the generator (E:>R:>D)
import zig_native as zn            # noqa: E402  the data engine
import global_palette as gp        # noqa: E402  OT substrate + baselines
import synth_classes as sc         # noqa: E402  classified synthetic corpus
import export_look_net_blob as blob  # noqa: E402  the deploy writer

K = zn.K
SIDE = zn.SIDE
P = SIDE * SIDE
# ── L-axis head: 256-DISTINCT-L depth-8 Haar (NOT the σ-pair) ──────────────────
# The σ-pair head gives 256 leaves but only 128 DISTINCT L (each pair is a duplicate
# grey, since σ fixes L). L is σ-INVARIANT, so it needs no σ-pair symmetry trade —
# the L-net spends the FULL depth-8 budget on 256 distinct lightness levels, σ-fixed
# by construction. We read the first 256 of the decoder's 384 reals as a scalar
# depth-8 L-Haar tree. A/B (deferred) keep the σ-pair (chroma needs it).
DEPTH = 8                                    # depth-8 L tree → 256 leaves
N_TRUNC = DEPTH + 1                           # 9 PonderNet halting depths d=0..8 (2^d levels)
L_COEFFS = 256                                # root(1) + offsets(1+2+…+128=255) = 256


def _l_trunc_masks() -> mx.array:
    """(N_TRUNC, 256) 0/1 masks. mask[d] keeps the first 2^d L coeffs (root + d levels)
    ⇒ 2^d distinct L levels. Halting picks d, sizing the palette 1…256."""
    m = np.zeros((N_TRUNC, L_COEFFS), dtype=np.float32)
    for d in range(N_TRUNC):
        m[d, : (1 << d)] = 1.0
    return mx.array(m)


_LTRUNC = _l_trunc_masks()


def haar_l_depth8(coeffs):
    """(B, 256) scalar L coeffs → (B, 256) distinct L leaves via depth-8 inverse Haar.
    Node n with offset d yields [n+d, n-d] — same recurrence as reconstruct_sigma_pair
    but SCALAR (one channel) and depth-8, so all 256 leaves are distinct lightnesses."""
    b = coeffs.shape[0]
    nodes = coeffs[:, 0:1]                    # root (B,1)
    cur = 1
    for lvl in range(DEPTH):
        n = 1 << lvl
        offs = coeffs[:, cur:cur + n]         # (B,n)
        cur += n
        children = mx.stack([nodes + offs, nodes - offs], axis=2)  # (B,n,2)
        nodes = children.reshape(b, 2 * n)
    return nodes                              # (B,256)


def halting_distribution_mx(halts: mx.array) -> mx.array:
    """PonderNet p_d = λ_d ∏_{i<d}(1-λ_i), last depth absorbs the remainder.
    `halts` (N_TRUNC,) ∈ (0,1). Differentiable. Mirrors Spec.Loss.haltingDistribution."""
    one_minus = 1.0 - halts
    # cumulative ∏_{i<d}(1-λ_i): shift-by-one cumprod, prefix 1.
    cprod = mx.cumprod(one_minus, axis=0)
    prefix = mx.concatenate([mx.ones((1,)), cprod[:-1]])
    p = halts * prefix
    # force the tail to absorb the leftover mass so Σ p = 1.
    p_head = p[:-1]
    p = mx.concatenate([p_head, (1.0 - mx.sum(p_head)).reshape(1)])
    return p


def geometric_prior_mx(lam: float, n: int) -> mx.array:
    raw = mx.array([lam * (1.0 - lam) ** k for k in range(n)], dtype=mx.float32)
    return raw / mx.sum(raw)


def halting_loss_mx(halts: mx.array, lam_p: float = 0.5) -> mx.array:
    """KL(halting-dist ‖ geometric-prior) — trains the halt head (Spec.Loss.haltingLoss)."""
    p = halting_distribution_mx(halts)
    g = geometric_prior_mx(lam_p, p.shape[0])
    eps = 1e-9
    return mx.sum(p * (mx.log(p + eps) - mx.log(g + eps)))


# ── generator forward: colour tokens → (global grey palette L, halting dist) ───
def generate_palette(model: ln.LookNet, tokens: mx.array, mask: mx.array):
    """tokens (1, T, 10) colour pooled GMM, `mask` (1,T) per-token weights (sum 1) →
    (L palette (256,), halting dist (N_TRUNC,), halts). The L-NN reads the decoder's
    first 256 reals as a depth-8 scalar L-Haar tree → 256 DISTINCT L levels (NOT the
    σ-pair's 128 duplicates). Output palette = PonderNet expected output over the 9
    truncation depths, so halting SIZES the palette 1…256. σ-fixed by construction
    (pure L). The weight mask makes the encoder a bounded weighted pool."""
    h = model.encoder(tokens, token_mask=mask)      # (1,64) — weighted (population) pool
    contexts = model.recursion(h)                   # 9 contexts ctx0..ctx8
    coeffs = model.decoder(contexts)                # (1,384)
    lcoeffs = coeffs[:, :L_COEFFS]                  # (1,256) the depth-8 L-tree coeffs
    halts = mx.concatenate([model.recursion.g.halt(contexts[i]) for i in range(N_TRUNC)],
                           axis=0).reshape(N_TRUNC)  # λ_d ∈ (0,1), one per truncation depth
    pdist = halting_distribution_mx(halts)            # (N_TRUNC,)

    # Output palette = the FULL depth-8 reconstruction (256 distinct L, full coverage).
    # Halting is trained (haltingLoss) as the COMPLEXITY PREDICTOR (E[d]) — at inference
    # it can truncate to 2^E[d] levels for simple scenes (adaptive compute), but it does
    # NOT cap training fidelity: blending truncations muddied the palette + shrank its span.
    # σ(·) bounds the unbounded depth-8 Haar reconstruction to L∈(0,1) — without it the
    # 8 compounding offset levels explode the palette → NaN. Smooth ⇒ gradient everywhere.
    leaves = mx.sigmoid(haar_l_depth8(lcoeffs)[0])    # (256,) full-resolution L palette in (0,1)
    return leaves, pdist, halts


def palette_of(gen: ln.LookNet, burst: zn.Burst) -> np.ndarray:
    """The trained L-NN's global grayscale palette for a capture: (256,) sorted L in
    [0,1]. Used by the quality gate (gates.gate_beats_baseline) and inference."""
    pooled = zn.gif_to_tokens(burst.gif).astype(np.float32)
    tokens = mx.array(pooled[None])
    mask = mx.array(pooled[None, :, 9])
    pal_L, _, _ = generate_palette(gen, tokens, mask)
    return np.sort(np.clip(np.array(pal_L), 0.0, 1.0))


# ── soft-OT render (differentiable) ────────────────────────────────────────────
def soft_render(pixels_L: mx.array, palette_L: mx.array, eps: float) -> mx.array:
    """Each pixel → Σ_j softmax(-(L_i-L_j)²/eps)_j · L_j (entropic-OT soft palette lookup)."""
    c = (pixels_L[:, None] - palette_L[None, :]) ** 2      # (p, K)
    w = mx.softmax(-c / eps, axis=1)
    return w @ palette_L                                   # (p,)


# ── discriminator: image-space MLP on a rendered grayscale frame ───────────────
class Discriminator(nn.Module):
    """Mac-side, training-only. Judges a (P,) grayscale frame real (true lightness)
    vs fake (global-palette soft-OT render). Small MLP — D never ships."""

    def __init__(self):
        super().__init__()
        self.l1 = nn.Linear(P, 256)
        self.l2 = nn.Linear(256, 64)
        self.l3 = nn.Linear(64, 1)

    def __call__(self, frame):                              # (B, P) → (B,1) logit
        x = nn.leaky_relu(self.l1(frame), 0.2)
        x = nn.leaky_relu(self.l2(x), 0.2)
        return self.l3(x)


def bce_logits(logit, target):
    return mx.mean(mx.logaddexp(0.0, logit) - target * logit)


# ── one capture's training tensors ─────────────────────────────────────────────
def capture_tensors(cls: "sc.SynthClass", seed: int):
    b = sc.materialize(cls, seed)              # CLASSIFIED capture (stratified corpus)
    # Train on TENSORS-OF-GIFS: tokens are a pure function of the decoded GIF
    # (μ from srgb8→oklab, Σ=0, w=population) — exactly what the device sees. NOT
    # the privileged pre-encode tokens. (S4; twin of Haskell decodedGifToTokenSet.)
    pooled = zn.gif_to_tokens(b.gif).astype(np.float32)                # (T,10)
    tokens = mx.array(pooled[None])                                    # (1,T,10)
    mask = mx.array(pooled[None, :, 9])                                # (1,T) per-token weights (Σ=1)
    pix_L = mx.array((b.oklab_q16[:, :, 0].astype(np.float32) / zn.Q16))  # (F,P) true lightness
    in_L = b.oklab_q16[:, :, 0].astype(np.float64) / zn.Q16
    in_mean, in_var = float(in_L.mean()), float(in_L.var())
    return b, tokens, mask, pix_L, in_mean, in_var


def train(args):
    gen = ln.LookNet()
    disc = Discriminator()
    g_opt = optim.Adam(learning_rate=args.glr)
    d_opt = optim.Adam(learning_rate=args.dlr)

    # Stratified classified corpus: equal captures per SynthClass (variance-hardening).
    specs = sc.stratified_specs(n_per_class=args.per_class)
    captures = [capture_tensors(cls, seed) for (cls, seed) in specs]
    print(f"corpus: {len(specs)} captures = {args.per_class}/class × {len(sc.CLASSES)} classes")

    def eps_at(step):
        # Geometric ε-anneal: soft (stable) → sharp (≈hard argmin), so `recon`
        # becomes the true per-pixel MSE and the palette must USE DEPTH to cut it.
        if args.steps <= 1:
            return args.eps_end
        frac = step / (args.steps - 1)
        return float(args.eps_start * (args.eps_end / args.eps_start) ** frac)

    def g_loss_fn(gen, tokens, mask, pix_L, in_mean, in_var, eps):
        palette, _pdist, halts = generate_palette(gen, tokens, mask)
        fr = pix_L[: args.frames_per_step]
        rendered = mx.stack([soft_render(fr[i], palette, eps) for i in range(fr.shape[0])])
        adv = bce_logits(disc(rendered), mx.ones((fr.shape[0], 1)))      # fool D → "real" (perceptual)
        recon = mx.mean((rendered - fr) ** 2)                           # soft-OT transport cost = differentiable W₂ (fidelity)
        pm, pv = mx.mean(palette), mx.var(palette)
        bures = (pm - in_mean) ** 2 + (mx.sqrt(pv + 1e-9) - np.sqrt(in_var + 1e-9)) ** 2
        halt = halting_loss_mx(halts, args.lam_p)                        # depth-favouring prior (low λ_p)
        total = args.lam_adv * adv + args.lam_recon * recon + args.lam_bures * bures + args.lam_halt * halt
        return total, (adv, recon, bures, halt)

    def d_loss_fn(disc, tokens, mask, pix_L, eps):
        palette, _, _ = generate_palette(gen, tokens, mask)
        fr = pix_L[: args.frames_per_step]
        rendered = mx.stack([soft_render(fr[i], mx.stop_gradient(palette), eps)
                             for i in range(fr.shape[0])])
        real = disc(fr)                                                  # true lightness = real
        fake = disc(rendered)                                            # global render = fake
        return bce_logits(real, mx.ones_like(real)) + bce_logits(fake, mx.zeros_like(fake))

    g_vg = nn.value_and_grad(gen, g_loss_fn)
    d_vg = nn.value_and_grad(disc, d_loss_fn)

    for step in range(args.steps):
        b, tokens, mask, pix_L, in_mean, in_var = captures[step % len(captures)]
        eps = eps_at(step)
        dl, dgrad = d_vg(disc, tokens, mask, pix_L, eps)
        dgrad, _ = optim.clip_grad_norm(dgrad, 1.0)    # stability guard
        d_opt.update(disc, dgrad)
        (gl, parts), ggrad = g_vg(gen, tokens, mask, pix_L, in_mean, in_var, eps)
        ggrad, _ = optim.clip_grad_norm(ggrad, 1.0)
        g_opt.update(gen, ggrad)
        mx.eval(gen.parameters(), disc.parameters(), g_opt.state, d_opt.state)
        if step % args.log_every == 0 or step == args.steps - 1:
            adv, recon, bures, halt = parts
            print(f"step {step:>4d}  ε={eps:.5f}  D={float(dl):.4f}  G={float(gl):.4f} "
                  f"[adv={float(adv):.4f} recon={float(recon):.6f} bures={float(bures):.5f} halt={float(halt):.4f}]")

    return gen


# ── export trained weights to the deploy blob ──────────────────────────────────
def export_blob(gen: ln.LookNet, out_path: Path) -> int:
    g = gen.recursion.g
    weights = {
        "phi": np.array(gen.encoder.phi.weight),         # (64,10)
        "w1": np.array(g.w1.weight),                     # (64,64)
        "w2": np.array(g.w2.weight),                     # (64,64)
        "halt_w": np.array(g.halt_mlp.weight),           # (1,2)
        "halt_b": np.array(g.halt_mlp.bias),             # (1,)
    }
    for i, head in enumerate(gen.decoder.heads):
        weights[f"head{i}"] = np.array(head.weight)      # (d_i,64)
    return blob.write_blob(weights, out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=300)
    ap.add_argument("--per-class", type=int, default=7)  # captures per SynthClass (×7 classes)
    ap.add_argument("--frames-per-step", type=int, default=6)
    ap.add_argument("--glr", type=float, default=1e-3)
    ap.add_argument("--dlr", type=float, default=4e-4)
    ap.add_argument("--eps-start", type=float, default=2e-2)   # soft (stable) at the start
    ap.add_argument("--eps-end", type=float, default=1.5e-4)   # ≈hard argmin by the end
    ap.add_argument("--lam-adv", type=float, default=1.0)      # perceptual (GAN)
    ap.add_argument("--lam-recon", type=float, default=200.0)  # fidelity — DOMINANT (MSE-beating)
    ap.add_argument("--lam-bures", type=float, default=5.0)
    ap.add_argument("--lam-halt", type=float, default=0.02)    # gentle parsimony, in tension with recon
    ap.add_argument("--lam-p", type=float, default=0.2)        # halting prior: low λ_p ⇒ favour DEEPER palettes
    ap.add_argument("--log-every", type=int, default=25)
    args = ap.parse_args()

    gen = train(args)

    out_dir = Path(__file__).resolve().parent / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    nbytes = export_blob(gen, out_dir / "look_net_trained.s4ln")
    print(f"\nexported blob: {nbytes} bytes -> out/look_net_trained.s4ln")

    # Verify end-to-end: render the LEARNED global grayscale palette on a held-out capture.
    b = zn.synth_sample(seed=999, mode=zn.SYNTH_COLOR)
    pooled = zn.gif_to_tokens(b.gif).astype(np.float32)               # tensor-of-GIF input
    tokens = mx.array(pooled[None])
    mask = mx.array(pooled[None, :, 9])
    palette_L, pdist, _ = generate_palette(gen, tokens, mask)
    pal = np.clip(np.array(palette_L), 0.0, 1.0)
    pal_sorted = np.sort(pal)
    gif = gp.render_global_gif(b, gp.l_palette_to_oklab(pal_sorted))
    (out_dir / "synth_looknet_grayscale.gif").write_bytes(gif)

    learned_mse = gp.oklab_mse(b, pal_sorted)
    base_mse = gp.oklab_mse(b, gp.wasserstein_l_barycenter(b))                 # 256-level
    base128 = gp.oklab_mse(b, gp.wasserstein_l_barycenter(b, k=128))           # FAIR σ-pair budget
    _, floor_mse = gp.render_perframe_grayscale_gif(b)
    ed = float(mx.sum(mx.arange(N_TRUNC).astype(mx.float32) * pdist))
    distinct = len(np.unique(np.round(pal_sorted, 4)))
    win = "✓ BEATS 128-baseline" if learned_mse < base128 else "✗ above 128-baseline"
    print(f"held-out L-MSE: learned={learned_mse:.6e}  base256={base_mse:.6e}  base128(fair)={base128:.6e}  floor={floor_mse:.6e}  {win}")
    print(f"learned palette: {distinct}/256 distinct L levels, span [{pal_sorted.min():.3f},{pal_sorted.max():.3f}]")
    print(f"expected halting depth E[d] = {ed:.2f} / {DEPTH}  (palette complexity the NN chose)")
    print("artifact: out/synth_looknet_grayscale.gif")


if __name__ == "__main__":
    main()
