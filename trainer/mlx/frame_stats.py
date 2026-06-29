"""
frame_stats.py -- the ABSTRACTED V2 diagnostic: facets of energy + entropy.

frame_energy.py used ONE average (the mean) on ONE projection (the raw pixel). This abstracts
all three axes the owner named:

  PROJECTION  (which linear combination of R,G,B we measure)
    R, G, B               -- the raw channels
    L = R+G+B             -- luma, the achromatic average axis
    a = R-G               -- opponent red-green chrominance contrast (first-class RGB projection)
    b = R+G-2B            -- opponent yellow-blue chrominance contrast (first-class RGB projection)
    Cr = R-B, Cg = G-B    -- the Eisenstein A2 chroma coords
  These opponent projections are first-class RGB-native linear functionals, NOT an approximation of
  any other colour space. RGB sRGB 8-bit is first class; Lab is deprecated entirely.

  STATISTIC  (which "average" the residual deviates from = which norm it minimizes)
    mean   = the L2 centre  -> residual energy = mean squared deviation
    median = the L1 centre  -> residual energy = mean absolute deviation (robust)
    mode   = the L0 centre  -> residual energy = off-mode fraction (sparsity)
  Models are averaging machines, but a vanilla one only learns the MEAN; training on
  mean/median/mode captures the distribution SHAPE (their spread is skew).

  TIME  (the t axis, and the GIF is CYCLIC)
    each projection's statistic over t is a time series;
    inter-frame deltas are the MOMENTUM (energy of motion);
    the GIF loops, so there are N seams not N-1: the frame[N-1] -> frame[0] delta is the
    loop DISCONTINUITY the owner pointed at.

ENTROPY is categorised the same way: one entropy per projection per frame (its value spread).

GIF89a-native: a frame is (palette (K,3) sRGB, index_map (H,W)). Run: python frame_stats.py
"""

from __future__ import annotations
from typing import Dict, List, Tuple

import numpy as np

# --- the projection basis (first-class RGB-native linear functionals) -----------

PROJECTIONS: Dict[str, Tuple[int, int, int]] = {
    "R":        (1, 0, 0),
    "G":        (0, 1, 0),
    "B":        (0, 0, 1),
    "L=R+G+B":  (1, 1, 1),     # luma, the achromatic average axis
    "a=R-G":    (1, -1, 0),    # opponent red-green chrominance contrast (first-class RGB)
    "b=R+G-2B": (1, 1, -2),    # opponent yellow-blue chrominance contrast (first-class RGB)
    "Cr=R-B":   (1, 0, -1),    # Eisenstein chroma coord
    "Cg=G-B":   (0, 1, -1),    # Eisenstein chroma coord
}

STATISTICS = ("mean", "median", "mode")    # the L2 / L1 / L0 centres


def render(palette: np.ndarray, index_map: np.ndarray) -> np.ndarray:
    return palette[index_map]


def project(pixels: np.ndarray, w: Tuple[int, int, int]) -> np.ndarray:
    """Project (..,3) pixels onto a linear functional w -> integer scalars."""
    return (pixels[..., 0] * w[0] + pixels[..., 1] * w[1] + pixels[..., 2] * w[2]).astype(int)


# --- the three averages = three residual norms ---------------------------------

def _mode(x: np.ndarray) -> float:
    vals, counts = np.unique(x, return_counts=True)
    return float(vals[int(np.argmax(counts))])


def centre_and_energy(x: np.ndarray, which: str) -> Tuple[float, float]:
    """Return (centre, residual energy) for a statistic. mean->L2 var, median->L1 MAD,
    mode->L0 off-mode fraction."""
    x = x.reshape(-1).astype(float)
    if which == "mean":
        c = float(x.mean())
        return c, float(((x - c) ** 2).mean())
    if which == "median":
        c = float(np.median(x))
        return c, float(np.abs(x - c).mean())
    if which == "mode":
        c = _mode(x)
        return c, float((x != c).mean())
    raise ValueError(which)


def proj_entropy(x: np.ndarray) -> float:
    """Shannon entropy (bits) of a projection's value distribution. The categorised entropy."""
    _, counts = np.unique(x.reshape(-1), return_counts=True)
    p = counts.astype(float) / counts.sum()
    return float(-(p * np.log2(p)).sum())


# --- per-frame facets ----------------------------------------------------------

