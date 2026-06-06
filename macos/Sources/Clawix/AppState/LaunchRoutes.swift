import Foundation

private enum AppStateLaunchRouteKeys {
    static let kind = "LaunchRouteKind"
    static let chatUuid = "LaunchRouteChatUuid"
    static let threadId = "LaunchRouteThreadId"
}

@MainActor
extension AppState {
    func applyLaunchRoute() {
        let arguments = ProcessInfo.processInfo.arguments
        let argumentRoute = arguments.indices
            .first(where: { arguments[$0] == "--route" && arguments.indices.contains($0 + 1) })
            .map { arguments[$0 + 1] }
        let env = ProcessInfo.processInfo.environment
        let route = argumentRoute ?? env["CLAWIX_ROUTE"] ?? ""
        switch route {
        case "search":
            currentRoute = .search
            searchQuery = "authentication"
            performSearch(searchQuery)
        case "plugins":
            currentRoute = .plugins
        case "automations":
            currentRoute = .automations
        case "project":
            currentRoute = .project
        case "settings":
            currentRoute = .settings
        case "rescue":
            currentRoute = .rescue
        case "chat":
            chats = [sampleChat]
            currentRoute = .chat(sampleChat.id)
        case "chat-browser":
            chats = [browserSampleChat, sampleChat]
            currentRoute = .chat(browserSampleChat.id)
        case "chat-computer-use":
            chats = [computerUseSampleChat, sampleChat]
            currentRoute = .chat(computerUseSampleChat.id)
        case "browser":
            currentRoute = .home
            openBrowser()
        default:
            if Self.isRunningUnderXCTest || !restorePersistedLaunchRoute() {
                currentRoute = .home
            }
        }
        if currentRoute == .secretsHome, !FeatureFlags.shared.isVisible(.secrets) {
            currentRoute = .home
        }
    }

    private func restorePersistedLaunchRoute() -> Bool {
        let defaults = Self.sidebarDefaults
        let kind = defaults.string(forKey: AppStateLaunchRouteKeys.kind)
        if kind == "rescue" {
            currentRoute = .rescue
            return true
        }
        guard kind == "chat" else {
            return false
        }

        let tokens = [
            defaults.string(forKey: AppStateLaunchRouteKeys.threadId),
            defaults.string(forKey: AppStateLaunchRouteKeys.chatUuid)
        ]
        for token in tokens.compactMap({ $0 }) {
            if openSessionDeepLink(token) {
                return true
            }
        }
        return false
    }

    func persistLaunchRoute() {
        let defaults = Self.sidebarDefaults
        switch currentRoute {
        case .chat(let id):
            guard let chat = chat(byId: id) else { return }
            defaults.set("chat", forKey: AppStateLaunchRouteKeys.kind)
            defaults.set(chat.id.uuidString, forKey: AppStateLaunchRouteKeys.chatUuid)
            if let threadId = chat.clawixThreadId {
                defaults.set(threadId, forKey: AppStateLaunchRouteKeys.threadId)
            } else {
                defaults.removeObject(forKey: AppStateLaunchRouteKeys.threadId)
            }
        case .home:
            defaults.set("home", forKey: AppStateLaunchRouteKeys.kind)
            defaults.removeObject(forKey: AppStateLaunchRouteKeys.chatUuid)
            defaults.removeObject(forKey: AppStateLaunchRouteKeys.threadId)
        case .rescue:
            defaults.set("rescue", forKey: AppStateLaunchRouteKeys.kind)
            defaults.removeObject(forKey: AppStateLaunchRouteKeys.chatUuid)
            defaults.removeObject(forKey: AppStateLaunchRouteKeys.threadId)
        default:
            break
        }
    }
}
