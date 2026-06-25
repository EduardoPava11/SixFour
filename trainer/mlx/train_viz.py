#!/usr/bin/env python3
"""train_viz.py — TRAINING OBSERVABILITY for the SixFour H-JEPA trainer.

This module produces an artifact bundle (under trainer/out/report/) that lets the OWNER
SEE the trainer is actually training, not just trust a green test. It is PURELY ADDITIVE:
it imports the gated modules and calls their PUBLIC seams; it never re-derives the loss and
never modifies a gated module's behaviour.

What it surfaces (all pulled from real runs, never hardcoded):

  (A) CHARTS that prove training:
      - L_composite (the one scalar SGD descends) AND L_band ALONE (the masked-band MSE
        objective), so descent is provably the OBJECTIVE falling, not the VICReg guard
        relaxing. Both come from train_loop.run()'s return values [0] and [1].
      - L_vic per-step, derived EXACTLY from the two returned arrays as
        (composite - band) / LAMBDA_VIC (pure algebra on run()'s outputs, not a re-derivation).
      - VICReg latent health: the FINAL live std-hinge (~0 => variance present) vs the
        INDUCED-CONSTANT control (hinge > 0.5), the demo_no_collapse proof that the guard
        WOULD bite a collapsed latent. cross_redundancy shown blind to constant collapse.
      - An lr=0 FLAT CONTROL overlaid: a SECOND real run() with lr=0.0, same seed/init, so
        the descent is visibly OPTIMIZER-DRIVEN, not cosmetic.

  (B) THE INPUT: the actual GIF the run trains on (the 64^3 synth capture), saved verbatim
      and viewable (animated in the HTML).

  (C) THE SCALE SPINE: the 16^3, 64^3 and 256^3 L-renders side by side.
      - 64^3 is the capture's REAL L-volume (jepa_synth_octants.l_volume), the volume the
        corpus octants are lifted from.
      - 16^3 is its REAL octree coarse (test_centered_cube.compress_to_16, byte-exact).
      - 256^3 is the HONEST FLOOR: nearest-neighbour upsample of the 64^3 (== octree
        synthesize with ZERO invented detail, the zero-genome==floor identity). There is NO
        trained super-res head in Python (grep for reconstruct256/Upscale256/NetSynth256 is
        empty), so a "real invented" 256^3 does not exist yet. It is LABELLED exactly:
        "256^3 floor (no invented detail yet; this is what the head will learn to add)".

CHARTING TOOL: matplotlib (importable 3.10.6, a CLAUDE.md Tier-1 trainer dep) is the primary
charter for the static PNG dashboard panels (the requested matplotlib-dashboard). It is kept
behind a SOFT import: if absent, the PNG charts are skipped (a dep-free inline-SVG fallback
draws the loss curve into the HTML) so gate portability is never broken. matplotlib cannot
animate the GIF, so a self-contained HTML index embeds the GIFs as animated <img> alongside
the PNG charts — the owner opens one file and watches the input move next to the curves.

Run:
  python3 train_viz.py --smoke        # ONE real run + ONE lr=0 control, ~ a few seconds
  python3 train_viz.py                 # fuller run
  # or via the CLI:  python3 cli.py report --smoke
"""
from __future__ import annotations

import argparse
import base64
import os
import sys
import time

# IMPORT ORDER TRAP (train_loop.py:55-65): jepa_synth_octants pollutes sys.path so a later
# `import mlx.core` resolves to trainer/mlx/__init__.py and fails. train_loop imports the REAL
# mlx FIRST, so importing train_loop here (before anything else touches the path) caches mlx
# correctly. Do this import FIRST.
import train_loop as TL                                       # noqa: E402  (pulls mlx in, cached)
import mlx.core as mx                                         # noqa: E402  (now resolves)
import numpy as np                                            # noqa: E402

import jepa_synth_octants as JSO                              # noqa: E402  (l_volume)
import test_centered_cube as TCC                              # noqa: E402  (compress_to_16)
from synth_capture import synthetic_capture                   # noqa: E402

# matplotlib is a SOFT dep (CLAUDE.md Tier-1 trainer dep, importable today, but NOT in the
# named-light spine). If it's missing we degrade to a dep-free inline-SVG loss chart.
try:
    import matplotlib
    matplotlib.use("Agg")                                     # headless PNG backend
    import matplotlib.pyplot as plt
    HAVE_MPL = True
except Exception:                                             # pragma: no cover
    HAVE_MPL = False

