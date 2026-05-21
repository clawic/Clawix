import Foundation

enum AgentRuntimeDemandReason: String {
    case chatOpened = "chat_opened"
    case sendMessage = "send_message"
    case manualRefresh = "manual_refresh"
    case modelPicker = "model_picker"
    case usageSurface = "usage_surface"
    case runtimeSurface = "runtime_surface"

    var triggerDescription: String {
        switch self {
        case .chatOpened:
            return "chat opens"
        case .sendMessage:
            return "message send"
        case .manualRefresh:
            return "manual refresh"
        case .modelPicker:
            return "model picker"
        case .usageSurface:
            return "usage surface"
        case .runtimeSurface:
            return "runtime surface"
        }
    }

    var signpostName: StaticString {
        switch self {
        case .chatOpened:
            return "runtime.start.chat_opened"
        case .sendMessage:
            return "runtime.start.send_message"
        case .manualRefresh:
            return "runtime.start.manual_refresh"
        case .modelPicker:
            return "runtime.start.model_picker"
        case .usageSurface:
            return "runtime.start.usage_surface"
        case .runtimeSurface:
            return "runtime.start.runtime_surface"
        }
    }
}
