import Foundation

struct AppHighRiskActionReceipt: Codable, Equatable, Hashable, Identifiable {
    enum Decision: String, Codable, Equatable, Hashable {
        case denied
        case approvedOnce
        case approvedAlways
        case preapproved
    }

    enum Outcome: String, Codable, Equatable, Hashable {
        case denied
        case approvalRecordedDispatchUnavailable
        case dispatchFailed
        case dispatched
    }

    var id: String
    var appId: UUID
    var appSlug: String
    var appName: String
    var capabilityId: String
    var action: String
    var decision: Decision
    var outcome: Outcome
    var riskTier: AppCapabilityRiskTier
    var interruptiveApproval: Bool
    var createdAt: Date
    var reason: String

    init(
        id: String = "app-action-\(UUID().uuidString.lowercased())",
        app: AppRecord,
        descriptor: AppCapabilityDescriptor,
        action: String,
        decision: Decision,
        outcome: Outcome,
        createdAt: Date = Date(),
        reason: String
    ) {
        self.id = id
        self.appId = app.id
        self.appSlug = app.slug
        self.appName = app.name
        self.capabilityId = descriptor.id
        self.action = action
        self.decision = decision
        self.outcome = outcome
        self.riskTier = descriptor.riskTier
        self.interruptiveApproval = descriptor.interruptiveApproval
        self.createdAt = createdAt
        self.reason = reason
    }
}

enum AppHighRiskActionAudit {
    static let filename = "high-risk-action-audit.jsonl"

    static func capabilityId(forTool tool: String) -> String {
        let normalized = tool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("secrets.") || normalized.contains("secret") {
            return "secrets.broker"
        }
        if normalized.hasPrefix("mac.") || normalized.hasPrefix("host.") || normalized.contains("native") {
            return "mac.action.plan"
        }
        if normalized.hasPrefix("iot.") || normalized.contains("device") {
            return "iot.device.action.invoke"
        }
        if normalized == "jobs.start" {
            return "jobs.start"
        }
        if normalized == "jobs.cancel" {
            return "jobs.cancel"
        }
        return "actions.invoke"
    }

    static func descriptor(forTool tool: String) -> AppCapabilityDescriptor? {
        AppCapabilityCatalog.descriptor(id: capabilityId(forTool: tool))
    }

    @discardableResult
    static func append(
        app: AppRecord,
        descriptor: AppCapabilityDescriptor,
        action: String,
        decision: AppHighRiskActionReceipt.Decision,
        outcome: AppHighRiskActionReceipt.Outcome,
        reason: String,
        auditURL: URL
    ) throws -> AppHighRiskActionReceipt {
        let receipt = AppHighRiskActionReceipt(
            app: app,
            descriptor: descriptor,
            action: action,
            decision: decision,
            outcome: outcome,
            reason: reason
        )
        try append(receipt, to: auditURL)
        return receipt
    }

    static func append(_ receipt: AppHighRiskActionReceipt, to auditURL: URL) throws {
        try FileManager.default.createDirectory(
            at: auditURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try redactedJSONData(for: receipt, encoder: encoder)
        if FileManager.default.fileExists(atPath: auditURL.path) {
            let handle = try FileHandle(forWritingTo: auditURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: auditURL, options: .atomic)
        }
    }

    private static func redactedJSONData(for receipt: AppHighRiskActionReceipt, encoder: JSONEncoder) throws -> Data {
        let data = try encoder.encode(receipt)
        let text = String(decoding: data, as: UTF8.self)
        return Data(ClawixDiagnosticRedactor.redact(text).utf8)
    }

    static func read(from auditURL: URL) throws -> [AppHighRiskActionReceipt] {
        guard FileManager.default.fileExists(atPath: auditURL.path) else { return [] }
        let text = try String(contentsOf: auditURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try text
            .split(separator: "\n")
            .map { try decoder.decode(AppHighRiskActionReceipt.self, from: Data($0.utf8)) }
    }
}
