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
        switch request.descriptor.id {
        case "iot.device.action.invoke":
            await dispatchIoTAction(request)
        default:
            .unavailable("No safe framework dispatcher is registered for capability: \(request.descriptor.id)")
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
