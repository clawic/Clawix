import ClawHostKit
import Foundation

struct AppHighRiskActionDispatchRequest {
    let app: AppRecord
    let descriptor: AppCapabilityDescriptor
    let tool: String
    let arguments: [String: Any]
}

enum AppHighRiskActionDispatchResult {
    case dispatched(Any)
    case unavailable(String)
    case failed(String)

    var receiptOutcome: AppHighRiskActionReceipt.Outcome {
        switch self {
        case .dispatched:
            return .dispatched
        case .unavailable:
            return .approvalRecordedDispatchUnavailable
        case .failed:
            return .dispatchFailed
        }
    }

    var rejectionMessage: String? {
        switch self {
        case .dispatched:
            return nil
        case let .unavailable(message), let .failed(message):
            return message
        }
    }

    var resolvedValue: Any {
        switch self {
        case let .dispatched(value):
            return value
        case .unavailable, .failed:
            return NSNull()
        }
    }
}

@MainActor
protocol AppHighRiskActionDispatcher {
    func dispatch(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult
}

@MainActor
struct AppUnavailableHighRiskActionDispatcher: AppHighRiskActionDispatcher {
    func dispatch(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult {
        .unavailable("Agent tool dispatch is not available in this build")
    }
}

@MainActor
struct AppFrameworkHighRiskActionDispatcher: AppHighRiskActionDispatcher {
    let iotManager: IoTManager?

    init(iotManager: IoTManager? = nil) {
        self.iotManager = iotManager
    }

