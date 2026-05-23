import SwiftUI

// MARK: - Plus menu

/// `+` button that opens an `NSMenu` covering the five attach/capture
/// actions the user listed: load file, load photo, take screenshot
/// (with a submenu of every visible screen and on-screen window),
/// take photo from camera, open application. We render through a
/// SwiftUI `Menu` rather than a custom popup panel because the system
/// menu (a) renders correctly outside the QuickAsk panel's bounds,
/// (b) handles keyboard navigation and ⌘O for free, and (c) styles
/// itself to match macOS dark mode automatically.
struct QuickAskPlusMenu: View {
    @State private var screens: [QuickAskCaptureSource.Screen] = []
    @State private var windows: [QuickAskCaptureSource.Window] = []

    var body: some View {
        Menu {
            Button {
                QuickAskActions.loadFile()
            } label: {
                Label("Load file", systemImage: "doc")
            }

            Button {
                QuickAskActions.loadPhoto()
            } label: {
                Label("Load photo", systemImage: "photo")
            }

            Menu {
                if !screens.isEmpty {
                    Section("Screens") {
                        ForEach(screens) { screen in
                            Button {
                                QuickAskActions.captureScreen(screen)
                            } label: {
                                Label(screen.name, systemImage: "display")
                            }
                        }
                    }
                }
                if !windows.isEmpty {
                    Section("Windows") {
                        ForEach(windows) { window in
                            Button {
                                QuickAskActions.captureWindow(window)
                            } label: {
                                Label(window.label, systemImage: "macwindow")
                            }
                        }
                    }
                }
                Divider()
                Button {
                    QuickAskActions.captureInteractive()
                } label: {
                    Label("Custom selection…", systemImage: "selection.pin.in.out")
                }
            } label: {
                Label("Take a screenshot", systemImage: "camera.viewfinder")
            }

            Button {
                QuickAskActions.takePhoto()
            } label: {
                Label("Take a photo", systemImage: "camera")
            }
        } label: {
            LucideIcon(.plus, size: 12.5)
                .foregroundColor(.white)
                .opacity(0.78)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .quickAskIconHover()
        // Refresh the screen and window inventory every time the menu
        // is about to surface so we never show a stale list (apps open
        // and close, monitors get plugged in/out).
        .onTapGesture {
            screens = QuickAskCaptureSource.currentScreens()
            windows = QuickAskCaptureSource.currentWindows()
        }
        .onAppear {
            screens = QuickAskCaptureSource.currentScreens()
            windows = QuickAskCaptureSource.currentWindows()
        }
    }
}

// MARK: - Model picker pill

/// Bare-text model picker bound to `AppState.selectedModel` (same
/// global the main `ComposerView` reads). Displays "GPT-<x>" in line
/// with the composer's `ModelMenuPopup`, and lists primary + other
/// models via the same `availableModels` / `otherModels` arrays so
/// QuickAsk's picker stays in sync with whatever the user configures
/// at the top level. No leading icon, no trailing chevron — the
/// dropdown affordance is implicit, surfaced only on hover via a
/// squircle background that highlights the label as a hit target.
struct QuickAskModelPicker: View {
    @Binding var selection: String
    @Binding var runtime: AgentRuntimeChoice
    let primary: [String]
    let others: [String]
    @ObservedObject private var flags = FeatureFlags.shared
    @State private var hovered = false

