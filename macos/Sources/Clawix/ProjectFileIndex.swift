import Foundation
import Combine

// MARK: - Project file index
//
// A small, cached, bounded listing of the selected project's files, used by the
// command menu's file search. Built lazily on first use and cached per project
// path so typing doesn't re-walk the tree. Heavy/vendored directories are
// skipped so large repos stay responsive.

@MainActor
final class ProjectFileIndex: ObservableObject {
    static let shared = ProjectFileIndex()

    private var cachedPath: String?
    private var cachedFiles: [URL] = []

    private let maxFiles = 4000
    private let skipDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "dist", "out",
        "DerivedData", ".next", ".nuxt", ".venv", "venv", "Pods",
        ".gradle", "target", "__pycache__", ".turbo", ".cache",
    ]

    private init() {}

    /// Files for a project path, cached until the path changes. Empty when no
    /// project is selected.
    func files(forProject path: String?) -> [URL] {
        guard let path, !path.isEmpty else {
            cachedPath = nil
            cachedFiles = []
            return []
        }
        if cachedPath == path { return cachedFiles }
        cachedPath = path
        cachedFiles = scan(root: URL(fileURLWithPath: path, isDirectory: true))
        return cachedFiles
    }

    func invalidate() {
        cachedPath = nil
        cachedFiles = []
    }

    private func scan(root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if files.count >= maxFiles { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if skipDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            files.append(url)
        }
        return files
    }
}
