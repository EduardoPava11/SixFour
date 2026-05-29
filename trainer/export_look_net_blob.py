"""export_look_net_blob.py — serialize MLX look-NN weights to a plain blob.

HAND-WRITTEN tooling (NOT generated). This is the deploy second-half of the MLX
training path (NOTES gap #15): MLX trains the look-NN weights, this tool writes
them to a dependency-free little-endian binary blob, and the hand-written
Swift/Zig forward pass on the iPhone (`SixFour/Native/SixFourNative.swift`,
C ABI in `Native/include/sixfour_native.h`) memory-maps and loads it — NO
mlx-swift, NO CoreML, NO third-party loader (CLAUDE.md Tier-2 zero-deps rule).

The weights are the SAME genome the golden gate transports (`check_golden.py`):
phi, w1, w2, halt_w, halt_b, and the 8 decoder heads. They are RAW (pre-σ-mask);
the on-device forward applies the σ-block-diagonal mask exactly as the Haskell
spec and the MLX/PyTorch ports do.

═══════════════════════════════════════════════════════════════════════════════
BYTE LAYOUT  (all multi-byte fields little-endian; floats IEEE-754 float32)
═══════════════════════════════════════════════════════════════════════════════
Header (16 bytes):
    offset 0  : magic        4 bytes   ASCII "S4LN"  (SixFour Look-Net)
    offset 4  : version      uint32    = 1
    offset 8  : tensor_count uint32    = number of tensor records that follow
    offset 12 : reserved     uint32    = 0  (alignment / future flags)

Then `tensor_count` tensor records, each:
    name_len   uint32                  = byte length of the UTF-8 name
    name       name_len bytes          = UTF-8 tensor name (e.g. "phi", "head0")
    ndim       uint32                  = number of dimensions
    shape      ndim × int32            = dimension sizes, row-major (out, in, …)
    data       prod(shape) × float32   = row-major float32 payload

Records appear in a FIXED canonical order (see TENSOR_ORDER) so the consumer can
read them positionally; names are still written for self-description / asserts.
There is no padding between records (the consumer streams them). Total size is
implied by the records; no trailing bytes.
═══════════════════════════════════════════════════════════════════════════════
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np

GOLDEN = Path(__file__).parent / "generated" / "look_net_golden.json"

MAGIC = b"S4LN"
VERSION = 1

# Canonical record order. heads are emitted as head0..head7 (8 decoder levels).
TENSOR_ORDER = ["phi", "w1", "w2", "halt_w", "halt_b"] + [f"head{i}" for i in range(8)]


# ---------------------------------------------------------------------------
# golden weight loader (mirrors check_golden.py's bit-exact hex decode)
# ---------------------------------------------------------------------------
def _h2d(s: str) -> float:
    """16-hex-digit IEEE-754 bit pattern -> float64 (bit-exact, no decimal parse)."""
    return struct.unpack(">d", int(s, 16).to_bytes(8, "big"))[0]


def _tensor(obj: dict) -> np.ndarray:
    flat = np.array([_h2d(s) for s in obj["hex"]], dtype=np.float64)
    return flat.reshape(obj["shape"])


def load_golden_weights(path: Path = GOLDEN) -> dict:
    """Load the look-NN genome from look_net_golden.json into a flat name->ndarray
    dict using the canonical TENSOR_ORDER names (heads -> head0..head7)."""
    g = json.loads(Path(path).read_text())
    W = g["weights"]
    weights = {
        "phi": _tensor(W["phi"]),       # (64, 10)
        "w1": _tensor(W["w1"]),         # (64, 64)
        "w2": _tensor(W["w2"]),         # (64, 64)
        "halt_w": _tensor(W["halt_w"]), # (1, 2)
        "halt_b": _tensor(W["halt_b"]), # (1,)
    }
    for i, h in enumerate(W["heads"]):
        weights[f"head{i}"] = _tensor(h)  # (d_i, 64)
    return weights


# ---------------------------------------------------------------------------
# blob writer / reader
# ---------------------------------------------------------------------------
def _write_tensor(name: str, arr: np.ndarray) -> bytes:
    a = np.ascontiguousarray(arr, dtype="<f4")  # little-endian float32, row-major
    name_b = name.encode("utf-8")
    out = bytearray()
    out += struct.pack("<I", len(name_b))
    out += name_b
    out += struct.pack("<I", a.ndim)
    out += struct.pack(f"<{a.ndim}i", *a.shape)
    out += a.tobytes(order="C")
    return bytes(out)


def write_blob(weights: dict, path) -> int:
    """Serialize `weights` (name -> ndarray) to `path` in the documented format.
    Tensors are written in the fixed TENSOR_ORDER. Returns the byte count."""
    missing = [n for n in TENSOR_ORDER if n not in weights]
    if missing:
        raise KeyError(f"weights missing tensors: {missing}")
    body = bytearray()
    for name in TENSOR_ORDER:
        body += _write_tensor(name, np.asarray(weights[name]))
    header = MAGIC + struct.pack("<III", VERSION, len(TENSOR_ORDER), 0)
    blob = header + bytes(body)
    Path(path).write_bytes(blob)
    return len(blob)


def read_blob(path) -> dict:
    """Read a blob written by `write_blob` back into a name -> float32 ndarray dict.
    Validates magic + version and the declared tensor count."""
    data = Path(path).read_bytes()
    if data[:4] != MAGIC:
        raise ValueError(f"bad magic: {data[:4]!r} (expected {MAGIC!r})")
    version, count, reserved = struct.unpack_from("<III", data, 4)
    if version != VERSION:
        raise ValueError(f"unsupported version {version} (expected {VERSION})")
    off = 16
    out: dict = {}
    for _ in range(count):
        (name_len,) = struct.unpack_from("<I", data, off); off += 4
        name = data[off:off + name_len].decode("utf-8"); off += name_len
        (ndim,) = struct.unpack_from("<I", data, off); off += 4
        shape = struct.unpack_from(f"<{ndim}i", data, off); off += 4 * ndim
        n = 1
        for d in shape:
            n *= d
        arr = np.frombuffer(data, dtype="<f4", count=n, offset=off).reshape(shape)
        off += 4 * n
        out[name] = np.array(arr, dtype=np.float32)  # copy out of the buffer
    if off != len(data):
        raise ValueError(f"trailing bytes: consumed {off} of {len(data)}")
    return out


# ---------------------------------------------------------------------------
# round-trip self-test
# ---------------------------------------------------------------------------
def main() -> None:
    out_path = Path(__file__).parent / "out" / "look_net.s4ln"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"look-NN deploy-blob — loading golden weights from {GOLDEN.name}")
    weights = load_golden_weights()
    for name in TENSOR_ORDER:
        print(f"  {name:8s} shape={tuple(weights[name].shape)}")

    nbytes = write_blob(weights, out_path)
    print(f"\nwrote {nbytes} bytes -> {out_path}")

    # Emit a tiny sidecar of float32 spot-values so the cross-language Zig test
    # (Native/src/root.zig) can assert byte-exact agreement with the Python
    # decode. Values are the first float32 of each tensor, plus phi[5] / w1[63];
    # written as the exact uint32 bit pattern AND the decoded float so the Zig
    # side can compare without any decimal-parse drift.
    spot_path = out_path.with_suffix(".spot.json")
    spot: dict = {"nbytes": nbytes, "tensor_count": len(TENSOR_ORDER), "values": {}}
    for name in TENSOR_ORDER:
        flat = np.ascontiguousarray(weights[name], dtype="<f4").reshape(-1)
        entry = {
            "shape": list(np.asarray(weights[name]).shape),
            "f0_bits": int(flat[:1].view("<u4")[0]),
            "f0": float(flat[0]),
        }
        spot["values"][name] = entry
    # extra interior spot-checks (offset reads, not just element 0)
    phi_flat = np.ascontiguousarray(weights["phi"], dtype="<f4").reshape(-1)
    w1_flat = np.ascontiguousarray(weights["w1"], dtype="<f4").reshape(-1)
    spot["values"]["phi"]["f5_bits"] = int(phi_flat[5:6].view("<u4")[0])
    spot["values"]["phi"]["f5"] = float(phi_flat[5])
    spot["values"]["w1"]["f63_bits"] = int(w1_flat[63:64].view("<u4")[0])
    spot["values"]["w1"]["f63"] = float(w1_flat[63])
    spot_path.write_text(json.dumps(spot, indent=2))
    print(f"wrote spot-values -> {spot_path}")

    back = read_blob(out_path)

    ok = True
    if set(back) != set(TENSOR_ORDER):
        print(f"  FAIL: tensor set mismatch {set(back)} != {set(TENSOR_ORDER)}")
        ok = False
    for name in TENSOR_ORDER:
        a = np.asarray(weights[name], dtype=np.float32)
        b = back[name]
        if a.shape != b.shape:
            print(f"  [{name}] FAIL shape {a.shape} != {b.shape}")
            ok = False
            continue
        # float32 round-trip is BIT-EXACT (no recompute) — allclose w/ zero tol.
        if not np.array_equal(a, b):
            d = float(np.max(np.abs(a - b)))
            print(f"  [{name}] FAIL max|Δ| = {d:.3e}")
            ok = False
        else:
            print(f"  [{name:8s}] round-trip OK  (bit-exact float32)")

    # sanity: corrupting a byte must break the round-trip equality.
    corrupt = bytearray(out_path.read_bytes())
    corrupt[-1] ^= 0xFF  # flip the last data byte
    tmp = out_path.with_suffix(".corrupt")
    tmp.write_bytes(corrupt)
    bad = read_blob(tmp)
    bites = not np.array_equal(bad["head7"], np.asarray(weights["head7"], dtype=np.float32))
    tmp.unlink()
    print(f"\nsanity: 1-byte corruption breaks equality -> {'OK ✓' if bites else 'did NOT bite ✗'}")
    ok &= bites

    print("\n" + ("BLOB ROUND-TRIP PASSED ✓" if ok else "BLOB ROUND-TRIP FAILED ✗"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
