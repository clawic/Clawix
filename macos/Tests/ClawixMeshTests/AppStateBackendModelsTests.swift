import Combine
import XCTest
@testable import Clawix

@MainActor
final class AppStateBackendModelsTests: XCTestCase {
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

    func testApplyingSameBackendModelsDoesNotPublishPickerArraysAgain() {
        let state = AppState()
        let entries = [
            ClawixService.ModelEntry(slug: "gpt-5.5", display: "GPT-5.5"),
            ClawixService.ModelEntry(slug: "gpt-5.4", display: "GPT-5.4"),
            ClawixService.ModelEntry(slug: "gpt-5.3-pro", display: "GPT-5.3 Pro")
        ]
        state.applyBackendModels(entries)
        var availablePublishes = 0
        var otherPublishes = 0
        var cancellables: Set<AnyCancellable> = []
        state.$availableModels.dropFirst().sink { _ in availablePublishes += 1 }.store(in: &cancellables)
        state.$otherModels.dropFirst().sink { _ in otherPublishes += 1 }.store(in: &cancellables)

        state.applyBackendModels(entries)

        XCTAssertEqual(availablePublishes, 0)
        XCTAssertEqual(otherPublishes, 0)

        state.applyBackendModels([
            ClawixService.ModelEntry(slug: "gpt-5.5", display: "GPT-5.5"),
            ClawixService.ModelEntry(slug: "gpt-5.4", display: "GPT-5.4"),
            ClawixService.ModelEntry(slug: "gpt-5.2", display: "GPT-5.2")
        ])

        XCTAssertEqual(availablePublishes, 0)
        XCTAssertEqual(otherPublishes, 1)
    }

    func testBackendStatusPublishesOutsideBroadAppState() {
        let state = AppState()
        var appStatePublishes = 0
        var statusPublishes = 0
        var cancellables: Set<AnyCancellable> = []
        state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
        state.backendStatusStore.$status.dropFirst().sink { _ in statusPublishes += 1 }.store(in: &cancellables)

        state.clawixBackendStatus = .starting

        XCTAssertEqual(appStatePublishes, 0)
        XCTAssertEqual(statusPublishes, 1)
    }
}
