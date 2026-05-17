import Foundation

struct NativeMacActionWireActor: Codable, Equatable {
    var kind: String
    var id: String
    var role: String?
    var assignmentId: String?
    var runId: String?
}

struct NativeMacActionWireHost: Codable, Equatable {
    var hostId: String
    var bundleId: String
    var signingIdentity: String?
    var teamId: String?
    var appVariant: String?
    var appVersion: String?
}

struct NativeMacActionWireTarget: Codable, Equatable {
    var kind: String
    var id: String?
    var name: String?
    var selector: [String: JSONValue]

    init(kind: String, id: String? = nil, name: String? = nil, selector: [String: JSONValue] = [:]) {
        self.kind = kind
        self.id = id
        self.name = name
        self.selector = selector
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case id
        case name
        case selector
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        selector = try container.decodeIfPresent([String: JSONValue].self, forKey: .selector) ?? [:]
    }
}

struct NativeMacActionWireRequest: Codable, Equatable {
    var schemaVersion: Int
    var requestId: String
    var capabilityId: String
    var actor: NativeMacActionWireActor
    var host: NativeMacActionWireHost
    var target: NativeMacActionWireTarget?
    var arguments: [String: JSONValue]
    var dryRun: Bool
    var reason: String?
    var approved: Bool?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestId
        case capabilityId
        case actor
        case host
        case target
        case arguments
        case dryRun
        case reason
        case approved
    }

    init(
        schemaVersion: Int = 1,
        requestId: String,
        capabilityId: String,
        actor: NativeMacActionWireActor,
        host: NativeMacActionWireHost,
        target: NativeMacActionWireTarget? = nil,
        arguments: [String: JSONValue] = [:],
        dryRun: Bool = false,
        reason: String? = nil,
        approved: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.capabilityId = capabilityId
        self.actor = actor
        self.host = host
        self.target = target
        self.arguments = arguments
        self.dryRun = dryRun
        self.reason = reason
        self.approved = approved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        requestId = try container.decode(String.self, forKey: .requestId)
        capabilityId = try container.decode(String.self, forKey: .capabilityId)
        actor = try container.decode(NativeMacActionWireActor.self, forKey: .actor)
        host = try container.decode(NativeMacActionWireHost.self, forKey: .host)
        target = try container.decodeIfPresent(NativeMacActionWireTarget.self, forKey: .target)
        arguments = try container.decodeIfPresent([String: JSONValue].self, forKey: .arguments) ?? [:]
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        approved = try container.decodeIfPresent(Bool.self, forKey: .approved)
    }
}

struct NativeMacActionWirePermissionRequirement: Codable, Equatable {
    var permissionId: String
    var required: Bool
    var currentOsState: String
    var currentFrameworkGrant: String
    var guidance: String?
}

struct NativeMacActionWireRequiredApproval: Codable, Equatable {
    var risk: String
    var reason: String
    var approverRoles: [String]
    var requestId: String?
}

struct NativeMacActionWireRollbackPlan: Codable, Equatable {
    var level: String
    var timerSeconds: Int?
    var snapshotRequired: Bool
    var snapshotRef: String?
    var reason: String?
}

struct NativeMacActionWirePlan: Codable, Equatable {
    var schemaVersion: Int
    var planId: String
    var requestId: String
    var capabilityId: String
    var risk: String
    var coverageState: String
    var actor: NativeMacActionWireActor
    var host: NativeMacActionWireHost
    var resolvedTarget: NativeMacActionWireTarget?
    var permissionRequirements: [NativeMacActionWirePermissionRequirement]
    var requiredApprovals: [NativeMacActionWireRequiredApproval]
    var rollback: NativeMacActionWireRollbackPlan
    var willMutate: Bool
    var executable: Bool
    var blockedReasons: [String]
    var relatedSurfaces: [String]
}

struct NativeMacActionWireRedaction: Codable, Equatable {
    var level: String
    var fields: [String]
}

struct NativeMacActionWireReceipt: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var requestId: String
    var planId: String?
    var capabilityId: String
    var actor: NativeMacActionWireActor
    var host: NativeMacActionWireHost
    var result: String
    var risk: String
    var permissionSnapshotRefs: [String]
    var beforeRef: String?
    var afterRef: String?
    var auditId: String
    var revert: NativeMacActionWireRollbackPlan
    var secretRefs: [String]
    var redaction: NativeMacActionWireRedaction
    var createdAt: String
}

