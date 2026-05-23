import Foundation

enum DiagnosticEvidenceCategory: String, CaseIterable, Codable, Equatable {
    case general = "general"
    case launch = "launch"
    case uiChat = "ui.chat"
    case uiSidebar = "ui.sidebar"
    case stateAppState = "state.appstate"
    case ipcClient = "ipc.client"
    case backendMetadata = "backend.metadata"
    case serviceSupervisor = "service.supervisor"
    case appsStore = "apps.store"
    case renderMarkdown = "render.markdown"
    case renderStreaming = "render.streaming"
    case imageLoad = "image.load"
    case secretsCrypto = "secrets.crypto"
    case hang = "hang"
    case resource = "resource"
    case diagnosticsExport = "diagnostics.export"
    case safetyReview = "safety.review"

    var isPerformanceTaxonomyCategory: Bool {
        PerfSignpost.allCases.contains { $0.rawValue == rawValue }
    }

    static var performanceTaxonomyRawValues: [String] {
        PerfSignpost.allCases.map(\.rawValue)
    }
}

enum ClawixDiagnosticLogCategory {
    static let resource = DiagnosticEvidenceCategory.resource.rawValue
    static let hang = DiagnosticEvidenceCategory.hang.rawValue
    static let metricKit = "diagnostics.metrickit"
    static let export = DiagnosticEvidenceCategory.diagnosticsExport.rawValue
}

struct DiagnosticArtifactReference: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var kind: String
    var category: String
    var byteCount: UInt64?
    var modifiedAt: String?
}

enum ClawixDiagnosticRedactor {
    static func redact(_ text: String) -> String {
        var redacted = text.replacingOccurrences(
            of: #"\brollout-\d{4}-\d{2}-\d{2}T\d{2}[-:]\d{2}[-:]\d{2}(?:-\d{3})?-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.jsonl\b"#,
            with: "[redacted_session]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)secret://[^\s"'`)},\]]+"#,
            with: "[redacted_secret_ref]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\bfile://[^\s"'`)},\]]+"#,
            with: "[redacted_file_url]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?:~|/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+)/\.codex/(?:sessions|goals)\b[^\s"'`)},\]]*"#,
            with: "[redacted_session]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: ClawixUserHomeRoutes.absoluteUsersPathRedactionPattern,
            with: "[redacted_path]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\b(path|local_path|filepath|file_path)\s*[:=]\s*("[^"]*"|'[^']*'|[^\n\r;]+)"#,
            with: "$1=[redacted_path]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{10,}\b"#,
            with: "Bearer [redacted_secret]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\b(?:sk|pk|rk)-[A-Za-z0-9_\-]{8,}\b|\b(?:gh[pousr]|github_pat)_[A-Za-z0-9_]{20,}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}\b|\bAKIA[0-9A-Z]{16}\b"#,
            with: "[redacted_secret]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\b(api[_-]?key|token|secret|password|authorization)\s*[:=]\s*("[^"]*"|'[^']*'|[^\s\n\r;]+)"#,
            with: "$1=[redacted_secret]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"-----BEGIN [A-Z ]+PRIVATE KEY-----(.|\n)*?-----END [A-Z ]+PRIVATE KEY-----"#,
            with: "[redacted_private_key]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\b(?:DEVELOPMENT_TEAM|TEAM_ID|team_id|teamId|Team ID|team identifier)\b[^\n]{0,60}\b[A-Z0-9]{10}\b"#,
            with: "[redacted_team_id]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\b(?:bundle_id|bundleId|bundle identifier|withBundleIdentifier)\b[^\n]{0,80}\bcom\.(?:claw|clawix)(?:\.[A-Za-z0-9_-]+)+\b"#,
            with: "[redacted_bundle_id]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            with: "[redacted_email]",
            options: [.regularExpression, .caseInsensitive]
        )
        redacted = redacted.replacingOccurrences(
            of: #"\b(prompt|input|message)\s*[:=]\s*("[^"]*"|'[^']*'|[^\n\r;]+)"#,
            with: "$1: [redacted_prompt]",
            options: .regularExpression
        )
        return redacted
    }

