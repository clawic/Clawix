import SwiftUI

struct QuickAskMessageBubble: View {
    let message: ChatMessage
    let appState: AppState
    @State private var rowHovered = false
    @State private var justCopied = false
    @State private var copyResetTask: Task<Void, Never>? = nil

    var body: some View {
        if message.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 36)
                Text(displayText)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.overlay(0.14))
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: -2) {
                assistantBody
                if !message.streamingFinished || displayText.isEmpty {
                    EmptyView()
                } else {
                    QuickAskCopyAction(
                        showCheck: justCopied,
                        rowHovered: rowHovered,
                        action: handleCopy
                    )
                    .padding(.leading, -6)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering in
                rowHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var assistantBody: some View {
        if message.isError {
            AssistantMarkdownText(
                text: displayText,
                renderKey: .message(message.id),
                weight: .regular,
                color: Palette.danger,
                checkpoints: [],
                streamingFinished: true
            )
            .environmentObject(appState)
            .fixedSize(horizontal: false, vertical: true)
        } else if displayText.isEmpty && !message.streamingFinished {
            ThinkingShimmer(
                text: String(
                    localized: "Thinking",
                    bundle: AppLocale.bundle,
                    locale: AppLocale.current
                )
            )
        } else {
            AssistantMarkdownText(
                text: displayText,
                renderKey: .message(message.id),
                weight: .light,
                color: Palette.textPrimary,
                checkpoints: message.streamCheckpoints,
                streamingFinished: message.streamingFinished
            )
            .environmentObject(appState)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayText: String {
        message.content.trimmingCharacters(in: .newlines)
    }

    private func handleCopy() {
        LegalSafetyStore.shared.requestSensitiveActionReview(action: .exportShare, appState: appState) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(LegalSafetyStore.shared.reviewedSensitiveOutputText(message.content), forType: .string)

            copyResetTask?.cancel()
            withAnimation(.easeOut(duration: 0.15)) {
                justCopied = true
            }
            copyResetTask = Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.2)) {
                        justCopied = false
                    }
                }
            }
        }
    }
}

/// Mirrors `MessageActionIcon` from `ChatView.swift` for the assistant
/// copy affordance: a 27pt squircle hit area with the same custom
/// `CopyIconViewSquircle` glyph and identical hover / "Copied"
/// transitions, so the HUD's copy button reads as the same control
/// the main chat exposes.
private struct QuickAskCopyAction: View {
    let showCheck: Bool
    let rowHovered: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.overlay(hovered ? 0.07 : 0))
                if showCheck {
                    CheckIcon(size: 13)
                        .foregroundColor((hovered ? Color.gray(light: 0.12, dark: 0.94) : Color.gray(light: 0.27, dark: 0.78)))
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    CopyIconViewSquircle(
                        color: (hovered ? Color.gray(light: 0.17, dark: 0.88) : Color.gray(light: 0.45, dark: 0.55)),
                        lineWidth: 0.85
                    )
                    .frame(width: 13, height: 13)
                    .transition(.opacity)
                }
            }
            .frame(width: 27, height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovered = h }
        }
        .opacity(showCheck ? 1 : (rowHovered ? 1 : 0))
        .allowsHitTesting(showCheck || rowHovered)
        .animation(.easeOut(duration: 0.15), value: rowHovered)
        .accessibilityLabel(
            showCheck
                ? String(localized: "Copied", bundle: AppLocale.bundle, locale: AppLocale.current)
                : String(localized: "Copy", bundle: AppLocale.bundle, locale: AppLocale.current)
        )
    }
}

enum QuickAskScrollAnchor: Hashable {
    case bottom
}
