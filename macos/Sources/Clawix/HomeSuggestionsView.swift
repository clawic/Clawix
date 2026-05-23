import SwiftUI

// MARK: - Home suggestions
//
// Shown beneath the composer on the new-chat home surface. Renders the
// project-aware ambient suggestions (see `AmbientSuggestionStore`) as compact,
// tappable rows plus a quiet "connect your apps" entry point. Tapping a
// suggestion seeds the composer draft and pulls focus; the row's dismiss
// control hides that suggestion for the project permanently. The whole surface
// fades out the moment the user starts typing (handled by the host).

struct HomeSuggestionsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var composer: ComposerState
    @ObservedObject private var ambient = AmbientSuggestionStore.shared
    @ObservedObject private var role = WelcomeRoleStore.shared

    private var hasUsableProject: Bool {
        guard let project = appState.selectedProject else { return false }
        return project.folderState == .active
    }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(ambient.visible) { suggestion in
                HomeSuggestionRow(
                    icon: .sparkles,
                    text: suggestion.title,
                    dismissible: true,
                    onTap: { seed(suggestion.title) },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.16)) { ambient.dismiss(suggestion.id) }
                    }
                )
            }

            HomeSuggestionRow(
                icon: .link,
                text: L10n.t("Connect your apps"),
                muted: true,
                dismissible: false,
                onTap: { appState.navigate(to: .plugins) },
                onDismiss: {}
            )
        }
        .frame(maxWidth: 680)
        .onAppear { refresh() }
        .onChange(of: appState.selectedProject?.id) { refresh() }
        .onChange(of: role.selectedRole) { refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Suggested starts"))
    }

    private func refresh() {
        let project = hasUsableProject ? appState.selectedProject : nil
        ambient.refresh(projectPath: project?.path, projectName: project?.name)
    }

    private func seed(_ prompt: String) {
        withAnimation(.easeOut(duration: 0.16)) { composer.text = prompt }
        appState.requestComposerFocus()
    }
}

private struct HomeSuggestionRow: View {
    let icon: LucideIcon.Kind
    let text: String
    var muted: Bool = false
    let dismissible: Bool
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    private var textOpacity: Double {
        if hovering { return muted ? 0.78 : 0.94 }
        return muted ? 0.5 : 0.72
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    LucideIcon(icon, size: 13)
                        .foregroundColor(Color.overlay(hovering ? 0.7 : 0.45))
                        .accessibilityHidden(true)
                    Text(text)
                        .font(BodyFont.system(size: 13, wght: 450))
                        .foregroundColor(Color.overlay(textOpacity))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if dismissible {
                Button(action: onDismiss) {
                    XIcon(size: 11)
                        .foregroundColor(Color.overlay(0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel(L10n.t("Dismiss suggestion"))
                .accessibilityHint(text)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.overlay(hovering ? 0.05 : 0.0))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
    }
}
