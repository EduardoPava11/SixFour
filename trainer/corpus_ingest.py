"""corpus_ingest.py - load an AirDropped SixFour training corpus (the real-capture corpus).

The app's CORPUS export (Feature.trainingCorpus -> TrainingCorpus.exportArchive) AirDrops one zip,
`SixFour-corpus.zip`, holding every capture's artifacts under a shared per-capture stem plus one
`corpus_manifest.json` naming them all:

    corpus_manifest.json             schema sixfour.corpus/1: createdAt, buildSHA, captures{stem: [files]}
    sixfour_<stamp>.gif              the collapse (the shipped GIF)
    sixfour_<stamp>.s4cr             the shutter's ledger (deterministic CBOR, Spec.CaptureRecord)
    sixfour_<stamp>.volume.npy       the burst as int32 Q16 OKLab, shape (frames, side, side, 3) - the
                                     SAME bytes CaptureGene.volume fed the on-device somatic trainer
    sixfour_<stamp>.train.json       the device's training verdicts + labels (schema
                                     sixfour.corpus.capture/1): shipped theta_up, band-head outcome,
                                     per-slot halt orders, drained t-band pairs
    sixfour_<stamp>.contact.png      optional visual index

This module unpacks nothing (unzip the archive first, or point it at the folder), reads the manifest
FIRST, and returns plain dicts. The volume reshaped to (frames, side*side, 3) is a drop-in for the
synthetic burst pixel tensors (`native_kernels.synth_burst` / `mlx.scene_corpus`) - the corpus is
raw-volume-first precisely so every derived feature (octant pairs for W0/theta, root-chart bands,
any future basis) is re-manufactured here with the shared kernels instead of being trusted from disk.

The .s4cr reader decodes exactly the deterministic-CBOR subset the spec pins (RFC 8949 core subset:
majors 0/2/3/4/5, minimal heads, no floats) - anything else is a hard error, which is the point.

Run `python3 trainer/corpus_ingest.py` to self-check against a synthetic corpus folder.
"""
from __future__ import annotations

import json
import os

import numpy as np

SIDECAR_SCHEMA = "sixfour.corpus.capture/1"
MANIFEST_SCHEMA = "sixfour.corpus/1"


# ---------------------------------------------------------------- CBOR (deterministic subset)

def _cbor_head(buf: bytes, i: int) -> tuple[int, int, int]:
    """Decode one CBOR head at `i`: returns (major, argument, next_index)."""
    major, low = buf[i] >> 5, buf[i] & 0x1F
    if low < 24:
        return major, low, i + 1
    n = {24: 1, 25: 2, 26: 4, 27: 8}.get(low)
    if n is None:
        raise ValueError(f"unsupported CBOR head 0x{buf[i]:02x} at {i}")
    return major, int.from_bytes(buf[i + 1:i + 1 + n], "big"), i + 1 + n


def _cbor_decode(buf: bytes, i: int = 0):
    """Decode one deterministic-CBOR value (majors 0/2/3/4/5 only, the Spec.CaptureRecord
    subset). Returns (value, next_index): uint -> int, bytes -> bytes, text -> str,
    array -> list, map -> dict."""
    major, arg, i = _cbor_head(buf, i)
    if major == 0:
        return arg, i
    if major == 2:
        return buf[i:i + arg], i + arg
    if major == 3:
        return buf[i:i + arg].decode("ascii"), i + arg
    if major == 4:
        out = []
        for _ in range(arg):
            v, i = _cbor_decode(buf, i)
            out.append(v)
        return out, i
    if major == 5:
        d = {}
        for _ in range(arg):
            k, i = _cbor_decode(buf, i)
            v, i = _cbor_decode(buf, i)
            d[k] = v
        return d, i
    raise ValueError(f"CBOR major {major} is outside the deterministic subset")


def zigzag_decode(n: int) -> int:
    """The signed zigzag the .s4cr `ev` triples ride (S4Cbor.zigzag inverse)."""
    return (n >> 1) ^ -(n & 1)