def frame_facets(palette: np.ndarray, index_map: np.ndarray) -> Dict[str, Dict[str, float]]:
    """For every projection: the entropy + (centre, energy) under each of mean/median/mode."""
    px = render(palette, index_map)
    out: Dict[str, Dict[str, float]] = {}
    for name, w in PROJECTIONS.items():
        x = project(px, w)
        rec: Dict[str, float] = {"entropy": proj_entropy(x)}
        for s in STATISTICS:
            c, e = centre_and_energy(x, s)
            rec[f"{s}_centre"] = c
            rec[f"{s}_energy"] = e
        out[name] = rec
    return out


# --- temporal: deltas (momentum) and the CYCLIC seam ---------------------------

def delta_energy(palette_a, idx_a, palette_b, idx_b, w) -> float:
    """Energy of the inter-frame difference along projection w (the motion energy between two
    frames). Pixelwise, so it sees actual movement, not just a shift of the average."""
    xa = project(render(palette_a, idx_a), w).reshape(-1).astype(float)
    xb = project(render(palette_b, idx_b), w).reshape(-1).astype(float)
    d = xb - xa
    return float((d * d).mean())


def momentum_series(frames, w) -> Tuple[List[float], float]:
    """Inter-frame delta energy along w for each consecutive pair, PLUS the cyclic seam energy
    (frame[N-1] -> frame[0], the loop discontinuity). Returns (deltas, seam)."""
    n = len(frames)
    deltas = [delta_energy(*frames[t - 1], *frames[t], w) for t in range(1, n)]
    seam = delta_energy(*frames[n - 1], *frames[0], w)   # the GIF loops: last -> first
    return deltas, seam


# --- the categorised facet tensor the model trains on --------------------------

def facet_tensor(frames):
    """The full per-frame facet table (the training signal): frame -> projection -> {entropy,
    mean/median/mode centre+energy}. Plus the temporal momentum + cyclic seam per projection."""
    per_frame = [frame_facets(*f) for f in frames]
    temporal = {}
    for name, w in PROJECTIONS.items():
        deltas, seam = momentum_series(frames, w)
        temporal[name] = {"delta_energy": deltas, "cyclic_seam_energy": seam}
    return {"per_frame": per_frame, "temporal": temporal}


# ===========================================================================
# Demo + self-check
# ===========================================================================

def _palette(k: int = 256) -> np.ndarray:
    i = np.arange(k)
    return np.stack([i, (i * 7) % 256, 255 - i], axis=1).astype(int)


def _demo_frames(pal, h=24, w=24):
    """A cyclic narrative that deliberately does NOT close: a panning band whose phase at the
    last frame differs from the first, so the loop seam carries real energy."""
    frames = []
    rng = np.random.default_rng(1)
    for t in range(12):
        if t < 2:
            idx = np.full((h, w), 100, dtype=int)
        elif t < 8:
            idx = ((np.arange(w)[None, :] + t * 18) % 256 + np.zeros((h, 1), dtype=int)).astype(int)
        else:
            idx = (100 + rng.integers(-60, 61, size=(h, w))).clip(0, 255)
        frames.append((pal, idx.astype(int)))
    return frames


