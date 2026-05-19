import Foundation

enum SearchEntrypointShortcutState: String, Codable, Equatable {
    case ready
    case externalPending = "external_pending"
    case blocked
}

struct SearchEntrypointShortcutContract: Codable, Equatable {
    let entrypointId: String
    let bindingId: String
    let queryScope: String
    let routeTarget: String?
    let owner: String
    let state: SearchEntrypointShortcutState
    let reservedChord: String?
    let notes: [String]
}

struct SearchEntrypointShortcutRequest: Equatable {
    let entrypointId: String
    let bindingId: String
    let chord: String
    let routeTarget: String?
}

struct SearchEntrypointShortcutDecision: Equatable {
    let allowed: Bool
    let state: SearchEntrypointShortcutState
    let reason: String
}

enum SearchEntrypointShortcutBroker {
    static let rootEntrypointId = "root-search"
    static let rootBindingId = "search.root.global"
    static let rootRouteTarget = "root-search"
    static let rootDefaultChord = "Option-Command-Space"
    static let chatEntrypointId = "chat-search"
    static let chatBindingId = "search.chat.current"
    static let conversationsRouteTarget = "search"
    static let commandGChord = "Command-G"

    static func contracts() -> [SearchEntrypointShortcutContract] {
        [
            SearchEntrypointShortcutContract(
                entrypointId: rootEntrypointId,
                bindingId: rootBindingId,
                queryScope: "framework",
                routeTarget: rootRouteTarget,
                owner: "signed_host",
                state: .ready,
                reservedChord: nil,
                notes: [
                    "Root Search opens the signed-host root-search panel route target.",
                    "Root Search must not reuse the Command-G conversations-only search route.",
                ]
            ),
            SearchEntrypointShortcutContract(
                entrypointId: chatEntrypointId,
                bindingId: chatBindingId,
                queryScope: "conversations_only",
                routeTarget: conversationsRouteTarget,
                owner: "host_ui",
                state: .ready,
                reservedChord: commandGChord,
                notes: [
                    "Command-G opens Clawix conversation search only.",
                ]
            ),
        ]
    }

    static func contract(for entrypointId: String) -> SearchEntrypointShortcutContract? {
        contracts().first { $0.entrypointId == entrypointId }
    }

    static func validate(_ request: SearchEntrypointShortcutRequest) -> SearchEntrypointShortcutDecision {
        switch (request.entrypointId, request.bindingId) {
        case (chatEntrypointId, chatBindingId):
            return validateChatSearch(request)
        case (rootEntrypointId, rootBindingId):
            return validateRootSearch(request)
        default:
            return SearchEntrypointShortcutDecision(
                allowed: false,
                state: .blocked,
                reason: "Unknown Search entrypoint shortcut binding."
            )
        }
    }

    private static func validateChatSearch(_ request: SearchEntrypointShortcutRequest) -> SearchEntrypointShortcutDecision {
        guard request.chord == commandGChord else {
            return SearchEntrypointShortcutDecision(
                allowed: false,
                state: .blocked,
                reason: "Chat search keeps the reserved Command-G chord."
            )
        }
        guard normalizedRouteTarget(request.routeTarget) == conversationsRouteTarget else {
            return SearchEntrypointShortcutDecision(
                allowed: false,
                state: .blocked,
                reason: "Chat search must target the conversations-only search route."
            )
        }
        return SearchEntrypointShortcutDecision(
            allowed: true,
            state: .ready,
            reason: "Command-G is reserved for conversations-only search."
        )
    }

    private static func validateRootSearch(_ request: SearchEntrypointShortcutRequest) -> SearchEntrypointShortcutDecision {
        if request.chord == commandGChord {
            return SearchEntrypointShortcutDecision(
                allowed: false,
                state: .blocked,
                reason: "Root Search must not reuse Command-G."
            )
        }
        guard let routeTarget = normalizedRouteTarget(request.routeTarget), !routeTarget.isEmpty else {
            return SearchEntrypointShortcutDecision(
                allowed: false,
                state: .externalPending,
                reason: "Root Search needs an explicit host-owned route target before binding a global shortcut."
            )
        }
        if routeTarget == conversationsRouteTarget {
            return SearchEntrypointShortcutDecision(
                allowed: false,
                state: .blocked,
                reason: "Root Search must not target the conversations-only search route."
            )
        }
        return SearchEntrypointShortcutDecision(
            allowed: true,
            state: .ready,
            reason: "Root Search shortcut target is separate from conversations-only search."
        )
    }

    private static func normalizedRouteTarget(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
