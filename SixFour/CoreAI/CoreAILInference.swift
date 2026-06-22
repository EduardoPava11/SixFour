//
//  CoreAILInference.swift
//  SixFour
//
//  PURPOSE: the on-device inference seam for the frozen L (grayscale) net.
//  Loads the `L.aimodel` produced by `trainer/coreai_export/` and runs it through
//  Apple's Core AI runtime. This is the iOS half of the 2026-06-20 pivot — see
//  CLAUDE.md (the amendment block).
//
//  CONTRACT (amended 2026-06-20, see CLAUDE.md):
//   • Core AI is an Apple SYSTEM framework, so it satisfies the zero-third-party
//     Tier-2 rule. It is adopted ONLY for L INFERENCE — never for training, never
//     for A/B (those stay MPSGraph in `Atlas/`).
//   • Core AI ships only in the DEVICE SDK, not the iOS Simulator SDK
//     (coreai-models issue #49), so every use is behind `#if canImport(CoreAI)`.
//     On the simulator / headless builds the type still compiles via the
//     `floorOnly` path below; the Core AI branch is verifiable only on a device.
//   • DETERMINISM: Core AI float output is NOT cross-device bit-exact. Callers
//     MUST route the result through the `zero-genome == floor` short-circuit into
//     the Zig Q16 core (see `Native/`) before it can reach the GIF bytes. This
//     type returns a float prediction; it never writes output pixels directly.
//
//  STATUS: ORPHANED 2026-06-22. The target (frozen grayscale-L look-net) was
//  abandoned 2026-06-17 (look_net_trained.s4ln deleted); it fed the V2-deferred
//  global-palette path (Feature.globalPaletteV2 = false). The settled encoder needs
//  NO learned L: the lift is frozen, theta_B (63 params) ships hand-written in
//  Native/MaskedBandForward.swift with no Core AI, A/B stays MPSGraph, CarrierL is
//  deterministic. Retired, not deleted: kept as the audit record of
//  Core-AI-considered-and-dropped. Do NOT repoint at DisplayDecoder (a spec-only
//  quarantine stub with no determinism need = no Core AI justification). Resurrect
//  ONLY if a genuinely LARGE on-device generative-L head is roadmapped with a real
//  trainer + weights. Zero callers; this annotation is comment-only, no behaviour change.
//

import Foundation
#if canImport(CoreAI)
import CoreAI
#endif

/// Loads and runs the frozen L (grayscale) net via Core AI, with a deterministic
/// fall-through so the build is valid where Core AI is unavailable.
final class CoreAILInference {

    /// Whether the Core AI runtime is present (device builds with iOS 27 SDK).
    static var isAvailable: Bool {
        #if canImport(CoreAI)
        return true
        #else
        return false
        #endif
    }

    #if canImport(CoreAI)
    private let model: AIModel

    /// Load `L.aimodel` from the app bundle (delivered via Background Assets).
    /// - Throws: if the asset is missing or fails to specialize for this device.
    init(assetURL: URL) throws {
        // AOT-specialized on first load and cached; see WWDC26 session 324.
        self.model = try AIModel(contentsOf: assetURL)
    }
    #endif

    /// Run L inference. Returns the raw float prediction; the CALLER must pass it
    /// through the Zig `zero-genome == floor` short-circuit before any GIF write.
    ///
    /// On a build without Core AI this returns `nil`, signalling the caller to use
    /// the deterministic Zig floor directly (the safe, bit-exact path).
    func predictL(tokens: [Float]) -> [Float]? {
        #if canImport(CoreAI)
        // TODO(pivot): build an NDArray view over `tokens` (zero-copy), run the
        // model's inference function, and return the L logits. Verify on device.
        return nil
        #else
        // Core AI absent (simulator / pre-iOS-27 SDK): signal the caller to use
        // the deterministic Zig floor directly. Intentional — this is the seam.
        return nil
        #endif
    }
}
