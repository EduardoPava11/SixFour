import SwiftUI
import simd

/// Horizontal strip visualisation of the **palette stack** P̂ (MATH.md §2,
/// Definition 4). Draws K = 256 cells, one per palette entry, coloured by
/// each entry's sRGB triple.
///
/// Two operating modes follow directly from the spectrum endpoints:
///
/// * **Static (global mode):** `palettes.count == 1` — one row representing
///   the file's Global Color Table. Drawn once; never changes.
/// * **Animated (per-frame mode):** `palettes.count == T = 64` — the strip
///   advances through per-frame palettes in sync with the GIF's 20 fps
///   playback. Driven by a `TimelineView(.animation)` so the parent view
///   doesn't re-render on every tick.
///
/// Honours `@Environment(\.accessibilityReduceMotion)`: when reduce-motion
/// is on, the animated path freezes on frame 0 (still informative — the
/// user sees one frame's palette — but no motion).
struct PaletteStripView: View {
    let palettes: [[SIMD3<UInt8>]]
    let frameRate: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(palettes: [[SIMD3<UInt8>]], frameRate: Int = 20) {
        self.palettes = palettes
        self.frameRate = frameRate
    }

    var body: some View {
        let isAnimated = palettes.count > 1 && !reduceMotion
        Group {
            if isAnimated {
                TimelineView(.animation(minimumInterval: 1.0 / Double(frameRate))) { ctx in
                    canvas(at: indexFor(date: ctx.date))
                }
            } else {
                canvas(at: 0)
            }
        }
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if palettes.count == 1 {
            return "Global palette strip, 256 colours shared across all frames."
        }
        return "Per-frame palette strip, 256 colours per frame, advancing at \(frameRate) frames per second."
    }

    /// Map wall-clock to a frame index modulo T so the strip loops with the
    /// GIF underneath it. `Date.timeIntervalSinceReferenceDate` gives a
    /// monotonic high-res clock that survives view re-creation.
    private func indexFor(date: Date) -> Int {
        let t = date.timeIntervalSinceReferenceDate
        let frame = Int((t * Double(frameRate)).rounded(.down)) % palettes.count
        return frame
    }

    private func canvas(at index: Int) -> some View {
        let palette = palettes[min(index, palettes.count - 1)]
        return Canvas { context, size in
            let cellWidth = size.width / 256.0
            for (k, c) in palette.enumerated() {
                let rect = CGRect(
                    x: CGFloat(k) * cellWidth,
                    y: 0,
                    width: cellWidth + 0.5,   // hairline overlap to suppress gaps
                    height: size.height
                )
                context.fill(
                    Path(rect),
                    with: .color(Color(
                        red: Double(c.x) / 255,
                        green: Double(c.y) / 255,
                        blue: Double(c.z) / 255
                    ))
                )
            }
        }
    }
}
