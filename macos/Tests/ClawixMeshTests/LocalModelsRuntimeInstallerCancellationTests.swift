import XCTest
@testable import Clawix

@MainActor
final class LocalModelsRuntimeInstallerCancellationTests: XCTestCase {
    func testCancellingInstallStopsInjectedExtraction() async throws {
        let started = expectation(description: "Runtime extraction started")
        let cancelled = expectation(description: "Runtime extraction cancelled")
        let tarball = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-runtime-\(UUID().uuidString).tgz")
        try Data("fixture".utf8).write(to: tarball)
        defer { try? FileManager.default.removeItem(at: tarball) }

        let installer = LocalModelsRuntimeInstaller(
            downloadOperation: { tarball },
            verifyOperation: { _ in },
            extractOperation: { _ in
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    cancelled.fulfill()
                    throw CancellationError()
                }
            },
            refreshOnInit: false
        )

        let task = Task { await installer.install() }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()

        await fulfillment(of: [cancelled], timeout: 1)
        await task.value
        XCTAssertEqual(installer.state, .notInstalled)
    }
}