struct NativeMacActionWireAuditEvent: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var receiptId: String
    var requestId: String
    var planId: String?
    var capabilityId: String
    var actor: NativeMacActionWireActor
    var host: NativeMacActionWireHost
    var result: String
    var risk: String
    var summary: String
    var redaction: NativeMacActionWireRedaction
    var metadata: [String: JSONValue]
    var createdAt: String
}

struct NativeMacActionWireEvaluation: Codable, Equatable {
    var schemaVersion: Int
    var decision: String
    var requestId: String
    var planId: String
    var capabilityId: String
    var actor: NativeMacActionWireActor
    var host: NativeMacActionWireHost
    var reasons: [String]
    var approvalRequestIds: [String]
    var receipt: NativeMacActionWireReceipt?
    var auditEvent: NativeMacActionWireAuditEvent?
}

@MainActor
enum NativeMacActionWire {
    static let schemaVersion = 1

    static func decodeRequest(_ data: Data) throws -> NativeMacActionWireRequest {
        let request = try JSONDecoder().decode(NativeMacActionWireRequest.self, from: data)
        guard request.schemaVersion == schemaVersion else {
            throw NativeMacActionBroker.Error.commandFailed("Unsupported Mac action schemaVersion \(request.schemaVersion)")
        }
        return request
    }

    static func planJSON(for data: Data, encoder: JSONEncoder? = nil) throws -> Data {
        let request = try decodeRequest(data)
        let nativeRequest = request.nativeRequest
        let nativePlan = try NativeMacActionBroker.plan(for: nativeRequest)
        return try (encoder ?? wireEncoder()).encode(wirePlan(from: nativePlan, request: request))
    }

    static func evaluateJSON(
        for data: Data,
        defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard,
        auditURL: URL? = nil,
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        encoder: JSONEncoder? = nil
    ) throws -> Data {
        let request = try decodeRequest(data)
        let nativeRequest = request.nativeRequest
        let nativePlan = try? NativeMacActionBroker.plan(for: nativeRequest)
        let receipt = NativeMacActionBroker.evaluate(
            nativeRequest,
            defaults: defaults,
            auditURL: auditURL,
            runner: runner
        )
        let plan = nativePlan.map { wirePlan(from: $0, request: request) }
        return try (encoder ?? wireEncoder()).encode(wireEvaluation(from: receipt, plan: plan, request: request))
    }

    static func wirePlan(from plan: NativeMacActionPlan, request: NativeMacActionWireRequest) -> NativeMacActionWirePlan {
        let blockedReasons = [plan.blockedReason].compactMap { $0 }
        return NativeMacActionWirePlan(
            schemaVersion: schemaVersion,
            planId: plan.planId,
            requestId: plan.requestId,
            capabilityId: plan.capabilityId,
            risk: plan.risk.rawValue,
            coverageState: "executable",
            actor: request.actor,
            host: request.host,
            resolvedTarget: request.target,
            permissionRequirements: plan.requiredPermissionIds.map {
                NativeMacActionWirePermissionRequirement(
                    permissionId: $0.rawValue,
                    required: true,
                    currentOsState: "unknown",
                    currentFrameworkGrant: "not_granted",
                    guidance: nil
                )
            },
            requiredApprovals: plan.requiresApproval ? [
                NativeMacActionWireRequiredApproval(
                    risk: plan.risk.rawValue,
                    reason: request.reason ?? "\(plan.capabilityId) requires \(plan.risk.rawValue) approval",
                    approverRoles: ["owner", "admin"],
                    requestId: nil
                ),
            ] : [],
            rollback: rollbackPlan(from: plan),
            willMutate: plan.risk != .read,
            executable: blockedReasons.isEmpty && !plan.steps.isEmpty,
            blockedReasons: blockedReasons,
            relatedSurfaces: []
        )
    }