def load_s4cr(path: str) -> dict:
    """Parse a shutter ledger. Returns the raw key->value dict (v/win/d0/weave/dtus/s16/gct,
    v2: c64/c32/c16/ev/tel, v3: dw) with `ev` entries decoded to
    (duration_us, iso_milli, ev_centistops)."""
    with open(path, "rb") as fh:
        buf = fh.read()
    rec, end = _cbor_decode(buf)
    if end != len(buf):
        raise ValueError(f"{path}: {len(buf) - end} trailing bytes after the record")
    if not isinstance(rec, dict) or "v" not in rec:
        raise ValueError(f"{path}: not a capture record")
    if rec.get("ev"):
        rec["ev"] = [(d, iso, zigzag_decode(z)) for d, iso, z in rec["ev"]]
    return rec


# ---------------------------------------------------------------- The corpus

def _find_manifest(path: str) -> str:
    """Resolve `path` to the corpus manifest: the file itself, or a directory holding one."""
    if path.endswith(".json"):
        return path
    hit = os.path.join(path, "corpus_manifest.json")
    if not os.path.exists(hit):
        raise FileNotFoundError(f"no corpus_manifest.json under {path}")
    return hit


def load_corpus(path: str) -> list[dict]:
    """Load every capture in an unzipped corpus folder. `path` is the manifest or its directory.

    Returns one dict per capture: `stem`, `volume` (int32 (frames, side, side, 3) Q16 OKLab or
    None), `sidecar` (the train.json dict or None), `s4cr` (the ledger dict or None), and
    `gif` (absolute path or None). Shapes are validated against the sidecar where both exist.
    """
    manifest_path = _find_manifest(path)
    base = os.path.dirname(os.path.abspath(manifest_path))
    with open(manifest_path) as fh:
        man = json.load(fh)
    if man.get("schema") != MANIFEST_SCHEMA:
        raise ValueError(f"unknown corpus schema {man.get('schema')!r} (want {MANIFEST_SCHEMA})")

    captures = []
    for stem in sorted(man.get("captures", {})):
        entry: dict = {"stem": stem, "volume": None, "sidecar": None, "s4cr": None, "gif": None}

        p = os.path.join(base, stem + ".train.json")
        if os.path.exists(p):
            with open(p) as fh:
                sc = json.load(fh)
            if sc.get("schema") != SIDECAR_SCHEMA:
                raise ValueError(f"{stem}: unknown sidecar schema {sc.get('schema')!r}")
            entry["sidecar"] = sc

        p = os.path.join(base, stem + ".volume.npy")
        if os.path.exists(p):
            vol = np.load(p)
            if vol.dtype != np.int32 or vol.ndim != 4 or vol.shape[-1] != 3:
                raise ValueError(f"{stem}: volume is {vol.dtype} {vol.shape}, want int32 (F,S,S,3)")
            sc = entry["sidecar"]
            if sc and (vol.shape[0] != sc["frames"] or vol.shape[1] != sc["side"]):
                raise ValueError(f"{stem}: volume {vol.shape} disagrees with sidecar "
                                 f"({sc['frames']}, {sc['side']})")
            entry["volume"] = vol

        p = os.path.join(base, stem + ".s4cr")
        if os.path.exists(p):
            entry["s4cr"] = load_s4cr(p)

        p = os.path.join(base, stem + ".gif")
        entry["gif"] = p if os.path.exists(p) else None
        captures.append(entry)
    return captures


def volumes_as_bursts(captures: list[dict]) -> list[np.ndarray]:
    """The corpus volumes reshaped to (frames, side*side, 3) - the synthetic-burst pixel-tensor
    shape (`native_kernels.synth_burst` / `mlx.scene_corpus.scene_burst`), so a real-capture
    loader drops into every consumer the synthetic corpus already feeds (jepa octants, theta_up
    pair manufacture, the future real-corpus W0)."""
    return [c["volume"].reshape(c["volume"].shape[0], -1, 3)
            for c in captures if c["volume"] is not None]


# ---------------------------------------------------------------- self-check

