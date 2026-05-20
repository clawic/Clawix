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