    private static func wireEvaluation(
        from receipt: NativeMacActionReceipt,
        plan: NativeMacActionWirePlan?,
        request: NativeMacActionWireRequest
    ) -> NativeMacActionWireEvaluation {
        let decision = decisionValue(from: receipt)
        let result = resultValue(from: receipt)
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let fallbackRollback = NativeMacActionWireRollbackPlan(level: "none", timerSeconds: nil, snapshotRequired: false, snapshotRef: nil, reason: nil)
        let rollback = plan?.rollback ?? fallbackRollback
        let risk = plan?.risk ?? "high"
        let redaction = NativeMacActionWireRedaction(level: risk == "high" || risk == "critical" ? "high" : "low", fields: ["arguments"])
        let auditId = "macaudit_\(receipt.requestId)_\(result)".replacingOccurrences(of: "-", with: "_")
        let wireReceipt = NativeMacActionWireReceipt(
            schemaVersion: schemaVersion,
            id: receipt.receiptId,
            requestId: receipt.requestId,
            planId: receipt.planId,
            capabilityId: receipt.capabilityId,
            actor: request.actor,
            host: request.host,
            result: result,
            risk: risk,
            permissionSnapshotRefs: [],
            beforeRef: nil,
            afterRef: nil,
            auditId: auditId,
            revert: rollback,
            secretRefs: secretRefs(from: request.arguments),
            redaction: redaction,
            createdAt: createdAt
        )
        let auditEvent = NativeMacActionWireAuditEvent(
            schemaVersion: schemaVersion,
            id: auditId,
            receiptId: wireReceipt.id,
            requestId: receipt.requestId,
            planId: receipt.planId,
            capabilityId: receipt.capabilityId,
            actor: request.actor,
            host: request.host,
            result: result,
            risk: risk,
            summary: "Mac action \(receipt.capabilityId) \(result)",
            redaction: redaction,
            metadata: receipt.error.map { ["error": .string($0)] } ?? [:],
            createdAt: createdAt
        )
        return NativeMacActionWireEvaluation(
            schemaVersion: schemaVersion,
            decision: decision,
            requestId: receipt.requestId,
            planId: receipt.planId,
            capabilityId: receipt.capabilityId,
            actor: request.actor,
            host: request.host,
            reasons: receipt.error.map { [$0] } ?? (decision == "dry_run" ? ["dry_run"] : []),
            approvalRequestIds: [],
            receipt: wireReceipt,
            auditEvent: auditEvent
        )
    }

    private static func rollbackPlan(from plan: NativeMacActionPlan) -> NativeMacActionWireRollbackPlan {
        NativeMacActionWireRollbackPlan(
            level: plan.revertLevel.rawValue,
            timerSeconds: plan.risk == .critical && plan.revertLevel != .none ? 120 : nil,
            snapshotRequired: (plan.risk == .high || plan.risk == .critical) && plan.revertLevel != .none,
            snapshotRef: nil,
            reason: plan.revertLevel == .none ? "No reliable automated revert is declared for this capability." : nil
        )
    }

    private static func decisionValue(from receipt: NativeMacActionReceipt) -> String {
        switch receipt.outcome {
        case .planned:
            return "dry_run"
        case .approvalRequired:
            return "approval_required"
        case .blocked:
            return "blocked"
        case .executed, .failed:
            return "allow"
        }
    }

    private static func resultValue(from receipt: NativeMacActionReceipt) -> String {
        switch receipt.outcome {
        case .planned, .approvalRequired:
            return "planned"
        case .blocked:
            return "blocked"
        case .executed:
            return "ok"
        case .failed:
            return "error"
        }
    }

    private static func secretRefs(from arguments: [String: JSONValue]) -> [String] {
        var refs: [String] = []
        if let secretRef = arguments["secretRef"]?.stringValue {
            refs.append(secretRef)
        }
        if case .array(let values)? = arguments["secretRefs"] {
            refs.append(contentsOf: values.compactMap(\.stringValue))
        }
        return Array(Set(refs)).sorted()
    }

    private static func wireEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension NativeMacActionWireRequest {
    var nativeRequest: NativeMacActionRequest {
        NativeMacActionRequest(
            requestId: requestId,
            capabilityId: capabilityId,
            actorId: actor.id,
            origin: actor.kind.nativeMacActionOrigin,
            arguments: arguments.compactMapValues(\.stringValue),
            dryRun: dryRun,
            approved: approved ?? false
        )
    }
}

private extension String {
    var nativeMacActionOrigin: HostActionOrigin {
        switch self {
        case "owner_cli", "user_ui":
            return .userInterface
        case "agent":
            return .agent
        case "mcp_client", "automation", "system":
            return .framework
        default:
            return .framework
        }
    }
}

private extension JSONValue {
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null, .array, .object:
            return nil
        }
    }
}
