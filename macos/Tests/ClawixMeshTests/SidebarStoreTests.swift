import XCTest
@testable import Clawix

@MainActor
final class SidebarStoreTests: XCTestCase {
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

    func testAssistantContentDeltaDoesNotAdvanceSidebarRevision() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: chatId, title: "Streaming", messages: [assistant], createdAt: Date())
        ]
        let store = SidebarStore(appState: state)
        let revision = store.revision

        state.appendAssistantDelta(chatId: chatId, delta: "hello")
        state.flushPendingAssistantTextDeltas(chatId: chatId)

        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.snapshot.chrono.map(\.id), [chatId])
    }

    func testWorkSummaryAndReasoningDeltasDoNotAdvanceSidebarRevision() {
        let state = AppState()
        let chatId = UUID()
        let messageId = UUID()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(
                id: chatId,
                title: "Tools",
                messages: [
                    ChatMessage(id: messageId, role: .assistant, content: "", streamingFinished: false)
                ],
                createdAt: Date()
            )
        ]
        let store = SidebarStore(appState: state)
        let revision = store.revision

        state.beginWorkSummary(chatId: chatId, messageId: messageId, startedAt: Date())
        state.upsertWorkItem(
            chatId: chatId,
            messageId: messageId,
            item: WorkItem(id: "tool-1", kind: .webSearch, status: .completed)
        )
        state.appendReasoningDelta(chatId: chatId, delta: "thinking")

        XCTAssertEqual(store.revision, revision)
    }

    func testLongStreamingRunDoesNotAdvanceSidebarRevisionUntilSummaryChanges() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: chatId, title: "Long stream", messages: [assistant], createdAt: Date())
        ]
        let store = SidebarStore(appState: state)
        let revision = store.revision

        for index in 0..<1_000 {
            state.appendAssistantDelta(chatId: chatId, delta: "token-\(index) ")
            state.flushPendingAssistantTextDeltas(chatId: chatId)
            state.appendReasoningDelta(chatId: chatId, delta: "reason-\(index) ")
            state.flushPendingReasoningDeltas(chatId: chatId)
        }

        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.snapshot.chrono.map(\.id), [chatId])

        state.markChat(chatId: chatId, hasActiveTurn: true)

        XCTAssertGreaterThan(store.revision, revision)
        XCTAssertEqual(store.snapshot.chrono.first?.hasActiveTurn, true)
    }

    func testSummaryStatusChangesAdvanceSidebarRevision() {
        let state = AppState()
        let chatId = UUID()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: chatId, title: "Status", messages: [], createdAt: Date())
        ]
        let store = SidebarStore(appState: state)
        let initialRevision = store.revision

        state.markChat(chatId: chatId, hasActiveTurn: true)

        XCTAssertGreaterThan(store.revision, initialRevision)
        XCTAssertEqual(store.snapshot.chrono.first?.hasActiveTurn, true)
        let activeRevision = store.revision

        state.toggleChatUnread(chatId: chatId)

        XCTAssertGreaterThan(store.revision, activeRevision)
        XCTAssertEqual(store.snapshot.chrono.first?.hasUnreadCompletion, true)
    }

    func testRouteOnlyChangeUpdatesSelectionWithoutRebuildingSnapshot() {
        let state = AppState()
        let firstId = UUID()
        let secondId = UUID()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: firstId, title: "First", messages: [], createdAt: Date(timeIntervalSince1970: 100)),
            Chat(id: secondId, title: "Second", messages: [], createdAt: Date(timeIntervalSince1970: 200))
        ]
        let store = SidebarStore(appState: state)
        let initialRevision = store.revision
        let initialChrono = store.snapshot.chrono.map(\.id)

        state.currentRoute = .chat(secondId)

        XCTAssertEqual(store.selectedRoute, .chat(secondId))
        XCTAssertEqual(store.revision, initialRevision)
        XCTAssertEqual(store.snapshot.chrono.map(\.id), initialChrono)

        state.markChat(chatId: secondId, hasActiveTurn: true)

        XCTAssertGreaterThan(store.revision, initialRevision)
        XCTAssertEqual(store.snapshot.currentRoute, .chat(secondId))
    }

    func testHydrationOnlySummaryChangesDoNotRebuildSidebarSnapshot() {
        let state = AppState()
        let chatId = UUID()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: chatId, title: "Hydration", messages: [], createdAt: Date(timeIntervalSince1970: 100))
        ]
        let store = SidebarStore(appState: state)
        let initialRevision = store.revision
        let initialChrono = store.snapshot.chrono.map(\.id)

        state.chatStore.updateSummary(id: chatId) { summary in
            summary.historyHydrated = true
            summary.lastMessageAt = Date(timeIntervalSince1970: 200)
            summary.lastTurnInterrupted = true
        }

        XCTAssertEqual(store.revision, initialRevision)
        XCTAssertEqual(store.snapshot.chrono.map(\.id), initialChrono)

        state.chatStore.updateSummary(id: chatId) { summary in
            summary.title = "Renamed"
        }

        XCTAssertGreaterThan(store.revision, initialRevision)
        XCTAssertEqual(store.snapshot.chrono.first?.title, "Renamed")
    }

    func testNoOpStructuralSidebarPublicationsDoNotAdvanceRevision() {
        let state = AppState()
        let project = Project(id: UUID(), name: "Alpha", path: "")
        let chatId = UUID()
        state.projects = [project]
        state.manualProjectOrder = [project.id]
        state.pinnedOrder = [chatId]
        state.archivedLoading = false
        state.archivedChats = []
        state.chats = [
            Chat(id: chatId, title: "Pinned", messages: [], createdAt: Date(), isPinned: true)
        ]
        let store = SidebarStore(appState: state)
        let initialRevision = store.revision
        let initialPinned = store.snapshot.pinned.map(\.id)
        let initialProjects = store.snapshot.projectsCustom.map(\.id)

        state.pinnedOrder = [chatId]
        state.projects = [project]
        state.manualProjectOrder = [project.id]
        state.archivedLoading = false

        XCTAssertEqual(store.revision, initialRevision)
        XCTAssertEqual(store.snapshot.pinned.map(\.id), initialPinned)
        XCTAssertEqual(store.snapshot.projectsCustom.map(\.id), initialProjects)

        state.archivedLoading = true

        XCTAssertGreaterThan(store.revision, initialRevision)
        XCTAssertTrue(store.snapshot.archivedLoading)
    }

    func testPinMoveArchiveAndCustomProjectSortUpdateSnapshot() {
        let state = AppState()
        let projectA = Project(id: UUID(), name: "Alpha", path: "")
        let projectB = Project(id: UUID(), name: "Beta", path: "")
        let firstId = UUID()
        let secondId = UUID()
        let old = Date(timeIntervalSince1970: 100)
        let fresh = Date(timeIntervalSince1970: 200)
        state.projects = [projectA, projectB]
        state.manualProjectOrder = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: firstId, title: "First", messages: [], createdAt: old, projectId: projectA.id),
            Chat(id: secondId, title: "Second", messages: [], createdAt: fresh, projectId: nil)
        ]
        let store = SidebarStore(appState: state)

        state.togglePin(chatId: secondId)

        XCTAssertEqual(store.snapshot.pinned.map(\.id), [secondId])
        XCTAssertFalse(store.snapshot.chrono.contains { $0.id == secondId })

        state.moveChatToProject(chatId: secondId, projectId: projectB.id)

        XCTAssertTrue(store.snapshot.pinned.isEmpty)
        XCTAssertEqual(store.snapshot.byProject[projectB.id]?.map(\.id), [secondId])

        state.reorderProject(projectId: projectB.id, beforeProjectId: projectA.id)

        XCTAssertEqual(store.snapshot.projectsCustom.map(\.id), [projectB.id, projectA.id])

        state.archiveChat(chatId: secondId)

        XCTAssertFalse(store.snapshot.chrono.contains { $0.id == secondId })
        XCTAssertEqual(store.snapshot.archived.map(\.id), [secondId])
    }

    func testSideChatsAreExcludedFromSidebarSnapshot() {
        let state = AppState()
        let regularId = UUID()
        let sideId = UUID()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: regularId, title: "Regular", messages: [], createdAt: Date()),
            Chat(id: sideId, title: "Side", messages: [], createdAt: Date(), isSideChat: true)
        ]
        let store = SidebarStore(appState: state)

        XCTAssertEqual(store.snapshot.chrono.map(\.id), [regularId])
        XCTAssertFalse(store.snapshot.chrono.contains { $0.id == sideId })
        XCTAssertFalse(store.snapshot.byProject.values.flatMap { $0 }.contains { $0.id == sideId })
    }
}
