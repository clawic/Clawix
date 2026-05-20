import Foundation

enum AppSwiftSurfaceActionBridgeResult: Equatable {
    case reportedRead(String)
    case executedRead(String, Int)
    case denied(String)
    case dispatched(AppHighRiskActionReceipt.Outcome)
    case failed(String)
}

@MainActor
struct AppSwiftSurfaceActionBridge {
    typealias ApprovalHandler = (
        _ app: AppRecord,
        _ action: AppSwiftSurfaceRenderedAction,
        _ completion: @escaping (AppPermissionPrompt.Decision) -> Void
    ) -> Void

    let app: AppRecord
    let appsStore: AppsStore
    let databaseManager: DatabaseManager?
    let resourceRegistry: AppResourceRegistryStore
    let surfaceReporter: SurfaceRouteReporter
    let highRiskActionDispatcher: AppHighRiskActionDispatcher
    let approvalHandler: ApprovalHandler

    init(
        app: AppRecord,
        appsStore: AppsStore,
        databaseManager: DatabaseManager? = nil,
        resourceRegistry: AppResourceRegistryStore = AppResourceRegistryStore(directory: AppResourceRegistryStore.defaultDirectory()),
        surfaceReporter: SurfaceRouteReporter = .noop,
        highRiskActionDispatcher: AppHighRiskActionDispatcher,
        approvalHandler: ApprovalHandler? = nil
    ) {
        self.app = app
        self.appsStore = appsStore
        self.databaseManager = databaseManager
        self.resourceRegistry = resourceRegistry
        self.surfaceReporter = surfaceReporter
        self.highRiskActionDispatcher = highRiskActionDispatcher
        self.approvalHandler = approvalHandler ?? { app, action, completion in
            AppPermissionPrompt.shared.requestToolApproval(
                appName: app.name,
                tool: action.operation,
                completion: completion
            )
        }
    }

    func handle(_ action: AppSwiftSurfaceRenderedAction) async -> AppSwiftSurfaceActionBridgeResult {
        switch action.invocation {
        case .sdkRead:
            return await handleRead(action)
        case .sdkAction:
            return await handleHighRiskAction(action)
        }
    }

    private func handleRead(_ action: AppSwiftSurfaceRenderedAction) async -> AppSwiftSurfaceActionBridgeResult {
        guard case .allowed = AppCapabilityCatalog.activationGate(for: app) else {
            let message = "App activation review is required before using this capability"
            surfaceReporter.error(message)
            return .failed(message)
        }
        guard let descriptor = AppCapabilityCatalog.descriptor(id: action.capabilityId),
              descriptor.customAppAccess == .localWide else {
            let message = "Swift surface read action is not local-wide: \(action.capabilityId)"
            surfaceReporter.error(message)
            return .failed(message)
        }
        guard canUseDeclaredCapability(descriptor.id) else {
            let message = "App manifest does not declare capability: \(descriptor.id)"
            surfaceReporter.error(message)
            return .failed(message)
        }
        if action.capabilityId == "db.query" {
            return await executeDBQuery(action)
        }
        if action.capabilityId == "search.query" {
            return await executeSearchQuery(action)
        }
        if action.capabilityId == "resources.list" || action.capabilityId == "resources.read" {
            return await executeResourceRead(action)
        }
        let message = "Swift surface read action accepted: \(action.operation)"
        surfaceReporter.partial(message)
        return .reportedRead(action.operation)
    }

