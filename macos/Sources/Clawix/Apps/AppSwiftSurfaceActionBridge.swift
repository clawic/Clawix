import Foundation

enum AppSwiftSurfaceActionBridgeResult: Equatable {
    case reportedRead(String)
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
    let surfaceReporter: SurfaceRouteReporter
    let highRiskActionDispatcher: AppHighRiskActionDispatcher
    let approvalHandler: ApprovalHandler

    init(
        app: AppRecord,
        appsStore: AppsStore,
        surfaceReporter: SurfaceRouteReporter = .noop,
        highRiskActionDispatcher: AppHighRiskActionDispatcher,
        approvalHandler: ApprovalHandler? = nil
    ) {
        self.app = app
        self.appsStore = appsStore
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
            return handleRead(action)
        case .sdkAction:
            return await handleHighRiskAction(action)
        }
    }

    private func handleRead(_ action: AppSwiftSurfaceRenderedAction) -> AppSwiftSurfaceActionBridgeResult {
        guard let descriptor = AppCapabilityCatalog.descriptor(id: action.capabilityId),
              descriptor.customAppAccess == .localWide else {
            let message = "Swift surface read action is not local-wide: \(action.capabilityId)"
            surfaceReporter.error(message)
            return .failed(message)
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
                    arguments: [:]
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
}