    func dispatch(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult {
        guard FeatureFlags.shared.isVisible(.apps) else {
            return .unavailable("Apps dispatch is experimental and disabled in stable mode.")
        }
        switch request.descriptor.id {
        case "jobs.start":
            return await dispatchJobsStart(request)
        case "jobs.cancel":
            return await dispatchJobsCancel(request)
        case "mac.action.plan":
            return dispatchMacActionPlan(request)
        case "iot.device.action.invoke":
            return await dispatchIoTAction(request)
        case "actions.invoke":
            return .unavailable("Generic framework action dispatch is unavailable until an allowlisted safe runner is registered")
        case "secrets.broker":
            return .unavailable("Secrets broker dispatch is unavailable until a safe non-plaintext lease/ref runner is registered")
        default:
            return .unavailable("No safe framework dispatcher is registered for capability: \(request.descriptor.id)")
        }
    }

    private func dispatchJobsStart(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult {
        do {
            let lease = await ClawJSServiceManager.shared.acquire(
                services: [.runtime],
                reason: .capability("runtime jobs"),
                consumer: "capability.runtime.jobs.start"
            )
            defer { Task { await ClawJSServiceManager.shared.release(lease) } }
            let kind = ((request.arguments["kind"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !kind.isEmpty else {
                return .failed("jobs.start requires a kind.")
            }
            let input = (request.arguments["input"] as? [String: Any]) ?? [:]
            let reason = (request.arguments["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .runtime)
            let value = try await ClawJSRuntimeClient(bearerToken: token).startJob(
                kind: kind,
                input: input,
                reason: reason?.isEmpty == true ? nil : reason
            )
            return .dispatched(value)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func dispatchJobsCancel(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult {
        do {
            let lease = await ClawJSServiceManager.shared.acquire(
                services: [.runtime],
                reason: .capability("runtime jobs"),
                consumer: "capability.runtime.jobs.cancel"
            )
            defer { Task { await ClawJSServiceManager.shared.release(lease) } }
            let id = ((request.arguments["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                return .failed("jobs.cancel requires an id.")
            }
            let reason = (request.arguments["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .runtime)
            let value = try await ClawJSRuntimeClient(bearerToken: token).cancelJob(
                id: id,
                reason: reason?.isEmpty == true ? nil : reason
            )
            return .dispatched(value)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func dispatchMacActionPlan(_ request: AppHighRiskActionDispatchRequest) -> AppHighRiskActionDispatchResult {
        do {
            let action = try AppCustomMacActionPlanRequest(app: request.app, arguments: request.arguments, fallbackTool: request.tool)
            let data = try JSONEncoder().encode(action.request)
            let planBytes = try NativeMacActionWire.planJSON(for: data)
            let plan = try JSONDecoder().decode(NativeMacActionWirePlan.self, from: planBytes)
            return .dispatched(Self.bridgeValue(plan))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func dispatchIoTAction(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult {
        guard let iotManager else {
            return .unavailable("IoT dispatcher is unavailable")
        }
        do {
            let action = try AppCustomIoTActionRequest(arguments: request.arguments, fallbackTool: request.tool)
            let result = try await iotManager.runAction(action.request)
            return .dispatched(Self.bridgeValue(result))
        } catch is CancellationError {
            return .failed("IoT action cancelled")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func bridgeValue<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return object
    }
}

struct AppCustomIoTActionRequest {
    enum Error: LocalizedError {
        case missingAction

        var errorDescription: String? {
            switch self {
            case .missingAction:
                return "IoT action requires an action name."
            }
        }
    }

    let request: IoTActionRequest

    init(arguments: [String: Any], fallbackTool: String) throws {
        let action = Self.string(arguments["action"])
            ?? Self.actionFromTool(fallbackTool)
        guard let action, !action.isEmpty else {
            throw Error.missingAction
        }
        request = IoTActionRequest(
            homeId: Self.string(arguments["homeId"]),
            selector: Self.string(arguments["selector"]),
            area: Self.string(arguments["area"]),
            family: Self.string(arguments["family"]),
            capability: Self.string(arguments["capability"]),
            action: action,
            value: arguments["value"].map(ToolJSONValue.init),
            targets: Self.stringArray(arguments["targets"])
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        guard let array = value as? [Any] else { return nil }
        let values = array.compactMap { string($0) }
        return values.isEmpty ? nil : values
    }

    private static func actionFromTool(_ tool: String) -> String? {
        let normalized = tool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("iot.") else { return nil }
        return normalized.split(separator: ".").last.map(String.init)
    }
}

struct AppCustomMacActionPlanRequest {
    enum Error: LocalizedError {
        case missingCapability
        case unsupportedCapability(String)
        case executeNotAvailable

        var errorDescription: String? {
            switch self {
            case .missingCapability:
                return "Mac action plan requires a Mac Control capability id."
            case .unsupportedCapability(let capabilityId):
                return "Unsupported Mac Control capability for custom app plan: \(capabilityId)."
            case .executeNotAvailable:
                return "Custom app Mac Control execution is not available; request a plan instead."
            }
        }
    }

    let request: NativeMacActionWireRequest

    init(app: AppRecord, arguments: [String: Any], fallbackTool: String) throws {
        if Self.bool(arguments["execute"]) == true || Self.string(arguments["operation"]) == "execute" {
            throw Error.executeNotAvailable
        }

        guard let capabilityId = Self.capabilityId(arguments: arguments, fallbackTool: fallbackTool) else {
            throw Error.missingCapability
        }
        guard MacControlSettingsCapability.capability(id: capabilityId) != nil else {
            throw Error.unsupportedCapability(capabilityId)
        }

        request = NativeMacActionWireRequest(
            requestId: "macreq_custom_\(UUID().uuidString.lowercased())",
            capabilityId: capabilityId,
            actor: NativeMacActionWireActor(
                kind: "custom_app",
                id: app.slug,
                role: "workspace_app"
            ),
            host: NativeMacActionWireHost(
                hostId: ProcessInfo.processInfo.hostName,
                bundleId: Bundle.main.bundleIdentifier ?? "com.example.clawix",
                signingIdentity: nil,
                teamId: nil,
                appVariant: Self.appVariant,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ),
            arguments: Self.wireStringArguments(from: arguments).mapValues { .string($0) },
            dryRun: true,
            reason: "Custom app \(app.name): Mac Control plan",
            approved: false
        )
    }

    private static func capabilityId(arguments: [String: Any], fallbackTool: String) -> String? {
        if let explicit = string(arguments["capabilityId"]) ?? string(arguments["capability"]) {
            return explicit
        }
        let tool = fallbackTool.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacControlSettingsCapability.capability(id: tool) != nil {
            return tool
        }
        return nil
    }

    private static func wireStringArguments(from arguments: [String: Any]) -> [String: String] {
        let nested = (arguments["arguments"] as? [String: Any]) ?? [:]
        let source = nested.isEmpty ? arguments : nested
        var result: [String: String] = [:]
        for (key, value) in source {
            guard !reservedKeys.contains(key), let string = string(value) else { continue }
            result[key] = string
        }
        return result
    }

    private static let reservedKeys: Set<String> = [
        "approved",
        "capability",
        "capabilityId",
        "dryRun",
        "execute",
        "operation",
        "reason"
    ]

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let int = value as? Int {
            return String(int)
        }
        if let double = value as? Double {
            return double.rounded() == double ? String(Int(double)) : String(double)
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let string = string(value)?.lowercased() {
            if ["true", "yes", "1"].contains(string) { return true }
            if ["false", "no", "0"].contains(string) { return false }
        }
        return nil
    }

    private static var appVariant: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
