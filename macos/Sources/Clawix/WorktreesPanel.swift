import SwiftUI

// MARK: - Worktrees
//
// A read-only browser of the git worktrees attached to the active project's
// repository. Useful when parallel/forked work spreads across several
// checkouts. Reads `git worktree list --porcelain`; no mutation. Reachable via
// the `/worktrees` composer command.

struct WorktreeEntry: Identifiable {
    let id: String          // worktree path (unique)
    let path: String
    let branch: String?     // short branch name, nil when detached
    let head: String?       // short sha
    let isMain: Bool
    let isDetached: Bool
    let isLocked: Bool

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

enum WorktreeReader {
    static func list(projectPath: String?) -> [WorktreeEntry] {
        guard let projectPath, !projectPath.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectPath, "worktree", "list", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    private static func parse(_ text: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var path: String?
        var head: String?
        var branch: String?
        var detached = false
        var locked = false

        func flush() {
            guard let path else { return }
            entries.append(WorktreeEntry(
                id: path,
                path: path,
                branch: branch,
                head: head.map { String($0.prefix(8)) },
                isMain: entries.isEmpty, // first listed worktree is the main checkout
                isDetached: detached,
                isLocked: locked
            ))
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                if path != nil { flush() }
                path = String(line.dropFirst("worktree ".count))
                head = nil; branch = nil; detached = false; locked = false
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "detached" {
                detached = true
            } else if line.hasPrefix("locked") {
                locked = true
            }
        }
        if path != nil { flush() }
        return entries
    }
}

struct WorktreesPanel: View {
    let onClose: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var entries: [WorktreeEntry] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("Worktrees"))
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { onClose() } label: {
                    XIcon(size: 12)
                        .foregroundColor(Color.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            if entries.isEmpty {
                VStack(spacing: 8) {
                    LucideIcon(.workflow, size: 26)
                        .foregroundColor(Color.white.opacity(0.28))
                    Text(loaded ? L10n.t("No worktrees here") : L10n.t("Loading…"))
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(entries) { entry in
                            WorktreeRow(entry: entry) { reveal(entry) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 440, height: 480)
        .background(Palette.background)
        .onAppear {
            entries = WorktreeReader.list(projectPath: appState.selectedProject?.path)
            loaded = true
        }
    }

    private func reveal(_ entry: WorktreeEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }
}

private struct WorktreeRow: View {
    let entry: WorktreeEntry
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LucideIcon(.folder, size: 13)
                    .foregroundColor(entry.isMain ? Palette.pastelBlue.opacity(0.85) : Color.white.opacity(0.55))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(BodyFont.system(size: 13, wght: 500))
                            .foregroundColor(Palette.textPrimary.opacity(0.92))
                            .lineLimit(1)
                        if entry.isMain {
                            Text(L10n.t("main"))
                                .font(BodyFont.system(size: 9.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                    HStack(spacing: 6) {
                        Text(entry.isDetached ? L10n.t("detached") : (entry.branch ?? "—"))
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                        if let head = entry.head {
                            Text(head)
                                .font(BodyFont.system(size: 10.5, design: .monospaced))
                                .foregroundColor(Palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.05 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