from PIL import Image

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "out", "report"))

# The SMOKE corpus train_loop.main() actually trains on (train_loop.py:335). We MUST show the
# GIF / 64^3 / 16^3 / 256^3 for the EXACT same (seed, kind) the run() trains on, or the
# "this is the input" claim is dishonest. So the report derives ALL of them from this one pair.
SMOKE_SPEC = (7, "high-lab")
SMOKE_FS = SMOKE_SP = 16
SMOKE_OCTANTS = 8
SMOKE_STEPS = 30
FULL_STEPS = 60


# ---------------------------------------------------------------------------
# Q16 OKLab-L -> u8 display scaler (the L-volume is Q16, ~7531..58799, NOT 0..255).
# Display-only; never touches the gated integer math.
# ---------------------------------------------------------------------------
def q16_to_u8(vol_q16: np.ndarray) -> np.ndarray:
    return np.clip(np.asarray(vol_q16) * 255.0 / 65536.0, 0, 255).astype(np.uint8)


def _montage_u8(vol_u8: np.ndarray, scale: int, cols: int | None = None) -> Image.Image:
    """Lay every frame of a (F, S, S) u8 volume into one grayscale grid image (NEAREST upscale)."""
    n, s = vol_u8.shape[0], vol_u8.shape[1]
    if cols is None:
        cols = int(np.ceil(np.sqrt(n)))
    rows = int(np.ceil(n / cols))
    tile = s * scale
    sheet = np.full((rows * tile, cols * tile), 40, dtype=np.uint8)  # dark gutter
    for f in range(n):
        r, c = divmod(f, cols)
        t = vol_u8[f].repeat(scale, 0).repeat(scale, 1)
        sheet[r * tile:r * tile + tile, c * tile:c * tile + tile] = t
    return Image.fromarray(sheet, "L")


def _save_gif_u8(vol_u8: np.ndarray, path: str, scale: int, duration: int = 50):
    frames = [Image.fromarray(vol_u8[f], "L").resize(
        (vol_u8.shape[1] * scale, vol_u8.shape[2] * scale), Image.NEAREST)
        for f in range(vol_u8.shape[0])]
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=duration,
                   loop=0, optimize=False, disposal=2)


# ---------------------------------------------------------------------------
# (A) METRICS — pull two real runs and assemble the trajectory record.
# ---------------------------------------------------------------------------
def collect_metrics(seed: int, steps: int, smoke: bool):
    """Two REAL run() calls (descending + lr=0 control) + the final live VICReg health and the
    induced-constant control. Returns everything the charts need. NO hardcoded curves."""
    if smoke:
        specs, fs, ss, ncap = [SMOKE_SPEC], SMOKE_FS, SMOKE_SP, SMOKE_OCTANTS
    else:
        specs, fs, ss, ncap = [(7, "high-lab"), (11, "high-detail"), (23, "smooth-grey")], 8, 8, 24

    examples, n_oct = TL.build_corpus(specs, frame_step=fs, space_step=ss)
    examples = examples[:ncap]
    d6 = mx.array(TL.octant_lattice_d6(TL.N_TOKENS), dtype=mx.float32)
    mx.eval(d6)

    lr = 8e-3
    t0 = time.time()
    # RUN A: the real descending optimizer run. Charts come from THESE arrays.
    traj, band_traj, head, tokens_b, masks = TL.run(seed, examples, d6, steps, lr, verbose=False)
    # RUN B: identical run with lr=0.0 -> SGD takes no step -> flat line == optimizer-driven proof.
    traj0, band0, _h0, _t0, _m0 = TL.run(seed, examples, d6, steps, 0.0, verbose=False)
    wall = time.time() - t0

    # L_vic per-step, EXACT from the two returned arrays (composite = band + LAMBDA_VIC*vic).
    comp = np.asarray(traj, dtype=np.float64)
    band = np.asarray(band_traj, dtype=np.float64)
    vic = (comp - band) / TL.LAMBDA_VIC

    # FINAL live latent health + the induced-constant control (the demo_no_collapse proof).
    latent0, _ = head(tokens_b[0], d6)
    mx.eval(latent0)
    live_hinge, live_cov, live_floor = TL.vicreg_python_read(latent0)
    const_rows = [[7.0] * TL.VIC_NEURON_SLICE for _ in range(TL.N_TOKENS)]
    const_hinge = TL.vicreg.variance_floor_penalty(TL.VIC_GAMMA, TL.VIC_EPS, const_rows)
    const_cov = TL.vicreg.cross_redundancy(const_rows)

    return {
        "seed": seed, "steps": steps, "lr": lr, "n_oct": n_oct, "n_used": len(examples),
        "specs": specs, "wall": wall,
        "composite": comp, "band": band, "vic": vic,
        "composite0": np.asarray(traj0, dtype=np.float64),
        "band0": np.asarray(band0, dtype=np.float64),
        "live_hinge": float(live_hinge), "live_cov": float(live_cov), "live_floor": float(live_floor),
        "const_hinge": float(const_hinge), "const_cov": float(const_cov),
        # PASS/FAIL property badges (reuse the gated demos so the report can't drift from them).
        "descent_ok": bool(TL.demo_descent(traj, band_traj)),
        "nocollapse_ok": bool(TL.demo_no_collapse(head, tokens_b, d6)),
    }


