import Foundation

struct AppCapabilityDescriptor: Codable, Equatable, Hashable {
    var id: String
    var title: String
    var summary: String
    var inputSchemaRef: String? = nil
    var outputSchemaRef: String? = nil
    var eventSchemaRefs: AppCapabilityEventSchemaRefs? = nil
    var customAppAccess: AppCapabilityAccess
    var maturity: FeatureMaturity = .stable
    var activationPolicy: FeatureActivationPolicy = .enabled
    var redactionPolicyRef: String? = nil
    var riskTier: AppCapabilityRiskTier
    var interruptiveApproval: Bool
    var touchesSecrets: Bool
    var touchesNativeHost: Bool
    var touchesPhysicalWorld: Bool
    var destructive: Bool
}

struct AppCapabilitySurfaceBinding: Codable, Equatable, Hashable {
    var surface: String
    var status: String
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
    case blockedCapabilities([String])
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
    static let jobsGetSchemaRef = "claw.jobs.get.v1"
    static let jobsDetailSchemaRef = "claw.jobs.detail.v1"
    static let jobsEventsSchemaRef = "claw.jobs.events.v1"
    static let jobsEventsResultSchemaRef = "claw.jobs.eventsResult.v1"
    static let jobsStreamSchemaRef = "claw.jobs.stream.v1"
    static let jobsStreamResultSchemaRef = "claw.jobs.streamResult.v1"
    static let jobsStartSchemaRef = "claw.jobs.start.v1"
    static let jobsStartResultSchemaRef = "claw.jobs.startResult.v1"
    static let jobsCancelSchemaRef = "claw.jobs.cancel.v1"
    static let jobsCancelResultSchemaRef = "claw.jobs.cancelResult.v1"
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
    static let protectedRouteTargets: Set<String> = [
        "approvals",
        "chat",
        "chat-core",
        "native-permissions",
        "permissions",
        "rescue",
        "secrets"
    ]

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
            maturity: .experimental,
            activationPolicy: .optIn,
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
            maturity: .experimental,
            activationPolicy: .optIn,
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
            id: "jobs.get",
            title: "Jobs detail",
            summary: "Read one framework job/run detail with redacted entity summaries through the host bridge.",
            inputSchemaRef: jobsGetSchemaRef,
            outputSchemaRef: jobsDetailSchemaRef,
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
            id: "jobs.events",
            title: "Jobs events",
            summary: "Read a redacted job/run event timeline derived from framework run records through the host bridge.",
            inputSchemaRef: jobsEventsSchemaRef,
            outputSchemaRef: jobsEventsResultSchemaRef,
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
            id: "jobs.stream",
            title: "Jobs stream",
            summary: "Read runtime job events from the host bridge stream contract without starting or cancelling work.",
            inputSchemaRef: jobsStreamSchemaRef,
            outputSchemaRef: jobsStreamResultSchemaRef,
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
            id: "jobs.start",
            title: "Jobs start",
            summary: "Start an allowlisted runtime job through native approval, host audit, and the runtime jobs API.",
            inputSchemaRef: jobsStartSchemaRef,
            outputSchemaRef: jobsStartResultSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
            customAppAccess: .approvalRequired,
            redactionPolicyRef: AppBridgeRedactionPolicy.policyId,
            riskTier: .high,
            interruptiveApproval: true,
            touchesSecrets: false,
            touchesNativeHost: false,
            touchesPhysicalWorld: false,
            destructive: false
        ),
        AppCapabilityDescriptor(
            id: "jobs.cancel",
            title: "Jobs cancel",
            summary: "Cancel a runtime job through native approval, host audit, and the runtime jobs API.",
            inputSchemaRef: jobsCancelSchemaRef,
            outputSchemaRef: jobsCancelResultSchemaRef,
            eventSchemaRefs: readEventSchemaRefs,
            customAppAccess: .approvalRequired,
            redactionPolicyRef: AppBridgeRedactionPolicy.policyId,
            riskTier: .high,
            interruptiveApproval: true,
            touchesSecrets: false,
            touchesNativeHost: false,
            touchesPhysicalWorld: false,
            destructive: true
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

    static func riskMap(for record: AppRecord, descriptors availableDescriptors: [AppCapabilityDescriptor] = descriptors) -> AppCapabilityRiskMap {
        let requested = record.effectiveDeclaredCapabilities
        let descriptorsById = Dictionary(uniqueKeysWithValues: availableDescriptors.map { ($0.id, $0) })
        let knownDescriptorIds = Set(descriptors.map(\.id))
        let selected = requested.isEmpty ? availableDescriptors : requested.compactMap { descriptorsById[$0] }
        let known = Set(selected.map(\.id))
        let unknown = requested.filter { !known.contains($0) && !knownDescriptorIds.contains($0) }.sorted()

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
        guard protectedRouteTargets.contains(target) else { return [] }
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
        let requested = Set(record.effectiveDeclaredCapabilities)
        let requestedBlocked = riskMap.blocked.filter { requested.contains($0) }
        if !requestedBlocked.isEmpty {
            return .blockedCapabilities(requestedBlocked)
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
            jobsDetailSchemaRef,
            jobsEventsResultSchemaRef,
            jobsEventsSchemaRef,
            jobsGetSchemaRef,
            jobsCancelResultSchemaRef,
            jobsCancelSchemaRef,
            jobsListResultSchemaRef,
            jobsListSchemaRef,
            jobsStartResultSchemaRef,
            jobsStartSchemaRef,
            jobsStreamResultSchemaRef,
            jobsStreamSchemaRef,
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

    static var blockedSurfaceBindingsBridgeValue: [[String: String]] {
        surfaceBindingsBridgeValue(statuses: Dictionary(uniqueKeysWithValues: canonicalSurfaceNames.map { ($0, "blocked") }))
    }

    static let canonicalSurfaceNames = ["sdk", "cli", "serviceApi", "mcp", "relay", "hostBridge"]

    static func surfaceBindingsBridgeValue(for descriptor: AppCapabilityDescriptor) -> [[String: String]] {
        var statuses = Dictionary(uniqueKeysWithValues: canonicalSurfaceNames.map { ($0, "available") })

        switch descriptor.id {
        case "jobs.list", "jobs.get", "jobs.events", "jobs.stream", "jobs.start", "jobs.cancel":
            statuses["cli"] = "blocked"
        case "secrets.broker":
            statuses["mcp"] = "blocked"
        default:
            break
        }

        return surfaceBindingsBridgeValue(statuses: statuses, descriptor: descriptor)
    }

    private static func surfaceBindingsBridgeValue(
        statuses: [String: String],
        descriptor: AppCapabilityDescriptor? = nil
    ) -> [[String: String]] {
        canonicalSurfaceNames.map { surface in
            let status = statuses[surface] ?? "blocked"
            var value = ["surface": surface, "status": status]
            if status == "available", let descriptor, let ref = surfaceRef(for: descriptor, surface: surface) {
                value["ref"] = ref
            }
            return value
        }
    }

    private static func surfaceRef(for descriptor: AppCapabilityDescriptor, surface: String) -> String? {
        switch surface {
        case "sdk":
            return sdkSurfaceRef(for: descriptor.id)
        case "cli":
            return cliSurfaceRef(for: descriptor.id)
        case "serviceApi":
            return "service_api.contracts/custom-app-sdk"
        case "mcp":
            return "mcp.custom_app_sdk metadata-only contract projection"
        case "relay":
            return "relay.remote.custom_app_sdk metadata-only contract projection"
        case "hostBridge":
            return "window.clawix"
        default:
            return nil
        }
    }

    private static func sdkSurfaceRef(for capabilityID: String) -> String {
        switch capabilityID {
        case "search.query":
            return "window.clawix.search.query"
        case "db.query":
            return "window.clawix.db.query"
        case "resources.list":
            return "window.clawix.resources.list"
        case "resources.read":
            return "window.clawix.resources.read"
        case "system.telemetry.snapshot":
            return "window.clawix.system.telemetry.snapshot"
        case "system.telemetry.history":
            return "window.clawix.system.telemetry.history"
        case "jobs.list":
            return "window.clawix.jobs.list"
        case "jobs.get":
            return "window.clawix.jobs.get"
        case "jobs.events":
            return "window.clawix.jobs.events"
        case "jobs.stream":
            return "window.clawix.jobs.stream"
        case "jobs.start":
            return "window.clawix.jobs.start"
        case "jobs.cancel":
            return "window.clawix.jobs.cancel"
        case "actions.invoke":
            return "window.clawix.actions.invoke"
        case "secrets.broker":
            return "window.clawix.secrets.broker"
        case "mac.action.plan":
            return "window.clawix.mac.planAction"
        case "iot.device.action.invoke":
            return "window.clawix.iot.invokeAction"
        default:
            return "window.clawix.capabilities.get"
        }
    }

    private static func cliSurfaceRef(for capabilityID: String) -> String {
        switch capabilityID {
        case "search.query":
            return "claw search query --json"
        case "db.query":
            return "claw db <collection> query --json"
        case "resources.list":
            return "claw resources list --json"
        case "resources.read":
            return "claw resources read --json"
        case "system.telemetry.snapshot":
            return "claw system snapshot --json"
        case "system.telemetry.history":
            return "claw system history <metric-key> --range 1h|24h --json"
        case "actions.invoke":
            return "brokered claw <domain> <action> --json"
        case "secrets.broker":
            return "claw secrets ... --json"
        case "mac.action.plan":
            return "claw wifi/window/permissions/system mac --json"
        case "iot.device.action.invoke":
            return "claw iot ... --json"
        default:
            return "claw inspect custom-app-sdk --json"
        }
    }

    static func contractsBridgeValue(for record: AppRecord, descriptors availableDescriptors: [AppCapabilityDescriptor] = descriptors) -> [String: Any] {
        [
            "schemaVersion": 1,
            "source": source,
            "hostBridgeRole": "sdk_host_bridge_contract_resource",
            "richUiRuntime": "sdk_host_bridge_not_cli_process",
            "executionBoundary": executionBoundaryBridgeValue,
            "schemaRefs": schemaRefs,
            "referencedSchemaRefs": referencedSchemaRefs,
            "missingSchemaRefs": missingSchemaRefs,
            "riskMap": riskMap(for: record, descriptors: availableDescriptors).bridgeValue,
            "capabilities": availableDescriptors.map(\.bridgeValue)
        ]
    }

    static func dispatchBridgeValue(for descriptor: AppCapabilityDescriptor) -> [String: Any] {
        switch descriptor.id {
        case "search.query", "db.query", "resources.list", "resources.read", "system.telemetry.snapshot", "system.telemetry.history", "jobs.list", "jobs.get", "jobs.events", "jobs.stream":
            return [
                "status": "available",
                "mode": "localWideRead",
                "approvalRequired": false,
                "runner": "clawix.hostBridge",
                "reason": "Local-wide read through the host bridge; no CLI process required."
            ]
        case "jobs.start", "jobs.cancel":
            return [
                "status": "available",
                "mode": "approvalRequiredDispatch",
                "approvalRequired": true,
                "runner": "ClawJSRuntimeClient",
                "reason": "Dispatches through the runtime jobs API after native approval and host audit."
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
        case _ where descriptor.customAppAccess == .blocked:
            return [
                "status": "unavailable",
                "mode": "blocked",
                "approvalRequired": false,
                "runner": "pending",
                "reason": "This custom-app capability is an explicit blocked gap until a safe backend contract and host adapter exist."
            ]
        default:
            return [
                "status": "unavailable",
                "mode": "unclassifiedBlocked",
                "approvalRequired": descriptor.interruptiveApproval,
                "runner": "pending",
                "reason": "This custom-app capability has not been classified for custom-app dispatch and is blocked until it has an explicit contract, policy, runner, and tests."
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
            "maturity": maturity.label,
            "activationPolicy": activationPolicy.rawValue,
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
        value["surfaces"] = AppCapabilityCatalog.surfaceBindingsBridgeValue(for: self)
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
