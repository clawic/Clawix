import Foundation

struct AppCapabilityDescriptor: Codable, Equatable, Hashable {
    var id: String
    var title: String
    var summary: String
    var customAppAccess: AppCapabilityAccess
    var redactionPolicyRef: String? = nil
    var riskTier: AppCapabilityRiskTier
    var interruptiveApproval: Bool
    var touchesSecrets: Bool
    var touchesNativeHost: Bool
    var touchesPhysicalWorld: Bool
    var destructive: Bool
}

enum AppCapabilityAccess: String, Codable, Equatable, Hashable {
    case localWide
    case declared
    case approvalRequired
    case blocked
}

enum AppCapabilityRiskTier: String, Codable, Equatable, Hashable {
    case low
    case medium
    case high
    case critical
}

struct AppCapabilityRiskMap: Codable, Equatable, Hashable {
    var authorityModel: String
    var capabilityIds: [String]
    var ordinaryAccess: [String]
    var approvalRequired: [String]
    var blocked: [String]
    var highRisk: [String]
    var unknown: [String]
    var requiresActivationReview: Bool
    var source: String
}

enum AppActivationGate: Equatable {
    case allowed
    case reviewRequired(AppCapabilityRiskMap)
    case blockedUnknownCapabilities([String])
}

enum AppCapabilityCatalog {
    static let source = "docs/adr/0019-sdk-first-custom-surfaces-and-nonblocking-shell.md"

    static let descriptors: [AppCapabilityDescriptor] = [
        AppCapabilityDescriptor(
            id: "search.query",
            title: "Search query",
            summary: "Federated framework search through the SDK/bridge, not direct indexes.",
            customAppAccess: .localWide,
            redactionPolicyRef: AppBridgeRedactionPolicy.policyId,
            riskTier: .low,
            interruptiveApproval: false,
            touchesSecrets: false,
            touchesNativeHost: false,
            touchesPhysicalWorld: false,
            destructive: false
        ),
        AppCapabilityDescriptor(
            id: "db.query",
            title: "Database query",
            summary: "Structured local collection queries through the framework contract, not direct SQLite.",
            customAppAccess: .localWide,
            redactionPolicyRef: AppBridgeRedactionPolicy.policyId,
            riskTier: .low,
            interruptiveApproval: false,
            touchesSecrets: false,
            touchesNativeHost: false,
            touchesPhysicalWorld: false,
            destructive: false
        ),
        AppCapabilityDescriptor(
            id: "resources.read",
            title: "Resource read",
            summary: "Read registered resources through resource contracts.",
            customAppAccess: .localWide,
            redactionPolicyRef: AppBridgeRedactionPolicy.policyId,
            riskTier: .low,
            interruptiveApproval: false,
            touchesSecrets: false,
            touchesNativeHost: false,
            touchesPhysicalWorld: false,
            destructive: false
        ),
        AppCapabilityDescriptor(
            id: "actions.invoke",
            title: "Framework action invoke",
            summary: "Brokered framework actions that may write or affect external state.",
            customAppAccess: .approvalRequired,
            riskTier: .high,
            interruptiveApproval: true,
            touchesSecrets: false,
            touchesNativeHost: false,
            touchesPhysicalWorld: false,
            destructive: false
        ),
        AppCapabilityDescriptor(
            id: "secrets.broker",
            title: "Secrets broker",
            summary: "Brokered secret references and leases without exposing plaintext secrets.",
            customAppAccess: .approvalRequired,
            riskTier: .critical,
            interruptiveApproval: true,
            touchesSecrets: true,
            touchesNativeHost: true,
            touchesPhysicalWorld: false,
            destructive: false
        ),
        AppCapabilityDescriptor(
            id: "mac.action.plan",
            title: "Mac action plan",
            summary: "Plan and evaluate native Mac actions before signed-host execution.",
            customAppAccess: .approvalRequired,
            riskTier: .high,
            interruptiveApproval: true,
            touchesSecrets: false,
            touchesNativeHost: true,
            touchesPhysicalWorld: false,
            destructive: true
        ),
        AppCapabilityDescriptor(
            id: "iot.device.action.invoke",
            title: "IoT device action",
            summary: "Invoke physical device actions through policy, plan, and audit.",
            customAppAccess: .approvalRequired,
            riskTier: .high,
            interruptiveApproval: true,
            touchesSecrets: false,
            touchesNativeHost: false,
            touchesPhysicalWorld: true,
            destructive: false
        )
    ]