# ---------------------------------------------------------------------------
# (A) CHARTS — matplotlib PNG dashboard (soft dep). Drawn from the run() arrays.
# ---------------------------------------------------------------------------
def render_charts_mpl(m, out_dir) -> list[str]:
    if not HAVE_MPL:
        return []
    os.makedirs(out_dir, exist_ok=True)   # robust if an external process clears trainer/out mid-run
    paths = []
    x = np.arange(len(m["composite"]))

    # Panel 1: loss trajectory — composite + band ALONE + lr=0 control overlay (log y).
    fig, ax = plt.subplots(figsize=(7, 4.2), dpi=120)
    ax.plot(x, m["composite"], color="#1f77b4", lw=2, label="L_composite (SGD descends this)")
    ax.plot(x, m["band"], color="#d62728", lw=2, label="L_band alone (objective term)")
    ax.plot(x, m["composite0"], color="#888888", lw=1.6, ls="--",
            label="lr=0 control (frozen optimizer)")
    ax.set_yscale("log")
    ax.set_xlabel("SGD step"); ax.set_ylabel("loss (log)")
    ax.set_title("Training trajectory — descent is optimizer-driven\n"
                 "(band falls independently of the VICReg guard; lr=0 stays flat)")
    ax.legend(fontsize=8); ax.grid(True, which="both", alpha=0.25)
    p = os.path.join(out_dir, "chart_loss.png"); fig.tight_layout(); fig.savefig(p); plt.close(fig)
    paths.append(p)

    # Panel 2: L_vic per-step (derived) — shows the hinge zeroing early while L_band keeps falling.
    fig, ax = plt.subplots(figsize=(7, 4.2), dpi=120)
    ax.plot(x, m["vic"], color="#2ca02c", lw=2, label="L_vic (=(comp-band)/LAMBDA_VIC)")
    ax.axhline(0.0, color="#444", lw=0.8, ls=":")
    ax.set_xlabel("SGD step"); ax.set_ylabel("VICReg hinge contribution")
    ax.set_title("VICReg std-hinge per step (derived from run() arrays)\n"
                 "guard relaxes to its floor early; the objective keeps fitting")
    ax.legend(fontsize=8); ax.grid(True, alpha=0.25)
    p = os.path.join(out_dir, "chart_vic.png"); fig.tight_layout(); fig.savefig(p); plt.close(fig)
    paths.append(p)

    # Panel 3: latent health — final live hinge/cov vs induced-constant control.
    fig, ax = plt.subplots(figsize=(7, 4.2), dpi=120)
    labels = ["std-hinge", "cross-cov"]
    live = [m["live_hinge"], m["live_cov"]]
    const = [m["const_hinge"], m["const_cov"]]
    xx = np.arange(len(labels)); w = 0.36
    ax.bar(xx - w/2, live, w, color="#1f77b4", label="live ViT latent")
    ax.bar(xx + w/2, const, w, color="#d62728", label="INDUCED constant latent")
    ax.axhline(0.5, color="#444", ls="--", lw=1, label="hinge trip threshold (0.5)")
    ax.set_xticks(xx); ax.set_xticklabels(labels)
    ax.set_ylabel("penalty")
    ax.set_title("Latent health — no collapse\n"
                 "live hinge ~0 (variance present); the guard WOULD bite a constant latent;\n"
                 "cov is BLIND to constant collapse (why both are needed)")
    ax.legend(fontsize=8); ax.grid(True, axis="y", alpha=0.25)
    p = os.path.join(out_dir, "chart_health.png"); fig.tight_layout(); fig.savefig(p); plt.close(fig)
    paths.append(p)
    return paths


