import Foundation

enum UserFacingEmptyState: Equatable {
    case chats
    case chatsFiltered
    case projectChats
    case pinnedChatsFiltered
    case tools
    case mcpServers
    case localModels
    case chatTranscriptLoading
    case chatTranscriptEmpty
    case searchPrompt
    case searchNoMatches
    case providers
    case providersQuery(String)
    case providerOAuthAccounts
    case providerAPIKeyAccounts

    var message: String {
        switch self {
        case .chats:
            return L10n.t("No chats")
        case .chatsFiltered:
            return L10n.t("No chats match the filter")
        case .projectChats:
            return L10n.t("No chats in this project yet")
        case .pinnedChatsFiltered:
            return L10n.t("No pinned chats match the filter")
        case .tools:
            return L10n.t("No tools visible")
        case .mcpServers:
            return L10n.t("No MCP servers connected yet.")
        case .localModels:
            return L10n.t("No models yet. Browse the catalog or pull one by name.")
        case .chatTranscriptLoading:
            return L10n.t("Loading conversation...")
        case .chatTranscriptEmpty:
            return L10n.t("No messages loaded")
        case .searchPrompt:
            return L10n.t("Search by chat title")
        case .searchNoMatches:
            return L10n.t("No matches")
        case .providers:
            return L10n.t("No providers match.")
        case .providersQuery(let query):
            return String(format: L10n.t("No providers match \"%@\"."), locale: AppLocale.current, query)
        case .providerOAuthAccounts:
            return L10n.t("No accounts yet. Sign in to start using this provider.")
        case .providerAPIKeyAccounts:
            return L10n.t("No accounts yet. Add an API key to start using this provider.")
        }
    }
}
