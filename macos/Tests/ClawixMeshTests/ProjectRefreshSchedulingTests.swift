import XCTest
@testable import Clawix

@MainActor
final class ProjectRefreshSchedulingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
        setenv("CLAWIX_DUMMY_MODE", "1", 1)
    }

    override func tearDown() {
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        unsetenv("CLAWIX_DUMMY_MODE")
        super.tearDown()
    }

    func testProjectsDoNotRefreshUntilRequested() async throws {
        let state = AppState()
        let project = makeProject("NoImplicit")
        var starts = 0
        state.projects = [project]
        state.projectThreadListLoader = { _, _ in
            starts += 1
            return []
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(starts, 0)
    }

    func testExpandedRefreshesDeduplicateByPath() async throws {
        let state = AppState()
        let first = makeProject("Shared")
        let second = Project(name: "Shared Again", path: first.path)
        var starts = 0
        state.projectThreadListLoader = { _, _ in
            starts += 1
            try await Task.sleep(nanoseconds: 500_000_000)
            return []
        }

        state.requestExpandedProjectRefresh(first)
        state.requestExpandedProjectRefresh(second)

        try await waitUntil { starts == 1 }
        XCTAssertEqual(starts, 1)
        state.cancelProjectRefresh(first)
    }

    func testExpandedRefreshRespectsDebounceAfterSuccess() async throws {
        let state = AppState()
        let project = makeProject("Debounced")
        var starts = 0
        state.projectThreadListLoader = { _, _ in
            starts += 1
            return []
        }

        state.requestExpandedProjectRefresh(project)
        try await waitUntil { starts == 1 }
        state.requestExpandedProjectRefresh(project)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(starts, 1)
    }

    func testVisibleRefreshDoesNotStartRuntimeLoader() async throws {
        let state = AppState()
        let project = makeProject("Visible")
        var starts = 0
        state.projectThreadListLoader = { _, _ in
            starts += 1
            return []
        }

        state.requestVisibleProjectRefresh(project)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(starts, 0)
    }

    func testCancelProjectRefreshCancelsRetainedTask() async throws {
        let state = AppState()
        let project = makeProject("Canceled")
        var starts = 0
        var cancellations = 0
        state.projectThreadListLoader = { _, _ in
            starts += 1
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancellations += 1
                throw CancellationError()
            }
            return []
        }

        state.requestExpandedProjectRefresh(project)
        try await waitUntil { starts == 1 }
        state.cancelProjectRefresh(project)

        try await waitUntil { cancellations == 1 }
    }

    private func makeProject(_ name: String) -> Project {
        Project(name: name, path: "/tmp/clawix-project-refresh-\(name)")
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}
