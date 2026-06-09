#include <metal_stdlib>
#include "../Generated/FieldTuning.metal.h"   // generated: kField* constants (Spec.InfluenceField)
using namespace metal;

// THE INFLUENCE FIELD on the GPU (S2) — a fragment shader port of `FieldModel` (InfluenceField.swift),
// the radiation ground. Renders the whole Stage per frame off the main thread, replacing the CPU
// per-tick CellBitmap bake (the fluidity fix; docs/SIXFOUR-CAPTURE-FLUIDITY-SYSTEMS.md M1).
//
// Spec-aligned: the falloff/seam/lift constants come from FieldTuning.metal.h (one source with the
// Swift FieldTuning facade); the Stage mask is the byte-exact integer `Boundary.inside`; the dither
// noise is the byte-exact hash (verified == the Haskell golden). Cells stay discrete (the shader
// floors to the 4 pt grid). No occlusion branch — widgets draw opaque ON TOP in SwiftUI, so a lifted
// widget moving away reveals live (lift-dimmed) field, never a black hole.

// One radiating order-source (a widget). Passed in its OWN buffer (not nested in the uniforms
// struct) so the Swift↔Metal layout is a flat array of a simple struct — robust to alignment.
// Swift mirror: `FieldSourceU` in FieldMetalView.swift (same field order).
struct FieldSourceU {
    float minX;   // top-left in CELL coords (inclusive)
    float minY;
    float maxX;   // bottom-right in CELL coords (exclusive)
    float maxY;
    int   kind;   // 0 = arrangement (bleed the tile), 1 = set (usage-weighted palette wheel)
    int   _pad0;  // explicit pad → 24-byte stride, matched exactly in Swift
};

// Scalars only (no nested arrays) → trivially layout-matched with the Swift mirror via setBytes.
struct FieldUniforms {
    float cellSizePx;                 // drawable pixels per cell (gifPx · contentScale)
    float liftAmount;                 // 0…1 eased lift-dim (F3)
    int   cols, rows;                 // lattice extent (SixFourLattice)
    int   minC, maxC, minR, maxR;     // Stage bounds (SixFourBoundary)
    int   cornerCells;                // Stage corner radius (cells)
    int   sourceCount;                // active sources
    int   tick;                       // κ monotonic tick (drives the breathing drift)
    int   _pad0;                      // pad to 16-byte multiple (matched in Swift)
};

// --- pure helpers (byte-/tolerance-faithful to FieldModel) ---

// Byte-exact dither noise hash (== Spec.InfluenceField.noiseHash / InfluenceFieldGolden).
static uint fieldNoiseHash(int c, int r, int f) {
    uint h = uint(c * 73856093) ^ uint(r * 19349663) ^ uint(f * 83492791) ^ 0x9e3779b9u;
    h ^= h >> 13; h *= 0x5bd1e995u; h ^= h >> 15;
    return h;
}
static float fieldNoiseUnit(int c, int r, int f) {
    return float(fieldNoiseHash(c, r, f)) / float(0xFFFFFFFFu);
}

// Euclidean distance (cells) from p to the rect [lo,hi) (0 inside).
static float distToRect(float2 p, float2 lo, float2 hi) {
    float dx = max(max(lo.x - p.x, 0.0), p.x - hi.x);
    float dy = max(max(lo.y - p.y, 0.0), p.y - hi.y);
    return sqrt(dx * dx + dy * dy);
}

// Angle of p about centre c: 0 at top, clockwise, normalised to [0,1).
static float turnOf(float2 p, float2 c) {
    float a = atan2(p.x - c.x, -(p.y - c.y));
    if (a < 0.0) a += 2.0 * M_PI_F;
    return a / (2.0 * M_PI_F);
}

// The integer Stage mask — byte-exact `Boundary.inside` (SixFourBoundary).
static bool stageInside(constant FieldUniforms& u, int c, int r) {
    if (c < u.minC || c >= u.maxC || r < u.minR || r >= u.maxR) return false;
    int rad = u.cornerCells;
    int nx = (c < u.minC + rad) ? (u.minC + rad) - c : ((c >= u.maxC - rad) ? c - (u.maxC - rad - 1) : 0);
    int ny = (r < u.minR + rad) ? (u.minR + rad) - r : ((r >= u.maxR - rad) ? r - (u.maxR - rad - 1) : 0);
    return nx * nx + ny * ny <= rad * rad;
}

