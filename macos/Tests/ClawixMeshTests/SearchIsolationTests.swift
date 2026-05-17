import XCTest
@testable import Clawix

@MainActor
final class SearchIsolationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
    }

    override func tearDown() {
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        super.tearDown()
    }

    func test_searchResultsRemainConversationOnly() {
        let state = AppState()
        let normalChatId = UUID()
        let archivedChatId = UUID()
        let quickAskId = UUID()
        let sideChatId = UUID()
        let projectId = UUID()

        state.projects = [
            Project(id: projectId, name: "Needle Project", path: "/tmp/needle-project")
        ]
        state.plugins = [
            Plugin(id: UUID(), name: "Needle Plugin", description: "Not a conversation", isEnabled: true, iconName: "puzzlepiece")
        ]
        state.chats = [
            Chat(
                id: normalChatId,
                title: "Needle Planning",
                messages: [
                    ChatMessage(role: .user, content: "Find the framework needle here.")
                ],
                createdAt: Date(),
                projectId: projectId
            ),
            Chat(
                id: quickAskId,
                title: "Needle QuickAsk",
                messages: [],
                createdAt: Date(),
                isQuickAskTemporary: true
            ),
            Chat(
                id: sideChatId,
                title: "Needle Side Chat",
                messages: [],
                createdAt: Date(),
                isSideChat: true
            )
        ]
        state.archivedChats = [
            Chat(
                id: archivedChatId,
                title: "Archived Needle",
                messages: [],
                createdAt: Date(),
                isArchived: true
            )
        ]

        state.performSearch("needle")

        XCTAssertFalse(state.searchResults.isEmpty)
        XCTAssertTrue(state.searchResults.contains { $0.contains("Needle Planning") })
        XCTAssertTrue(state.searchResults.contains { $0.contains("Archived Needle") })
        XCTAssertFalse(state.searchResults.contains { $0.contains("Needle QuickAsk") })
        XCTAssertFalse(state.searchResults.contains { $0.contains("Needle Side Chat") })
        XCTAssertFalse(state.searchResults.contains { $0.contains("Needle Project") })
        XCTAssertFalse(state.searchResults.contains { $0.contains("Needle Plugin") })
        XCTAssertTrue(state.searchResultRoutes.values.allSatisfy { route in
            route == .chat(normalChatId) || route == .chat(archivedChatId)
        })
    }
}