    static func containsSensitivePattern(_ text: String) -> Bool {
        redact(text) != text
    }
}

enum DiagnosticArtifactClassifier {
    private static let stampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func reference(for url: URL, fileManager: FileManager = .default) -> DiagnosticArtifactReference {
        let rawName = url.lastPathComponent.isEmpty ? "diagnostic" : url.lastPathComponent
        let name = ClawixDiagnosticRedactor.redact(rawName)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.uint64Value
        let modifiedAt = (attributes?[.modificationDate] as? Date).map { stampFormatter.string(from: $0) }
        return DiagnosticArtifactReference(
            name: name,
            kind: kind(for: rawName),
            category: category(for: rawName).rawValue,
            byteCount: byteCount,
            modifiedAt: modifiedAt
        )
    }

    static func collectRecentReferences(
        in directoryURL: URL,
        limit: Int = 40,
        fileManager: FileManager = .default
    ) -> [DiagnosticArtifactReference] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted { lhs, rhs in
                modifiedDate(for: lhs) > modifiedDate(for: rhs)
            }
            .prefix(max(0, limit))
            .map { reference(for: $0, fileManager: fileManager) }
    }

    static func categories(from message: String, artifacts: [DiagnosticArtifactReference]) -> [String] {
        var categories = Set<String>()
        categories.insert(DiagnosticEvidenceCategory.general.rawValue)
        for artifact in artifacts {
            categories.insert(artifact.category)
        }

        let normalized = message.lowercased()
        let keywordCategories: [(String, DiagnosticEvidenceCategory)] = [
            ("launch", .launch),
            ("startup", .launch),
            ("chat", .uiChat),
            ("sidebar", .uiSidebar),
            ("bridge", .ipcClient),
            ("ipc", .ipcClient),
            ("daemon", .serviceSupervisor),
            ("render", .renderMarkdown),
            ("markdown", .renderMarkdown),
            ("stream", .renderStreaming),
            ("image", .imageLoad),
            ("hang", .hang),
            ("freeze", .hang),
            ("stuck", .hang),
            ("slow", .resource),
            ("cpu", .resource),
            ("memory", .resource),
            ("ram", .resource),
            ("battery", .resource),
            ("secret", .secretsCrypto),
            ("safety", .safetyReview)
        ]
        for (keyword, category) in keywordCategories where normalized.contains(keyword) {
            categories.insert(category.rawValue)
        }
        return categories.sorted()
    }

    private static func kind(for name: String) -> String {
        let lower = name.lowercased()
        if lower == ResourceSampler.lastResourcesFileName { return "resource.snapshot" }
        if lower == ResourceSampler.resourceSamplesFileName { return "resource.samples" }
        if lower.hasPrefix("metrics-") { return "metrickit.metrics" }
        if lower.hasPrefix("diagnostics-") { return "metrickit.diagnostics" }
        if lower.contains("receipt") { return "receipt" }
        if lower.hasSuffix(".log") { return "log" }
        if lower.hasSuffix(".json") { return "json" }
        return "diagnostic"
    }

    private static func modifiedDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private static func category(for name: String) -> DiagnosticEvidenceCategory {
        let lower = name.lowercased()
        if lower.contains("launch") { return .launch }
        if lower.contains("render") { return .renderMarkdown }
        if lower.contains("quickask") { return .uiChat }
        if lower.contains("hotkey") { return .uiChat }
        if lower.contains("resource") { return .resource }
        if lower.contains("metrics") { return .resource }
        if lower.contains("diagnostics") { return .hang }
        if lower.contains("hang") { return .hang }
        if lower.contains("bridge") { return .ipcClient }
        if lower.contains("daemon") { return .serviceSupervisor }
        if lower.contains("feedback") { return .diagnosticsExport }
        return .general
    }
}
