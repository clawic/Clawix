import Foundation

struct AppCapabilityDescriptor: Codable, Equatable, Hashable {
    var id: String
    var title: String
    var summary: String
    var inputSchemaRef: String? = nil
    var outputSchemaRef: String? = nil
    var eventSchemaRefs: AppCapabilityEventSchemaRefs? = nil
    var customAppAccess: AppCapabilityAccess
    var redactionPolicyRef: String? = nil
    var riskTier: AppCapabilityRiskTier
    var interruptiveApproval: Bool
    var touchesSecrets: Bool
    var touchesNativeHost: Bool
    var touchesPhysicalWorld: Bool
    var destructive: Bool
}

struct AppCapabilityEventSchemaRefs: Codable, Equatable, Hashable {
    var cancel: String?
    var progress: String?
    var partial: String?
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
    static let searchQuerySchemaRef = "claw.search.query.v1"
    static let searchResultsSchemaRef = "claw.search.results.v1"
    static let dbQuerySchemaRef = "claw.db.query.v1"
    static let dbRecordsSchemaRef = "claw.db.records.v1"
    static let resourcesListSchemaRef = "claw.resources.list.v1"
    static let resourcesListResultSchemaRef = "claw.resources.listResult.v1"
    static let resourcesReadSchemaRef = "claw.resources.read.v1"
    static let resourcesPayloadSchemaRef = "claw.resources.payload.v1"
    static let systemTelemetrySnapshotRequestSchemaRef = "claw.system.telemetry.snapshot.request.v1"
    static let systemTelemetrySnapshotSchemaRef = "claw.system.telemetry.snapshot.v1"
    static let systemTelemetryHistoryRequestSchemaRef = "claw.system.telemetry.history.request.v1"
    static let systemTelemetryHistorySchemaRef = "claw.system.telemetry.history.v1"
    static let jobsListSchemaRef = "claw.jobs.list.v1"
    static let jobsListResultSchemaRef = "claw.jobs.listResult.v1"
    static let actionsInvokeSchemaRef = "claw.actions.invoke.v1"
    static let actionsReceiptSchemaRef = "claw.actions.receipt.v1"
    static let secretsBrokerSchemaRef = "claw.secrets.broker.v1"
    static let secretsReceiptSchemaRef = "claw.secrets.receipt.v1"
    static let macActionRequestSchemaRef = "claw.mac.actionRequest.v1"
    static let macActionPlanSchemaRef = "claw.mac.actionPlan.v1"
    static let iotActionSchemaRef = "claw.iot.action.v1"
    static let iotActionResultSchemaRef = "claw.iot.actionResult.v1"
    static let requestCancelSchemaRef = "claw.customApp.request.cancel.v1"
    static let requestProgressSchemaRef = "claw.customApp.request.progress.v1"
    static let requestPartialSchemaRef = "claw.customApp.request.partial.v1"

    static let readEventSchemaRefs = AppCapabilityEventSchemaRefs(
        cancel: requestCancelSchemaRef,
        progress: requestProgressSchemaRef,
        partial: requestPartialSchemaRef
    )