    var body: some View {
        Menu {
            Section("Runtime") {
                Button {
                    runtime = .codex
                    if selection.contains("/") { selection = "5.5" }
                } label: {
                    if runtime == .codex { Label("Codex", systemImage: "checkmark") } else { Text("Codex") }
                }
                if flags.isVisible(.openCode) {
                    Button {
                        runtime = .opencode
                        selection = AgentRuntimeChoice.defaultOpenCodeModel
                    } label: {
                        if runtime == .opencode { Label("OpenCode", systemImage: "checkmark") } else { Text("OpenCode") }
                    }
                }
            }
            Section("Model") {
                if flags.isVisible(.openCode), runtime == .opencode {
                    Button {
                        selection = AgentRuntimeChoice.defaultOpenCodeModel
                    } label: {
                        if selection == AgentRuntimeChoice.defaultOpenCodeModel {
                            Label(AgentRuntimeChoice.defaultOpenCodeModel, systemImage: "checkmark")
                        } else {
                            Text(AgentRuntimeChoice.defaultOpenCodeModel)
                        }
                    }
                } else {
                ForEach(primary, id: \.self) { m in
                    Button {
                        selection = m
                    } label: {
                        if m == selection {
                            Label("GPT-\(m)", systemImage: "checkmark")
                        } else {
                            Text("GPT-\(m)")
                        }
                    }
                }
                }
            }
            if runtime == .codex && !others.isEmpty {
                Section("Other models") {
                    ForEach(others, id: \.self) { m in
                        Button {
                            selection = m
                        } label: {
                            if m == selection {
                                Label("GPT-\(m)", systemImage: "checkmark")
                            } else {
                                Text("GPT-\(m)")
                            }
                        }
                    }
                }
            }
        } label: {
            Text(flags.isVisible(.openCode) && runtime == .opencode ? selection : "GPT-\(selection)")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Color(white: 0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.09 : 0))
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Completion dropdown

struct QuickAskCompletionRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let action: () -> Void
}

struct QuickAskCompletionPanel: View {
    private static let visibleRowLimit = 8

    let title: String
    let rows: [QuickAskCompletionRow]

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(BodyFont.system(size: 10, wght: 700))
                    .foregroundColor(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                ForEach(rows.prefix(Self.visibleRowLimit)) { row in
                    QuickAskCompletionRowView(row: row)
                }
            }
            .padding(.vertical, 4)
            .background(VisualEffectBlur(material: .menu, blendingMode: .behindWindow))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
            )
            .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 6)
        }
    }
}

struct QuickAskCompletionRowView: View {
    let row: QuickAskCompletionRow
    @State private var hovered = false

    var body: some View {
        Button(action: row.action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(BodyFont.system(size: 10, wght: 500))
                    .foregroundColor(.white.opacity(0.50))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.white.opacity(hovered ? 0.06 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Hover feedback helpers

// Each chrome icon in the open Quick Ask panel already bakes its own
// resting opacity into its `foregroundColor` (close 0.50, temporary
// toggle 0.50/0.95, plus 0.78, etc.). The hover modifiers below
// preserve that resting weight and brighten on hover via an
// `.opacity(1.6)` multiplier (clamps at fully opaque), animated with
// `.easeOut(0.12)` to match `ComposerView`/sidebar pacing.

/// Standard 28x28 chrome icon button with the canonical Quick Ask
/// hover feedback so every chrome icon in the open panel reacts to
/// the pointer the same way the main chat composer and the sidebar do.
struct QuickAskHoverIconButton<Content: View>: View {
    let action: () -> Void
    let tooltip: String
    @ViewBuilder var content: () -> Content
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .opacity(hovered ? 1.6 : 1.0)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Brightens any view on hover for the in-panel chrome icons that
/// don't go through `hoverIconButton` (web search toggle, work-with-
/// apps, plus menu, selection dismiss, chat title pill).
struct QuickAskIconHoverModifier: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .opacity(hovered ? 1.6 : 1.0)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Subtle scale-up hover for solid-disc CTAs (send, stop recording,
/// send voice note). Opacity boost wouldn't read on these because the
/// disc is already at full alpha; a small scale signals interactivity
/// without changing the resting visual weight.
struct QuickAskDiscHoverModifier: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? 1.06 : 1.0)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

extension View {
    func quickAskIconHover() -> some View {
        modifier(QuickAskIconHoverModifier())
    }

    func quickAskDiscHover() -> some View {
        modifier(QuickAskDiscHoverModifier())
    }
}
