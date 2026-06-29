"""
frame_energy.py -- a V2 diagnostic tool: per-frame ENERGY and ENTROPY over time.

The premise: models are averaging machines. The coarse output is the MEAN; everything
else is deviation from that average = the residual. So a frame's ENERGY is its residual
energy: the mean squared deviation of its pixels from the frame's OWN mean colour, in
sRGB 8-bit (Lab is deprecated). Its ENTROPY is how that energy is SPREAD across the
per-frame palette: the Shannon entropy of slot usage (a frame can hold its energy in a
few dominant colours, low entropy, or scatter it across many, high entropy).

The tool plots normalized energy over time, coloured by entropy, so you can see which
frames hold more or less energy AND whether that energy is concentrated or diffuse.

A frame is GIF89a-native: (palette: (K,3) sRGB ints, index_map: (H,W) slot indices).
Energy is decomposed the V2 way via eisenstein.py: luma (the (1,1,1) average axis) +
Eisenstein A2 chroma. Run `python frame_energy.py` for the self-check + a demo plot.
"""

from __future__ import annotations
from typing import Tuple

import numpy as np

from eisenstein import enorm  # the V2 Eisenstein A2 chroma norm (sRGB-native, Lab dropped)

Palette = np.ndarray   # (K, 3) sRGB ints
IndexMap = np.ndarray  # (H, W) slot indices into the palette


# --- rendering -----------------------------------------------------------------

def render(palette: Palette, index_map: IndexMap) -> np.ndarray:
    """The GIF89a render: colour = palette[index]. Returns (H, W, 3) sRGB pixels."""
    return palette[index_map]


# --- energy: deviation from the average (the residual energy) -------------------

def frame_energy(palette: Palette, index_map: IndexMap) -> float:
    """Residual energy = mean squared deviation of the frame's pixels from their mean
    colour (the average the averaging-machine produces). Zero iff the frame is flat."""
    px = render(palette, index_map).reshape(-1, 3).astype(float)
    mean = px.mean(axis=0)
    dev = px - mean
    return float((dev * dev).sum(axis=1).mean())


def palette_capacity(palette: Palette) -> float:
    """The palette's OWN energy spread (variance of its colours). The normalizer: how much
    deviation the palette even makes available."""
    p = palette.astype(float)
    mean = p.mean(axis=0)
    dev = p - mean
    return float((dev * dev).sum(axis=1).mean()) + 1e-9


def frame_energy_normalized(palette: Palette, index_map: IndexMap) -> float:
    """Per-palette normalized energy in [0, ~1]: of the colour spread the palette offers,
    how much this frame actually uses. Comparable across frames with different palettes."""
    return frame_energy(palette, index_map) / palette_capacity(palette)


def energy_luma_chroma(palette: Palette, index_map: IndexMap) -> Tuple[float, float]:
    """The V2-native split of the residual energy: luma energy (deviation along the (1,1,1)
    average axis) + Eisenstein A2 chroma energy (the mean hexagonal norm of chroma deviation).
    Lab is deprecated; this is the sRGB / Z[w] decomposition."""
    px = render(palette, index_map).reshape(-1, 3).astype(int)
    lum = (px[:, 0] + px[:, 1] + px[:, 2]).astype(float)        # luma = (1,1,1) projection
    ca = (px[:, 0] - px[:, 2]).astype(float)                    # Eisenstein chroma coord a
    cb = (px[:, 1] - px[:, 2]).astype(float)                    # Eisenstein chroma coord b
    luma_e = float(lum.var())
    da = ca - ca.mean()
    db = cb - cb.mean()
    chroma_e = float((da * da - da * db + db * db).mean())      # mean N(dchroma), the A2 norm
    return luma_e, chroma_e


# --- entropy: how the energy is spread across the palette -----------------------

def frame_entropy(index_map: IndexMap, k: int = 256) -> float:
    """Normalized Shannon entropy of slot usage, in [0, 1]. 0 = one colour (concentrated);
    1 = all k slots used evenly (maximally diffuse). The 'effective colour count' meter."""
    counts = np.bincount(index_map.reshape(-1), minlength=k).astype(float)
    total = counts.sum()
    if total == 0:
        return 0.0
    p = counts / total
    p = p[p > 0]
    h = float(-(p * np.log2(p)).sum())
    return max(0.0, h / np.log2(k))    # clamp the -0.0 that a single-slot frame produces


# --- the tool: energy-vs-time, coloured by entropy ------------------------------

def frame_series(frames):
    """Compute (energy_norm, entropy, luma_e, chroma_e) per frame. frames = [(palette, index_map)]."""
    out = []
    for palette, idx in frames:
        e = frame_energy_normalized(palette, idx)
        h = frame_entropy(idx, k=palette.shape[0])
        le, ce = energy_luma_chroma(palette, idx)
        out.append((e, h, le, ce))
    return out