static float3 paletteColor(device const uchar* palette, int idx) {
    int i = clamp(idx, 0, 255) * 3;
    return float3(float(palette[i]), float(palette[i + 1]), float(palette[i + 2])) / 255.0;
}

// --- vertex: a single fullscreen triangle from the vertex id ---
struct VOut { float4 pos [[position]]; };

vertex VOut fieldVertex(uint vid [[vertex_id]]) {
    float2 uv = float2(float((vid << 1) & 2), float(vid & 2)); // (0,0),(2,0),(0,2)
    VOut o;
    o.pos = float4(uv * 2.0 - 1.0, 0.0, 1.0);                  // (-1,-1),(3,-1),(-1,3)
    return o;
}

// --- fragment: the field colour for this pixel's cell ---
fragment float4 fieldFragment(VOut in [[stage_in]],
                              constant FieldUniforms&    u       [[buffer(0)]],
                              device const uchar*        palette [[buffer(1)]],   // 256 × (r,g,b)
                              device const float*        usage   [[buffer(2)]],   // 256, normalised
                              device const uchar*        tile    [[buffer(3)]],   // 64×64 indices
                              device const FieldSourceU* sources [[buffer(4)]]) {  // u.sourceCount
    int c = int(floor(in.pos.x / u.cellSizePx));
    int r = int(floor(in.pos.y / u.cellSizePx));
    if (!stageInside(u, c, r)) return float4(0.0, 0.0, 0.0, 1.0);  // outside the Stage = black bezel

    float2 p = float2(float(c) + 0.5, float(r) + 0.5);

    // Energy from every source; track the top two + the dominant source's colour AND centre.
    float w1 = 0.0, w2 = 0.0, sum = 0.0;
    float3 domColor = kFieldNeutral;
    float2 domC = p;
    for (int i = 0; i < u.sourceCount; i++) {
        FieldSourceU s = sources[i];
        float2 lo = float2(s.minX, s.minY);
        float2 hi = float2(s.maxX, s.maxY);
        float2 ctr = (lo + hi) * 0.5;
        float d = distToRect(p, lo, hi);
        float reach;
        float3 col;
        if (s.kind == 1) {                                    // .set — usage-weighted palette wheel
            int rank = clamp(int(turnOf(p, ctr) * 256.0), 0, 255);
            reach = kFieldReachSet * (kFieldUsageReachMin + (1.0 - kFieldUsageReachMin) * usage[rank]);
            col = paletteColor(palette, rank);
        } else {                                              // .arrangement — bleed the tile edge
            reach = kFieldReachArrangement;
            int lc = clamp(int(p.x - s.minX), 0, 63);
            int lr = clamp(int(p.y - s.minY), 0, 63);
            col = paletteColor(palette, int(tile[lr * 64 + lc]));
        }
        float w = max(0.0, 1.0 - d / max(1.0, reach));
        sum += w;
        if (w > w1) { w2 = w1; w1 = w; domColor = col; domC = ctr; }
        else if (w > w2) { w2 = w; }
    }
    if (sum <= 0.001) return float4(kFieldFarDark, 1.0);       // far calm

    float E = min(1.0, sum) * (1.0 - u.liftAmount * (1.0 - kFieldLiftDim));
    float interplay = (w1 > 0.0) ? (w2 / w1) : 0.0;
    float3 lit = mix(domColor, kFieldNeutral, kFieldSeamMute * interplay);

    // Coherent outward drift: sample the dither threshold at a point marching outward from the
    // dominant source by driftPerTick·tick — the chaos flows out of the order each tick.
    float2 dv = p - domC;
    float len = max(0.001, length(dv));
    float off = float(u.tick) * kFieldDriftPerTick;
    int sx = int(floor(p.x - dv.x / len * off));
    int sy = int(floor(p.y - dv.y / len * off));
    float n = fieldNoiseUnit(sx, sy, 0);
    return (n < E) ? float4(lit, 1.0) : float4(kFieldFarDark, 1.0);
}
