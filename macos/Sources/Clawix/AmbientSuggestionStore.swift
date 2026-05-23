import Foundation
import Combine
import CryptoKit

// MARK: - Ambient suggestions
//
// Proactive, per-project suggestions surfaced on the home screen, distinct
// from the static quick-start chips. The source of truth, when present, is a
// per-project file the runtime can populate at
// `~/.clawix/ambient-suggestions/<projectHash>/suggestions.json`. When no file
// exists yet, the store derives a small, project-aware fallback set so the home
// never feels empty. Each suggestion can be dismissed; dismissals persist per
// project so a dismissed item never returns.

struct AmbientSuggestion: Identifiable, Equatable {
    let id: String
    /// Short, tappable headline that seeds the composer.
    let title: String
    /// Optional one-line elaboration (unused in the compact row, kept for
    /// accessibility and future detail surfaces).
    let detail: String?
}

@MainActor
final class AmbientSuggestionStore: ObservableObject {
    static let shared = AmbientSuggestionStore()

    /// Suggestions for the project the home is currently scoped to, with
    /// dismissed ones already filtered out. Capped for a calm home.
    @Published private(set) var visible: [AmbientSuggestion] = []

    private var projectKey: String?
    private let maxVisible = 3
    private let dismissDefaultsKey = "clawix.home.ambient.dismissed"

    private init() {}

    /// Recompute the visible set for a project. Cheap to call on appear and on
    /// project change. `path` nil means "no project" (general home).
    func refresh(projectPath path: String?, projectName name: String?) {
        let key = path ?? "__none__"
        projectKey = key
        let all = load(projectPath: path, projectName: name)
        let dismissed = dismissedIds(for: key)
        visible = Array(all.filter { !dismissed.contains($0.id) }.prefix(maxVisible))
    }

    /// Permanently hide a suggestion for the current project.
    func dismiss(_ id: String) {
        guard let key = projectKey else { return }
        var dismissed = dismissedIds(for: key)
        dismissed.insert(id)
        persistDismissed(dismissed, for: key)
        visible.removeAll { $0.id == id }
    }

    // MARK: - Loading

    private func load(projectPath path: String?, projectName name: String?) -> [AmbientSuggestion] {
        if let path, let fromDisk = readDisk(projectPath: path), !fromDisk.isEmpty {
            return fromDisk
        }
        return derived(projectName: name, hasProject: path != nil)
    }

    /// Reads a runtime-populated file if one exists. Shape mirrors the generic
    /// proactive-suggestion contract: `{ suggestions: [{ id, title, description }],
    /// currentSuggestionIds?: [String] }`.
    private func readDisk(projectPath: String) -> [AmbientSuggestion]? {
        let url = Self.fileURL(forProjectPath: projectPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let raw = root["suggestions"] as? [[String: Any]] else { return nil }
        let current = root["currentSuggestionIds"] as? [String]
        var out: [AmbientSuggestion] = []
        for item in raw {
            guard let id = item["id"] as? String,
                  let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            if let current, !current.isEmpty, !current.contains(id) { continue }
            out.append(AmbientSuggestion(id: id, title: title, detail: item["description"] as? String))
        }
        return out
    }

    /// Project-aware fallback when no runtime file exists. Original phrasing,
    /// generic enough to fit any repository; the runtime can replace these with
    /// context-specific ones by writing the file above.
    private func derived(projectName: String?, hasProject: Bool) -> [AmbientSuggestion] {
        guard hasProject else {
            if let role = WelcomeRoleStore.shared.selectedRole {
                return role.seeds.enumerated().map { index, title in
                    AmbientSuggestion(id: "derived.role.\(role.rawValue).\(index)", title: title, detail: nil)
                }
            }
            return [
                AmbientSuggestion(id: "derived.general.outline", title: "Outline a small project I could build today", detail: nil),
                AmbientSuggestion(id: "derived.general.learn", title: "Teach me something new with a hands-on example", detail: nil),
                AmbientSuggestion(id: "derived.general.organize", title: "Help me organize my notes and to-dos", detail: nil),
            ]
        }
        let name = (projectName?.isEmpty == false) ? projectName! : "this project"
        return [
            AmbientSuggestion(id: "derived.proj.tour", title: "Walk me through how \(name) fits together", detail: nil),
            AmbientSuggestion(id: "derived.proj.risk", title: "Point out the riskiest code in \(name) to clean up", detail: nil),
            AmbientSuggestion(id: "derived.proj.tests", title: "Add the tests \(name) is missing most", detail: nil),
        ]
    }

    // MARK: - Dismissal persistence

    private func dismissedIds(for key: String) -> Set<String> {
        let map = UserDefaults.standard.dictionary(forKey: dismissDefaultsKey) as? [String: [String]] ?? [:]
        return Set(map[key] ?? [])
    }

    private func persistDismissed(_ ids: Set<String>, for key: String) {
        var map = UserDefaults.standard.dictionary(forKey: dismissDefaultsKey) as? [String: [String]] ?? [:]
        map[key] = Array(ids)
        UserDefaults.standard.set(map, forKey: dismissDefaultsKey)
    }

    // MARK: - Paths

    static func fileURL(forProjectPath projectPath: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".clawix/ambient-suggestions", isDirectory: true)
        return base
            .appendingPathComponent(hash(projectPath), isDirectory: true)
            .appendingPathComponent("suggestions.json", isDirectory: false)
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }
}
