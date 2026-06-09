#if DEBUG
import Foundation
import simd

/// SYNTHETIC CAMERA for a TESTABLE Act I — the iOS Simulator has no camera, so the live path
/// produces no `previewTile`/palette and the influence field has nothing to radiate. `DemoScene`
/// stands in for the sensor: a 64×64 index tile + 256-colour palette that DRIFTS with the κ tick
/// and has deliberately NON-UNIFORM colour usage, so the field's usage-weighted spokes, edge
/// bleed, ridge muting, and 20 fps breathing are all exercised without hardware.
///
/// The "order vs chaos" lens (user, 2026-06-09): the two widgets are ORDER; the cells around them
/// are CHAOS radiating out of them. The scene below feeds that — two moving "subjects" dominate
/// the histogram (their colours throw long, ordered spokes) while drifting interference bands keep
/// the rest of the field alive and varied.
///
/// DEBUG-ONLY — never compiled into release. Enable in the running app with the launch argument
/// `-demoScene` (Scheme ▸ Run ▸ Arguments), or use the `LivePhaseField` #Preview.
/// (docs/SIXFOUR-TESTABLE-ACT1-WORKFLOW.md)
enum DemoScene {
    static let side = 64

    /// A fixed, representative 256-colour live palette: a hue sweep modulated by value + sat waves.
    static let palette: [SIMD3<UInt8>] = (0 ..< 256).map { i in
        let h = Double(i) / 256.0 * 360.0
        let s = 0.55 + 0.35 * (0.5 + 0.5 * cos(Double(i) * 0.11))
        let v = 0.45 + 0.50 * (0.5 + 0.5 * sin(Double(i) * 0.19))
        return hsv(h, s, v)
    }

    /// The 64×64 index tile (row-major `y·64+x`) at κ `tick`: drifting interference bands with two
    /// moving dominant subjects, so a few palette colours are used far more than the rest.
    static func tile(tick: Int) -> [UInt8] {
        let t = Double(tick) * 0.12
        var out = [UInt8](repeating: 0, count: side * side)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let fx = Double(x), fy = Double(y)
                var v = sin(fx * 0.18 + t) + sin(fy * 0.16 - t * 0.7) + sin((fx + fy) * 0.13 + t * 0.5)
                v = (v + 3) / 6                                   // → [0,1]
                var idx = Int(v * 255)
                // Two drifting "subjects" that dominate the histogram → long, ordered spokes.
                if blob(fx, fy, 18 + 14 * sin(t), 22 + 12 * cos(t * 0.8), 9) { idx = 40 }
                if blob(fx, fy, 44 + 10 * cos(t * 0.6), 40 + 14 * sin(t * 0.9), 8) { idx = 200 }
                out[y * side + x] = UInt8(max(0, min(255, idx)))
            }
        }
        return out
    }

    private static func blob(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ r: Double) -> Bool {
        let dx = x - cx, dy = y - cy
        return dx * dx + dy * dy <= r * r
    }

    /// Minimal HSV→sRGB8 (demo only — off the verified colour path).
    private static func hsv(_ h: Double, _ s: Double, _ v: Double) -> SIMD3<UInt8> {
        let c = v * s, hp = h / 60.0
        let xx = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r = 0.0, g = 0.0, b = 0.0
        switch Int(hp) % 6 {
        case 0: r = c; g = xx
        case 1: r = xx; g = c
        case 2: g = c; b = xx
        case 3: g = xx; b = c
        case 4: r = xx; b = c
        default: r = c; b = xx
        }
        let m = v - c
        @inline(__always) func u(_ z: Double) -> UInt8 { UInt8(max(0, min(255, ((z + m) * 255).rounded()))) }
        return SIMD3(u(r), u(g), u(b))
    }
}
#endif
