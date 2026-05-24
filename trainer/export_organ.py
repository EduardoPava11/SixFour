"""Wrap a trained model into an OrganDescriptor + payload pair, ready for AirDrop.

For the JSON-based organs (metric, dither), this just packages the trained JSON
under a content-hashed filename and emits the matching index.json snippet.

For Core ML organs (postProc, ranker), see export_postproc.py / export_ranker.py
(those scripts will be added once the corresponding trainer is written).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from datetime import datetime, timezone


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--slot", required=True, choices=["metric", "postProc", "dither", "ranker"])
    p.add_argument("--input", required=True, help="Trained model file (JSON or .mlpackage)")
    p.add_argument("--name", required=True, help="Human-readable organ name")
    p.add_argument("--generation", type=int, default=0)
    p.add_argument("--parents", nargs="*", default=[])
    p.add_argument("--out-dir", default="out/genes")
    args = p.parse_args()

    src = pathlib.Path(args.input)
    if not src.exists():
        sys.exit(f"Missing input: {src}")

    payload = src.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()[:16]

    ext = src.suffix.lstrip(".")
    if args.slot in ("metric", "dither") and ext != "json":
        sys.exit(f"Slot {args.slot} expects a JSON input, got .{ext}")
    if args.slot in ("postProc", "ranker") and ext != "mlpackage":
        sys.exit(f"Slot {args.slot} expects a .mlpackage input, got .{ext}")

    filename = f"{digest}.{ext}"
    out_dir = pathlib.Path(args.out_dir) / args.slot
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / filename
    dest.write_bytes(payload)

    descriptor = {
        "slot": args.slot,
        "name": args.name,
        "hash": digest,
        "generation": args.generation,
        "parentHashes": args.parents,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "filename": filename,
    }

    # Append to per-slot index.json
    index_path = out_dir / "index.json"
    if index_path.exists():
        existing = json.loads(index_path.read_text())
    else:
        existing = []
    existing = [d for d in existing if d.get("hash") != digest]
    existing.append(descriptor)
    index_path.write_text(json.dumps(existing, indent=2))

    print(f"Exported {dest}")
    print(f"Index → {index_path}")
    print(json.dumps(descriptor, indent=2))


if __name__ == "__main__":
    main()
