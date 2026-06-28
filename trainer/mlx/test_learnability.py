"""Force the trainer to reproduce the LEARNABILITY THEOREM byte-exact, against learnability_golden.json.

The spec proves, as a theorem (Spec.LearnabilityTheorem.lawJointObjectiveIdentifiesFullPalette), that the
joint objective (theta_B + the value head) IDENTIFIES the data-manufactured target -- the optimum is unique
and visible to the objective -- walking the statistical moment ladder over the cell aggregate A = C.S^T (the
2nd cross-moment between colour and the data-fixed octant space lattice). This is IDENTIFIABILITY, NOT proof
the model reaches the optimum on real data (CONTRACT-ONLY; see the descentFixture _contractOnly note +
SIXFOUR-MODEL.md). Spec.Codegen.LearnabilityTheorem emits the concrete scalars and integer vectors that proof
turns on; this loader is the gate that makes the spec the DESIGN AUTHORITY for the identifiability claim.

It is NO-TRAIN: every section is reproduced by an INDEPENDENT Python computation (not a JSON
tautology) and asserted equal to the spec golden. One section per conjunct of the capstone:

  SIGNAL        - the two owner lenses (d6/l1 lattice norm on L = discrete geometry; Z[i] Gaussian
                  norm on chroma = algebraic number theory) reproduced from the raw octant voxels via
                  a local octant-lift port; Flat (0,0) is the boundary tooth (nothing to learn).
  EXPRESSIVITY  - the Q16 commit margin (1 LSB survives, 1/2 LSB floors) via q16.quantize_q16, and the
                  A7 mean-free residual witness via a from_root_coords port.
  IDENTIFIABILITY - THE HEART: the cell aggregate / cellLoss (cell_loss.py) reproduces 0 of 24 vs all
                  witnesses; the value head sees Sum cb^2 = 8 the cellLoss is BLIND to.
  DESCENT FIXTURE - (CONTRACT-ONLY) a single retired-trainer fixture's endpoints tied to
                  masked_band_trainer's own gated constants; NOT proof the full-matrix model descends.
  NO-COLLAPSE   - the VICReg combined guard reproduced on the exact emitted factor vectors.
  SIDE COND     - w_value > 0 is required (objectiveIdentifiesFullPalette 1 = True, ...0 = False).

Run `python3 trainer/mlx/test_learnability.py` to self-check. Regenerate the golden with
`cd spec && cabal run spec-codegen` after any change to the learnability spec.
"""
from __future__ import annotations

import json
import os
from math import sqrt

from cell_loss import cell_loss, cell_aggregate, det3
from q16 import to_q16, quantize_q16
from masked_band_trainer import TRAINER_STEPS, GOLDEN_FLOOR_BAND, GOLDEN_TRAINED_BAND

GOLDEN = os.path.join(os.path.dirname(__file__), "..", "generated", "learnability_golden.json")


def load_golden(path: str = GOLDEN):
    with open(path) as fh:
        return json.load(fh)


