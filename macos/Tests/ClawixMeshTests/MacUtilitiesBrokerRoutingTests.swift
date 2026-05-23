import Foundation
import XCTest
@testable import Clawix

@MainActor
final class MacUtilitiesBrokerRoutingTests: XCTestCase {
    func testEveryMacUtilityActionRoutesThroughNativeActionBroker() {
        let runner = MacUtilitiesRecordingRunner()
        let controller = MacUtilitiesController(runner: runner, auditURL: temporaryAuditURL())

        for action in MacUtilityActionID.allCases where action != .toggleKeepAwake {
            controller.perform(action)
        }

        XCTAssertEqual(runner.nativeCalls.map(\.action), [
            "utility.hide_all_windows",
            "utility.minimize_all_windows",
            "utility.minimize_all_windows_except_frontmost",
            "utility.minimize_app_windows_except_frontmost",
            "utility.isolate_window",
            "utility.unminimize_all_windows",
            "utility.show_desktop",
            "utility.clear_clipboard",
            "utility.sleep_displays",
            "utility.center_mouse_pointer",
            "utility.show_color_picker",
            "utility.toggle_dark_mode",
            "utility.toggle_mute_sound",
            "utility.toggle_desktop_icons",
            "utility.open_finder",
            "utility.open_terminal",
            "utility.open_shortcuts",
            "utility.open_passwords",
            "utility.open_airdrop",
            "utility.open_vpn_settings",
            "utility.open_private_relay_settings",
            "utility.open_hide_my_email_settings",
            "utility.open_keyboard_settings",
            "utility.open_display_settings",
            "utility.open_desktop_dock_settings",
            "utility.open_notifications_settings",
            "utility.open_sound_settings",
            "utility.open_privacy_settings",
        ])
        XCTAssertTrue(runner.processCalls.isEmpty)
        XCTAssertTrue(runner.appleScriptCalls.isEmpty)
    }

    func testKeepAwakeUsesSeparateBrokeredOnAndOffCapabilities() {
        let runner = MacUtilitiesRecordingRunner()
        let controller = MacUtilitiesController(runner: runner, auditURL: temporaryAuditURL())

        controller.perform(.toggleKeepAwake)
        XCTAssertTrue(controller.keepAwakeEnabled)

        controller.perform(.toggleKeepAwake)
        XCTAssertFalse(controller.keepAwakeEnabled)

        XCTAssertEqual(runner.nativeCalls.map(\.action), [
            "utility.keep_awake_on",
            "utility.keep_awake_off",
        ])
    }

    func testBrokerFailurePublishesErrorAndDoesNotFlipKeepAwakeState() {
        let runner = MacUtilitiesRecordingRunner(failingNativeActions: ["utility.keep_awake_on"])
        let controller = MacUtilitiesController(runner: runner, auditURL: temporaryAuditURL())

        controller.perform(.toggleKeepAwake)

        XCTAssertFalse(controller.keepAwakeEnabled)
        XCTAssertTrue(controller.lastStatusIsError)
        XCTAssertEqual(runner.nativeCalls.map(\.action), ["utility.keep_awake_on"])
    }

    private func temporaryAuditURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-utilities-broker-routing-\(UUID().uuidString)")
            .appendingPathComponent(NativeMacActionPolicy.auditFilename)
    }
}

final class MacUtilitiesRecordingRunner: NativeMacActionCommandRunning {
    struct NativeCall: Equatable {
        var action: String
        var arguments: [String]
    }

    private(set) var nativeCalls: [NativeCall] = []
    private(set) var processCalls: [(String, [String])] = []
    private(set) var appleScriptCalls: [String] = []
    private let failingNativeActions: Set<String>

    init(failingNativeActions: Set<String> = []) {
        self.failingNativeActions = failingNativeActions
    }

    func runProcess(_ executable: String, arguments: [String]) throws -> String {
        processCalls.append((executable, arguments))
        return "ok"
    }

    func runAppleScript(_ source: String) throws -> String {
        appleScriptCalls.append(source)
        return "ok"
    }

    func runNative(_ action: String, arguments: [String]) throws -> String {
        nativeCalls.append(NativeCall(action: action, arguments: arguments))
        if failingNativeActions.contains(action) {
            throw NSError(domain: "MacUtilitiesRecordingRunner", code: 1)
        }
        return "ok"
    }
}
