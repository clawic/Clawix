import Foundation

extension AppState {
    func applyBackendModels(_ entries: [ClawixService.ModelEntry]) {
        let labels = unique(entries.compactMap(Self.modelPickerLabel))
        guard !labels.isEmpty else { return }

        let preferredPrimary = ["5.5", "5.4"]
        let primary = preferredPrimary.filter { labels.contains($0) }
        let nextAvailableModels: [String]
        let nextOtherModels: [String]
        if primary.isEmpty {
            nextAvailableModels = Array(labels.prefix(2))
            nextOtherModels = Array(labels.dropFirst(2))
        } else {
            nextAvailableModels = primary
            nextOtherModels = labels.filter { !primary.contains($0) }
        }
        if availableModels != nextAvailableModels {
            availableModels = nextAvailableModels
        }
        if otherModels != nextOtherModels {
            otherModels = nextOtherModels
        }
    }

    private static func modelPickerLabel(for entry: ClawixService.ModelEntry) -> String? {
        let raw = entry.slug.isEmpty ? entry.display : entry.slug
        let withoutPrefix: String
        if raw.lowercased().hasPrefix("gpt-") {
            withoutPrefix = String(raw.dropFirst(4))
        } else if entry.display.lowercased().hasPrefix("gpt-") {
            withoutPrefix = String(entry.display.dropFirst(4))
        } else {
            withoutPrefix = raw
        }
        let cleaned = withoutPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.contains("/") else { return nil }
        return cleaned
            .split(separator: "-")
            .map { part -> String in
                switch part.lowercased() {
                case "mini": return "Mini"
                case "pro": return "Pro"
                case "spark": return "Spark"
                default: return String(part)
                }
            }
            .joined(separator: "-")
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
