import SwiftUI
import UIKit
import simd

/// THE ONE GROUND for every act — a full-screen cell field of the 4 pt atom, MASKED to the
/// canonical **Stage**: the inset rounded rectangle `Boundary.inside`. Every rendered cell is a
/// whole 4 pt square that fits the physical screen — nothing under the Dynamic Island, nothing
/// in the four physical rounded corners (~56 pt radius, matched by `Boundary.cornerCells`).
/// Cells outside the Stage are transparent → the black background (== the device bezel), so the
/// lit field reads as a rounded rectangle floating on black.
///
/// The masking lives HERE, not in each caller's sampler: `StageField` calls `cell(c, r, frame)`
/// only where `Boundary.inside(c, r)` is true and emits `nil` (transparent) everywhere else. So
/// the live influence field, the B/W heartbeat checker, and any future ground all share one
/// masked renderer and one canonical grid (the "same grid for all acts" requirement).
///
/// PERF — the O(1)-flip discipline (mirrors `GridRefreshFieldView`): the `phaseCount` animation
/// frames are pre-baked into `UIImage`s ONCE per `bakeKey` (the inputs the field depends on —
/// widget positions, palette, usage), and each 20 fps tick SWAPS to `frames[phase % phaseCount]`,
/// never a per-cell re-bake. A 2-frame checker and an N-frame breathing noise ring both fit.
///
/// Tier-2 pure: SwiftUI + UIKit + simd, zero third-party deps. Off the deterministic GIF path
/// (a tinted ground, not an indexed GIF cell), so a blended/dithered sampler is allowed here.
struct StageField: View {
    /// How many pre-baked animation frames to cycle (2 for a checker parity, N for a noise ring).
    let phaseCount: Int
    /// The 20 fps heartbeat bit from κ; selects `frames[phase % phaseCount]`.
    let phase: Int
    /// Re-bake the frames ONLY when this changes (the field's inputs: positions / palette / usage).
    /// A stable key across ticks keeps the 20 fps loop a pure texture swap.
    let bakeKey: AnyHashable
    /// The sRGB8 a Stage cell shows on animation `frame` (0 ..< phaseCount); `nil` = transparent.
    /// Called ONLY for cells inside the Stage — callers never repeat the mask test.
    let cell: (_ c: Int, _ r: Int, _ frame: Int) -> SIMD3<UInt8>?

    /// Cache: the key the current frames were baked for, plus the pre-baked images.
    @State private var baked: (key: AnyHashable, frames: [UIImage?])? = nil

    var body: some View {
        let frames = ensure()
        let img = frames.isEmpty ? nil : frames[((phase % phaseCount) + phaseCount) % phaseCount]
        return Group {
            if let img {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: GlobalLattice.gif(SixFourLattice.cols),
                           height: GlobalLattice.gif(SixFourLattice.rows))
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Return the cached frame ring, re-baking only when `bakeKey` changes.
    private func ensure() -> [UIImage?] {
        if let b = baked, b.key == bakeKey { return b.frames }
        let n = max(1, phaseCount)
        let frames = (0 ..< n).map { f in
            CellBitmap.image(cols: SixFourLattice.cols, rows: SixFourLattice.rows) { c, r in
                Boundary.inside(c, r) ? cell(c, r, f) : nil   // the Stage mask, applied once, here
            }
        }
        // Defer the @State write out of the view-update pass (matches `TintedCheckerField`).
        DispatchQueue.main.async { baked = (bakeKey, frames) }
        return frames
    }
}
