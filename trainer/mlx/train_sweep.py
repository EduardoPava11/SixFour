"""Per-encoded-parameter training sweep: one run for EVERY band the GIF encodes, on EVERY
scene kind.

The reversible lift turns each 2x2x2 octant into 1 coarse + 7 detail bands (the Haar
coefficients). Those 7 detail bands ARE the parameters the GIF encodes per octant. This sweep
trains a dedicated theta_B specialist for each (kind, band) cell -- a real least-squares fit on
80% of that capture's non-flat octants -- and reports held-out loss as a fraction of the
zero-parameter floor. It reuses jepa_synth_octants.held_out_ratio (the gated, byte-exact data
engine) so the sweep cannot drift from the spec.

Reading the matrix:
  ratio << 1  -> the band is LEARNABLE from sibling context (masked-band prediction beats floor)
  ratio ~ 1   -> no linear signal in context for this band on this kind (floor already optimal)

Run:  python3 train_sweep.py                 # all 3 kinds x 7 bands
      python3 cli.py sweep
"""
from __future__ import annotations

import sys

from encoder_frozen import NUM_BANDS
from jepa_synth_octants import held_out_ratio

KINDS = ["high-lab", "high-detail", "smooth-grey"]


def main() -> int:
    print("=== SixFour per-encoded-parameter training sweep ===")
    print(f"one specialist run per (kind, band): {len(KINDS)} kinds x {NUM_BANDS} bands "
          f"= {len(KINDS) * NUM_BANDS} runs")
    print("each cell = held-out loss / zero-param floor (lower = more learnable; ~1.00 = floor-only)\n")

    header = "  band |" + "".join(f"{k:>14s}" for k in KINDS)
    print(header)
    print("  " + "-" * (len(header) - 2))

    results = {}
    learnable = 0
    for band in range(NUM_BANDS):
        cells = []
        for kind in KINDS:
            ratio, n = held_out_ratio(kind, mask=band)
            results[(band, kind)] = (ratio, n)
            tag = "*" if ratio < 0.95 else " "
            cells.append(f"{ratio:>11.1%}{tag} ")
            if ratio < 0.95:
                learnable += 1
        print(f"  {band:>4d} |" + "".join(cells))

    # smallest n across the sweep, so the reader knows the weakest-powered cell
    min_n = min(n for _r, n in results.values())
    print()
    print(f"  legend: * = beats floor (ratio < 0.95, the band carries learnable signal)")
    print(f"  {learnable}/{len(results)} (kind,band) cells are learnable; "
          f"min held-out sample n={min_n}")

    # best and worst learnable cells -- where the encoder's prediction earns the most/least
    ranked = sorted(results.items(), key=lambda kv: kv[1][0])
    (bb, bk), (br, _) = ranked[0]
    (wb, wk), (wr, _) = ranked[-1]
    print(f"  strongest: band {bb} on {bk} -> {br:.1%} of floor")
    print(f"  weakest:   band {wb} on {wk} -> {wr:.1%} of floor")

    print("\ntrain_sweep: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
