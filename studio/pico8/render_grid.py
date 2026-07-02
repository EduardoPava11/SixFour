#!/usr/bin/env python3
"""Headless full-RGB renderer + parity harness for the cell grid.

Reads the pinned constants straight from the Haskell spec (so it is always
spec-accurate), ports Lattice.cellOnScreen, then:

  * --verify : re-checks the four proven laws (symmetry, corner monotonicity,
               spans-screen, widgets-clear-corners) over the Python port,
               a cross-language parity check against what cabal test proves.
  * (default): also writes true-RGB PNGs you can open without any PICO-8,
               cellgrid_overview.png (whole phone) + cellgrid_corner.png (zoom).

Zero third-party deps: PNG is emitted via stdlib zlib/struct.

Usage:
  python3 studio/pico8/render_grid.py            # verify + render PNGs
  python3 studio/pico8/render_grid.py --verify   # verify only (a CI gate)
"""
import struct
import sys
import zlib
from pathlib import Path

from check_sync import LATTICE, GRIDLAYOUT, hs_int, hs_regions

HERE = Path(__file__).resolve().parent

# spec constants ----------------------------------------------------------
lat = LATTICE.read_text()
grid = GRIDLAYOUT.read_text()
GIFPX = hs_int(lat, "gifPx")
COLS = hs_int(lat, "screenWidthPt") // GIFPX
ROWS = hs_int(lat, "screenHeightPt") // GIFPX
CORNER_R = hs_int(lat, "cornerRadiusPt") // GIFPX
CORNER_N = hs_int(lat, "cornerExponent")
RAD_HALF = 2 * CORNER_R
SAFE_TOP_R = 62 // GIFPX
SAFE_BOT_R = 34 // GIFPX
_regions = hs_regions(grid)
PREVIEW = dict(zip("col row w h".split(), _regions[0]))
PALETTE = dict(zip("col row w h".split(), _regions[1]))

# All named scenes, parsed from the spec (captureScene / decisionScene /
# curateScene / ...): scene -> [(widget, {col,row,w,h,inter})], file order.
import re as _re

def hs_scenes(text: str):
    scenes = {}
    for m in _re.finditer(r"^(\w+Scene) :: Scene\n\1 =\n(.*?)^\s*\]", text,
                          _re.MULTILINE | _re.DOTALL):
        name, body = m.group(1), m.group(2)
        widgets = []
        for wm in _re.finditer(
                r'\("(\w+)",\s*LRegion \{ lrCol = (\d+), lrRow = (\d+),\s*'
                r'lrW = (\d+), lrH = (\d+)[^}]*lrInteractive = (True|False)',
                body, _re.DOTALL):
            widgets.append((wm.group(1),
                            dict(col=int(wm.group(2)), row=int(wm.group(3)),
                                 w=int(wm.group(4)), h=int(wm.group(5)),
                                 inter=wm.group(6) == "True")))
        scenes[name] = widgets
    return scenes

SCENES = hs_scenes(grid)

# vivid per-widget palette (index order within a scene)
WIDGET_RGB = [
    (60, 200, 120), (220, 64, 64), (70, 130, 240), (240, 200, 60),
    (200, 90, 220), (80, 210, 210), (240, 130, 50), (150, 150, 150),
]

# real-RGB representation (not limited to PICO-8's 16) --------------------
RGB = {
    "off":     (0, 0, 0),
    "on":      (20, 24, 40),
    "safe":    (64, 42, 84),
    "preview": (60, 200, 120),
    "palette": (220, 64, 64),
}


def on_screen(c: int, r: int) -> bool:
    """Line-for-line port of SixFour.Spec.Lattice.cellOnScreen (n==2 exact)."""
    if not (0 <= c < COLS and 0 <= r < ROWS):
        return False
    dc = max(0, RAD_HALF - (2 * min(c, COLS - 1 - c) + 1))
    dr = max(0, RAD_HALF - (2 * min(r, ROWS - 1 - r) + 1))
    if dc == 0 or dr == 0:
        return True
    if CORNER_N == 2:
        return dc * dc + dr * dr <= RAD_HALF * RAD_HALF
    return (dc / RAD_HALF) ** CORNER_N + (dr / RAD_HALF) ** CORNER_N <= 1


def in_rect(c: int, r: int, w: dict) -> bool:
    return w["col"] <= c < w["col"] + w["w"] and w["row"] <= r < w["row"] + w["h"]


def cell_class(c: int, r: int) -> str:
    if not on_screen(c, r):
        return "off"
    if in_rect(c, r, PREVIEW):
        return "preview"
    if in_rect(c, r, PALETTE):
        return "palette"
    if r < SAFE_TOP_R or r >= ROWS - SAFE_BOT_R:
        return "safe"
    return "on"