    static let descriptors: [AppCapabilityDescriptor] = [
        AppCapabilityDescriptor(
            id: "search.query",
            title: "Search query",
            summary: "Federated framework search through the SDK/bridge, not direct indexes.",
            inputSchemaRef: searchQuerySchemaRef,
            outputSchemaRef: searchResultsSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
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
            inputSchemaRef: dbQuerySchemaRef,
            outputSchemaRef: dbRecordsSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
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
            id: "resources.list",
            title: "Resource list",
            summary: "List registered resources through resource contracts.",
            inputSchemaRef: resourcesListSchemaRef,
            outputSchemaRef: resourcesListResultSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
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
            inputSchemaRef: resourcesReadSchemaRef,
            outputSchemaRef: resourcesPayloadSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
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
            id: "system.telemetry.snapshot",
            title: "System telemetry snapshot",
            summary: "Read the safe local system telemetry snapshot through the host bridge.",
            inputSchemaRef: systemTelemetrySnapshotRequestSchemaRef,
            outputSchemaRef: systemTelemetrySnapshotSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
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
            id: "system.telemetry.history",
            title: "System telemetry history",
            summary: "Read retained Monitor-backed telemetry history for approved local metrics.",
            inputSchemaRef: systemTelemetryHistoryRequestSchemaRef,
            outputSchemaRef: systemTelemetryHistorySchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
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
            id: "jobs.list",
            title: "Jobs list",
            summary: "Read recent framework jobs and run records through the host bridge without starting work.",
            inputSchemaRef: jobsListSchemaRef,
            outputSchemaRef: jobsListResultSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
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
            inputSchemaRef: actionsInvokeSchemaRef,
            outputSchemaRef: actionsReceiptSchemaRef,
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
            inputSchemaRef: secretsBrokerSchemaRef,
            outputSchemaRef: secretsReceiptSchemaRef,
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
            inputSchemaRef: macActionRequestSchemaRef,
            outputSchemaRef: macActionPlanSchemaRef,
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
            inputSchemaRef: iotActionSchemaRef,
            outputSchemaRef: iotActionResultSchemaRef,
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

    static var schemaRefs: [String] {
        [
            dbQuerySchemaRef,
            dbRecordsSchemaRef,
            actionsInvokeSchemaRef,
            actionsReceiptSchemaRef,
            iotActionResultSchemaRef,
            iotActionSchemaRef,
            jobsListResultSchemaRef,
            jobsListSchemaRef,
            macActionPlanSchemaRef,
            macActionRequestSchemaRef,
            requestCancelSchemaRef,
            requestPartialSchemaRef,
            requestProgressSchemaRef,
            resourcesListResultSchemaRef,
            resourcesListSchemaRef,
            resourcesPayloadSchemaRef,
            resourcesReadSchemaRef,
            secretsBrokerSchemaRef,
            secretsReceiptSchemaRef,
            searchQuerySchemaRef,
            searchResultsSchemaRef,
            systemTelemetryHistoryRequestSchemaRef,
            systemTelemetryHistorySchemaRef,
            systemTelemetrySnapshotRequestSchemaRef,
            systemTelemetrySnapshotSchemaRef
        ].sorted()
    }

    static var referencedSchemaRefs: [String] {
        Array(Set(descriptors.flatMap { descriptor in
            [
                descriptor.inputSchemaRef,
                descriptor.outputSchemaRef,
                descriptor.eventSchemaRefs?.cancel,
                descriptor.eventSchemaRefs?.progress,
                descriptor.eventSchemaRefs?.partial
            ].compactMap { $0 }
        })).sorted()
    }

    static var missingSchemaRefs: [String] {
        let known = Set(schemaRefs)
        return referencedSchemaRefs.filter { !known.contains($0) }.sorted()
    }

    static var executionBoundaryBridgeValue: [String: Any] {
        [
            "kind": "metadata_only_contract_catalog",
            "executesCapabilityCalls": false,
            "richUiExecutionPath": "sdk_host_bridge",
            "localExecutableSurface": "host_bridge",
            "hostBridgeImplementation": "window.clawix",
            "nonExecutableSurfaces": [
                "cli.inspect",
                "service_api.contracts",
                "mcp.custom_app_sdk",
                "relay.remote.custom_app_sdk"
            ],
            "dbSearchExecution": "host_bridge_only"
        ]
    }

    static func contractsBridgeValue(for record: AppRecord) -> [String: Any] {
        [
            "schemaVersion": 1,
            "source": source,
            "hostBridgeRole": "sdk_host_bridge_contract_resource",
            "richUiRuntime": "sdk_host_bridge_not_cli_process",
            "executionBoundary": executionBoundaryBridgeValue,
            "schemaRefs": schemaRefs,
            "referencedSchemaRefs": referencedSchemaRefs,
            "missingSchemaRefs": missingSchemaRefs,
            "riskMap": riskMap(for: record).bridgeValue,
            "capabilities": descriptors.map(\.bridgeValue)
        ]
    }

    static func dispatchBridgeValue(for descriptor: AppCapabilityDescriptor) -> [String: Any] {
        switch descriptor.id {
        case "search.query", "db.query", "resources.list", "resources.read", "system.telemetry.snapshot", "system.telemetry.history", "jobs.list":
            return [
                "status": "available",
                "mode": "localWideRead",
                "approvalRequired": false,
                "runner": "clawix.hostBridge",
                "reason": "Local-wide read through the host bridge; no CLI process required."
            ]
        case "mac.action.plan":
            return [
                "status": "available",
                "mode": "approvalRequiredPlanOnly",
                "approvalRequired": true,
                "runner": "NativeMacActionWire.planJSON",
                "reason": "Returns a dry-run Mac Control plan after approval; native execution remains unavailable."
            ]
        case "iot.device.action.invoke":
            return [
                "status": "available",
                "mode": "approvalRequiredDispatch",
                "approvalRequired": true,
                "runner": "IoTManager.runAction",
                "externalValidation": "EXTERNAL PENDING",
                "reason": "Dispatches through IoTManager after approval; live physical/provider validation requires explicit authorization."
            ]
        case "actions.invoke":
            return [
                "status": "unavailable",
                "mode": "approvalRequiredNoRunner",
                "approvalRequired": true,
                "runner": "pending",
                "reason": "Generic framework action dispatch still needs a safe runner."
            ]
        case "secrets.broker":
            return [
                "status": "unavailable",
                "mode": "approvalRequiredNoPlaintextBroker",
                "approvalRequired": true,
                "runner": "pending",
                "reason": "Secrets broker dispatch still needs a safe lease/ref runner and must not expose plaintext."
            ]
        default:
            return [
                "status": "unavailable",
                "mode": "unknown",
                "approvalRequired": descriptor.interruptiveApproval,
                "runner": "pending",
                "reason": "No custom-app dispatcher is registered for this capability."
            ]
        }
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
            "destructive": destructive,
            "dispatch": AppCapabilityCatalog.dispatchBridgeValue(for: self)
        ]
        if let redactionPolicyRef {
            value["redactionPolicyRef"] = redactionPolicyRef
        }
        if let inputSchemaRef {
            value["inputSchemaRef"] = inputSchemaRef
        }
        if let outputSchemaRef {
            value["outputSchemaRef"] = outputSchemaRef
        }
        if let eventSchemaRefs {
            value["eventSchemaRefs"] = eventSchemaRefs.bridgeValue
        }
        return value
    }
}

extension AppCapabilityEventSchemaRefs {
    var bridgeValue: [String: Any] {
        var value: [String: Any] = [:]
        if let cancel { value["cancel"] = cancel }
        if let progress { value["progress"] = progress }
        if let partial { value["partial"] = partial }
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
