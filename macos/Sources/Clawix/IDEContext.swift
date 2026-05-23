import SwiftUI
import AppKit
import Combine

// MARK: - IDE context
//
// Detects whether a code editor is running and offers a composer chip to
// include lightweight editor context (open file / selection) with the next
// message. Detection is passive (running-app bundle-id inspection); the actual
// context payload is assembled by the runtime when `includeContext` is on. The
// chip only appears when an editor is detected, so it stays out of the way
// otherwise. The presentation is intentionally generic ("editor") rather than
// naming a specific product.

@MainActor
final class IDEContextStore: ObservableObject {
    static let shared = IDEContextStore()

    /// Whether a known editor is currently running.
    @Published private(set) var isEditorRunning: Bool = false
    /// Whether editor context is folded into the next message.
    @Published var includeContext: Bool = true

    private var observers: [NSObjectProtocol] = []

    /// Bundle-id prefixes for common editors, matched case-insensitively.
    /// These are technical integration identifiers used only for detection.
    private static let editorBundlePrefixes: [String] = [
        "com.microsoft.vscode",
        "com.vscodium",
        "com.todesktop",
        "dev.zed.zed",
        "com.apple.dt.xcode",
        "com.sublimetext",
        "com.jetbrains",
        "com.google.android.studio",
    ]

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            observers.append(token)
        }
    }

    func refresh() {
        let running = NSWorkspace.shared.runningApplications
        let present = running.contains { app in
            guard let bundleId = app.bundleIdentifier?.lowercased() else { return false }
            return Self.editorBundlePrefixes.contains { bundleId.hasPrefix($0) }
        }
        if isEditorRunning != present { isEditorRunning = present }
    }

    func toggle() { includeContext.toggle() }
}

struct IDEContextChip: View {
    @ObservedObject private var store = IDEContextStore.shared
    @State private var hovering = false

    var body: some View {
        if store.isEditorRunning {
            Button { store.toggle() } label: {
                HStack(spacing: 5) {
                    LucideIcon(.appWindow, size: 12)
                    Text(L10n.t("IDE"))
                        .font(BodyFont.system(size: 11.5, wght: 500))
                    if store.includeContext {
                        CheckIcon(size: 9)
                    }
                }
                .foregroundColor(store.includeContext ? Palette.pastelBlue : Color.white.opacity(hovering ? 0.7 : 0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(store.includeContext ? Palette.pastelBlue.opacity(0.10)
                                                   : Color.white.opacity(hovering ? 0.06 : 0.0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .hoverHint(store.includeContext ? L10n.t("Including editor context") : L10n.t("Include editor context"))
            .accessibilityLabel(L10n.t("Editor context"))
        }
    }
}
