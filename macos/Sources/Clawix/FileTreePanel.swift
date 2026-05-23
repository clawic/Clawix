import SwiftUI

// MARK: - File tree panel
//
// A lazy directory browser for the active project. Folders expand on demand
// (children are read only when first opened, heavy/vendored dirs skipped), and
// tapping a file opens it. Reachable via the `/files` composer command.

enum FileTreeScanner {
    static let skip: Set<String> = [
        ".git", "node_modules", ".build", "build", "dist", "out",
        "DerivedData", ".next", ".venv", "venv", "Pods", ".gradle",
        "target", "__pycache__", ".turbo", ".cache",
    ]

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    static func children(of dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .filter { !skip.contains($0.lastPathComponent) }
            .sorted { a, b in
                let ad = isDirectory(a), bd = isDirectory(b)
                if ad != bd { return ad && !bd } // directories first
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
    }
}

struct FileTreePanel: View {
    let onClose: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var filter: String = ""

    private func filteredFiles(path: String) -> [URL] {
        let query = filter.lowercased()
        return Array(
            ProjectFileIndex.shared.files(forProject: path)
                .filter { $0.lastPathComponent.lowercased().contains(query) }
                .prefix(40)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.t("Files"))
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                if let name = appState.selectedProject?.name {
                    Text(name)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
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

            if let path = appState.selectedProject?.path, !path.isEmpty {
                TextField(L10n.t("Filter files"), text: $filter)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if filter.isEmpty {
                            ForEach(FileTreeScanner.children(of: URL(fileURLWithPath: path, isDirectory: true)), id: \.path) { url in
                                FileTreeEntry(url: url, depth: 0) { open($0) }
                            }
                        } else {
                            ForEach(filteredFiles(path: path), id: \.path) { url in
                                FileTreeEntry(url: url, depth: 0) { open($0) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                VStack(spacing: 8) {
                    LucideIcon(.folder, size: 28)
                        .foregroundColor(Color.white.opacity(0.28))
                    Text(L10n.t("No project selected"))
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 420, height: 560)
        .background(Palette.background)
    }

    private func open(_ url: URL) {
        appState.openFileInSidebar(url.path)
        onClose()
    }
}

private struct FileTreeEntry: View {
    let url: URL
    let depth: Int
    let onOpen: (URL) -> Void

    @State private var expanded = false
    @State private var children: [URL]?
    @State private var hovering = false

    private var isDir: Bool { FileTreeScanner.isDirectory(url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: activate) {
                HStack(spacing: 6) {
                    if isDir {
                        LucideIcon(expanded ? .chevronDown : .chevronRight, size: 11)
                            .foregroundColor(Color.white.opacity(0.45))
                            .frame(width: 12)
                        LucideIcon(.folder, size: 13)
                            .foregroundColor(Palette.pastelBlue.opacity(0.85))
                    } else {
                        Spacer().frame(width: 12)
                        LucideIcon(.fileText, size: 13)
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                    Text(url.lastPathComponent)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textPrimary.opacity(isDir ? 0.95 : 0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(depth) * 14 + 14)
                .padding(.trailing, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.05 : 0.0))
                        .padding(.horizontal, 6)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            if isDir, expanded, let children {
                ForEach(children, id: \.path) { child in
                    FileTreeEntry(url: child, depth: depth + 1, onOpen: onOpen)
                }
            }
        }
    }

    private func activate() {
        if isDir {
            if children == nil { children = FileTreeScanner.children(of: url) }
            withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
        } else {
            onOpen(url)
        }
    }
}
