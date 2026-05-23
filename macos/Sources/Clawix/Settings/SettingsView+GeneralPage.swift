import SwiftUI

struct GeneralPage: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var flags: FeatureFlags
    @StateObject private var backgroundBridge: BackgroundBridgeService = .shared
    @AppStorage(SyncSettings.archiveKey, store: SyncSettings.store) private var syncArchiveWithCodex = true
    @AppStorage(SyncSettings.renamesKey, store: SyncSettings.store) private var syncRenamesWithCodex = true
    @AppStorage(SyncSettings.autoReloadKey, store: SyncSettings.store) private var autoReloadOnFocus = false

    enum WorkMode: Hashable { case coding, daily }
    enum FollowBehavior: Hashable { case queue, drive }
    enum CodeReview: Hashable { case inline, detached }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "General")

#if DEBUG
            // Developer-only tooling ships in dev builds only. Release builds
            // compile the switch as `let developerSurfaces = false` (see
            // FeatureFlags.swift), so the setter Binding below cannot exist
            // there.
            SectionLabel(title: "Developer tools")
            SettingsCard {
                ToggleRow(
                    title: "Developer-only surfaces",
                    detail: "Show internal tools that are explicitly outside product v1, such as simulators. Off by default.",
                    isOn: Binding(
                        get: { flags.developerSurfaces },
                        set: { flags.developerSurfaces = $0 }
                    )
                )
            }
            .padding(.bottom, 8)
#endif

            if flags.developerSurfaces {
                SectionLabel(title: "Developer surface status")
                SettingsCard {
                    GeneralCapabilityStatusRow(
                        title: "Work mode presets",
                        detail: "Hidden until runtime prompts and response-detail preferences consume a persisted setting.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Permission defaults",
                        detail: "Hidden until approvals, grants, and audit routes expose a single persisted policy source.",
                        status: "Blocked"
                    )
                }
            }

            SectionLabel(title: "General")
            SettingsCard {
                DropdownRow(
                    title: "Language",
                    detail: "App interface language",
                    options: AppLanguage.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { appState.preferredLanguage },
                        set: { appState.preferredLanguage = $0 }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Run bridge in background",
                    detail: "Registers the LaunchAgent bridge so the daemon can stay alive after Clawix quits. Status: \(backgroundBridge.statusLabel)\(backgroundBridge.lastError.map { " — \($0)" } ?? "")",
                    isOn: Binding(
                        get: { backgroundBridge.isEnabled },
                        set: {
                            backgroundBridge.toggle($0)
                            appState.reconcileBridgeTransport(reason: "background-setting")
                        }
                    )
                )
                CardDivider()
                SegmentedRow(
                    title: "Agent runtime",
                    detail: appState.selectedAgentRuntime == .opencode
                        ? "OpenCode uses \(appState.openCodeModelSelection). Restart the background bridge after switching."
                        : "Codex remains the default runtime.",
                    options: AgentRuntimeChoice.visibleCases().map { ($0, $0.label) },
                    selection: $appState.selectedAgentRuntime
                )
                CardDivider()
                DropdownRow(
                    title: "OpenCode model",
                    detail: "Provider/model id used when OpenCode is active. DeepSeek V4 Pro is selected by default.",
                    options: [(AgentRuntimeChoice.defaultOpenCodeModel, AgentRuntimeChoice.defaultOpenCodeModel)],
                    selection: Binding(
                        get: { appState.openCodeModelSelection },
                        set: {
                            appState.selectedModel = $0
                            appState.selectedAgentRuntime = .opencode
                        }
                    )
                )
                if flags.developerSurfaces {
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Default open destination",
                        detail: "Unavailable until file and folder open actions read a persisted destination route.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Show in the menu bar",
                        detail: "Unavailable until the signed app lifecycle owns a persisted menu bar preference.",
                        status: "Blocked"
                    )
                    CardDivider()
                    ActionPillRow(
                        title: "Popover keyboard shortcut",
                        detail: "Set a global keyboard shortcut for the popover. Leave empty to keep it disabled.",
                        primaryLabel: "Change",
                        trailingDisabled: "⌥Space",
                        isEnabled: false,
                        onPrimary: {}
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Prevent sleep during execution",
                        detail: "Unavailable until active generation owns a signed power assertion lifecycle.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Require ⌘ + Return to send long prompts",
                        detail: "Unavailable until the composer consumes a persisted send-policy setting.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Speed",
                        detail: "Unavailable until runtime requests accept and report a persisted speed policy.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Follow-up behavior",
                        detail: "Unavailable until the chat queue exposes route evidence for queue and steering modes.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Code review",
                        detail: "Unavailable until review launch routes declare inline and detached behavior.",
                        status: "Blocked"
                    )
                }
            }

            SectionLabel(title: "Sync with Codex")
            SettingsCard {
                ToggleRow(
                    title: "Sync archived chats with Codex",
                    detail: "When you archive or unarchive a chat, mirror that to Codex CLI. Disable to keep archive state local to this app. Reactivating sync does not propagate previous local-only changes.",
                    isOn: $syncArchiveWithCodex
                )
                CardDivider()
                ToggleRow(
                    title: "Sync chat renames with Codex",
                    detail: "When you rename a chat, also update the title in Codex CLI. Disable to keep custom titles only in this app.",
                    isOn: $syncRenamesWithCodex
                )
                CardDivider()
                PinsStorageNoticeRow()
            }

            HiddenCodexFoldersSection()

            if flags.developerSurfaces {
                SectionLabel(title: "Dictation")
                SettingsCard {
                    GeneralCapabilityStatusRow(
                        title: "Push-to-dictate keyboard shortcut",
                        detail: "Configure dictation shortcuts on the Voice to Text page, where recorder state and permissions are visible.",
                        status: "Moved"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Toggle dictation keyboard shortcut",
                        detail: "Configure dictation shortcuts on the Voice to Text page, where recorder state and permissions are visible.",
                        status: "Moved"
                    )
                }

                SectionLabel(title: "Notifications")
                SettingsCard {
                    GeneralCapabilityStatusRow(
                        title: "Enable completion notifications",
                        detail: "Unavailable until notification authorization and delivery policy share a persisted source.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Enable permission notifications",
                        detail: "Unavailable until approval prompts report notification delivery state.",
                        status: "Blocked"
                    )
                    CardDivider()
                    GeneralCapabilityStatusRow(
                        title: "Enable question notifications",
                        detail: "Unavailable until pending-question events expose a notification route.",
                        status: "Blocked"
                    )
                }
            }

            SectionLabel(title: "App behavior")
            SettingsCard {
                ToggleRow(
                    title: "Auto-refresh on focus",
                    detail: "When enabled, reload chats from the Codex runtime when this app becomes the active window.",
                    isOn: $autoReloadOnFocus
                )
            }

            SectionLabel(title: "Danger zone")
            SettingsCard {
                ResetLocalOverridesRow()
            }
        }
    }

}

private struct GeneralCapabilityStatusRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let status: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            Text(status)
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
                        )
                )
                .accessibilityLabel(Text(status))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct PinsStorageNoticeRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pins")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color.gray(light: 0.12, dark: 0.94))
                Text("Pins are stored locally in Clawix and session state is synchronized through the ClawJS sessions adapter.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct HiddenCodexFoldersSection: View {
    @EnvironmentObject var appState: AppState
    @State private var hidden: [String] = []

    var body: some View {
        SectionLabel(title: "Hidden Codex folders")
        SettingsCard {
            if hidden.isEmpty {
                HStack {
                    Text("No hidden folders. Right-click a Codex folder in the sidebar to hide it.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(hidden.enumerated()), id: \.element) { idx, path in
                    if idx > 0 { CardDivider() }
                    HiddenFolderRow(path: path) {
                        appState.showCodexRoot(path: path)
                        reload()
                    }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: appState.projects) { _, _ in reload() }
    }

    private func reload() {
        hidden = appState.hiddenCodexRoots()
    }
}

struct HiddenFolderRow: View {
    let path: String
    let onShow: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color.gray(light: 0.12, dark: 0.94))
                Text(path)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button("Show", action: onShow)
                .buttonStyle(SheetCancelButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ResetLocalOverridesRow: View {
    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset local overrides")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color.gray(light: 0.12, dark: 0.94))
                Text("Permanently delete all local pins, archives, custom titles, project overrides and hidden Codex folders. The app will resync from Codex on next refresh. Codex's data is not affected.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Reset") { presentConfirmation() }
                .buttonStyle(SheetDestructiveButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func presentConfirmation() {
        let counts = appState.localOverrideCounts()
        let header = NSLocalizedString(
            "This will permanently delete the following local data from this app:",
            comment: "reset local overrides body header"
        )
        let footer = NSLocalizedString(
            "After reset, the app will reload from Codex on the next refresh. Codex's data and other Codex apps are not affected. This cannot be undone.",
            comment: "reset local overrides body footer"
        )
        let lines = [
            String(format: "• %@: %d", NSLocalizedString("Pinned threads", comment: ""), counts.pins),
            String(format: "• %@: %d", NSLocalizedString("Local projects", comment: ""), counts.projects),
            String(format: "• %@: %d", NSLocalizedString("Chat-project overrides", comment: ""), counts.chatProjectOverrides),
            String(format: "• %@: %d", NSLocalizedString("Projectless markers", comment: ""), counts.projectlessThreads),
            String(format: "• %@: %d", NSLocalizedString("Local archive entries", comment: ""), counts.archives),
            String(format: "• %@: %d", NSLocalizedString("Custom titles", comment: ""), counts.titles),
            String(format: "• %@: %d", NSLocalizedString("Hidden Codex folders", comment: ""), counts.hiddenRoots)
        ].joined(separator: "\n")
        let body = "\(header)\n\n\(lines)\n\n\(footer)"
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Reset local overrides?",
            body: LocalizedStringKey(body),
            confirmLabel: "Reset",
            isDestructive: true,
            onConfirm: { appState.resetLocalOverrides() }
        )
    }
}

struct WorkModeCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                LucideIcon.auto(icon, size: 14)
                    .foregroundColor(Color.gray(light: 0.19, dark: 0.86))
                    .frame(width: 28, height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.overlay(0.06))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(subtitle)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .stroke(Color.overlay(0.18), lineWidth: 1)
                        .frame(width: 16, height: 16)
                    if isOn {
                        Circle()
                            .fill(Color(red: 0.30, green: 0.55, blue: 1.0))
                            .frame(width: 16, height: 16)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 18)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray(light: 0.95, dark: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isOn ? Color.overlay(0.16) : Color.overlay(0.06),
                                    lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CollapsibleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @State private var open: Bool = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                RowLabel(title: title, detail: detail)
                Spacer(minLength: 12)
                LucideIcon.auto(open ? "chevron.up" : "chevron.down", size: 11)
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DictionaryExpandableRow: View {
    @Binding var entries: [String]
    @State private var open: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    RowLabel(title: "Dictation dictionary",
                             detail: "Words or phrases dictation should recognize")
                    Spacer(minLength: 12)
                    LucideIcon.auto(open ? "chevron.up" : "chevron.down", size: 11)
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 8) {
                    ForEach(entries.indices, id: \.self) { idx in
                        DictionaryEntryField(
                            text: $entries[idx],
                            onDelete: {
                                guard entries.indices.contains(idx) else { return }
                                entries.remove(at: idx)
                            }
                        )
                    }
                    Button {
                        entries.append("")
                    } label: {
                        HStack(spacing: 6) {
                            LucideIcon(.plus, size: 11)
                            Text("Add entry")
                                .font(BodyFont.system(size: 12.5))
                        }
                        .foregroundColor(Color.gray(light: 0.38, dark: 0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.30))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.overlay(0.08), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }
}

struct DictionaryEntryField: View {
    @Binding var text: String
    let onDelete: () -> Void
    @FocusState private var focused: Bool
    @State private var trashHovered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .padding(.leading, 12)
                .padding(.vertical, 9)
            Spacer(minLength: 8)
            Button(action: onDelete) {
                LucideIcon(.trash, size: 13)
                    .foregroundColor((trashHovered ? Color.gray(light: 0.12, dark: 0.94) : Color.gray(light: 0.45, dark: 0.55)))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { trashHovered = $0 }
            .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(focused
                                ? Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.85)
                                : Color.overlay(0.08),
                                lineWidth: focused ? 1.0 : 0.5)
                )
        )
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

struct RecentDictationRow: View {
    let stamp: String
    let text: String
    @State private var copyHovered: Bool = false
    @State private var copied: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(stamp)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(text)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                withAnimation(.easeOut(duration: 0.12)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.18)) { copied = false }
                }
            } label: {
                Group {
                    if copied {
                        CheckIcon(size: 13)
                    } else {
                        CopyIconViewSquircle(
                            color: (copyHovered ? Color.gray(light: 0.12, dark: 0.94) : Color.gray(light: 0.42, dark: 0.60)),
                            lineWidth: 1.0
                        )
                        .frame(width: 13, height: 13)
                    }
                }
                .foregroundColor((copyHovered ? Color.gray(light: 0.12, dark: 0.94) : Color.gray(light: 0.42, dark: 0.60)))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { copyHovered = $0 }
            .hoverHint(L10n.t("Copy"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