def _svg_loss_chart(m) -> str:
    """Dep-free fallback: inline-SVG loss chart built from the run() arrays (log-y polylines)."""
    W, H, pad = 640, 320, 40
    series = [("L_composite", m["composite"], "#1f77b4"),
              ("L_band", m["band"], "#d62728"),
              ("lr=0 control", m["composite0"], "#888888")]
    allv = np.concatenate([np.clip(s[1], 1e-9, None) for s in series])
    lo, hi = float(np.log10(allv.min())), float(np.log10(allv.max()))
    if hi - lo < 1e-9:
        hi = lo + 1.0
    n = len(m["composite"])

    def pt(i, v):
        x = pad + (W - 2 * pad) * (i / max(1, n - 1))
        ly = (np.log10(max(v, 1e-9)) - lo) / (hi - lo)
        y = (H - pad) - (H - 2 * pad) * ly
        return f"{x:.1f},{y:.1f}"

    polys, legend = [], []
    for k, (name, arr, col) in enumerate(series):
        pts = " ".join(pt(i, v) for i, v in enumerate(arr))
        polys.append(f'<polyline fill="none" stroke="{col}" stroke-width="2" points="{pts}"/>')
        legend.append(f'<text x="{pad}" y="{16 + 14*k}" fill="{col}" font-size="12">{name}</text>')
    return (f'<svg width="{W}" height="{H}" xmlns="http://www.w3.org/2000/svg" '
            f'style="background:#fff;border:1px solid #ccc">'
            f'<rect x="{pad}" y="{pad}" width="{W-2*pad}" height="{H-2*pad}" '
            f'fill="none" stroke="#ddd"/>' + "".join(polys) + "".join(legend) +
            f'<text x="{pad}" y="{H-12}" font-size="11" fill="#444">SGD step (log-y loss)'
            f'</text></svg>')


