import XCTest
import GRDB
@testable import Clawix

@MainActor
final class AppStateLazyDatabaseLaunchTests: XCTestCase {
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
        cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-first-paint-\(UUID().uuidString).json")
        FirstPaintCache.fileURLOverride = cacheURL
    }

    override func tearDown() {
        FirstPaintCache.fileURLOverride = nil
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        super.tearDown()
    }

    func testAppStateInitDoesNotOpenDatabase() {
        var openCount = 0
        let provider = LazyDatabaseProvider(
            opener: {
                openCount += 1
                return try DatabaseQueue()
            },
            migrator: { _ in }
        )

        _ = AppState(databaseProvider: provider)

        XCTAssertEqual(openCount, 0)
    }

    func testAppStateInitDoesNotCreateSkillsStore() {
        let state = AppState()

        XCTAssertNil(state.skillsStore)
    }

    func testSkillsActiveSnapshotLoadsOnlyCompactActiveRecord() async {
        let flags = FeatureFlags.shared
        let wasExperimental = flags.experimentalSurfaces
        let wasDeveloper = flags.developerSurfaces
        flags.experimentalSurfaces = true
        flags.developerSurfaces = false
        defer {
            flags.experimentalSurfaces = wasExperimental
            flags.developerSurfaces = wasDeveloper
        }

        var calls: [[String]] = []
        let client = ClawJSFrameworkRecordsClient(runner: .init { args in
            calls.append(args)
            if args == ["skills", "get", "clawix-active-skills", "--json"] {
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "id": "active",
                    "slug": "clawix-active-skills",
                    "kind": "clawix_state",
                    "name": "Clawix active skills",
                    "body": "{\\"global\\":[{\\"slug\\":\\"review\\",\\"kind\\":\\"procedure\\",\\"scopeTag\\":\\"global\\",\\"priority\\":10,\\"params\\":null}]}",
                    "metadata": { "surface": "skills.activeByScope" }
                  }
                }
                """.utf8)
            }
            return Data(#"{"ok":true,"data":null}"#.utf8)
        })
        let chatId = UUID()
        let state = AppState()
        state.chats = [Chat(id: chatId, title: "Prompt prep")]
        state.makeSkillsStore = { seedBuiltins, loadMode in
            XCTAssertFalse(seedBuiltins)
            XCTAssertEqual(loadMode, .none)
            return SkillsStore(seedBuiltins: seedBuiltins, frameworkClient: client, loadMode: loadMode)
        }

        let snapshot = await state.skillsActiveSnapshot(for: chatId)

        XCTAssertEqual(snapshot?.map(\.slug), ["review"])
        XCTAssertEqual(snapshot?.first?.kind, "procedure")
        XCTAssertEqual(snapshot?.first?.scope, "global")
        XCTAssertEqual(snapshot?.first?.priority, 10)
        XCTAssertEqual(calls, [["skills", "get", "clawix-active-skills", "--json"]])
    }

    func testSkillsActiveSnapshotDoesNotLoadWhenSkillsAreHidden() async {
        let flags = FeatureFlags.shared
        let wasExperimental = flags.experimentalSurfaces
        let wasDeveloper = flags.developerSurfaces
        flags.experimentalSurfaces = false
        flags.developerSurfaces = false
        defer {
            flags.experimentalSurfaces = wasExperimental
            flags.developerSurfaces = wasDeveloper
        }

        let chatId = UUID()
        let state = AppState()
        state.chats = [Chat(id: chatId, title: "Prompt prep")]
        state.makeSkillsStore = { _, _ in
            XCTFail("Hidden Skills must not construct the framework-backed store.")
            return SkillsStore(loadMode: .none)
        }

        let snapshot = await state.skillsActiveSnapshot(for: chatId)

        XCTAssertNil(snapshot)
        XCTAssertNil(state.skillsStore)
    }

    func testFirstPaintCachePopulatesSidebarState() throws {
        let projectID = UUID()
        let chatID = UUID()
        FirstPaintCache.save(FirstPaintCache.Payload(
            version: 1,
            projects: [
                FirstPaintCache.ProjectItem(
                    id: projectID.uuidString,
                    resourceId: "res_project",
                    name: "Project",
                    path: "/tmp/clawix-project"
                )
            ],
            chats: [
                FirstPaintCache.ChatItem(
                    threadId: "thread-1",
                    chatUuid: chatID.uuidString,
                    title: "Cached chat",
                    cwd: "/tmp/clawix-project",
                    projectId: projectID.uuidString,
                    projectPath: "/tmp/clawix-project",
                    updatedAt: 1_700_000_000,
                    pinned: true
                )
            ],
            pinnedThreadIds: ["thread-1"],
            projectPathHints: ["/tmp/clawix-project"]
        ))

        let state = AppState()

        XCTAssertEqual(state.projects.map(\.id), [projectID])
        XCTAssertEqual(state.chats.map(\.id), [chatID])
        XCTAssertEqual(state.chats.first?.title, "Cached chat")
        XCTAssertEqual(state.chats.first?.clawixThreadId, "thread-1")
        XCTAssertEqual(state.chats.first?.projectId, projectID)
        XCTAssertEqual(state.pinnedOrder, [chatID])
    }

    func testCorruptFirstPaintCacheDoesNotPreventLaunch() throws {
        try "not-json".data(using: .utf8)?.write(to: cacheURL)

        _ = AppState()
    }

    func testPostFirstFrameSnapshotDoesNotHydrateProjectIndexGlobally() async throws {
        let queue = try migratedQueue()
        let projectPath = "/tmp/clawix-post-first-frame-project"
        try await queue.write { db in
            try Self.insertSidebarSnapshot(
                threadId: "global-top",
                projectPath: projectPath,
                updatedAt: 1_000,
                in: db
            )
            for index in 0..<1_000 {
                try Self.insertProjectSnapshot(
                    threadId: "project-\(index)",
                    projectId: nil,
                    projectPath: projectPath,
                    updatedAt: Int64(index),
                    in: db
                )
            }
        }
        let provider = LazyDatabaseProvider(opener: { queue }, migrator: { _ in })
        let state = AppState(
            databaseProvider: provider,
            snapshotRepository: SnapshotRepository(db: queue)
        )

        state.startPostFirstFramePersistence()
        await waitUntil { state.chats.map(\.clawixThreadId).contains("global-top") }

        XCTAssertEqual(state.chats.map(\.clawixThreadId), ["global-top"])
    }

    func testVisibleProjectLoadsOnlyOneCachedProjectPage() throws {
        let queue = try migratedQueue()
        let project = Project(id: UUID(), name: "Project", path: "/tmp/clawix-demand-project")
        try queue.write { db in
            for index in 0..<25 {
                try Self.insertProjectSnapshot(
                    threadId: "project-\(index)",
                    projectId: project.id.uuidString,
                    projectPath: project.path,
                    updatedAt: Int64(index),
                    in: db
                )
            }
        }
        let state = AppState(snapshotRepository: SnapshotRepository(db: queue))

        state.requestVisibleProjectRefresh(project)

        XCTAssertEqual(state.chats.count, AppState.snapshotPerProjectCap)
        XCTAssertEqual(
            state.chats.compactMap(\.clawixThreadId),
            (15..<25).reversed().map { "project-\($0)" }
        )
    }

    func testMigrationFailureSetsRescueDecision() async {
        let provider = LazyDatabaseProvider(
            opener: { try DatabaseQueue() },
            migrator: { _ in throw StubError.migrationFailed }
        )
        let state = AppState(databaseProvider: provider)

        state.startPostFirstFramePersistence()
        await waitUntil {
            state.rescueDecision.pendingRepairSignals.contains(.migrationFailure)
        }

        XCTAssertEqual(state.rescueDecision.mode, .ephemeralChat)
        XCTAssertTrue(state.rescueDecision.pendingRepairSignals.contains(.migrationFailure))
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private enum StubError: Error {
        case migrationFailed
    }

    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrator.migrate(queue)
        return queue
    }

    nonisolated private static func insertSidebarSnapshot(
        threadId: String,
        projectPath: String,
        updatedAt: Int64,
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: """
            INSERT INTO sidebar_snapshot(
                thread_id, chat_uuid, title, cwd, project_id, project_path, updated_at, archived, pinned, captured_at
            ) VALUES (?, ?, 'Thread', NULL, NULL, ?, ?, 0, 0, 10)
        """, arguments: [threadId, UUID().uuidString, projectPath, updatedAt])
    }

    nonisolated private static func insertProjectSnapshot(
        threadId: String,
        projectId: String?,
        projectPath: String,
        updatedAt: Int64,
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: """
            INSERT INTO sidebar_snapshot_project(
                thread_id, chat_uuid, title, cwd, project_id, project_path, updated_at, archived, pinned, captured_at
            ) VALUES (?, ?, 'Thread', NULL, ?, ?, ?, 0, 0, 10)
        """, arguments: [threadId, UUID().uuidString, projectId, projectPath, updatedAt])
    }
}
