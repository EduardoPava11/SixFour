import SwiftUI

/// Reusable Liquid Glass (iOS 26) control primitives for SixFour's floating
/// chrome — the navigation/control layer that hovers over the camera content.
///
/// Why a dedicated component file instead of inline `.glassEffect` calls?
///   1. *Consistency* — every floating button shares one size, shape, and
///      `.interactive()` press behaviour. New options drop in as one line.
///   2. *Correctness* — Apple's rule "glass cannot sample other glass" means
///      sibling glass shapes must share a `GlassEffectContainer`. Bundling
///      that into `GlassToolbarCluster` makes the right thing the easy thing.
///   3. *Layering* — glass is reserved for chrome; content (the camera feed,
///      the 64×64 tile, the GIF, the palette strip) never gets it. Keeping
///      these here keeps that boundary legible.
///
/// To add a future control (e.g. a Settings gear), append another
/// `GlassIconButton` inside the existing `GlassToolbarCluster` — no new
/// glass plumbing required.

/// A circular, tinted-glass icon button sized to `SFTheme.glassIconButtonSize`.
///
/// The SF Symbol animates with `.symbolEffect(.replace)` when `systemImage`
/// changes within an animated transaction, so callers that flip the icon
/// (e.g. the preview-mode toggle) get a fluid morph for free — just mutate
/// state inside `withAnimation`.
struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(
                    width: SFTheme.glassIconButtonSize,
                    height: SFTheme.glassIconButtonSize
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        // `.interactive()` gives the glass a live press/scale response;
        // it is an iOS-only variant, which is fine — SixFour is iOS-only.
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(Text(accessibilityLabel))
        .modifier(OptionalAccessibilityHint(hint: accessibilityHint))
    }
}

/// Groups its glass children into one `GlassEffectContainer` so they sample
/// a single shared region (no glass-on-glass artifacts) and can morph
/// between one another. Use it to wrap any row/stack of glass controls.
struct GlassToolbarCluster<Content: View>: View {
    var spacing: CGFloat = SFTheme.glassClusterSpacing
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) { content }
        }
    }
}

/// A floating glass "chip" for read-only status text (timing summaries,
/// phase banners). Centralises the chrome treatment for ephemeral overlays.
struct GlassInfoChip<Content: View>: View {
    var cornerRadius: CGFloat = SFTheme.cardCorner
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Applies `.accessibilityHint` only when a hint string is present, so
/// `GlassIconButton` can keep `accessibilityHint` optional without two code
/// paths. A no-op `EmptyModifier` when nil keeps the view tree stable.
private struct OptionalAccessibilityHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(Text(hint))
        } else {
            content
        }
    }
}
