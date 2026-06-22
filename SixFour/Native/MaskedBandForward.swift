//
//  MaskedBandForward.swift
//  SixFour
//
//  The JEPA encoder's LEARNED forward, hand-written (NO Core AI). The encoder is the
//  frozen reversible lift (zero params, the Zig s4_haar core) plus the ONLY learned
//  object: the 63-param theta_B masked-band predictor (SixFour.Spec.MaskedBandPrediction).
//  theta_B is a 9-wide dot product per band, so it ships as a hand-written Swift forward
//  per the CLAUDE.md "on-device NN inference = hand-written forward pass" rule. It is
//  byte-exact to the Haskell spec, gated by `MaskedBandGolden` (Generated) in
//  MaskedBandForwardTests.
//
//  The committed value is the Q16 BYTE = quantizeQ16(raw) = round-half-to-even(raw*65536),
//  the single sanctioned float->device crossing (Spec.ByteCarrier.reenterQ16). The Mac-side
//  `raw` is a float Latent and must never reach a byte except through `predict`.
//

import Foundation

enum MaskedBandForward {
    static let numBands = 7
    static let featureCount = 9          // phi_B = [1, vtilde, vtilde^2] ++ 6 siblings
    private static let q16 = 65536.0

    /// Clamp a band index into [0, numBands) the same way the spec's `clampIndex` does.
    private static func clampIndex(_ m: Int) -> Int {
        ((m % numBands) + numBands) % numBands
    }

    /// The 6 VISIBLE sibling bands (every band except the masked one), canonical order.
    /// Mirrors `MaskedBandPrediction.siblingsOf`.
    static func siblings(detail: [Int], masked: Int) -> [Int] {
        let m = clampIndex(masked)
        return detail.enumerated().filter { $0.offset != m }.map { $0.element }
    }

    /// phi_B(coarse, siblings) = [1, vtilde, vtilde^2] ++ map toQ16 siblings, always
    /// `featureCount` wide (siblings padded/trimmed to 6). Mirrors `featuresB`.
    static func features(coarse: Int, siblings sibs: [Int]) -> [Double] {
        let v = Double(coarse) / q16
        var f: [Double] = [1.0, v, v * v]
        for x in sibs.prefix(6) { f.append(Double(x) / q16) }
        while f.count < featureCount { f.append(0.0) }
        return f
    }

    /// rawMaskedBand = theta row(masked) . phi_B, summed LEFT-TO-RIGHT to match the
    /// Haskell `sum (zipWith (*) ...)` order exactly (so the float result is bit-identical,
    /// not merely within tolerance). A Mac-side Latent; not a device byte.
    static func raw(theta: [Double], coarse: Int, detail: [Int], masked: Int) -> Double {
        let m = clampIndex(masked)
        let phi = features(coarse: coarse, siblings: siblings(detail: detail, masked: masked))
        let row = theta[(m * featureCount)..<((m + 1) * featureCount)]
        var acc = 0.0
        var i = 0
        for w in row { acc += w * phi[i]; i += 1 }
        return acc
    }

    /// THE committed prediction: the masked band's Q16 byte. This is the single
    /// float->device crossing: `quantizeQ16(raw) = round-half-to-even(raw * 65536)`
    /// (Haskell `round`). Mirrors `predictMaskedBand`.
    static func predict(theta: [Double], coarse: Int, detail: [Int], masked: Int) -> Int {
        Int((raw(theta: theta, coarse: coarse, detail: detail, masked: masked) * q16)
            .rounded(.toNearestOrEven))
    }
}
