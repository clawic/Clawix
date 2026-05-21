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
}