# parity harness: the four proven laws, re-checked on the Python port ------
def verify() -> bool:
    checks = []

    sym = all(on_screen(c, r) == on_screen(COLS - 1 - c, r) == on_screen(c, ROWS - 1 - r)
              for r in range(ROWS) for c in range(COLS))
    checks.append(("corners symmetric (H+V mirror)", sym))

    def in_box(c, r):
        return min(c, COLS - 1 - c) < CORNER_R and min(r, ROWS - 1 - r) < CORNER_R
    spans = (any(on_screen(0, r) for r in range(ROWS))
             and any(on_screen(COLS - 1, r) for r in range(ROWS))
             and any(on_screen(c, 0) for c in range(COLS))
             and any(on_screen(c, ROWS - 1) for c in range(COLS))
             and all(on_screen(c, r) for r in range(ROWS) for c in range(COLS)
                     if not in_box(c, r)))
    checks.append(("grid spans whole screen (clip in corners only)", spans))

    mono = all((not on_screen(c, r) or (on_screen(c + 1, r) and on_screen(c, r + 1)))
               for c in range(CORNER_R) for r in range(CORNER_R))
    checks.append(("corner is a clean monotone arc", mono))

    def clears(w):
        return all(on_screen(c, r)
                   for r in range(w["row"], w["row"] + w["h"])
                   for c in range(w["col"], w["col"] + w["w"]))
    all_widgets = [w for ws in SCENES.values() for _, w in ws] or [PREVIEW, PALETTE]
    checks.append(("widgets clear the corners (ALL scenes)",
                   all(clears(w) for w in all_widgets)))

    corner_clipped = not on_screen(0, 0)
    checks.append(("physical corner (0,0) is clipped", corner_clipped))

    ok = all(p for _, p in checks)
    print(f"parity harness (Python port of cellOnScreen, n={CORNER_N}):")
    for name, p in checks:
        print(f"  [{'PASS' if p else 'FAIL'}] {name}")
    clipped = sum(1 for r in range(ROWS) for c in range(COLS) if not on_screen(c, r))
    print(f"  clipped cells total: {clipped}  (~{clipped // 4} per corner)")
    print("  => IN PARITY with the proven laws" if ok else "  => PARITY BROKEN")
    return ok


# minimal stdlib PNG writer (RGB, 8-bit) ----------------------------------
def write_png(path: Path, w: int, h: int, rgb: bytearray) -> None:
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))
    raw = bytearray()
    for y in range(h):
        raw.append(0)                       # filter type 0 (none)
        raw += rgb[y * w * 3:(y + 1) * w * 3]
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)   # color type 2 = RGB
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", ihdr)
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                     + chunk(b"IEND", b""))


def scene_cell_class(scene_widgets, c, r):
    """off / safe / on / widget index for one scene's overview."""
    if not on_screen(c, r):
        return "off"
    for i, (_, w) in enumerate(scene_widgets):
        if in_rect(c, r, w):
            return i
    if r < SAFE_TOP_R or r >= ROWS - SAFE_BOT_R:
        return "safe"
    return "on"


def render_scene(path, scene_widgets, scale=3):
    W, H = COLS * scale, ROWS * scale
    buf = bytearray(W * H * 3)
    for ry in range(ROWS):
        for rx in range(COLS):
            cls = scene_cell_class(scene_widgets, rx, ry)
            col = WIDGET_RGB[cls % len(WIDGET_RGB)] if isinstance(cls, int) else RGB[cls]
            for dy in range(scale):
                base = ((ry * scale + dy) * W + rx * scale) * 3
                for dx in range(scale):
                    off = base + dx * 3
                    buf[off:off + 3] = bytes(col)
    write_png(path, W, H, buf)
    print(f"  wrote {path.name}  ({W}x{H})")


def render_region(path, c0, r0, cw, ch, scale):
    W, H = cw * scale, ch * scale
    buf = bytearray(W * H * 3)
    for ry in range(ch):
        for rx in range(cw):
            col = RGB[cell_class(c0 + rx, r0 + ry)]
            for dy in range(scale):
                base = ((ry * scale + dy) * W + rx * scale) * 3
                for dx in range(scale):
                    off = base + dx * 3
                    buf[off:off + 3] = bytes(col)
    write_png(path, W, H, buf)
    print(f"  wrote {path.name}  ({W}x{H})")


def main() -> int:
    ok = verify()
    if "--verify" not in sys.argv:
        print("rendering:")
        render_region(HERE / "cellgrid_overview.png", 0, 0, COLS, ROWS, 3)
        span = RAD_HALF
        render_region(HERE / "cellgrid_corner.png", 0, 0, span, span, 10)
        for sname, widgets in SCENES.items():
            render_scene(HERE / f"cellgrid_{sname.removesuffix('Scene')}.png", widgets)
            print(f"    {sname}: " + ", ".join(
                f"{n}=({w['col']},{w['row']}) {w['w']}x{w['h']}" for n, w in widgets))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
