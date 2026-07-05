#include <metal_stdlib>
using namespace metal;

/// YANG-HEAD TRAINING, ON THE PHONE — the fused full-batch gradient-descent
/// kernel for one tiny linear band head (the S_t / S_y / S_x lineage:
/// theorem-sized widths, Spec.YinYangCNN). Plain Metal (no MPSGraph), so it
/// runs in the simulator and on device alike — the RungDispatch pattern.
///
/// DETERMINISM FIRST: thread 0 performs the whole descent SEQUENTIALLY —
/// fixed accumulation order, bit-stable across runs on the same device (the
/// BandHeadTrainerTests determinism gate). The batch is tiny by design (the
/// heads are 1/2/4-wide per block; features are a handful of context values),
/// so a single thread finishes in milliseconds; the SIMT reduction is a later
/// optimization, gated against this kernel's bytes when it lands.
///
/// The trained float weights re-enter the Zig Q16 floor before touching any
/// GIF byte (the contract) — this kernel owns descent, never realization.

struct BandHeadParams {
    uint  nPairs;     // training pairs in the batch
    uint  nFeatures;  // feature width (small)
    uint  steps;      // full-batch GD steps
    float eta;        // learning rate
};

kernel void bandHeadTrainKernel(
    device const float *feats    [[buffer(0)]],  // nPairs x nFeatures, row-major
    device const float *targets  [[buffer(1)]],  // nPairs
    device float       *weights  [[buffer(2)]],  // nFeatures, in/out (init by host)
    constant BandHeadParams &p   [[buffer(3)]],
    device float        *outMSE  [[buffer(4)]],  // [0] initial, [1] final
    uint tid [[thread_position_in_grid]])
{
    if (tid != 0) { return; }
    const uint n = p.nPairs;
    const uint f = p.nFeatures;

    // initial loss
    float mse0 = 0.0f;
    for (uint i = 0; i < n; i++) {
        float pred = 0.0f;
        for (uint j = 0; j < f; j++) { pred += weights[j] * feats[i * f + j]; }
        float d = pred - targets[i];
        mse0 += d * d;
    }
    outMSE[0] = mse0 / float(n);

    // full-batch gradient descent, fixed order
    for (uint s = 0; s < p.steps; s++) {
        for (uint j = 0; j < f; j++) {
            float g = 0.0f;
            for (uint i = 0; i < n; i++) {
                float pred = 0.0f;
                for (uint k = 0; k < f; k++) { pred += weights[k] * feats[i * f + k]; }
                g += (pred - targets[i]) * feats[i * f + j];
            }
            weights[j] -= p.eta * 2.0f * g / float(n);
        }
    }

    // final loss
    float mse1 = 0.0f;
    for (uint i = 0; i < n; i++) {
        float pred = 0.0f;
        for (uint j = 0; j < f; j++) { pred += weights[j] * feats[i * f + j]; }
        float d = pred - targets[i];
        mse1 += d * d;
    }
    outMSE[1] = mse1 / float(n);
}
