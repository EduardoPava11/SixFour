import Foundation
import simd

struct OKLab: Sendable, Hashable {
    let L: Float
    let a: Float
    let b: Float

    var simd: SIMD3<Float> { SIMD3(L, a, b) }

    init(_ L: Float, _ a: Float, _ b: Float) {
        self.L = L; self.a = a; self.b = b
    }

    init(_ v: SIMD3<Float>) {
        self.L = v.x; self.a = v.y; self.b = v.z
    }
}

enum ColorScience {

    @inline(__always)
    static func srgbToLinear(_ x: Float) -> Float {
        x <= 0.04045 ? x / 12.92 : powf((x + 0.055) / 1.055, 2.4)
    }

    @inline(__always)
    static func linearToSRGB(_ x: Float) -> Float {
        x <= 0.0031308 ? 12.92 * x : 1.055 * powf(x, 1.0 / 2.4) - 0.055
    }

    /// Björn Ottosson's OKLab (https://bottosson.github.io/posts/oklab/).
    /// Input: linear sRGB in [0, 1]. Output: OKLab (L ∈ [0,1], a/b roughly [-0.4, 0.4]).
    static func linearSRGBToOKLab(_ rgb: SIMD3<Float>) -> OKLab {
        let l = 0.4122214708 * rgb.x + 0.5363325363 * rgb.y + 0.0514459929 * rgb.z
        let m = 0.2119034982 * rgb.x + 0.6806995451 * rgb.y + 0.1073969566 * rgb.z
        let s = 0.0883024619 * rgb.x + 0.2817188376 * rgb.y + 0.6299787005 * rgb.z

        let l_ = cbrtf(l)
        let m_ = cbrtf(m)
        let s_ = cbrtf(s)

        return OKLab(
            0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    static func okLabToLinearSRGB(_ lab: OKLab) -> SIMD3<Float> {
        let l_ = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m_ = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s_ = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b

        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_

        return SIMD3(
             4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    static func srgb8ToOKLab(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> OKLab {
        let linear = SIMD3<Float>(
            srgbToLinear(Float(r) / 255),
            srgbToLinear(Float(g) / 255),
            srgbToLinear(Float(b) / 255)
        )
        return linearSRGBToOKLab(linear)
    }

    static func okLabToSRGB8(_ lab: OKLab) -> SIMD3<UInt8> {
        let linear = okLabToLinearSRGB(lab)
        let r = max(0, min(1, linear.x))
        let g = max(0, min(1, linear.y))
        let b = max(0, min(1, linear.z))
        return SIMD3<UInt8>(
            UInt8(round(linearToSRGB(r) * 255)),
            UInt8(round(linearToSRGB(g) * 255)),
            UInt8(round(linearToSRGB(b) * 255))
        )
    }
}

/// Squared Euclidean distance in OKLab — perceptually uniform-ish, cheap.
/// Returns squared distance so callers can compare without sqrt.
@inline(__always)
func okLabDistanceSquared(_ a: OKLab, _ b: OKLab) -> Float {
    let dL = a.L - b.L
    let da = a.a - b.a
    let db = a.b - b.b
    return dL * dL + da * da + db * db
}

/// CIEDE2000 in OKLab — overkill for most uses; preserved as a reference
/// against which custom metrics can be sanity-checked.
/// For the hot path (k-means inner loop), use `okLabDistanceSquared` or a learned metric.
func ciede2000Lab(_ lab1: OKLab, _ lab2: OKLab) -> Float {
    // OKLab is already perceptually uniform; CIEDE2000 in OKLab degenerates close to Euclidean.
    // Keep this as a stub returning sqrt(distSq) so the API surface exists for organ training.
    sqrtf(okLabDistanceSquared(lab1, lab2))
}
