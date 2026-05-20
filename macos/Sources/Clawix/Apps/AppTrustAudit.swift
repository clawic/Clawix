import Foundation

struct AppTrustAuditEvent: Codable, Equatable, Hashable, Identifiable {
    enum EventType: String, Codable, Equatable, Hashable {
        case packageImported
        case activationApproved
    }

    var id: String
    var appId: UUID
    var appSlug: String
    var appName: String
    var eventType: EventType
    var originClass: AppOriginClass
    var createdAt: Date
    var actor: String
    var sourcePath: String?
    var sourceSlug: String?
    var sourceOriginClass: AppOriginClass?
    var packageKind: String?
    var signatureStatus: AppPackageSignatureStatus?
    var riskMapSource: String?
    var ordinaryAccess: [String]
    var approvalRequired: [String]
    var highRisk: [String]
    var reason: String

    init(
        id: String = "app-trust-\(UUID().uuidString.lowercased())",
        app: AppRecord,
        eventType: EventType,
        actor: String = NSFullUserName(),
        createdAt: Date = Date(),
        riskMap: AppCapabilityRiskMap? = nil,
        reason: String
    ) {
        let provenance = app.packageProvenance
        self.id = id
        self.appId = app.id
        self.appSlug = app.slug
        self.appName = app.name
        self.eventType = eventType
        self.originClass = app.effectiveOriginClass
        self.createdAt = createdAt
        self.actor = actor
        self.sourcePath = provenance?.sourcePath
        self.sourceSlug = provenance?.sourceSlug
        self.sourceOriginClass = provenance?.sourceOriginClass
        self.packageKind = provenance?.packageKind
        self.signatureStatus = provenance?.signatureStatus
        self.riskMapSource = riskMap?.source
        self.ordinaryAccess = riskMap?.ordinaryAccess ?? []
        self.approvalRequired = riskMap?.approvalRequired ?? []
        self.highRisk = riskMap?.highRisk ?? []
        self.reason = reason
    }
}

enum AppTrustAudit {
    static let filename = "trust-audit.jsonl"

    @discardableResult
    static func append(
        app: AppRecord,
        eventType: AppTrustAuditEvent.EventType,
        riskMap: AppCapabilityRiskMap? = nil,
        reason: String,
        auditURL: URL
    ) throws -> AppTrustAuditEvent {
        let event = AppTrustAuditEvent(
            app: app,
            eventType: eventType,
            riskMap: riskMap,
            reason: reason
        )
        try append(event, to: auditURL)
        return event
    }

    static func append(_ event: AppTrustAuditEvent, to auditURL: URL) throws {
        try FileManager.default.createDirectory(
            at: auditURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(event)
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

    static func read(from auditURL: URL) throws -> [AppTrustAuditEvent] {
        guard FileManager.default.fileExists(atPath: auditURL.path) else { return [] }
        let text = try String(contentsOf: auditURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try text
            .split(separator: "\n")
            .map { try decoder.decode(AppTrustAuditEvent.self, from: Data($0.utf8)) }
    }
}