    private func handleHighRiskAction(_ action: AppSwiftSurfaceRenderedAction) async -> AppSwiftSurfaceActionBridgeResult {
        guard case .allowed = AppCapabilityCatalog.activationGate(for: app) else {
            let message = "App activation review is required before using this capability"
            surfaceReporter.error(message)
            return .failed(message)
        }
        guard let descriptor = AppCapabilityCatalog.descriptor(id: action.capabilityId) else {
            let message = "Unknown Swift surface action capability: \(action.capabilityId)"
            surfaceReporter.error(message)
            return .failed(message)
        }
        guard descriptor.customAppAccess == .approvalRequired else {
            let message = "Swift surface action capability does not require approval: \(descriptor.id)"
            surfaceReporter.error(message)
            return .failed(message)
        }
        guard app.effectiveDeclaredCapabilities.contains(descriptor.id) else {
            let message = "App manifest does not declare capability: \(descriptor.id)"
            surfaceReporter.error(message)
            return .failed(message)
        }

        let decision = await requestApproval(for: action)
        let auditURL = appsStore.highRiskActionAuditURL(for: app)
        switch decision {
        case .denied:
            appendReceipt(
                descriptor: descriptor,
                action: action,
                decision: .denied,
                outcome: .denied,
                auditURL: auditURL
            )
            surfaceReporter.degraded("User denied Swift surface action: \(action.operation)")
            return .denied(action.operation)
        case .once, .always:
            let result = await highRiskActionDispatcher.dispatch(
                AppHighRiskActionDispatchRequest(
                    app: app,
                    descriptor: descriptor,
                    tool: action.operation,
                    arguments: action.bridgeArguments
                )
            )
            appendReceipt(
                descriptor: descriptor,
                action: action,
                decision: decision == .always ? .approvedAlways : .approvedOnce,
                outcome: result.receiptOutcome,
                auditURL: auditURL
            )
            if let rejection = result.rejectionMessage {
                surfaceReporter.degraded(rejection)
                return .failed(rejection)
            }
            surfaceReporter.partial("Swift surface action dispatched: \(action.operation)")
            return .dispatched(result.receiptOutcome)
        }
    }

