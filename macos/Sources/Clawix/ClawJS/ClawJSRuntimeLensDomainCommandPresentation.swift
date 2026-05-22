import Foundation

struct ClawJSRuntimeLensDomainCommandPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let command: String
        let index: Int

        var accessibilityLabel: String {
            "runtime domain command \(index), command \(command)"
        }
    }

    let domain: String
    let totalCommandCount: Int
    let visibleCommandCount: Int
    let hiddenCommandCount: Int
    let rows: [Row]

    var hasCommands: Bool {
        totalCommandCount > 0
    }

    var accessibilityLabel: String {
        [
            "Runtime domain commands",
            "domain \(domain)",
            "commands \(totalCommandCount)",
            "visible \(visibleCommandCount)",
            "hidden \(hiddenCommandCount)"
        ]
        .joined(separator: ", ")
    }

    static func make(
        domain: String,
        commands: [String],
        limit: Int = 3
    ) -> ClawJSRuntimeLensDomainCommandPresentation {
        let normalizedCommands = commands.compactMap(normalized)
        let visibleLimit = max(0, limit)
        let rows = normalizedCommands.prefix(visibleLimit).enumerated().map { index, command in
            Row(
                id: stableId(command, fallback: "\(index + 1)"),
                command: command,
                index: index + 1
            )
        }

        return ClawJSRuntimeLensDomainCommandPresentation(
            domain: domain,
            totalCommandCount: normalizedCommands.count,
            visibleCommandCount: rows.count,
            hiddenCommandCount: max(0, normalizedCommands.count - rows.count),
            rows: rows
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static func stableId(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let id = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .lowercased()
        return id.isEmpty ? fallback : id
    }
}
