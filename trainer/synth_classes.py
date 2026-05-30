"""synth_classes.py — CLASSIFICATION of the synthetic training corpus.

We do not train on captured data (synthetic-only, for now), so the regimen must
*span the quality envelope on purpose*. Each SynthClass is a named region of the
input space the L-NN nucleus must handle — a grey dynamic range × chroma × key
preset. The regimen samples a STRATIFIED corpus (equal per class) so training sees
the whole envelope, and the quality gate (gates.py) requires the NN to beat the
baseline on EVERY class, not just on average (variance-hardening).

A "class" is a deterministic generation preset (NOT a learned label): given
(class, seed) the capture is reproducible byte-for-byte on any M1.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Tuple

import zig_native as zn

_Q = zn.Q16


def _q(x: float) -> int:
    return int(round(x * _Q))


@dataclass(frozen=True)
class SynthClass:
    """A named region of the synthetic input envelope (a generation preset)."""
    name: str
    l_min: int          # grey dynamic-range floor (Q16)
    l_max: int          # grey dynamic-range ceiling (Q16)
    chroma_max: int     # chroma deviation bound (Q16); 0 = achromatic input
    mode: int           # zn.SYNTH_COLOR / SYNTH_GRAYSCALE


# The L-NN training envelope: COLOUR captures (the device input) across dynamic
# range, chroma, and key (overall lightness). Each class stresses a distinct
# failure mode the global-grayscale collapse must survive.
CLASSES: List[SynthClass] = [
    SynthClass("wide_color",   _q(0.05), _q(0.95), _q(0.28), zn.SYNTH_COLOR),  # full range, normal chroma
    SynthClass("wide_gray",    _q(0.05), _q(0.95), 0,        zn.SYNTH_COLOR),  # already achromatic input
    SynthClass("mid_color",    _q(0.25), _q(0.75), _q(0.20), zn.SYNTH_COLOR),  # compressed mid-tones
    SynthClass("narrow",       _q(0.38), _q(0.50), _q(0.12), zn.SYNTH_COLOR),  # very narrow DR (significance stress)
    SynthClass("lowkey",       _q(0.05), _q(0.45), _q(0.18), zn.SYNTH_COLOR),  # dark scenes
    SynthClass("highkey",      _q(0.55), _q(0.95), _q(0.18), zn.SYNTH_COLOR),  # bright scenes
    SynthClass("highchroma",   _q(0.15), _q(0.85), _q(0.32), zn.SYNTH_COLOR),  # saturated (chroma ignored by L, but stresses μL)
]

CLASS_BY_NAME = {c.name: c for c in CLASSES}


def materialize(cls: SynthClass, seed: int) -> zn.Burst:
    """Reproducible capture for (class, seed) — byte-identical on any host."""
    return zn.synth_sample(seed=seed, mode=cls.mode, l_min_q16=cls.l_min,
                           l_max_q16=cls.l_max, chroma_max_q16=cls.chroma_max)


def stratified_specs(n_per_class: int, seed0: int = 0,
                     classes: List[SynthClass] = CLASSES) -> List[Tuple[SynthClass, int]]:
    """A balanced corpus: `n_per_class` (class, seed) specs per class, distinct seeds.
    Materialize lazily with `materialize(cls, seed)` to keep memory flat."""
    specs: List[Tuple[SynthClass, int]] = []
    sid = seed0
    for c in classes:
        for _ in range(n_per_class):
            specs.append((c, sid))
            sid += 1
    return specs