def plot_energy_time(frames, path: str, title: str = "Frame energy over time (coloured by entropy)") -> str:
    """Plot normalized energy vs frame index, each point coloured by its entropy. Saves a PNG."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    series = frame_series(frames)
    t = np.arange(len(series))
    energy = np.array([s[0] for s in series])
    entropy = np.array([s[1] for s in series])

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(t, energy, color="0.6", linewidth=1.0, zorder=1)
    sc = ax.scatter(t, energy, c=entropy, cmap="viridis", vmin=0, vmax=1, s=120, zorder=2, edgecolor="k")
    ax.set_xlabel("frame index (time)")
    ax.set_ylabel("normalized residual energy  (deviation from the mean)")
    ax.set_title(title)
    ax.grid(True, alpha=0.3)
    cbar = fig.colorbar(sc, ax=ax)
    cbar.set_label("entropy  (0 = concentrated, 1 = diffuse)")
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)
    return path


# ===========================================================================
# Demo + self-check (run: python frame_energy.py)
# ===========================================================================

def _gradient_palette(k: int = 256) -> Palette:
    """A 256-colour palette: a warm-to-cool ramp with luma and chroma spread."""
    i = np.arange(k)
    r = (i).astype(int)
    g = ((i * 7) % 256).astype(int)
    b = (255 - i).astype(int)
    return np.stack([r, g, b], axis=1)


def _demo_frames(pal: Palette, h: int = 32, w: int = 32):
    """A 16-frame narrative: flat -> two-tone (high energy, low entropy) -> diffuse
    (lower energy, high entropy) -> collapse back toward flat."""
    frames = []
    rng = np.random.default_rng(0)
    for t in range(16):
        if t < 3:                                   # flat: the average dominates
            idx = np.full((h, w), 128, dtype=int)
        elif t < 6:                                 # two-tone: distant colours, few slots
            idx = np.where(rng.random((h, w)) < 0.5, 0, 255).astype(int)
        elif t < 9:                                 # banded structure
            idx = ((np.arange(w)[None, :] * (t - 5) * 8) % 256 + np.zeros((h, 1), dtype=int)).astype(int)
        elif t < 12:                                # diffuse: many slots, evenly
            idx = rng.integers(0, 256, size=(h, w))
        else:                                       # collapse back toward flat
            spread = max(1, 64 - (t - 11) * 20)
            idx = (128 + rng.integers(-spread, spread + 1, size=(h, w))).clip(0, 255)
        frames.append((pal, idx.astype(int)))
    return frames


def _self_check() -> int:
    pal = _gradient_palette()
    h = w = 16
    flat = (pal, np.full((h, w), 100, dtype=int))
    two_tone = (pal, np.where(np.arange(h * w).reshape(h, w) % 2 == 0, 0, 255))
    all_slots = (pal, (np.arange(h * w) % 256).reshape(h, w))

    laws = [
        ("flatEnergyIsZero", frame_energy(*flat) == 0.0),
        ("variedEnergyPositive", frame_energy(*two_tone) > 0.0),
        ("flatEntropyIsZero", frame_entropy(flat[1], k=256) == 0.0),
        ("uniformEntropyIsMax", abs(frame_entropy(all_slots[1], k=256) - 1.0) < 1e-9),
        ("normalizedEnergyInRange", 0.0 <= frame_energy_normalized(*two_tone) <= 4.0),
        # the headline: two-tone holds MORE energy than the diffuse-all-slots frame, yet LESS entropy.
        ("energyVsEntropyOrthogonal",
         frame_energy(*two_tone) > frame_energy(*all_slots)
         and frame_entropy(two_tone[1], 256) < frame_entropy(all_slots[1], 256)),
    ]
    print("frame_energy.py  -- V2 diagnostic: per-frame energy + entropy over time")
    print("-" * 72)
    for name, ok in laws:
        print(("PASS" if ok else "FAIL") + "  " + name)
    print("-" * 72)
    passed = sum(1 for _, ok in laws if ok)
    total = len(laws)
    allg = "  (all green)" if passed == total else "  (FAILURES present)"
    print(f"SUMMARY: {passed}/{total} checks PASS{allg}")
    return 0 if passed == total else 1


def main() -> None:
    rc = _self_check()
    pal = _gradient_palette()
    frames = _demo_frames(pal)
    series = frame_series(frames)
    print()
    print("frame |  energy  | entropy |  luma_E  | chroma_E   (sRGB, Lab deprecated)")
    for t, (e, hh, le, ce) in enumerate(series):
        print(f"  {t:3d} | {e:7.4f}  |  {hh:5.3f}  | {le:8.1f} | {ce:8.1f}")
    out = "/private/tmp/claude-501/-Users-daniel/377d723e-d53b-4d6f-851b-166f3fa21dea/scratchpad/frame_energy_demo.png"
    try:
        plot_energy_time(frames, out)
        print(f"\nplot written: {out}")
    except Exception as exc:  # pragma: no cover
        print(f"\nplot skipped ({exc})")
    raise SystemExit(rc)


if __name__ == "__main__":
    main()