    static func descriptor(id: String) -> AppCapabilityDescriptor? {
        descriptors.first { $0.id == id }
    }

    static func riskMap(for record: AppRecord) -> AppCapabilityRiskMap {
        let requested = record.effectiveDeclaredCapabilities
        let selected = requested.isEmpty ? descriptors : requested.compactMap(descriptor)
        let known = Set(selected.map(\.id))
        let unknown = requested.filter { !known.contains($0) }.sorted()

        return AppCapabilityRiskMap(
            authorityModel: "localWideReadsHighRiskApproval",
            capabilityIds: selected.map(\.id),
            ordinaryAccess: selected.filter { $0.customAppAccess == .localWide }.map(\.id),
            approvalRequired: selected.filter { $0.customAppAccess == .approvalRequired }.map(\.id),
            blocked: selected.filter { $0.customAppAccess == .blocked }.map(\.id),
            highRisk: selected.filter { $0.interruptiveApproval || $0.riskTier == .high || $0.riskTier == .critical }.map(\.id),
            unknown: unknown,
            requiresActivationReview: record.effectiveOriginClass == .imported || record.effectiveOriginClass == .marketplace || !unknown.isEmpty,
            source: source
        )
    }

    static func protectedRouteViolations(for record: AppRecord) -> [String] {
        guard let target = record.routeTarget?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !target.isEmpty else {
            return []
        }
        let protectedRoutes: Set<String> = ["secrets", "native-permissions", "permissions", "rescue", "approvals", "chat", "chat-core"]
        guard protectedRoutes.contains(target) else { return [] }
        switch record.effectiveProtectedRoutePolicy {
        case .blocked:
            return ["Route \(target) is protected and cannot be replaced."]
        case .variantOnly:
            return record.variant?.originalRoute == target ? [] : ["Protected route \(target) variants must preserve originalRoute."]
        case .none:
            return ["Protected route \(target) requires blocked or variantOnly policy."]
        }
    }

    static func activationGate(for record: AppRecord) -> AppActivationGate {
        let riskMap = riskMap(for: record)
        if !riskMap.unknown.isEmpty {
            return .blockedUnknownCapabilities(riskMap.unknown)
        }
        if riskMap.requiresActivationReview && record.activationReview == nil {
            return .reviewRequired(riskMap)
        }
        return .allowed
    }
}

extension AppCapabilityDescriptor {
    var bridgeValue: [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "title": title,
            "summary": summary,
            "customAppAccess": customAppAccess.rawValue,
            "riskTier": riskTier.rawValue,
            "interruptiveApproval": interruptiveApproval,
            "touchesSecrets": touchesSecrets,
            "touchesNativeHost": touchesNativeHost,
            "touchesPhysicalWorld": touchesPhysicalWorld,
            "destructive": destructive
        ]
        if let redactionPolicyRef {
            value["redactionPolicyRef"] = redactionPolicyRef
        }
        return value
    }
}

extension AppCapabilityRiskMap {
    var bridgeValue: [String: Any] {
        [
            "authorityModel": authorityModel,
            "capabilityIds": capabilityIds,
            "ordinaryAccess": ordinaryAccess,
            "approvalRequired": approvalRequired,
            "blocked": blocked,
            "highRisk": highRisk,
            "unknown": unknown,
            "requiresActivationReview": requiresActivationReview,
            "source": source
        ]
    }
}
