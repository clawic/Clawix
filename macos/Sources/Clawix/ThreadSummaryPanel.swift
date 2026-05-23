import SwiftUI

// MARK: - Thread summary side-panel surface
//
// Right side-panel that summarises the active conversation: the agent's
// plan (Progress), files it changed (Changes), web/browser citations
// (Sources), generated images (Outputs), and integrated-terminal activity
// (Terminal). Toggled by the ⓘ button in the chat chrome. Aggregated live
// from the chat transcript's work items plus the parsed `update_plan`
// checklist in `AppState.planByChat`.

// MARK: Toggle button (chat chrome)

struct ThreadSummaryToggleButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var hovered = false

    private var isActive: Bool {
        guard appState.isRightSidebarOpen else { return false }
        if case .summary = appState.activeSidebarItem { return true }
        return false
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                appState.toggleSummaryInSidebar()
            }
        } label: {
            LucideIcon(.info, size: 14)
                .foregroundColor(isActive
                    ? Palette.textPrimary
                    : Color(white: hovered ? 0.78 : 0.55))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive
                            ? Color(white: 0.16)
                            : (hovered ? Color(white: 0.12) : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(L10n.t("Toggle thread summary"))
        .accessibilityLabel(L10n.t("Toggle thread summary"))
    }
}

// MARK: Panel

struct ThreadSummaryPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let chatId = appState.currentChatId,
               let transcript = appState.chatStore.transcript(for: chatId) {
                ThreadSummaryContent(chatId: chatId, transcript: transcript)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            LucideIcon(.info, size: 26).foregroundColor(Color.white.opacity(0.28))
            Text(L10n.t("No conversation"))
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ThreadSummaryContent: View {
    let chatId: UUID
    @ObservedObject var transcript: ChatTranscriptStore
    @EnvironmentObject private var appState: AppState

    private var items: [WorkItem] {
        transcript.messages.flatMap { $0.workSummary?.items ?? [] }
    }

    private var plan: [PlanStep] { appState.planByChat[chatId] ?? [] }

    private var changedPaths: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            if case .fileChange(let paths) = item.kind {
                for p in paths where seen.insert(p).inserted { out.append(p) }
            }
        }
        return out
    }

    private var generatedImages: [WorkItem] {
        items.filter { if case .imageGeneration = $0.kind { return true } else { return false } }
    }

    private var webSearchCount: Int {
        items.filter { if case .webSearch = $0.kind { return true } else { return false } }.count
    }

    private var browserCount: Int {
        items.filter {
            switch $0.kind {
            case .jsCall(_, .browser): return true
            case .dynamicTool(let name): return name.lowercased().contains("browser")
            default: return false
            }
        }.count
    }

    private var terminalCount: Int {
        items.filter {
            if case .dynamicTool(let name) = $0.kind { return name == "the terminal" }
            return false
        }.count
    }

    private var isEmpty: Bool {
        plan.isEmpty && changedPaths.isEmpty && generatedImages.isEmpty
            && webSearchCount == 0 && browserCount == 0 && terminalCount == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            if isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !plan.isEmpty { progressSection }
                        if !changedPaths.isEmpty { changesSection }
                        if !generatedImages.isEmpty { outputsSection }
                        if webSearchCount > 0 || browserCount > 0 { sourcesSection }
                        if terminalCount > 0 { terminalSection }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .thinScrollers()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.t("Summary"))
                .font(BodyFont.system(size: 13.5, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 0)
            if !plan.isEmpty {
                Text("\(completedSteps)/\(plan.count)")
                    .font(BodyFont.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var completedSteps: Int {
        plan.filter { $0.status == .completed }.count
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            LucideIcon(.listChecks, size: 26).foregroundColor(Color.white.opacity(0.28))
            Text(L10n.t("Nothing to summarize yet"))
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textSecondary)
            Text(L10n.t("Plans, changes, sources and outputs appear here as the agent works."))
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Color(white: 0.42))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sections

    private var progressSection: some View {
        section(L10n.t("Progress")) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(plan.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 8) {
                        planStatusIcon(step.status)
                            .frame(width: 14, height: 14)
                        Text(step.step)
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(step.status == .completed
                                ? Palette.textSecondary
                                : Palette.textPrimary.opacity(0.92))
                            .strikethrough(step.status == .completed, color: Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planStatusIcon(_ status: PlanStep.Status) -> some View {
        switch status {
        case .completed:
            LucideIcon(.circleCheck, size: 13).foregroundColor(Self.doneColor)
        case .inProgress:
            LucideIcon(.circleDot, size: 13).foregroundColor(Palette.pastelBlue)
        case .pending:
            Circle()
                .stroke(Color(white: 0.4), lineWidth: 1.3)
                .frame(width: 11, height: 11)
        }
    }

    private var changesSection: some View {
        section(L10n.t("Changes"), action: (L10n.t("Review"), { appState.openReviewInSidebar() })) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(changedPaths.prefix(40), id: \.self) { path in
                    Button { appState.openFileInSidebar(absolute(path)) } label: {
                        HStack(spacing: 7) {
                            FileChipIcon(size: 12)
                                .foregroundColor(Color(white: 0.6))
                                .frame(width: 14, height: 14)
                            Text((path as NSString).lastPathComponent)
                                .font(BodyFont.system(size: 12.5))
                                .foregroundColor(Palette.textPrimary.opacity(0.9))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var outputsSection: some View {
        section(L10n.t("Outputs")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(generatedImages.enumerated()), id: \.offset) { idx, item in
                    Button {
                        if let path = item.generatedImagePath {
                            appState.imagePreviewURL = URL(fileURLWithPath: path)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            LucideIcon(.image, size: 13).foregroundColor(Color(white: 0.6))
                                .frame(width: 14, height: 14)
                            Text(L10n.t("Generated image") + " \(idx + 1)")
                                .font(BodyFont.system(size: 12.5))
                                .foregroundColor(Palette.textPrimary.opacity(0.9))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(item.generatedImagePath == nil)
                }
            }
        }
    }

    private var sourcesSection: some View {
        section(L10n.t("Sources")) {
            VStack(alignment: .leading, spacing: 6) {
                if webSearchCount > 0 {
                    sourceRow(icon: .globe, text: webSearchCount == 1
                        ? L10n.t("Searched the web")
                        : "\(L10n.t("Searched the web")) · \(webSearchCount)")
                }
                if browserCount > 0 {
                    sourceRow(icon: .globe, text: browserCount == 1
                        ? L10n.t("Used the browser")
                        : "\(L10n.t("Used the browser")) · \(browserCount)")
                }
            }
        }
    }

    private var terminalSection: some View {
        section(L10n.t("Terminal")) {
            sourceRow(icon: .terminal, text: "\(L10n.t("Terminal activity")) · \(terminalCount)")
        }
    }

    private func sourceRow(icon: LucideIcon.Kind, text: String) -> some View {
        HStack(spacing: 7) {
            LucideIcon(icon, size: 13).foregroundColor(Color(white: 0.6))
                .frame(width: 14, height: 14)
            Text(text)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary.opacity(0.9))
            Spacer(minLength: 0)
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section(
        _ title: String,
        action: (label: String, run: () -> Void)? = nil,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer(minLength: 0)
                if let action {
                    Button(action: action.run) {
                        Text(action.label)
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Color(white: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
    }

    private func absolute(_ path: String) -> String {
        if path.hasPrefix("/") { return path }
        if let root = appState.activeWorkingDirectory {
            return URL(fileURLWithPath: root).appendingPathComponent(path).path
        }
        return path
    }

    static let doneColor = Color(red: 0.45, green: 0.78, blue: 0.50)
}
