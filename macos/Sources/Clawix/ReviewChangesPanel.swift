import SwiftUI

// MARK: - Review / Changes side-panel surface
//
// Right side-panel git review: staged + unstaged file lists with +/- line
// counts, an inline unified diff per file, and stage / unstage / discard
// actions per file and across the whole working tree. Reachable from the
// side-panel launcher's "Review" tile, the `+` menu, and surfaces the same
// working directory as the file tree (active chat's project / cwd).

@MainActor
final class ReviewChangesModel: ObservableObject {
    @Published private(set) var snapshot: GitChangesSnapshot = .empty
    @Published private(set) var loading = false
    @Published var expandedFileId: String?
    @Published private(set) var diffCache: [String: String] = [:]

    private var cwd: String?
    private var busy = false

    func configure(cwd: String?) {
        guard cwd != self.cwd else { return }
        self.cwd = cwd
        expandedFileId = nil
        diffCache = [:]
        reload()
    }

    func reload() {
        let cwd = self.cwd
        loading = true
        Task.detached(priority: .userInitiated) {
            let snap = GitChangesService.snapshot(cwd: cwd)
            await MainActor.run {
                self.snapshot = snap
                self.loading = false
                // Drop cached diffs for files that no longer have changes.
                let live = Set((snap.staged + snap.unstaged).map(\.id))
                self.diffCache = self.diffCache.filter { live.contains($0.key) }
                if let exp = self.expandedFileId, !live.contains(exp) {
                    self.expandedFileId = nil
                }
            }
        }
    }

    func toggleDiff(for change: GitFileChange) {
        if expandedFileId == change.id {
            expandedFileId = nil
            return
        }
        expandedFileId = change.id
        guard diffCache[change.id] == nil, let root = snapshot.root else { return }
        Task.detached(priority: .userInitiated) {
            let text = GitChangesService.diff(for: change, root: root)
            await MainActor.run { self.diffCache[change.id] = text }
        }
    }

    private func mutate(_ work: @escaping (String) -> Void) {
        guard let root = snapshot.root, !busy else { return }
        busy = true
        Task.detached(priority: .userInitiated) {
            work(root)
            await MainActor.run {
                self.busy = false
                self.reload()
            }
        }
    }

    func stage(_ c: GitFileChange) { mutate { GitChangesService.stage(c, root: $0) } }
    func unstage(_ c: GitFileChange) { mutate { GitChangesService.unstage(c, root: $0) } }
    func discard(_ c: GitFileChange) { mutate { GitChangesService.discard(c, root: $0) } }
    func stageAll() { mutate { GitChangesService.stageAll(root: $0) } }
    func unstageAll() { mutate { GitChangesService.unstageAll(root: $0) } }
    func discardAll() { mutate { GitChangesService.discardAll(root: $0) } }
}

