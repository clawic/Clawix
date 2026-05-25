import SwiftUI
import ClawixCore

/// Floating circular control that returns the transcript to its tail.
///
/// Appears only when the reader has scrolled meaningfully away from the
/// bottom of an overflowing transcript (`ChatScrollBottomSentinel`
/// drives the visibility flag), and disappears once the tail is back in
/// view. Follows the floating-element recipe in `STYLE.md`: `cardFill`
/// body, a `popupStroke` hairline, and the canonical soft drop shadow.
struct ScrollToBottomButton: View {
    var action: () -> Void

    @State private var hovering = false

    private let diameter: CGFloat = 32

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(hovering ? Palette.cardHover : Palette.cardFill)
                .overlay(
                    Circle().strokeBorder(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                )
                .overlay(
                    LucideIcon(.chevronDown, size: 14)
                        .foregroundColor(Palette.textPrimary.opacity(0.92))
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: Color.black.opacity(0.40), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .clxControl("chat.scrollToBottom", role: "button", label: "Scroll to bottom", activate: action)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(String(localized: "Scroll to bottom", bundle: AppLocale.bundle, locale: AppLocale.current))
    }
}