    private func executeDBQuery(_ action: AppSwiftSurfaceRenderedAction) async -> AppSwiftSurfaceActionBridgeResult {
        do {
            guard let databaseManager else {
                let message = "Swift surface database bridge is unavailable"
                surfaceReporter.error(message)
                return .failed(message)
            }
            guard case .ready = databaseManager.state else {
                let message = "Swift surface database service is unavailable"
                surfaceReporter.error(message)
                return .failed(message)
            }
            let query = try AppBridgeQueryDSL.dbQuery(from: action.bridgeArguments)
            surfaceReporter.loading("Querying Swift surface database", progress: 0.2)
            let response = try await databaseManager.client.listRecords(
                namespaceId: databaseManager.currentNamespace,
                collection: query.collection,
                filter: query.backendFilterJSON,
                sort: query.sortString,
                limit: query.limit,
                offset: query.effectiveOffset
            )
            let filtered = query.postFilter(response.items)
            surfaceReporter.partial("Swift surface queried \(filtered.count) database records")
            return .executedRead(action.operation, filtered.count)
        } catch is CancellationError {
            surfaceReporter.partial("Swift surface database query cancelled")
            return .failed("Request cancelled")
        } catch {
            surfaceReporter.error(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    private func executeSearchQuery(_ action: AppSwiftSurfaceRenderedAction) async -> AppSwiftSurfaceActionBridgeResult {
        do {
            guard let databaseManager else {
                let message = "Swift surface search bridge is unavailable"
                surfaceReporter.error(message)
                return .failed(message)
            }
            guard case .ready = databaseManager.state else {
                let message = "Swift surface search service is unavailable"
                surfaceReporter.error(message)
                return .failed(message)
            }
            let query = try AppBridgeQueryDSL.searchQuery(from: action.bridgeArguments)
            let collections = query.collections.isEmpty ? databaseManager.collections.map(\.name) : query.collections
            let needle = query.query.lowercased()
            var matched = 0
            var skipped = 0
            surfaceReporter.loading("Searching Swift surface database", progress: 0.1)

            for collection in collections {
                try Task.checkCancellation()
                guard matched < query.limit else { break }
                let response = try await databaseManager.client.listRecords(
                    namespaceId: databaseManager.currentNamespace,
                    collection: collection,
                    filter: nil,
                    sort: "-updatedAt",
                    limit: 100,
                    offset: 0
                )
                for record in response.items {
                    guard matched < query.limit else { break }
                    let isMatch = record.titleString.lowercased().contains(needle)
                        || record.data.values.contains { $0.stringValue?.lowercased().contains(needle) == true }
                    guard isMatch else { continue }
                    if skipped < query.effectiveOffset {
                        skipped += 1
                        continue
                    }
                    matched += 1
                }
            }
            surfaceReporter.partial("Swift surface found \(matched) search results")
            return .executedRead(action.operation, matched)
        } catch is CancellationError {
            surfaceReporter.partial("Swift surface search query cancelled")
            return .failed("Request cancelled")
        } catch {
            surfaceReporter.error(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    private func executeResourceRead(_ action: AppSwiftSurfaceRenderedAction) async -> AppSwiftSurfaceActionBridgeResult {
        do {
            switch action.operation {
            case "resources.list":
                let status = string(action.bridgeArguments["status"])
                let kind = string(action.bridgeArguments["kind"])
                surfaceReporter.loading("Listing Swift surface resources", progress: 0.2)
                let registry = resourceRegistry
                let resources = try await CancellableBackgroundTask.run {
                    try Task.checkCancellation()
                    let resources = try registry.list(status: status, kind: kind)
                    try Task.checkCancellation()
                    return resources
                }
                surfaceReporter.partial("Swift surface listed \(resources.count) resources")
                return .executedRead(action.operation, resources.count)
            case "resources.read":
                guard let id = string(action.bridgeArguments["id"]) else {
                    let message = "Swift surface resources.read requires an id."
                    surfaceReporter.error(message)
                    return .failed(message)
                }
                let maxBytes = int(action.bridgeArguments["maxBytes"]) ?? 64_000
                surfaceReporter.loading("Reading Swift surface resource", progress: 0.2)
                let registry = resourceRegistry
                let result = try await CancellableBackgroundTask.run {
                    try Task.checkCancellation()
                    let result = try registry.read(id, maxBytes: maxBytes)
                    try Task.checkCancellation()
                    return result
                }
                if let error = result.error {
                    surfaceReporter.degraded(error)
                    return .failed(error)
                }
                surfaceReporter.partial("Swift surface read resource: \(id)")
                return .executedRead(action.operation, result.content == nil ? 0 : 1)
            default:
                let message = "Swift surface resource operation is unsupported: \(action.operation)"
                surfaceReporter.error(message)
                return .failed(message)
            }
        } catch is CancellationError {
            surfaceReporter.partial("Swift surface resource read cancelled")
            return .failed("Request cancelled")
        } catch {
            surfaceReporter.error(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    private func requestApproval(for action: AppSwiftSurfaceRenderedAction) async -> AppPermissionPrompt.Decision {
        await withCheckedContinuation { continuation in
            approvalHandler(app, action) { decision in
                continuation.resume(returning: decision)
            }
        }
    }

    private func appendReceipt(
        descriptor: AppCapabilityDescriptor,
        action: AppSwiftSurfaceRenderedAction,
        decision: AppHighRiskActionReceipt.Decision,
        outcome: AppHighRiskActionReceipt.Outcome,
        auditURL: URL
    ) {
        do {
            _ = try AppHighRiskActionAudit.append(
                app: app,
                descriptor: descriptor,
                action: action.operation,
                decision: decision,
                outcome: outcome,
                reason: descriptor.summary,
                auditURL: auditURL
            )
        } catch {
            surfaceReporter.error("Swift surface action audit write failed: \(error.localizedDescription)")
        }
    }

    private func canUseDeclaredCapability(_ capabilityId: String) -> Bool {
        let declared = app.effectiveDeclaredCapabilities
        guard declared.isEmpty else {
            return declared.contains(capabilityId)
        }
        return app.effectiveOriginClass == .localUserAuthored || app.effectiveOriginClass == .system
    }

    private func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = string(value) { return Int(string) }
        return nil
    }
}