# ===========================================================================
# Local octant-lift port (the byte-exact twin of Spec.OctreeCell.liftOct).
# Integer floor division matches Haskell `div` (both floor toward -inf).
# ===========================================================================
def _s_lift(x: int, y: int):
    """Spec.OctreeCell.sLift: the reversible 1-D S-transform (coarse, detail)."""
    d = x - y
    return (y + (d // 2), d)


def _lift_quad(a: int, b: int, c: int, d: int):
    """Spec.RGBTLift.liftQuad: 2x2 -> (ll, lh, hl, hh)."""
    la, ha = _s_lift(a, b)
    lc, hc = _s_lift(c, d)
    ll, lh = _s_lift(la, lc)
    hl, hh = _s_lift(ha, hc)
    return (ll, lh, hl, hh)


def _oct_detail(v8: list) -> list:
    """Spec.OctreeCell.liftOct then detailToList: the 7 detail sub-bands of 8 octant voxels."""
    a, b, c, d, e, f, g, h = v8
    r0, g0, b0, t0 = _lift_quad(a, b, c, d)
    r1, g1, b1, t1 = _lift_quad(e, f, g, h)
    _rr, dz = _s_lift(r0, r1)
    return [g0, b0, t0, g1, b1, t1, dz]


def _l_energy(lv: list) -> int:
    """ChannelDetail LDetail: the d6/l1 lattice norm (sum of abs) of the L detail."""
    return sum(abs(x) for x in _oct_detail(lv))


def _chroma_energy(av: list, bv: list) -> int:
    """ChannelDetail ChromaDetail: the sum of Z[i] Gaussian norms a^2 + b^2 over the bands."""
    da = _oct_detail(av)
    db = _oct_detail(bv)
    return sum(a * a + b * b for a, b in zip(da, db))


def _from_root_coords(b: int, cs: list) -> list:
    """Spec.RootLatticeDetail.fromRootCoords: rebuild a mean-free vector from its b-1 root coords."""
    def c(i: int) -> int:
        if i < 0 or i >= b - 1:
            return 0
        return cs[i]
    return [c(k) - c(k - 1) for k in range(b)]


# ===========================================================================
# The VICReg combined guard (byte-exact twin of Spec.VarianceFloorGuard.combinedGuard).
# ===========================================================================
def _factor_variance(xs: list) -> float:
    if not xs:
        return 0.0
    n = len(xs)
    m = sum(xs) / n
    return sum((x - m) * (x - m) for x in xs) / n


def _variance_hinge(gamma: float, xs: list) -> float:
    return max(0.0, gamma - sqrt(_factor_variance(xs) + 1e-4))


def _combined_guard(q: list, k: list) -> float:
    return _variance_hinge(1.0, q) + _variance_hinge(1.0, k)


# ===========================================================================
def _cell(rows: list) -> list:
    """A JSON cell ([[L,a,b,x,y,t], ...]) as cell_loss.py voxel tuples."""
    return [tuple(r) for r in rows]


def self_check(path: str = GOLDEN) -> int:
    g = load_golden(path)

    # --- SIGNAL: reproduce both lens energies from the raw voxels (not a tautology) -----------
    saw_flat = False
    for s in g["signal"]["scenes"]:
        le = _l_energy(s["lVoxels"])
        ce = _chroma_energy(s["aVoxels"], s["bVoxels"])
        assert le == s["lEnergy"], f"SIGNAL lEnergy[{s['kind']}]: {le} != {s['lEnergy']}"
        assert ce == s["chromaEnergy"], f"SIGNAL chromaEnergy[{s['kind']}]: {ce} != {s['chromaEnergy']}"
        if s["kind"] == "Flat":
            saw_flat = True
            assert le == 0 and ce == 0, "SIGNAL: Flat boundary must floor both lenses (nothing to learn)"
    assert saw_flat, "SIGNAL: the Flat boundary tooth is missing"

    # --- EXPRESSIVITY: the Q16 commit margin + the A7 residual witness ------------------------
    ex = g["expressivity"]
    assert ex["oneLsbLatent"] == to_q16(1), "EXPRESSIVITY: oneLsbLatent != to_q16(1)"
    assert quantize_q16(to_q16(1)) == ex["commitOneLsb"], "EXPRESSIVITY: 1-LSB commit drifted"
    assert quantize_q16(to_q16(1) / 2) == ex["commitHalfLsb"], "EXPRESSIVITY: 1/2-LSB commit drifted"
    assert ex["survivesOneLsb"] is True and ex["survivesHalfLsb"] is False, \
        "EXPRESSIVITY: survival flags drifted"
    a7 = ex["a7Witness"]
    got_a7 = _from_root_coords(a7["b"], a7["coords"])
    assert got_a7 == a7["result"], f"EXPRESSIVITY: A7 witness {got_a7} != {a7['result']}"

    # --- IDENTIFIABILITY: the heart (rank-3 cellLoss + the value-head complement) -------------
    idf = g["identifiability"]
    assert idf["identifiedDof"] + idf["blindDof"] == idf["totalColourDof"], \
        "IDENTIFIABILITY: 9 + 15 = 24 DOF accounting does not close"
    assert idf["identifiedDof"] == 9 and idf["blindDof"] == 15 and idf["rankS"] == 3

    cw = idf["cellAggregateIdentityWitness"]
    tgt_id = _cell(cw["cell"])
    agg = cell_aggregate(tgt_id)
    assert agg == cw["aggregate"], f"IDENTIFIABILITY: cell aggregate {agg} != {cw['aggregate']}"
    assert det3(agg) == cw["det"], "IDENTIFIABILITY: identity-witness det drifted"

    # the mispaired off-diagonal: each predicted voxel is itself rank-1 (per-voxel BLIND) but the
    # cell AGGREGATE loss sees the chroma<->space swap (the cell-aggregate teeth, pinned at 4).
    mis = _cell(idf["offDiagonalMispairCell"])
    assert all(det3([[c * s for s in (v[3], v[4], v[5])] for c in (v[1], v[2], v[0])]) == 0 for v in mis), \
        "IDENTIFIABILITY: a mispaired voxel is not rank-1 (per-voxel blindness witness broken)"
    assert cell_loss(mis, tgt_id) == idf["offDiagonalMispairLoss"] == 4, \
        "IDENTIFIABILITY: off-diagonal mispair aggregate loss drifted from 4"

    vh = idf["valueHead"]
    tgt = _cell(vh["tgtCell"])
    # THE value-head teeth: the checkerboard perturbation leaves cellLoss EXACTLY 0 (blind)...
    cl_comp = cell_loss(_cell(vh["predCellComplement"]), tgt)
    assert cl_comp == 0 == vh["cellLossComplement"], \
        f"IDENTIFIABILITY: complement cellLoss {cl_comp} != 0 (must be blind)"
    # ...yet the value (palette) head's regression Sum cb^2 SEES it (> 0).
    cb = vh["checkerboardParity"]
    value_loss = sum(d * d for d in cb)
    assert value_loss == vh["complementValueLoss"] > 0, \
        f"IDENTIFIABILITY: value-head loss {value_loss} != {vh['complementValueLoss']} (>0)"
    # the in-span(S) perturbation IS seen by cellLoss (so the loss is not blind to everything).
    cl_sub = cell_loss(_cell(vh["predCellSubspace"]), tgt)
    assert cl_sub == vh["cellLossSubspace"] > 0, \
        f"IDENTIFIABILITY: subspace cellLoss {cl_sub} != {vh['cellLossSubspace']} (>0)"
    # the a-only target's aggregate is rank-deficient by construction.
    assert det3(cell_aggregate(tgt)) == vh["tgtCellAggregateDet"] == 0, \
        "IDENTIFIABILITY: a-only target aggregate is not rank-deficient"

    # --- DESCENT FIXTURE (CONTRACT-ONLY): tie a SINGLE retired-trainer fixture's endpoints to the
    # trainer's own gated constants (NO-TRAIN). This is NOT proof the full-matrix model descends on
    # real data -- see _contractOnly in the golden + SIXFOUR-MODEL.md. ------------------------------
    d = g["descentFixture"]
    assert d["trainerSteps"] == TRAINER_STEPS, "DESCENT: trainerSteps != masked_band_trainer.TRAINER_STEPS"
    assert d["goldenFloorBand"] == GOLDEN_FLOOR_BAND, "DESCENT: goldenFloorBand drifted"
    assert d["goldenTrainedBand"] == GOLDEN_TRAINED_BAND, "DESCENT: goldenTrainedBand drifted"

    # --- NO-COLLAPSE: reproduce the combined guard on the exact emitted factor vectors --------
    nc = g["noCollapse"]
    varied, flat = nc["variedFactor"], nc["flatFactor"]
    assert (_combined_guard(flat, varied) > 0.5) == nc["flatVariedTripsGuard"] is True, \
        "NO-COLLAPSE: a flat factor must trip the guard (> 0.5)"
    assert (_combined_guard(varied, varied) < 1e-9) == nc["variedVariedPasses"] is True, \
        "NO-COLLAPSE: two varied factors must pass (< 1e-9)"

    # --- SIDE CONDITION: full-palette IDENTIFIABILITY holds IFF w_value > 0 --------------------
    sc = g["sideCondition"]
    assert sc["wValueRequired"] is True
    assert sc["identifiesAtOne"] is True, "SIDE: objectiveIdentifiesFullPalette(w=1) must be True"
    assert sc["identifiesAtZero"] is False, "SIDE: objectiveIdentifiesFullPalette(w=0) must be False (complement unidentified)"
    assert sc["lawJointObjectiveIdentifiesFullPalette"] is True, "SIDE: the capstone lawJointObjectiveIdentifiesFullPalette must be True"
    # the operational meaning, reproduced here: cellLoss alone (w=0) cannot separate the two palettes
    # (cl_comp == 0), but the joint objective at w=1 can (cl_comp + 1*value_loss = 8 > 0).
    assert cl_comp + 0 * value_loss == 0, "SIDE: at w_value=0 the complement is UNidentified"
    assert cl_comp + 1 * value_loss > 0, "SIDE: at w_value=1 the complement IS identified"

    return len(g["signal"]["scenes"])


if __name__ == "__main__":
    try:
        n = self_check()
        print(f"  learnability golden: {n} scenes + all 6 conjuncts (SIGNAL/EXPRESSIVITY/"
              "IDENTIFIABILITY/DESCENT/NO-COLLAPSE/SIDE) reproduce byte-exact")
        print("test_learnability: PASS")
        raise SystemExit(0)
    except AssertionError as e:
        print(f"FAIL: {e}")
        print("test_learnability: FAIL")
        raise SystemExit(1)