def _cbor_encode_uint(major: int, n: int) -> bytes:
    m = major << 5
    if n < 24:
        return bytes([m | n])
    for low, size in ((24, 1), (25, 2), (26, 4), (27, 8)):
        if n < (1 << (8 * size)):
            return bytes([m | low]) + n.to_bytes(size, "big")
    raise ValueError(n)


def _cbor_encode(v) -> bytes:
    """Deterministic encode for the self-check (mirror of S4Cbor.encoded)."""
    if isinstance(v, int):
        return _cbor_encode_uint(0, v)
    if isinstance(v, bytes):
        return _cbor_encode_uint(2, len(v)) + v
    if isinstance(v, str):
        b = v.encode("ascii")
        return _cbor_encode_uint(3, len(b)) + b
    if isinstance(v, list):
        return _cbor_encode_uint(4, len(v)) + b"".join(_cbor_encode(x) for x in v)
    if isinstance(v, dict):
        pairs = sorted((_cbor_encode(k), _cbor_encode(x)) for k, x in v.items())
        return _cbor_encode_uint(5, len(pairs)) + b"".join(k + x for k, x in pairs)
    raise TypeError(type(v))


def _self_check() -> None:
    import tempfile

    rng = np.random.default_rng(64)
    with tempfile.TemporaryDirectory() as d:
        stem = "sixfour_20260711T000000"
        frames, side = 4, 8
        vol = rng.integers(-(1 << 16), 1 << 16, size=(frames, side, side, 3), dtype=np.int32)
        np.save(os.path.join(d, stem + ".volume"), vol)  # np.save appends .npy

        sidecar = {"schema": SIDECAR_SCHEMA, "stem": stem, "frames": frames, "side": side,
                   "colorSpace": "rec709", "haltOrders": [2] * 256,
                   "tband": {"width": 5, "features": [1.0] * 10, "targets": [0.5, 0.25]}}
        with open(os.path.join(d, stem + ".train.json"), "w") as fh:
            json.dump(sidecar, fh)

        record = {"v": 2, "win": 320, "d0": 5, "weave": [0] * frames,
                  "dtus": [50_000] * (frames - 1), "s16": [7] * 12, "gct": b"\x01\x02",
                  "c64": [1, 2], "c32": [], "c16": [3],
                  "ev": [[8_000, 100_000, 10]], "tel": [[4], [4], 1000]}  # zigzag(5) = 10 on the wire
        with open(os.path.join(d, stem + ".s4cr"), "wb") as fh:
            fh.write(_cbor_encode(record))

        with open(os.path.join(d, stem + ".gif"), "wb") as fh:
            fh.write(b"GIF89a")

        manifest = {"schema": MANIFEST_SCHEMA, "captureCount": 1,
                    "captures": {stem: [stem + ".gif", stem + ".s4cr",
                                        stem + ".volume.npy", stem + ".train.json"]}}
        with open(os.path.join(d, "corpus_manifest.json"), "w") as fh:
            json.dump(manifest, fh)

        caps = load_corpus(d)
        assert len(caps) == 1 and caps[0]["stem"] == stem
        assert np.array_equal(caps[0]["volume"], vol)
        assert caps[0]["sidecar"]["haltOrders"] == [2] * 256
        rec = caps[0]["s4cr"]
        assert rec["v"] == 2 and rec["weave"] == [0] * frames and rec["gct"] == b"\x01\x02"
        assert rec["ev"] == [(8_000, 100_000, 5)], rec["ev"]  # zigzag(5) round-trip: 10 -> 5
        assert caps[0]["gif"] and caps[0]["gif"].endswith(".gif")

        bursts = volumes_as_bursts(caps)
        assert bursts[0].shape == (frames, side * side, 3)
        assert np.array_equal(bursts[0].reshape(vol.shape), vol)

        # zigzag: the wire value for -3 is 5, for 5 is 10.
        assert zigzag_decode(5) == -3 and zigzag_decode(10) == 5
    print("corpus_ingest self-check OK "
          f"(1 capture, volume {vol.shape}, ledger v{record['v']}, burst {bursts[0].shape})")


if __name__ == "__main__":
    _self_check()
