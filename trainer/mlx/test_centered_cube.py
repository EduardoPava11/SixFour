"""Compression sanity test: a 64-cubed volume with a solid cube in the middle, run through the
reversible octree lift (jepa_data.lift_oct, the gated data engine), should collapse to the 16-cubed
COARSE level with (near-)ZERO detail -- the content lives at coarse scale, the lift "spends bits"
only on the cube's surface.

The octree lift is Haar-like: a CONSTANT 2x2x2 block produces (coarse = the value, detail = all
zeros). So on a solid cube over a solid background, every block is fully-inside or fully-outside
(zero detail); only the cube's SURFACE blocks carry detail. 64-cubed -> 16-cubed is a 4x downsample
per axis (two lift levels), so:

  * a centered 4x4x4 block  -> exactly ONE black pixel in the 16-cubed coarse, ZERO detail.
  * a centered 16x16x16 block -> a 4x4x4 black region in the 16-cubed coarse, ZERO detail.

Both are LOSSLESS (reconstruct == input) because the lift is a bijection. Run:
  python3 test_centered_cube.py            # prints the compression report
  python3 test_centered_cube.py --gif      # also writes input + coarse GIFs to trainer/out/cube_test/
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from jepa_data import lift_oct, unlift_oct  # noqa: E402  (the gated reversible data engine)

BG, FG = 255, 0   # background = white, cube = black


def make_volume(side: int, cube: int, value_bg: int = BG, value_fg: int = FG) -> np.ndarray:
    """A side^3 volume (axes = frame, x, y): solid value_bg with a centered cube^3 of value_fg,
    aligned to the 4-voxel octree grid so the cube falls on whole coarse cells."""
    v = np.full((side, side, side), value_bg, dtype=np.int64)
    lo = ((side - cube) // 2) & ~3   # align the start to a multiple of 4
    hi = lo + cube
    v[lo:hi, lo:hi, lo:hi] = value_fg
    return v


def distill(vol: np.ndarray):
    """One reversible octree level: side^3 -> (coarse (side/2)^3, detail (side/2)^3 x 7) by running
    jepa_data.lift_oct on each 2x2x2 block (frame-pair x 2x2 spatial)."""
    s = vol.shape[0]
    h = s // 2
    coarse = np.zeros((h, h, h), dtype=np.int64)
    detail = np.zeros((h, h, h, 7), dtype=np.int64)
    for F in range(h):
        for X in range(h):
            for Y in range(h):
                blk = [int(vol[2*F, 2*X, 2*Y]),   int(vol[2*F, 2*X+1, 2*Y]),
                       int(vol[2*F, 2*X, 2*Y+1]), int(vol[2*F, 2*X+1, 2*Y+1]),
                       int(vol[2*F+1, 2*X, 2*Y]),   int(vol[2*F+1, 2*X+1, 2*Y]),
                       int(vol[2*F+1, 2*X, 2*Y+1]), int(vol[2*F+1, 2*X+1, 2*Y+1])]
                c, d = lift_oct(blk)
                coarse[F, X, Y] = c
                detail[F, X, Y] = d
    return coarse, detail


def synthesize(coarse: np.ndarray, detail: np.ndarray) -> np.ndarray:
    """The exact inverse of distill: (side/2)^3 coarse + detail -> side^3 volume (unlift each block)."""
    h = coarse.shape[0]
    s = h * 2
    vol = np.zeros((s, s, s), dtype=np.int64)
    for F in range(h):
        for X in range(h):
            for Y in range(h):
                a, b, c, d, e, f, g, hh = unlift_oct(int(coarse[F, X, Y]), [int(x) for x in detail[F, X, Y]])
                vol[2*F, 2*X, 2*Y], vol[2*F, 2*X+1, 2*Y] = a, b
                vol[2*F, 2*X, 2*Y+1], vol[2*F, 2*X+1, 2*Y+1] = c, d
                vol[2*F+1, 2*X, 2*Y], vol[2*F+1, 2*X+1, 2*Y] = e, f
                vol[2*F+1, 2*X, 2*Y+1], vol[2*F+1, 2*X+1, 2*Y+1] = g, hh
    return vol


def compress_to_16(vol: np.ndarray):
    """Two reversible levels: 64 -> 32 -> 16. Returns (coarse16, [detail_l1, detail_l2])."""
    c1, d1 = distill(vol)     # 64 -> 32
    c2, d2 = distill(c1)      # 32 -> 16
    return c2, [d1, d2]


def reconstruct_from_16(coarse16: np.ndarray, details) -> np.ndarray:
    """Invert both levels: 16 -> 32 -> 64."""
    d1, d2 = details
    c1 = synthesize(coarse16, d2)   # 16 -> 32
    return synthesize(c1, d1)       # 32 -> 64


def report(label: str, side: int, cube: int) -> bool:
    vol = make_volume(side, cube)
    coarse16, details = compress_to_16(vol)
    detail_energy = sum(int(np.abs(d).sum()) for d in details)
    recon = reconstruct_from_16(coarse16, details)
    lossless = bool(np.array_equal(recon, vol))
    black_cells = int((coarse16 == FG).sum())
    total_voxels = side ** 3

    print(f"--- {label}: {side}^3 volume, centered {cube}^3 black cube ---")
    print(f"  coarse 16^3: {black_cells} black cell(s) of {16**3} "
          f"(the cube at coarse scale; {cube}//4 = {cube//4} per axis -> {(cube//4)**3 if cube>=4 else 0} cells)")
    print(f"  detail energy (sum |detail| over BOTH levels): {detail_energy}  "
          f"{'(ZERO -> perfect, the content is purely coarse)' if detail_energy == 0 else '(nonzero -> boundary bits)'}")
    print(f"  lossless round-trip (reconstruct == input): {lossless}")
    nonzero_coarse = int((coarse16 != BG).sum())
    print(f"  compression: {total_voxels} voxels -> {nonzero_coarse} non-background coarse cell(s) "
          f"+ {detail_energy} detail  (ratio ~{total_voxels // max(1, nonzero_coarse)}x on the cube)")
    return lossless and detail_energy == 0


def write_gifs(side: int = 64, cube: int = 16):
    """Write the input 64^3 and the coarse 16^3 as grayscale GIFs for visual inspection."""
    try:
        from PIL import Image
    except Exception:
        print("  [skip GIF] Pillow not available"); return
    outdir = os.path.join(os.path.dirname(__file__), "..", "out", "cube_test")
    os.makedirs(outdir, exist_ok=True)
    vol = make_volume(side, cube)
    coarse16, _ = compress_to_16(vol)

    def save(vol3, path, scale):
        frames = [Image.fromarray(np.clip(vol3[f], 0, 255).astype(np.uint8), "L").resize(
            (vol3.shape[1] * scale, vol3.shape[2] * scale), Image.NEAREST) for f in range(vol3.shape[0])]
        # optimize=False / disposal=2 so identical white frames are NOT collapsed (keep all frames).
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=50, loop=0,
                       optimize=False, disposal=2)

    def montage(vol3, path, scale):
        """All frames laid out in a grid (one PNG) so the whole volume is visible at a glance."""
        n = vol3.shape[0]
        cols = int(np.ceil(np.sqrt(n)))
        rows = int(np.ceil(n / cols))
        s = vol3.shape[1] * scale
        sheet = np.full((rows * s, cols * s), 200, dtype=np.uint8)  # grey gutter
        for f in range(n):
            r, c = divmod(f, cols)
            tile = np.clip(vol3[f], 0, 255).astype(np.uint8).repeat(scale, 0).repeat(scale, 1)
            sheet[r*s:r*s+vol3.shape[1]*scale, c*s:c*s+vol3.shape[2]*scale] = tile
        Image.fromarray(sheet, "L").save(path)

    in_path = os.path.join(outdir, f"input_{side}cubed_{cube}cube.gif")
    co_path = os.path.join(outdir, "coarse_16cubed.gif")
    co_montage = os.path.join(outdir, "coarse_16cubed_montage.png")
    save(vol, in_path, 4)          # 64x64 frames upscaled x4 for visibility
    save(coarse16, co_path, 16)    # 16x16 frames upscaled x16
    montage(coarse16, co_montage, 12)   # all 16 coarse frames in one image
    print(f"  wrote {in_path}  ({vol.shape[0]} frames)")
    print(f"  wrote {co_path}  ({coarse16.shape[0]} frames; black region = the cube, on white; detail is zero)")
    print(f"  wrote {co_montage}  (all 16 coarse frames at a glance)")


if __name__ == "__main__":
    print("=== Octree compression sanity: solid cube in the middle of a 64^3 volume ===\n")
    ok1 = report("one-pixel", 64, 4)     # 4^3 block -> exactly ONE black coarse pixel
    print()
    ok2 = report("user-case", 64, 16)    # 16^3 block -> 4x4x4 black coarse region
    print()
    print("Both lossless + zero-detail (the cube is purely coarse-scale structure)."
          if (ok1 and ok2) else "UNEXPECTED: a case was not lossless/zero-detail.")
    if "--gif" in sys.argv:
        print("\nwriting GIFs:")
        write_gifs(64, 16)
    raise SystemExit(0 if (ok1 and ok2) else 1)
