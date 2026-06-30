"""v21_ingest.py - load an AirDropped V2.1 capture bundle (manifest + field + contested npy).

The app's AirDrop ships a self-describing bundle that shares one filename stem (V21Export.shareItems):

    <stem>.gif                       the collapse (the shipped GIF)
    <stem>_field_SxSx3xN.npy         the probability functions (int32 counts, [y,x,3,level])
    <stem>_contested_SxSx3.npy       the mode-margin sidecar ([y,x,3], peak - runner-up)
    <stem>_manifest.json             describes all of the above, incl. field_source

This module reads the manifest FIRST (so it never has to guess which field it got), loads the npy
arrays, validates their shapes against the manifest, and returns a plain dict. The energy face is
`total - counts`, the mass face is `counts / total`, matching SixFour.Spec.V21Field.

THE FIDELITY CROSS-CHECK: `margins_from_field` re-derives the mode margin from the field with the
SAME definition the device used (peak count minus runner-up count). `load_bundle` asserts the shipped
contested sidecar equals this re-derivation byte-for-byte, so the device and the trainer can never
silently disagree on what "contested" means.

Run `python3 trainer/v21_ingest.py` to self-check against a synthetic bundle.
"""
from __future__ import annotations

import glob
import json
import os

import numpy as np


def margins_from_field(field: np.ndarray) -> np.ndarray:
    """The mode margin `[y, x, 3]` from a field `[y, x, 3, level]`: peak count minus runner-up count
    over the level axis. Identical to the device's `V21Contested.margins` (top-1 minus top-2)."""
    if field.ndim != 4:
        raise ValueError(f"expected a 4-D field [y,x,3,level], got shape {field.shape}")
    top2 = np.sort(field, axis=-1)[..., -2:]            # the two largest counts per bin/channel
    return (top2[..., 1] - top2[..., 0]).astype(np.int32)


def _find_manifest(path: str) -> str:
    """Resolve `path` to a manifest file: accept the manifest itself, or a directory holding one."""
    if path.endswith(".json"):
        return path
    hits = sorted(glob.glob(os.path.join(path, "*_manifest.json")))
    if not hits:
        raise FileNotFoundError(f"no *_manifest.json under {path}")
    return hits[0]


def load_bundle(path: str, check_contested: bool = True) -> dict:
    """Load a V2.1 capture bundle. `path` is the manifest file or its directory.

    Returns a dict: `manifest` (the parsed JSON), `field` (int32 [y,x,3,level]), `contested`
    (int32 [y,x,3] or None), `gif` (absolute path or None), and `field_source` (the provenance string).
    """
    manifest_path = _find_manifest(path)
    base = os.path.dirname(os.path.abspath(manifest_path))
    with open(manifest_path) as fh:
        man = json.load(fh)
    arts = man.get("artifacts", {})

    if "field" not in arts:
        raise ValueError("manifest has no 'field' artifact")
    field = np.load(os.path.join(base, arts["field"]))
    if list(field.shape) != list(man["field"]["shape"]):
        raise ValueError(f"field shape {field.shape} != manifest {man['field']['shape']}")

    contested = None
    if "contested" in arts:
        contested = np.load(os.path.join(base, arts["contested"]))
        if list(contested.shape) != list(man["contested"]["shape"]):
            raise ValueError(f"contested shape {contested.shape} != manifest {man['contested']['shape']}")
        if check_contested:
            derived = margins_from_field(field)
            if not np.array_equal(contested, derived):
                raise ValueError("contested sidecar != margins_from_field(field): device/trainer disagree")

    gif = None
    if "gif" in arts and os.path.exists(os.path.join(base, arts["gif"])):
        gif = os.path.join(base, arts["gif"])

    return {
        "manifest": man,
        "field": field,
        "contested": contested,
        "gif": gif,
        "field_source": man.get("field_source"),
    }


def _self_check():
    """Build a synthetic bundle the way the app does (standard numpy .npy + a hand-shaped manifest),
    load it, and assert the round-trip and the contestedness cross-check hold."""
    import tempfile

    side, n = 4, 8
    rng = np.random.default_rng(0)
    field = rng.integers(0, 5, size=(side, side, 3, n)).astype(np.int32)
    contested = margins_from_field(field)

    with tempfile.TemporaryDirectory() as d:
        stem = "sixfour_deadbeef"
        field_name = f"{stem}_field_{side}x{side}x3x{n}.npy"
        cont_name = f"{stem}_contested_{side}x{side}x3.npy"
        np.save(os.path.join(d, field_name), field)
        np.save(os.path.join(d, cont_name), contested)
        manifest = {
            "schema": "sixfour.v21.capture/1",
            "stem": stem,
            "side": side,
            "n_levels": n,
            "field_source": "camera_box",
            "artifacts": {"field": field_name, "contested": cont_name},
            "field": {"dtype": "<i4", "shape": [side, side, 3, n],
                      "axes": ["y", "x", "channel", "level"]},
            "contested": {"dtype": "<i4", "shape": [side, side, 3],
                          "axes": ["y", "x", "channel"]},
        }
        with open(os.path.join(d, f"{stem}_manifest.json"), "w") as fh:
            json.dump(manifest, fh)

        bundle = load_bundle(d)
        assert bundle["field_source"] == "camera_box"
        assert bundle["field"].shape == (side, side, 3, n)
        assert bundle["contested"].shape == (side, side, 3)
        assert np.array_equal(bundle["contested"], contested)
        # A tampered sidecar must be caught (the cross-check is non-vacuous).
        bad = contested.copy()
        bad[0, 0, 0] += 1
        np.save(os.path.join(d, cont_name), bad)
        try:
            load_bundle(d)
            raise AssertionError("tampered contested sidecar was NOT caught")
        except ValueError as e:
            assert "disagree" in str(e)

    print(f"v21_ingest: self-check PASS - bundle load + shape validation + "
          f"contested cross-check (device == trainer margin) + tamper detection")


if __name__ == "__main__":
    _self_check()