struct ReviewChangesPanel: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = ReviewChangesModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .onAppear { model.configure(cwd: appState.activeWorkingDirectory) }
        .onChange(of: appState.activeWorkingDirectory) { _, new in
            model.configure(cwd: new)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.t("Changes"))
                .font(BodyFont.system(size: 13.5, wght: 600))
                .foregroundColor(Palette.textPrimary)
            if let branch = model.snapshot.branch {
                HStack(spacing: 4) {
                    GitCompareIcon(size: 11)
                        .foregroundColor(Palette.textSecondary)
                    Text(branch)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if !model.snapshot.isClean {
                Text("+\(model.snapshot.totalAdded)")
                    .font(BodyFont.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Self.addColor)
                Text("−\(model.snapshot.totalRemoved)")
                    .font(BodyFont.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Self.delColor)
            }
            Button { model.reload() } label: {
                LucideIcon(.refreshCw, size: 12)
                    .foregroundColor(Color(white: model.loading ? 0.4 : 0.6))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Refresh changes"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !model.snapshot.hasRepo {
            emptyState(icon: "git", title: L10n.t("Not a git repository"),
                       subtitle: L10n.t("Open a project under version control to review changes."))
        } else if model.snapshot.isClean {
            emptyState(icon: "check", title: L10n.t("No changes"),
                       subtitle: L10n.t("Your working tree is clean."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !model.snapshot.staged.isEmpty {
                        sectionHeader(
                            title: L10n.t("Staged"),
                            count: model.snapshot.staged.count,
                            actions: [(L10n.t("Unstage all"), false, { model.unstageAll() })]
                        )
                        ForEach(model.snapshot.staged) { change in
                            fileRow(change)
                        }
                    }
                    if !model.snapshot.unstaged.isEmpty {
                        sectionHeader(
                            title: L10n.t("Changes"),
                            count: model.snapshot.unstaged.count,
                            actions: [
                                (L10n.t("Stage all"), false, { model.stageAll() }),
                                (L10n.t("Revert all"), true, { confirmDiscardAll() }),
                            ]
                        )
                        ForEach(model.snapshot.unstaged) { change in
                            fileRow(change)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .thinScrollers()
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Group {
                if icon == "git" {
                    GitCompareIcon(size: 26).foregroundColor(Color.white.opacity(0.28))
                } else {
                    LucideIcon(.circleCheck, size: 26).foregroundColor(Color.white.opacity(0.28))
                }
            }
            Text(title)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textSecondary)
            Text(subtitle)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Color(white: 0.42))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Section header

    private func sectionHeader(
        title: String,
        count: Int,
        actions: [(label: String, destructive: Bool, run: () -> Void)]
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
            Text("\(count)")
                .font(BodyFont.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
            Spacer(minLength: 0)
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                SectionActionButton(label: action.label, destructive: action.destructive, run: action.run)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: File row

    @ViewBuilder
    private func fileRow(_ change: GitFileChange) -> some View {
        ReviewFileRow(
            change: change,
            expanded: model.expandedFileId == change.id,
            diff: model.diffCache[change.id],
            onToggle: { model.toggleDiff(for: change) },
            onOpen: { appState.openFileInSidebar(absolutePath(change)) },
            onStage: { model.stage(change) },
            onUnstage: { model.unstage(change) },
            onDiscard: { confirmDiscard(change) }
        )
    }

    private func absolutePath(_ change: GitFileChange) -> String {
        guard let root = model.snapshot.root else { return change.path }
        return URL(fileURLWithPath: root).appendingPathComponent(change.path).path
    }

    // MARK: Confirmations

    private func confirmDiscard(_ change: GitFileChange) {
        let name = (change.path as NSString).lastPathComponent
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Discard changes?",
            body: change.kind == .untracked
                ? "\(name) will be deleted. This cannot be undone."
                : "Changes to \(name) will be permanently discarded.",
            confirmLabel: "Discard",
            isDestructive: true,
            onConfirm: { model.discard(change) }
        )
    }

    private func confirmDiscardAll() {
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Revert all changes?",
            body: "Every uncommitted change will be discarded and untracked files removed. This cannot be undone.",
            confirmLabel: "Revert all",
            isDestructive: true,
            onConfirm: { model.discardAll() }
        )
    }

    static let addColor = Color(red: 0.45, green: 0.78, blue: 0.50)
    static let delColor = Color(red: 0.88, green: 0.45, blue: 0.45)
}

// MARK: - Section action button

private struct SectionActionButton: View {
    let label: String
    let destructive: Bool
    let run: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: run) {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(destructive
                    ? ReviewChangesPanel.delColor.opacity(hovered ? 1 : 0.85)
                    : Color(white: hovered ? 0.92 : 0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.07 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - File row

private struct ReviewFileRow: View {
    let change: GitFileChange
    let expanded: Bool
    let diff: String?
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onDiscard: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    LucideIcon(expanded ? .chevronDown : .chevronRight, size: 11)
                        .foregroundColor(Color.white.opacity(0.4))
                        .frame(width: 12)
                    statusBadge
                    pathLabel
                    Spacer(minLength: 6)
                    if hovered {
                        rowActions
                    } else {
                        counts
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.05 : 0))
                        .padding(.horizontal, 6)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }

            if expanded {
                diffBody
                    .padding(.leading, 26)
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private var pathLabel: some View {
        let dir = (change.path as NSString).deletingLastPathComponent
        let name = (change.path as NSString).lastPathComponent
        return HStack(spacing: 4) {
            Text(name)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
            if !dir.isEmpty {
                Text(dir)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Color(white: 0.45))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    private var statusBadge: some View {
        Text(String(statusLetter))
            .font(BodyFont.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundColor(statusColor)
            .frame(width: 14, height: 14)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(statusColor.opacity(0.16))
            )
    }

    private var counts: some View {
        HStack(spacing: 6) {
            if change.added > 0 {
                Text("+\(change.added)")
                    .font(BodyFont.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(ReviewChangesPanel.addColor)
            }
            if change.removed > 0 {
                Text("−\(change.removed)")
                    .font(BodyFont.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(ReviewChangesPanel.delColor)
            }
        }
    }

    private var rowActions: some View {
        HStack(spacing: 2) {
            iconButton(.fileText, label: L10n.t("Open file"), action: onOpen)
            if change.staged {
                iconButton(.minus, label: L10n.t("Unstage"), action: onUnstage)
            } else {
                iconButton(.plus, label: L10n.t("Stage"), action: onStage)
            }
            iconButton(.undo2, label: L10n.t("Discard"), destructive: true, action: onDiscard)
        }
    }

    private func iconButton(_ icon: LucideIcon.Kind, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 12)
                .foregroundColor(destructive ? ReviewChangesPanel.delColor.opacity(0.9) : Color(white: 0.72))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var diffBody: some View {
        if let diff {
            if diff.isEmpty {
                Text(L10n.t("No diff to display"))
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Color(white: 0.45))
            } else {
                DiffTextView(diff: diff)
            }
        } else {
            Text(L10n.t("Loading diff…"))
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Color(white: 0.45))
        }
    }

    private var statusLetter: Character {
        switch change.kind {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .typeChanged: return "T"
        case .untracked: return "U"
        case .unmerged: return "!"
        }
    }

    private var statusColor: Color {
        switch change.kind {
        case .added, .untracked, .copied: return ReviewChangesPanel.addColor
        case .deleted: return ReviewChangesPanel.delColor
        case .renamed, .typeChanged: return Palette.pastelBlue
        case .unmerged: return Color(red: 0.95, green: 0.62, blue: 0.32)
        case .modified: return Color(red: 0.85, green: 0.70, blue: 0.35)
        }
    }
}

// MARK: - Diff renderer

private struct DiffTextView: View {
    let diff: String

    private var lines: [Line] {
        diff.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(600)
            .enumerated()
            .map { Line(id: $0.offset, text: String($0.element)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                Text(line.text.isEmpty ? " " : line.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(color(for: line.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 0.5)
                    .background(background(for: line.text))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.popupStroke, lineWidth: 0.5)
        )
    }

    private func color(for text: String) -> Color {
        if text.hasPrefix("+++") || text.hasPrefix("---") { return Color(white: 0.5) }
        if text.hasPrefix("@@") { return Palette.pastelBlue.opacity(0.85) }
        if text.hasPrefix("+") { return ReviewChangesPanel.addColor }
        if text.hasPrefix("-") { return ReviewChangesPanel.delColor }
        if text.hasPrefix("diff ") || text.hasPrefix("index ") { return Color(white: 0.4) }
        return Color(white: 0.7)
    }

    private func background(for text: String) -> Color {
        if text.hasPrefix("+++") || text.hasPrefix("---") { return .clear }
        if text.hasPrefix("+") { return ReviewChangesPanel.addColor.opacity(0.10) }
        if text.hasPrefix("-") { return ReviewChangesPanel.delColor.opacity(0.10) }
        return .clear
    }

    private struct Line: Identifiable {
        let id: Int
        let text: String
    }
}
