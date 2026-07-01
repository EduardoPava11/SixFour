#!/usr/bin/env python3
"""Verify the PICO-8 cell-grid cart mirrors the Haskell spec.

PICO-8 is the look/demo sketchpad; the Haskell spec is the source of truth.
This guard parses the pinned constants out of both and fails loudly if the
cart has drifted from spec/src/SixFour/Spec/{Lattice,GridLayout}.hs, the
"inform Haskell first" discipline, applied to the sketchpad too.

Usage:  python3 studio/pico8/check_sync.py
Exit 0 = in sync, exit 1 = drift (prints the mismatches).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # .../SixFour
LATTICE = ROOT / "spec/src/SixFour/Spec/Lattice.hs"
GRIDLAYOUT = ROOT / "spec/src/SixFour/Spec/GridLayout.hs"
CART = ROOT / "studio/pico8/cellgrid.p8"


def die(msg: str) -> "None":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(2)


def hs_int(text: str, name: str) -> int:
    """Read a top-level `name = <int>` binding from a Haskell module."""
    m = re.search(rf"^{name}\s*=\s*(\d+)\b", text, re.MULTILINE)
    if not m:
        die(f"could not find `{name}` in the spec")
    return int(m.group(1))


def hs_regions(text: str):
    """Read the (lrCol,lrRow,lrW,lrH) tuples from GridLayout.captureScene, in order."""
    return [tuple(map(int, t)) for t in re.findall(
        r"lrCol\s*=\s*(\d+),\s*lrRow\s*=\s*(\d+),\s*lrW\s*=\s*(\d+),\s*lrH\s*=\s*(\d+)",
        text)]


def cart_int(text: str, name: str) -> int:
    m = re.search(rf"^{name}\s*=\s*(\d+)\b", text, re.MULTILINE)
    if not m:
        die(f"could not find `{name}` in the cart")
    return int(m.group(1))


def cart_widget(text: str, name: str):
    m = re.search(
        rf"{name}\s*=\s*{{col=(\d+),\s*row=(\d+),\s*w=(\d+),\s*h=(\d+)", text)
    if not m:
        die(f"could not find widget `{name}` in the cart")
    return tuple(map(int, m.groups()))


def main() -> int:
    for p in (LATTICE, GRIDLAYOUT, CART):
        if not p.exists():
            die(f"missing file: {p}")

    lat = LATTICE.read_text()
    grid = GRIDLAYOUT.read_text()
    cart = CART.read_text()

    # spec side
    spec = {
        "screen_w_pt": hs_int(lat, "screenWidthPt"),
        "screen_h_pt": hs_int(lat, "screenHeightPt"),
        "gifpx":       hs_int(lat, "gifPx"),
        "corner_pt":   hs_int(lat, "cornerRadiusPt"),
        "corner_n":    hs_int(lat, "cornerExponent"),
        "touch":       hs_int(lat, "touchFloorCells"),
    }
    regions = hs_regions(grid)
    if len(regions) < 2:
        die("expected >= 2 regions in captureScene")
    spec["preview"], spec["palette"] = regions[0], regions[1]

    # cart side
    cartv = {
        "screen_w_pt": cart_int(cart, "scr_w_pt"),
        "screen_h_pt": cart_int(cart, "scr_h_pt"),
        "gifpx":       cart_int(cart, "gifpx"),
        "corner_pt":   cart_int(cart, "corner_pt"),
        "corner_n":    cart_int(cart, "corner_n"),
        "touch":       cart_int(cart, "touch"),
        "preview":     cart_widget(cart, "preview"),
        "palette":     cart_widget(cart, "palette"),
    }

    mismatches = [(k, spec[k], cartv[k]) for k in spec if spec[k] != cartv[k]]

    # derived sanity: both must agree on the tiled grid + corner-in-cells
    d_spec = (spec["screen_w_pt"] // spec["gifpx"],
              spec["screen_h_pt"] // spec["gifpx"],
              spec["corner_pt"] // spec["gifpx"])
    d_cart = (cartv["screen_w_pt"] // cartv["gifpx"],
              cartv["screen_h_pt"] // cartv["gifpx"],
              cartv["corner_pt"] // cartv["gifpx"])
    if d_spec != d_cart:
        mismatches.append(("derived cols/rows/corner_cells", d_spec, d_cart))

    if mismatches:
        print("PICO-8 cart is OUT OF SYNC with the spec:\n")
        for name, s, c in mismatches:
            print(f"  {name:32}  spec={s}  cart={c}")
        print("\nfix studio/pico8/cellgrid.p8 to match the spec, then re-run.")
        return 1

    cols, rows, cr = d_spec
    print("PICO-8 cart is IN SYNC with the spec.")
    print(f"  grid {cols}x{rows} @ {spec['gifpx']}pt  corner r={cr} cells "
          f"({spec['corner_pt']}pt)  n={spec['corner_n']}")
    print(f"  preview {spec['preview']}  palette {spec['palette']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
