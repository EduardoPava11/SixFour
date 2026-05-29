"""End-to-end smoke test for the SixFour look-NN codegen pipeline.

Verifies: spec → emitted PyTorch → .mlpackage works on real CoreML, AND
σ-equivariance is bit-exact at runtime under random weights.

Usage (from ~/SixFour/trainer/):

    uv run python smoke_test.py

Requires: torch, coremltools (already in pyproject.toml deps).

What it checks:
  1. The generated LookNet instantiates and forward-passes at the spec shape
     (1, MAX_TOKENS=16384, GMM_TOKEN_DIM=10) → (1, DECODER_OUT_DIM=384).
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

import numpy as np
import torch
from look_net_torch import (
    LookNet, MAX_TOKENS, GMM_TOKEN_DIM, DECODER_OUT_DIM,
    GMM_TOKEN_SIGMA_MASK, SIGMA_DECODER_MASK,
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
    flip_out = torch.tensor([-1.0 if b else 1.0 for b in SIGMA_DECODER_MASK])
    with torch.no_grad():
        out_orig = model(tokens, token_mask=token_mask)
        out_sigma = model(tokens * flip_in, token_mask=token_mask)
        expected = out_orig * flip_out
        delta = (out_sigma - expected).abs().max().item()
        print(f"  max|σ(E(x)) - E(σx)| = {delta:.2e}  (must be 0 by algebraic guarantee)")
        if delta != 0.0:
            print(f"  ✗ σ-EQUIVARIANCE BROKEN — investigate Codegen.CoreML")
            return 1

    print("\n=== Step 3b: MLX σ-equivariance numerical check (bit-exact) ===")
    # The MLX module is the PRIMARY trainer; assert σ-equivariance bit-exact on it
    # too, exactly like the torch arm above. Same-weights transfer (the two modules
    # are structurally 1:1) lets us load the torch state_dict into MLX.
    try:
        import mlx.core as mx
        import look_net_mlx as mlxm
    except Exception as e:  # noqa: BLE001
        print(f"  ✗ MLX import failed: {e}")
        return 1
    mlx_net = mlxm.LookNet()
    sd = model.state_dict()
    mlx_net.encoder.phi.weight = mx.array(sd["encoder.phi.weight"].numpy())
    mlx_net.recursion.g.w1.weight = mx.array(sd["recursion.g.w1.weight"].numpy())
    mlx_net.recursion.g.w2.weight = mx.array(sd["recursion.g.w2.weight"].numpy())
    mlx_net.recursion.g.halt_mlp.weight = mx.array(sd["recursion.g.halt_mlp.weight"].numpy())
    mlx_net.recursion.g.halt_mlp.bias = mx.array(sd["recursion.g.halt_mlp.bias"].numpy())
    for k in range(len(mlx_net.decoder.heads)):
        mlx_net.decoder.heads[k].weight = mx.array(sd[f"decoder.heads.{k}.weight"].numpy())
    mx.eval(mlx_net.parameters())

    mlx_tokens = mx.array(tokens.numpy())
    mlx_mask = mx.array(token_mask.numpy())
    mlx_flip_in = mx.array(np.array([-1.0 if b else 1.0 for b in mlxm.GMM_TOKEN_SIGMA_MASK], dtype=np.float32))
    mlx_flip_out = mx.array(np.array([-1.0 if b else 1.0 for b in mlxm.SIGMA_DECODER_MASK], dtype=np.float32))
    mlx_out_orig = mlx_net(mlx_tokens, token_mask=mlx_mask)
    mlx_out_sigma = mlx_net(mlx_tokens * mlx_flip_in, token_mask=mlx_mask)
    mlx_expected = mlx_out_orig * mlx_flip_out
    mx.eval(mlx_out_orig, mlx_out_sigma, mlx_expected)
    mlx_delta = float(np.abs(np.array(mlx_out_sigma) - np.array(mlx_expected)).max())
    print(f"  max|σ(E(x)) - E(σx)| = {mlx_delta:.2e}  (must be 0 by algebraic guarantee)")
    if mlx_delta != 0.0:
        print(f"  ✗ MLX σ-EQUIVARIANCE BROKEN — investigate Codegen.MLX")
        return 1

    print("\n=== Step 3c: same-weights MLX vs PyTorch forward agreement ===")
    # Both backends load the IDENTICAL weights; outputs must agree to ~1e-6
    # (cross-framework matmul summation order differs only at the ULP level).
    torch_fwd = out_orig.numpy().astype(np.float64).reshape(-1)
    mlx_fwd = np.array(mlx_out_orig).astype(np.float64).reshape(-1)
    if not np.all(np.isfinite(mlx_fwd)):
        print("  ✗ MLX forward produced non-finite values")
        return 1
    fwd_max_abs = float(np.abs(mlx_fwd - torch_fwd).max())
    scale = max(float(np.abs(torch_fwd).max()), 1e-9)
    FWD_RTOL = 1e-5
    print(f"  max|mlx - torch| = {fwd_max_abs:.2e}  (relative {fwd_max_abs/scale:.2e} of |max|={scale:.4f})")
    if fwd_max_abs / scale > FWD_RTOL:
        print(f"  ✗ MLX↔PyTorch forward disagree beyond rtol={FWD_RTOL:.0e}")
        return 1
    print(f"  ✓ MLX and PyTorch agree within rtol={FWD_RTOL:.0e}")

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

    print("\n=== Step 7: numerical round-trip — PyTorch vs .mlpackage ===")
    # Run the SAME input through both backends. The .mlpackage is FP16 internally
    # (compute_precision=FLOAT16); PyTorch is FP32. FP16 has ~10 mantissa bits ⇒
    # ~5e-4 relative precision per op; with O(MAX_TOKENS) reductions inside L3
    # sum-pool the error can amplify by ~√MAX_TOKENS ≈ 128, giving ~6e-2 relative
    # drift as a generous bound. Outputs scale ~√MAX_TOKENS naturally under random
    # init (sum of 16384 unit-variance things), so ABSOLUTE tolerance is the wrong
    # frame; use RELATIVE (numpy.allclose-style atol + rtol).
    ml_in_tokens = tokens.numpy().astype(np.float32)
    ml_in_mask = token_mask.numpy().astype(np.float32)
    ml_out = mlmodel.predict({"tokens": ml_in_tokens, "token_mask": ml_in_mask})
    ml_haar = np.array(ml_out["haar_coeffs"]).astype(np.float32)
    torch_haar = out_orig.numpy().astype(np.float32)
    abs_diff = np.abs(ml_haar - torch_haar)
    max_abs = abs_diff.max()
    mean_abs = abs_diff.mean()
    pt_max = np.abs(torch_haar).max()
    rel = max_abs / max(pt_max, 1e-9)
    print(f"  PyTorch output range:   [{torch_haar.min():+.4f}, {torch_haar.max():+.4f}] (|max| = {pt_max:.4f})")
    print(f"  mlpackage output range: [{ml_haar.min():+.4f}, {ml_haar.max():+.4f}]")
    print(f"  max |mlpackage - pytorch| = {max_abs:.4f}  (relative: {rel:.2e} of |max|)")
    print(f"  mean|mlpackage - pytorch| = {mean_abs:.4f}")
    # Tolerance is derived from the architecture, not picked from a hat. The L3
    # sum-pool reduces MAX_TOKENS=16384 FP16 summands of per-summand magnitude
    # ~√GMM_TOKEN_DIM ≈ 3.16. The FP16 ulp at magnitude 3 is ~1.5e-3 absolute;
    # a random-walk accumulation over N summands has stddev √N · per-summand-ulp
    # ≈ 128 · 1.5e-3 ≈ 0.19 — i.e. ~0.5 is the architectural FP16 noise floor
    # for this layer's reduction. We allow that absolute bound + 5e-3 relative
    # for elements above the noise floor (standard FP16 per-op precision).
    # Anything beyond this is a real coremltools lowering bug, not numerics.
    RTOL = 5e-3
    ATOL = 0.5   # derived from √MAX_TOKENS · ulp(√GMM_TOKEN_DIM)
    numerical_ok = bool(np.allclose(ml_haar, torch_haar, rtol=RTOL, atol=ATOL))
    if numerical_ok:
        print(f"  ✓ within FP16 lowering tolerance (rtol={RTOL:.0e}, atol={ATOL:.0e})")
    else:
        print(f"  ✗ NUMERICAL DRIFT exceeds rtol={RTOL:.0e}, atol={ATOL:.0e}")
        # Show worst-offender index for debugging.
        worst = int(np.unravel_index(abs_diff.argmax(), abs_diff.shape)[1])
        print(f"    worst at idx {worst}: pytorch={torch_haar[0, worst]:+.4f}  mlpackage={ml_haar[0, worst]:+.4f}")

    print("\n=== Step 8: σ-equivariance preserved through .mlpackage lowering ===")
    # Run σ(x) through the .mlpackage; compare to σ(MLPkg(x)).
    ml_in_tokens_sigma = (tokens * flip_in).numpy().astype(np.float32)
    ml_out_sigma = mlmodel.predict({"tokens": ml_in_tokens_sigma, "token_mask": ml_in_mask})
    ml_haar_sigma = np.array(ml_out_sigma["haar_coeffs"]).astype(np.float32)
    flip_out_np = flip_out.numpy().astype(np.float32)
    expected_sigma_out = ml_haar * flip_out_np
    delta_sigma = np.abs(ml_haar_sigma - expected_sigma_out).max()
    mean_sigma = np.abs(ml_haar_sigma - expected_sigma_out).mean()
    print(f"  max |σ(MLPkg(x)) - MLPkg(σx)| = {delta_sigma:.2e}")
    print(f"  mean|σ(MLPkg(x)) - MLPkg(σx)| = {mean_sigma:.2e}")
    TOL_SIGMA = 1e-2
    if delta_sigma > TOL_SIGMA:
        print(f"  ✗ σ-EQUIVARIANCE BROKEN in .mlpackage (>{TOL_SIGMA})")
        sigma_ok = False
    else:
        print(f"  ✓ σ-equivariance survives the lowering (within {TOL_SIGMA:.0e})")
        sigma_ok = True

    print()
    if numerical_ok and sigma_ok:
        print("✓ END-TO-END SPEC → .mlpackage VERIFIED (PyTorch agreement + σ-equivariance)")
        return 0
    else:
        print("✗ END-TO-END FAILED — see diagnostics above")
        return 1


if __name__ == "__main__":
    sys.exit(main())
