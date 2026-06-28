"""Byte-exact Python port of Spec.Upscale256.upscale256 = Spec.ModelIO.buildFloor.

The deterministic 64^3 -> 256^3 endgame (recompute, never interpolate). This is THE floor the
learned PonderNet invention must beat: Phase 5's above-floor margin is measured against THIS, not a
zero baseline. Integers only (Q16), so the port is byte-identical to the Haskell oracle; the gate
(test_upscale256.py vs trainer/out/upscale256_golden.json) enforces it.

Faithful port of spec/src/SixFour/Spec/Upscale256.hs. Arithmetic shift `>> 2` matches Haskell's
signed `shiftR` (both floor toward -inf). Ties resolve to the LOWEST index everywhere (strict `<`).
"""
from __future__ import annotations

PRIOR_UNIT = 65536          # Spec.Upscale256.priorUnit
UPSCALE_FACTOR = 4          # 64 -> 256 in space AND time
EXIT_SLOT_COUNT = 256       # Spec.AtlasCascade.exitSlotCount


def _sign(x: int) -> int:
    return (x > 0) - (x < 0)


def dist_sq_q16(a, b) -> int:
    dl, da, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return dl * dl + da * da + db * db


def nearest_q16(pal, x) -> int:
    """argmin dist; ties -> lowest index. Empty palette -> 0."""
    if not pal:
        return 0
    bi, bd = 0, dist_sq_q16(x, pal[0])
    for i in range(1, len(pal)):
        d = dist_sq_q16(x, pal[i])
        if d < bd:
            bi, bd = i, d
    return bi


def align_slots(mt, mn, pt, pn):
    """sigma_t: lowest slot of P_{t+1} sharing a paletteMap image; else nearestQ16 fallback."""
    sigma = []
    for j, c in enumerate(pt):
        g = mt[j] if j < len(mt) else None
        match = None
        if g is not None:
            for jp, gp in enumerate(mn):
                if gp == g:
                    match = jp
                    break
        sigma.append(match if match is not None else nearest_q16(pn, c))
    return sigma


def blend_px_q16(k, a, b):
    """((4-k)*x + k*y) >> 2, componentwise (exact arithmetic shift)."""
    return tuple(((4 - k) * a[i] + k * b[i]) >> 2 for i in range(3))


def blend_palettes_q16(k, pt, pn, sigma):
    def index(ps, i):
        return ps[i] if 0 <= i < len(ps) else (0, 0, 0)
    return [blend_px_q16(k, c, index(pn, jp)) for c, jp in zip(pt, sigma)]


def apply_anchors(anchors, pal0):
    """Substitute each anchor verbatim into its nearest not-yet-anchored slot (ties -> lowest)."""
    pal = list(pal0)
    anchor_set = list(anchors)
    for a in anchor_set[:len(pal0)]:
        taken = {i for i, c in enumerate(pal) if c in anchor_set and c != a}
        free = [(i, c) for i, c in enumerate(pal) if i not in taken]
        if not free:
            continue
        bj, bd = free[0][0], dist_sq_q16(a, free[0][1])
        for i, c in free[1:]:
            d = dist_sq_q16(a, c)
            if d < bd:
                bj, bd = i, d
        pal = [a if i == bj else c for i, c in enumerate(pal)]
    return pal


def drift_prior(exit_drift, m, pal, x, j) -> int:
    """Carried drift agreement of slot j's M-image, scaled by PRIOR_UNIT. Out-of-range -> 0.

    exit_drift: dict {global_slot: (dL, dA, dB)} (zero slots omitted).
    """
    if j < 0 or j >= len(pal) or j >= len(m):
        return 0
    g = m[j]
    if g < 0 or g >= EXIT_SLOT_COUNT:
        return 0
    dl, da, db = exit_drift.get(g, (0, 0, 0))
    pl, pa, pb = pal[j]

    def agree(rate, diff):
        return 1 if rate != 0 and _sign(rate) == _sign(diff) else 0

    agreement = agree(dl, x[0] - pl) + agree(da, x[1] - pa) + agree(db, x[2] - pb)
    return PRIOR_UNIT * agreement


def quantize_prior_among(lam, pal, prior_fn, cands, x) -> int:
    """argmin_j d^2(x, pal[j]) - lam*prior(j) over valid candidates; ties -> lowest candidate."""
    valid = [j for j in cands if 0 <= j < len(pal)]
    if not valid:
        return 0

    def score(j):
        return dist_sq_q16(x, pal[j]) - lam * prior_fn(j)

    bj = valid[0]
    bs = score(bj)
    for j in valid[1:]:
        s = score(j)
        if s < bs:
            bj, bs = j, s
    return bj


def upscale256(inp):
    """The deterministic re-render. `inp` is the golden's 'input' dict (or build_floor's output).

    Returns {"palettes": [[ (l,a,b) ... ] ...], "cube": [[int ...] ...]} — 4T frames each (4S)^2.
    """
    tN = inp["frames"]
    s = inp["side"]
    s_out = UPSCALE_FACTOR * s
    palettes = [[tuple(px) for px in frame] for frame in inp["palettes"]]
    pmap = inp["map"]
    glob = [tuple(px) for px in inp["global"]]
    cube_b = inp["cubeB"]
    cube_a = inp["cubeA"]
    kill_threshold = inp["killThreshold"]
    exit_drift = {row[0]: (row[1], row[2], row[3]) for row in inp["exitDrift"]}
    anchors = [tuple(px) for px in inp["anchors"]]
    lam = inp["lambda"]

    def at(ps, i):
        return ps[i] if 0 <= i < len(ps) else (0, 0, 0)

    def killed(px):
        return px[0] > kill_threshold

    out_palettes = []
    out_cube = []
    for t in range(tN):
        for k in range(UPSCALE_FACTOR):
            tn = min(t + 1, tN - 1)
            pt, pn = palettes[t], palettes[tn]
            mt, mn = pmap[t], pmap[tn]
            sigma = align_slots(mt, mn, pt, pn)
            p_prime = apply_anchors(anchors, blend_palettes_q16(k, pt, pn, sigma))

            def b_at(fr, yy, xx):
                y_cl = max(0, min(s - 1, yy))
                x_cl = max(0, min(s - 1, xx))
                return cube_b[fr][y_cl * s + x_cl]

            plane = []
            for pix in range(s_out * s_out):
                y_o, x_o = pix // s_out, pix % s_out
                y, x = y_o // UPSCALE_FACTOR, x_o // UPSCALE_FACTOR
                j0 = b_at(t, y, x)
                ct = at(pt, j0)
                cn = at(pn, b_at(tn, y, x))
                xb = blend_px_q16(k, ct, cn)
                xc = at(glob, cube_a[t][y * s + x]) if killed(xb) else xb
                cands = sorted(set(
                    [j0] + [b_at(t, y + dy, x + dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
                ))
                idx = quantize_prior_among(
                    lam, p_prime, lambda j: drift_prior(exit_drift, mt, p_prime, xc, j), cands, xc)
                plane.append(idx)
            out_palettes.append(p_prime)
            out_cube.append(plane)
    return {"palettes": out_palettes, "cube": out_cube}