def _self_check() -> int:
    pal = _palette()
    h = w = 12
    flat = (pal, np.full((h, w), 77, dtype=int))
    # a RIGHT-SKEWED distribution on a monotonic-luma grayscale palette (luma = 3*slot), so the
    # three averages separate cleanly: a mode peak at slot 20, a body, and a long high tail ->
    # mean > median > mode (the spread between them IS the skew the model would otherwise miss).
    gray = np.stack([np.arange(256)] * 3, axis=1).astype(int)
    skew_idx = np.concatenate([np.full(60, 20), np.arange(21, 80), np.arange(80, 250, 3)])
    skew_idx = np.resize(skew_idx, h * w).reshape(h, w)
    skew = (gray, skew_idx.astype(int))

    Lw = PROJECTIONS["L=R+G+B"]
    mn, _ = centre_and_energy(project(render(*skew), Lw), "mean")
    md, _ = centre_and_energy(project(render(*skew), Lw), "median")
    mo, _ = centre_and_energy(project(render(*skew), Lw), "mode")

    # the opponent basis (L, a, b) must be invertible (a real first-class RGB change of coords)
    basis = np.array([PROJECTIONS["L=R+G+B"], PROJECTIONS["a=R-G"], PROJECTIONS["b=R+G-2B"]])

    laws = [
        ("flatAllAveragesAgree",
         len({centre_and_energy(project(render(*flat), Lw), s)[0] for s in STATISTICS}) == 1),
        ("flatAllEnergiesZero",
         all(centre_and_energy(project(render(*flat), Lw), s)[1] == 0.0 for s in STATISTICS)),
        ("skewSeparatesMeanMedianMode", mn != md and md != mo),   # the distribution shape is captured
        ("opponentBasisInvertible", abs(int(round(np.linalg.det(basis)))) != 0),
        ("deltaOfIdenticalFramesIsZero", delta_energy(*flat, *flat, Lw) == 0.0),
        ("entropyNonNegative", all(frame_facets(*flat)[n]["entropy"] >= 0.0 for n in PROJECTIONS)),
    ]
    print("frame_stats.py  -- abstracted facets: projection x average x time (sRGB, Lab deprecated)")
    print("-" * 78)
    for name, ok in laws:
        print(("PASS" if ok else "FAIL") + "  " + name)
    print("-" * 78)
    passed = sum(1 for _, ok in laws if ok)
    total = len(laws)
    print(f"SUMMARY: {passed}/{total} checks PASS" + ("  (all green)" if passed == total else "  (FAILURES)"))
    print(f"\nskew demo (luma): mean={mn:.1f} > median={md:.1f} > mode={mo:.1f}   (mean-mode = skew)")
    return 0 if passed == total else 1


def plot_facets(frames, path: str) -> str:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    ft = facet_tensor(frames)
    n = len(frames)
    t = np.arange(n)
    fig, axes = plt.subplots(3, 1, figsize=(11, 11))

    # Panel 1: the three averages of luma diverge (mean/median/mode over time)
    for s, col in zip(STATISTICS, ["C0", "C1", "C2"]):
        axes[0].plot(t, [ft["per_frame"][i]["L=R+G+B"][f"{s}_centre"] for i in t], marker="o", label=f"{s} (L{['2','1','0'][STATISTICS.index(s)]})", color=col)
    axes[0].set_title("the averages diverge: luma mean / median / mode over time")
    axes[0].set_xlabel("frame (time)"); axes[0].set_ylabel("luma centre"); axes[0].legend(); axes[0].grid(alpha=0.3)

    # Panel 2: categorised residual energy (L2) for the RGB opponent contrast channels
    for name, col in [("a=R-G", "C3"), ("b=R+G-2B", "C4"), ("L=R+G+B", "0.5")]:
        axes[1].plot(t, [ft["per_frame"][i][name]["mean_energy"] for i in t], marker="s", label=name, color=col)
    axes[1].set_title("categorised energy: residual (L2) per projection  (a, b = RGB opponent contrasts)")
    axes[1].set_xlabel("frame (time)"); axes[1].set_ylabel("residual energy"); axes[1].legend(); axes[1].grid(alpha=0.3)

    # Panel 3: momentum = inter-frame delta energy of luma, with the CYCLIC seam marked
    deltas, seam = momentum_series(frames, PROJECTIONS["L=R+G+B"])
    axes[2].plot(np.arange(1, n), deltas, marker="o", color="C0", label="delta energy (momentum)")
    axes[2].scatter([n], [seam], color="red", s=160, marker="*", zorder=3, label="cyclic seam (N-1 -> 0)")
    axes[2].axhline(np.mean(deltas), color="0.7", ls="--", lw=1)
    axes[2].set_title("momentum: inter-frame delta energy + the loop discontinuity (the GIF is cyclic)")
    axes[2].set_xlabel("frame transition"); axes[2].set_ylabel("delta energy"); axes[2].legend(); axes[2].grid(alpha=0.3)

    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


def main() -> None:
    rc = _self_check()
    frames = _demo_frames(_palette())
    out = "/private/tmp/claude-501/-Users-daniel/377d723e-d53b-4d6f-851b-166f3fa21dea/scratchpad/frame_stats_demo.png"
    try:
        plot_facets(frames, out)
        print(f"plot written: {out}")
    except Exception as exc:  # pragma: no cover
        print(f"plot skipped ({exc})")
    raise SystemExit(rc)


if __name__ == "__main__":
    main()
