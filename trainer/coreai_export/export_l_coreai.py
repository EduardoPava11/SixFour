"""export_l_coreai.py — convert the frozen L (grayscale) net to a Core AI .aimodel.

PURPOSE: the L-channel deploy bridge of the 2026-06-20 pivot (see
CLAUDE.md (2026-06-20 amendment) and ./README.md). Train L in MLX/PyTorch on the Mac;
this script exports it for INFERENCE on the iPhone via Apple Core AI.

SCOPE: L only, inference only. Core AI cannot train; the A/B chroma channels
learn on-device with MPSGraph and never pass through here.

STATUS: SCAFFOLD. The Core AI conversion call sequence below is the real,
verified coreai-torch API (coreai-torch 0.4.0, verified 2026-06-20: a round-trip
matched PyTorch to 6 d.p.). The TODOs are the SixFour-specific wiring: loading
the MLX-trained L weights from the .s4ln blob into the nn.Module, and the
optional TorchMetalKernel that embeds the owned cube-ladder collapse.

Requires: Apple-Silicon Mac, Python 3.11/3.12, `uv pip install coreai-torch`.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import torch

# coreai-torch is the PyTorch -> Core AI IR bridge (apple/coreai-torch).
import coreai_torch
from coreai_torch import TorchConverter
# from coreai_torch.dsl import TorchMetalKernel, MetalParameter  # owned-kernel embed


def load_frozen_l_net(weights: Path) -> torch.nn.Module:
    """Build the L (grayscale) forward module and load frozen MLX-trained weights.

    TODO(pivot): parse the .s4ln blob (Zig `s4_load_look_net` format) and copy the
    L head weights into this module. Until then this is a shape-only placeholder so
    the conversion pipeline below can be exercised end-to-end.
    """
    raise NotImplementedError(
        "wire .s4ln -> nn.Module L head; see trainer/export_look_net_blob.py for "
        "the blob layout and Generated/NetContract.swift for the canonical shape"
    )


def example_input() -> tuple[torch.Tensor, ...]:
    """One representative input: a per-frame 256-colour palette stack (NN input)."""
    # TODO(pivot): match Spec/StageA.hs token shape (per-frame palette tokens).
    return (torch.zeros(1, 256, 3),)


def export(weights: Path, out: Path) -> None:
    model = load_frozen_l_net(weights).eval()

    # 1. torch.export -> decompose to the op set Core AI lowers from.
    ep = torch.export.export(model, args=example_input())
    ep = ep.run_decompositions(coreai_torch.get_decomp_table())

    # 2. (optional) register the owned cube-ladder collapse as an inline Metal
    #    kernel so it ships INSIDE the asset rather than as an opaque op.
    converter = TorchConverter()
    # TODO(pivot): converter.register_custom_kernels([collapse_kernel])  # TorchMetalKernel

    # 3. convert + optimize -> Core AI program, then save the .aimodel asset.
    program = converter.add_exported_program(ep).to_coreai()
    program.optimize()  # quantize/palettize (coreai-optimization)
    program.save_asset(out)
    print(f"wrote {out}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--weights", type=Path, required=True, help="frozen L .s4ln blob")
    ap.add_argument("--out", type=Path, required=True, help="output L.aimodel path")
    args = ap.parse_args()
    export(args.weights, args.out)


if __name__ == "__main__":
    main()
