import SwiftUI
import KeyboardShortcuts

/// Settings page that lists every customizable keyboard shortcut in the
/// app. Each row wraps `KeyboardShortcuts.Recorder` so the user can pick
/// a new chord or clear the binding entirely. Currently exposes the
/// integrated terminal shortcuts; dictation shortcuts live on the
/// dictation page for now because they're paired with the recorder
/// state UI there.
struct ShortcutsSettingsPage: View {
    @StateObject private var nativeSystemSearch = NativeSystemSearchActivationStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Keyboard Shortcuts")

            SectionLabel(title: "Search")
            SettingsCard {
                ShortcutSettingRow(
                    title: "Root Search",
                    detail: "Open framework Root Search without changing Command-G chat search.",
                    name: .rootSearch
                )
                CardDivider()
                NativeSystemSearchActivationRow(store: nativeSystemSearch)
            }
            Spacer().frame(height: 16)

            SectionLabel(title: "Terminal")
            SettingsCard {
                ShortcutSettingRow(
                    title: "Toggle terminal panel",
                    detail: "Show or hide the integrated terminal at the bottom of the chat.",
                    name: .terminalToggle
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "New terminal tab",
                    detail: "Open a new tab in the integrated terminal.",
                    name: .terminalNewTab
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Close terminal tab",
                    detail: "Close the active terminal tab.",
                    name: .terminalCloseTab
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Split pane right",
                    detail: "Split the active pane horizontally into two side-by-side panes.",
                    name: .terminalSplitVertical
                )
                CardDivider()
                ShortcutSettingRow(
                    title: "Split pane down",
                    detail: "Split the active pane vertically into two stacked panes.",
                    name: .terminalSplitHorizontal
                )
            }
            Spacer().frame(height: 16)

            SectionLabel(title: "Editor")
            SettingsCard {
                ShortcutSettingRow(
                    title: "Open project in editor",
                    detail: "Open the current project's folder in the editor you last picked from the title-bar menu.",
                    name: .openFavoriteEditor
                )
            }
        }
    }
}

private struct NativeSystemSearchActivationRow: View {
    @ObservedObject var store: NativeSystemSearchActivationStore

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Native system source")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text("Manually index Shortcuts into Full Root Search.")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.statusText)
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(store.statusColor)
                    .lineLimit(1)
            }
        } trailing: {
            HStack(spacing: 8) {
                if store.isRebuilding {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(store.buttonTitle) {
                    store.rebuild()
                }
                .disabled(store.isRebuilding)
            }
        }
    }
}

@MainActor
final class NativeSystemSearchActivationStore: ObservableObject {
    enum State: Equatable {
        case idle
        case rebuilding
        case indexed(Int)
        case externalPending
        case failed(String)
    }

    typealias RebuildAction = @MainActor () async throws -> NativeSystemSearchIndexResult

    @Published private(set) var state: State = .idle

    private let rebuildAction: RebuildAction
    private var rebuildTask: Task<Void, Never>?

    init(rebuildAction: @escaping RebuildAction = {
        try NativeSystemSearchSourceBridge.rebuildShortcutsIndex()
    }) {
        self.rebuildAction = rebuildAction
    }

    deinit {
        rebuildTask?.cancel()
    }

    var isRebuilding: Bool {
        state == .rebuilding
    }

    var buttonTitle: String {
        isRebuilding ? "Indexing..." : "Rebuild"
    }

    var statusText: String {
        switch state {
        case .idle:
            return "Off until rebuilt manually."
        case .rebuilding:
            return "Building native.system snapshot."
        case .indexed(let count):
            return count == 1 ? "Indexed 1 native item." : "Indexed \(count) native items."
        case .externalPending:
            return "Shortcuts access is pending on this host."
        case .failed(let message):
            return message.isEmpty ? "Native system indexing failed." : message
        }
    }

    var statusColor: Color {
        switch state {
        case .idle, .rebuilding:
            return Palette.textSecondary
        case .indexed:
            return Palette.pastelBlue
        case .externalPending, .failed:
            return .orange
        }
    }

    func rebuild() {
        guard !isRebuilding else { return }
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            await rebuildNow()
        }
    }

    func rebuildNow() async {
        state = .rebuilding
        do {
            let result = try await rebuildAction()
            let indexed = result.data.indexedBySource[NativeSystemSearchSourceBridge.sourceId] ?? result.data.reindexed
            if indexed > 0 {
                state = .indexed(indexed)
            } else {
                state = .externalPending
            }
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct ShortcutSettingRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let name: KeyboardShortcuts.Name

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            KeyboardShortcuts.Recorder(for: name)
        }
    }
}
