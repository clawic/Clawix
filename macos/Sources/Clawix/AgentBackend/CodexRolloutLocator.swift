import Foundation

enum CodexRolloutLocator {
    static func find(
        threadId: String,
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true),
        fileManager: FileManager = .default
    ) -> URL? {
        let needle = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              !needle.contains("/"),
              !needle.contains("\\")
        else { return nil }

        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: []
        ) else { return nil }

        var best: (url: URL, modifiedAt: Date?)?
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasSuffix(".jsonl"), name.contains(needle) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let candidate = (url: url, modifiedAt: values?.contentModificationDate)
            if let current = best {
                if (candidate.modifiedAt ?? .distantPast) > (current.modifiedAt ?? .distantPast) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best?.url
    }
}
