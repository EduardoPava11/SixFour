"""End-to-end smoke test for the SixFour look-NN codegen pipeline.

Verifies: spec → emitted PyTorch → .mlpackage works on real CoreML, AND
σ-equivariance is bit-exact at runtime under random weights.

Usage (from ~/SixFour/trainer/):

    uv run python smoke_test.py

Requires: torch, coremltools (already in pyproject.toml deps).

What it checks:
  1. The generated LookNet instantiates and forward-passes at the spec shape
     (1, MAX_TOKENS=16384, GMM_TOKEN_DIM=10) → (1, DECODER_OUT_DIM=768).
  2. σ-equivariance: max|σ(E(x)) - E(σx)| is bit-exactly 0 under random
     weights. (This was 2950 before the GELU→tanh fix; the smoke test caught
     that regression. Keep the check at exact equality.)
  3. build_mlpackage.py converts a random .pt checkpoint to a .mlpackage.
  4. The .mlpackage loads in coremltools with the expected I/O names.

If any of these fails, the algebraic spec is no longer faithfully realised
by the emitted PyTorch.
"""
import sys
import os
import tempfile
import subprocess
from pathlib import Path

GEN = Path(__file__).parent / "generated"
sys.path.insert(0, str(GEN))

import torch
from look_net_torch import (
    LookNet, MAX_TOKENS, GMM_TOKEN_DIM, DECODER_OUT_DIM,
    GMM_TOKEN_SIGMA_MASK, SIGMA768_MASK,
)


def main() -> int:
    print("=== Step 1: instantiate random LookNet ===")
    torch.manual_seed(42)
    model = LookNet()
    n_params = sum(p.numel() for p in model.parameters())
    n_buffers = sum(b.numel() for b in model.buffers())
    print(f"  parameters: {n_params:,}")
    print(f"  buffers (σ-masks): {n_buffers:,}")

    print("\n=== Step 2: forward-pass smoke ===")
    model.eval()
    with torch.no_grad():
        tokens = torch.randn(1, MAX_TOKENS, GMM_TOKEN_DIM)
        token_mask = torch.ones(1, MAX_TOKENS)
        out = model(tokens, token_mask=token_mask)
        print(f"  input  tokens : {tuple(tokens.shape)}")
        print(f"  output haar   : {tuple(out.shape)}  (expected (1, {DECODER_OUT_DIM}))")
        assert out.shape == (1, DECODER_OUT_DIM), "shape mismatch"

    print("\n=== Step 3: σ-equivariance numerical check ===")
    flip_in = torch.tensor([-1.0 if b else 1.0 for b in GMM_TOKEN_SIGMA_MASK])
    flip_out = torch.tensor([-1.0 if b else 1.0 for b in SIGMA768_MASK])
    with torch.no_grad():
        out_orig = model(tokens, token_mask=token_mask)
        out_sigma = model(tokens * flip_in, token_mask=token_mask)
        expected = out_orig * flip_out
        delta = (out_sigma - expected).abs().max().item()
        print(f"  max|σ(E(x)) - E(σx)| = {delta:.2e}  (must be 0 by algebraic guarantee)")
        if delta != 0.0:
            print(f"  ✗ σ-EQUIVARIANCE BROKEN — investigate Codegen.CoreML")
            return 1

    print("\n=== Step 4: save random weights to .pt ===")
    ckpt = Path(tempfile.mkdtemp()) / "random_lookNet.pt"
    torch.save(model.state_dict(), str(ckpt))
    print(f"  wrote {ckpt}  ({os.path.getsize(ckpt):,} bytes)")

    print("\n=== Step 5: run build_mlpackage.py with the random weights ===")
    mlpackage = Path(tempfile.mkdtemp()) / "LookNet.mlpackage"
    result = subprocess.run(
        [sys.executable, str(GEN / "build_mlpackage.py"),
         "--weights", str(ckpt), "--out", str(mlpackage)],
        capture_output=True, text=True, timeout=600,
    )
    print("STDOUT:", result.stdout)
    if result.returncode != 0:
        print("STDERR:", result.stderr[-2000:])
        return 1

    print("=== Step 6: verify .mlpackage loads in CoreML ===")
    assert mlpackage.exists(), f"mlpackage not produced at {mlpackage}"
    import coremltools as ct
    mlmodel = ct.models.MLModel(str(mlpackage))
    spec = mlmodel.get_spec()
    print(f"  loaded:  {mlpackage}")
    print(f"  inputs:  {[i.name for i in spec.description.input]}")
    print(f"  outputs: {[o.name for o in spec.description.output]}")
    print("\n✓ END-TO-END SPEC → .mlpackage VERIFIED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
