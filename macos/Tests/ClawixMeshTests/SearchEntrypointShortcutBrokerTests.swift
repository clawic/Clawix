import XCTest
import KeyboardShortcuts
@testable import Clawix

final class SearchEntrypointShortcutBrokerTests: XCTestCase {
    func testContractsKeepRootSearchSeparateFromCommandGChatSearch() {
        let root = SearchEntrypointShortcutBroker.contract(for: "root-search")
        let chat = SearchEntrypointShortcutBroker.contract(for: "chat-search")

        XCTAssertEqual(root?.bindingId, "search.root.global")
        XCTAssertEqual(root?.queryScope, "framework")
        XCTAssertEqual(root?.state, .ready)
        XCTAssertEqual(root?.routeTarget, "root-search")
        XCTAssertNil(root?.reservedChord)

        XCTAssertEqual(chat?.bindingId, "search.chat.current")
        XCTAssertEqual(chat?.queryScope, "conversations_only")
        XCTAssertEqual(chat?.state, .ready)
        XCTAssertEqual(chat?.routeTarget, "search")
        XCTAssertEqual(chat?.reservedChord, "Command-G")
    }

    func testCommandGOnlyBindsToConversationSearch() {
        let decision = SearchEntrypointShortcutBroker.validate(
            SearchEntrypointShortcutRequest(
                entrypointId: "chat-search",
                bindingId: "search.chat.current",
                chord: "Command-G",
                routeTarget: "search"
            )
        )

        XCTAssertTrue(decision.allowed)
        XCTAssertEqual(decision.state, .ready)
    }

    func testRootSearchRejectsCommandGAndConversationRoute() {
        let commandG = SearchEntrypointShortcutBroker.validate(
            SearchEntrypointShortcutRequest(
                entrypointId: "root-search",
                bindingId: "search.root.global",
                chord: "Command-G",
                routeTarget: "root-search"
            )
        )
        let chatRoute = SearchEntrypointShortcutBroker.validate(
            SearchEntrypointShortcutRequest(
                entrypointId: "root-search",
                bindingId: "search.root.global",
                chord: "Option-Command-Space",
                routeTarget: "search"
            )
        )

        XCTAssertFalse(commandG.allowed)
        XCTAssertEqual(commandG.state, .blocked)
        XCTAssertFalse(chatRoute.allowed)
        XCTAssertEqual(chatRoute.state, .blocked)
    }

    func testRootSearchIsPendingUntilHostRouteTargetExists() {
        let pending = SearchEntrypointShortcutBroker.validate(
            SearchEntrypointShortcutRequest(
                entrypointId: "root-search",
                bindingId: "search.root.global",
                chord: "Option-Command-Space",
                routeTarget: nil
            )
        )
        let ready = SearchEntrypointShortcutBroker.validate(
            SearchEntrypointShortcutRequest(
                entrypointId: "root-search",
                bindingId: "search.root.global",
                chord: "Option-Command-Space",
                routeTarget: "root-search"
            )
        )

        XCTAssertFalse(pending.allowed)
        XCTAssertEqual(pending.state, .externalPending)
        XCTAssertTrue(ready.allowed)
        XCTAssertEqual(ready.state, .ready)
    }

    func testRootSearchDefaultShortcutTargetsSignedHostPanel() {
        let decision = SearchEntrypointShortcutBroker.validate(
            SearchEntrypointShortcutRequest(
                entrypointId: SearchEntrypointShortcutBroker.rootEntrypointId,
                bindingId: SearchEntrypointShortcutBroker.rootBindingId,
                chord: SearchEntrypointShortcutBroker.rootDefaultChord,
                routeTarget: SearchEntrypointShortcutBroker.rootRouteTarget
            )
        )

        XCTAssertTrue(decision.allowed)
        XCTAssertEqual(decision.state, .ready)
    }

    func testRootSearchInstallerValidatesCurrentRecordedShortcut() {
        let blocked = SearchEntrypointShortcutsInstaller.validateRootSearchShortcut(
            KeyboardShortcuts.Shortcut(.g, modifiers: [.command])
        )
        let ready = SearchEntrypointShortcutsInstaller.validateRootSearchShortcut(
            KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .option])
        )

        XCTAssertFalse(blocked.allowed)
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertEqual(blocked.reason, "Root Search must not reuse Command-G.")
        XCTAssertTrue(ready.allowed)
        XCTAssertEqual(ready.state, .ready)
    }
}