# ---------------------------------------------------------------------------
# (B)+(C) INPUT GIF + SCALE SPINE — all derived from the SAME (seed, kind) the run trains on.
# ---------------------------------------------------------------------------
def render_input_and_spine(seed: int, kind: str, out_dir, smoke: bool):
    os.makedirs(out_dir, exist_ok=True)   # robust if an external process clears trainer/out mid-run
    arts = {}
    # (B) the actual GIF the run trains on, saved VERBATIM (the camera-format bytes).
    cap = synthetic_capture(seed, kind)
    gif_path = os.path.join(out_dir, "input.gif")
    with open(gif_path, "wb") as f:
        f.write(cap.gif)
    arts["input_gif"] = gif_path
    arts["input_gif_bytes"] = len(cap.gif)

    # (C) 64^3 = the REAL L-volume the corpus octants are lifted from (jepa_synth_octants.l_volume).
    vol64 = JSO.l_volume(seed, kind)                          # (64,64,64) Q16 OKLab-L, REAL
    arts["q16_range"] = (int(vol64.min()), int(vol64.max()))
    u8_64 = q16_to_u8(vol64)

    # 16^3 = the REAL octree coarse (two reversible levels 64->32->16; byte-exact).
    c16, _details = TCC.compress_to_16(vol64)                 # (16,16,16) Q16, REAL coarse
    u8_16 = q16_to_u8(c16)

    # 256^3 FLOOR = NN upsample of the 64^3 == octree synthesize with ZERO invented detail
    # (zero-genome==floor). np.repeat x4 per axis is IDENTICAL-by-construction to the zero-detail
    # synthesize (unlift_oct(c,[0]*7) replicates c into its 2x2x2 block) but sub-second. There is
    # NO trained super-res head in Python (no reconstruct256/Upscale256/NetSynth256), so this is
    # the honest ceiling today. It is LABELLED as the floor everywhere it is shown.
    # For the spine strip we only need frames at the 256 grid; build the full-res frames we render.
    # (Build a few representative frames to keep --smoke fast; the upsample is exact for all.)
    spine_frames = [0, 16, 32, 48] if smoke else list(range(0, 64, 8))

    # Render the 16/64/256 as a side-by-side spine strip PNG (one representative frame, upscaled
    # so all three are the SAME on-screen size — the honest comparison is "same field of view").
    rep = spine_frames[0]
    f16 = u8_16[rep // 4]                                     # the coarse frame nearest rep
    f64 = u8_64[rep]
    # 256 floor frame = NN-upsample of the 64 frame x4 (exact zero-detail synthesize equivalent).
    f256 = f64.repeat(4, 0).repeat(4, 1)
    # upscale each to ~256px tall for the strip
    img16 = Image.fromarray(f16, "L").resize((256, 256), Image.NEAREST)
    img64 = Image.fromarray(f64, "L").resize((256, 256), Image.NEAREST)
    img256 = Image.fromarray(f256, "L").resize((256, 256), Image.NEAREST)

    gap = 24
    strip = Image.new("L", (256 * 3 + gap * 2, 256), 40)
    strip.paste(img16, (0, 0))
    strip.paste(img64, (256 + gap, 0))
    strip.paste(img256, (256 * 2 + gap * 2, 0))
    spine_path = os.path.join(out_dir, "scale_spine.png")
    strip.save(spine_path)
    arts["scale_spine"] = spine_path

    # Also save each level as its own animated GIF so the owner can scrub all 16/64 frames.
    g16 = os.path.join(out_dir, "scale_16.gif")
    g64 = os.path.join(out_dir, "scale_64.gif")
    g256 = os.path.join(out_dir, "scale_256_floor.gif")
    _save_gif_u8(u8_16, g16, scale=16)
    _save_gif_u8(u8_64, g64, scale=4)
    # 256 floor: NN-upsample every frame x4 (exact), then save (scale=1, already 256px).
    u8_256_floor = u8_64.repeat(4, 1).repeat(4, 2)            # (64,256,256) zero-detail floor
    _save_gif_u8(u8_256_floor, g256, scale=1)
    arts.update(scale_16_gif=g16, scale_64_gif=g64, scale_256_gif=g256)

    # A 64^3 frame montage so the whole trained volume is visible at a glance.
    mont = _montage_u8(u8_64, scale=2)
    mont_path = os.path.join(out_dir, "input_volume_montage.png")
    mont.save(mont_path)
    arts["volume_montage"] = mont_path
    return arts


# ---------------------------------------------------------------------------
# HTML index — self-contained, embeds animated GIFs (matplotlib can't) + the PNG charts.
# ---------------------------------------------------------------------------
def _data_uri(path: str, mime: str) -> str:
    with open(path, "rb") as f:
        return f"data:{mime};base64," + base64.b64encode(f.read()).decode("ascii")


def write_html(m, chart_paths, spine, out_dir):
    seed, kind = m["specs"][0]
    badge = lambda ok: ('<span style="color:#0a0;font-weight:600">PASS</span>' if ok
                        else '<span style="color:#c00;font-weight:600">FAIL</span>')

    gif_uri = _data_uri(spine["input_gif"], "image/gif")
    g256_uri = _data_uri(spine["scale_256_gif"], "image/gif")
    g64_uri = _data_uri(spine["scale_64_gif"], "image/gif")
    g16_uri = _data_uri(spine["scale_16_gif"], "image/gif")
    spine_uri = _data_uri(spine["scale_spine"], "image/png")
    mont_uri = _data_uri(spine["volume_montage"], "image/png")

    charts_html = ""
    if chart_paths:
        for p in chart_paths:
            charts_html += f'<img src="{_data_uri(p, "image/png")}" style="max-width:680px;display:block;margin:8px 0"/>'
    else:
        charts_html = _svg_loss_chart(m) + "<p><i>(matplotlib not importable; dep-free SVG loss chart shown)</i></p>"

    html = f"""<!doctype html><meta charset="utf-8">
<title>SixFour H-JEPA — training observability</title>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:920px;margin:24px auto;color:#222">
<h1>SixFour H-JEPA — training observability report</h1>
<p>Seed <b>{seed}</b>, kind <b>{kind}</b>, steps <b>{m['steps']}</b>, lr <b>{m['lr']}</b>,
corpus {len(m['specs'])} capture(s) → {m['n_oct']} octant records (using {m['n_used']}).
Wall (2 runs): {m['wall']:.1f}s. Charts: {'matplotlib PNG' if chart_paths else 'dep-free inline SVG'}.</p>

<h2>(A) Training proof</h2>
<p>Property badges (reusing the gated demos): descent {badge(m['descent_ok'])}
&nbsp; no-collapse {badge(m['nocollapse_ok'])}</p>
<ul>
<li>L_composite {m['composite'][0]:.6f} → {m['composite'][-1]:.6f}</li>
<li>L_band alone {m['band'][0]:.6f} → {m['band'][-1]:.6f} (objective descends independently of the guard)</li>
<li>lr=0 control {m['composite0'][0]:.6f} → {m['composite0'][-1]:.6f} (flat → descent is optimizer-driven)</li>
<li>live latent std-hinge {m['live_hinge']:.4f} (≈0, variance present) vs INDUCED constant {m['const_hinge']:.4f} (&gt;0.5, guard bites)</li>
<li>cross-cov live {m['live_cov']:.4f} vs constant {m['const_cov']:.4f} (cov is blind to constant collapse → both guards needed)</li>
</ul>
{charts_html}

<h2>(B) The input the run trains on</h2>
<p>The actual 64-frame 64×64 synthetic-capture GIF (camera-format bytes, {spine['input_gif_bytes']:,} B), animated:</p>
<img src="{gif_uri}" style="width:256px;image-rendering:pixelated;border:1px solid #ccc"/>
<p>The 64³ L-volume the corpus octants are lifted from (all frames):</p>
<img src="{mont_uri}" style="max-width:680px;border:1px solid #ccc"/>

<h2>(C) The scale spine — 16³ · 64³ · 256³ (floor)</h2>
<p>Same field of view, NEAREST upscaled to equal on-screen size:</p>
<img src="{spine_uri}" style="max-width:900px;border:1px solid #ccc"/>
<p style="font-size:13px;color:#555">left → right: <b>16³</b> octree coarse (REAL, byte-exact) ·
<b>64³</b> the REAL capture L-volume (Q16 range {spine['q16_range'][0]}..{spine['q16_range'][1]}) ·
<b>256³ floor</b> — <b>no invented detail yet; this is what the head will learn to add</b>
(nearest-neighbour upsample = octree synthesize with ZERO detail; there is no trained super-res head wired in Python).</p>
<p>Animated, each level:</p>
<div style="display:flex;gap:16px;align-items:flex-start">
  <div><div>16³ coarse</div><img src="{g16_uri}" style="width:160px;image-rendering:pixelated;border:1px solid #ccc"/></div>
  <div><div>64³ (trained volume)</div><img src="{g64_uri}" style="width:160px;image-rendering:pixelated;border:1px solid #ccc"/></div>
  <div><div>256³ <b>floor</b> (zero invented detail)</div><img src="{g256_uri}" style="width:160px;image-rendering:pixelated;border:1px solid #ccc"/></div>
</div>
</body>"""
    path = os.path.join(out_dir, "index.html")
    with open(path, "w") as f:
        f.write(html)
    return path


# ---------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="SixFour H-JEPA training observability report.")
    ap.add_argument("--smoke", action="store_true", help="ONE real run + ONE lr=0 control, ~ a few seconds")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--steps", type=int, default=None)
    args = ap.parse_args(argv)

    os.makedirs(OUT_DIR, exist_ok=True)
    steps = args.steps if args.steps is not None else (SMOKE_STEPS if args.smoke else FULL_STEPS)
    seed, kind = (args.seed, SMOKE_SPEC[1])

    print(f"=== SixFour H-JEPA training observability ({'SMOKE' if args.smoke else 'FULL'}) ===")
    print(f"out: {OUT_DIR}")
    print(f"charts: {'matplotlib PNG dashboard' if HAVE_MPL else 'dep-free inline SVG (matplotlib absent)'}")

    print("\n[A] collecting metrics from TWO real run() calls (descend + lr=0 control)...")
    m = collect_metrics(seed, steps, args.smoke)
    print(f"    composite {m['composite'][0]:.6f} -> {m['composite'][-1]:.6f} | "
          f"band {m['band'][0]:.6f} -> {m['band'][-1]:.6f} | "
          f"lr=0 {m['composite0'][0]:.6f} -> {m['composite0'][-1]:.6f} | wall {m['wall']:.1f}s")

    chart_paths = render_charts_mpl(m, OUT_DIR)
    print(f"    wrote {len(chart_paths)} chart PNG(s)" if chart_paths else "    SVG chart (in HTML)")

    print("\n[B]+[C] rendering input GIF + 16/64/256 scale spine (same seed/kind the run trains on)...")
    spine = render_input_and_spine(seed, kind, OUT_DIR, args.smoke)
    print(f"    input.gif {spine['input_gif_bytes']:,} B | 64^3 Q16 range {spine['q16_range']}")
    print(f"    256^3 = honest FLOOR (zero invented detail; no super-res head in Python)")

    html = write_html(m, chart_paths, spine, OUT_DIR)
    print(f"\nwrote report: {html}")
    print("open it in a browser to watch the input GIF animate next to the loss curves.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
