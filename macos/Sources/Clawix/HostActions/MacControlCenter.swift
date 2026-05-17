import ClawHostKit
import Foundation
import SwiftUI

enum MacControlSettingsFamily: String, CaseIterable, Identifiable {
    case wifi
    case window
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi:     return "Wi-Fi"
        case .window:   return "Windows"
        case .shortcut: return "Shortcuts"
        }
    }
}

struct MacControlSettingsCapability: Identifiable, Equatable {
    let id: String
    let family: MacControlSettingsFamily
    let title: String
    let detail: String
    let canRun: Bool

    static let all: [MacControlSettingsCapability] = [
        MacControlSettingsCapability(id: "mac.wifi.status", family: .wifi, title: "Status", detail: "Read power and current network.", canRun: false),
        MacControlSettingsCapability(id: "mac.wifi.list", family: .wifi, title: "Known networks", detail: "List preferred Wi-Fi networks.", canRun: false),
        MacControlSettingsCapability(id: "mac.wifi.connect", family: .wifi, title: "Connect", detail: "Join a network using a stored secret.", canRun: true),
        MacControlSettingsCapability(id: "mac.wifi.disconnect", family: .wifi, title: "Disconnect", detail: "Drop the current Wi-Fi connection.", canRun: true),
        MacControlSettingsCapability(id: "mac.wifi.power.on", family: .wifi, title: "Turn on", detail: "Enable the Wi-Fi device.", canRun: true),
        MacControlSettingsCapability(id: "mac.wifi.power.off", family: .wifi, title: "Turn off", detail: "Disable the Wi-Fi device.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.list", family: .window, title: "List", detail: "Read visible application windows.", canRun: false),
        MacControlSettingsCapability(id: "mac.window.focus", family: .window, title: "Focus", detail: "Bring a matching window forward.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.move", family: .window, title: "Move", detail: "Move a matching window to x/y.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.resize", family: .window, title: "Resize", detail: "Resize a matching window.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.close", family: .window, title: "Close", detail: "Close the focused window.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.minimize", family: .window, title: "Minimize", detail: "Minimize the focused window.", canRun: true),
        MacControlSettingsCapability(id: "mac.shortcut.list", family: .shortcut, title: "List", detail: "Read installed Shortcuts.", canRun: false),
        MacControlSettingsCapability(id: "mac.shortcut.show", family: .shortcut, title: "Show", detail: "Open a named Shortcut.", canRun: false),
        MacControlSettingsCapability(id: "mac.shortcut.run", family: .shortcut, title: "Run", detail: "Run a named Shortcut.", canRun: true),
    ]

    static func capabilities(in family: MacControlSettingsFamily) -> [MacControlSettingsCapability] {
        all.filter { $0.family == family }
    }

    static func capability(id: String) -> MacControlSettingsCapability? {
        all.first { $0.id == id }
    }
}

@MainActor
struct MacControlPermissionSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String

    static var current: [MacControlPermissionSnapshot] {
        [
            snapshot(.accessibility, title: "Accessibility"),
            snapshot(.automationAppleEvents, title: "Automation"),
            snapshot(.microphone, title: "Microphone"),
            snapshot(.speechRecognition, title: "Speech recognition"),
            snapshot(.camera, title: "Camera"),
            snapshot(.inputMonitoring, title: "Input monitoring"),
        ]
    }

    private static func snapshot(_ permission: NativeMacPermissionBroker.PermissionID, title: String) -> MacControlPermissionSnapshot {
        MacControlPermissionSnapshot(id: permission.rawValue, title: title, status: statusLabel(NativeMacPermissionBroker.status(for: permission)))
    }

    private static func statusLabel(_ status: NativeMacPermissionBroker.Status) -> String {
        switch status {
        case .granted:       return "Granted"
        case .denied:        return "Denied"
        case .notDetermined: return "Not requested"
        }
    }
}

@MainActor
final class MacControlCenter: ObservableObject {
    @Published private(set) var lastPlan: NativeMacActionWirePlan?
    @Published private(set) var lastEvaluation: NativeMacActionWireEvaluation?
    @Published private(set) var lastError: String?

    private let runner: NativeMacActionCommandRunning
    private let defaults: UserDefaults
    private let auditURL: URL?

    init(
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        defaults: UserDefaults = .standard,
        auditURL: URL? = nil
    ) {
        self.runner = runner
        self.defaults = defaults
        self.auditURL = auditURL
    }

    func plan(_ capability: MacControlSettingsCapability, arguments: [String: String] = [:]) {
        do {
            lastError = nil
            lastEvaluation = nil
            let data = try requestData(for: capability, arguments: arguments, dryRun: true, approved: false)
            let planData = try NativeMacActionWire.planJSON(for: data)
            lastPlan = try JSONDecoder().decode(NativeMacActionWirePlan.self, from: planData)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func execute(_ capability: MacControlSettingsCapability, arguments: [String: String] = [:], approved: Bool = true) {
        do {
            lastError = nil
            let data = try requestData(for: capability, arguments: arguments, dryRun: false, approved: approved)
            let evaluationData = try NativeMacActionWire.evaluateJSON(for: data, defaults: defaults, auditURL: auditURL, runner: runner)
            lastEvaluation = try JSONDecoder().decode(NativeMacActionWireEvaluation.self, from: evaluationData)
            lastPlan = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func arguments(
        for capability: MacControlSettingsCapability,
        wifiSSID: String,
        wifiSecretRef: String,
        wifiDevice: String,
        windowApp: String,
        windowTitle: String,
        windowX: String,
        windowY: String,
        windowWidth: String,
        windowHeight: String,
        shortcutName: String
    ) -> [String: String] {
        var arguments: [String: String] = [:]

        if capability.family == .wifi {
            arguments.addTrimmed("device", wifiDevice)
            if capability.id == "mac.wifi.connect" {
                arguments.addTrimmed("ssid", wifiSSID)
                arguments.addTrimmed("secretRef", wifiSecretRef)
            }
        }

        if capability.family == .window {
            arguments.addTrimmed("app", windowApp)
            arguments.addTrimmed("title", windowTitle)
            if capability.id == "mac.window.move" {
                arguments.addTrimmed("x", windowX)
                arguments.addTrimmed("y", windowY)
            }
            if capability.id == "mac.window.resize" {
                arguments.addTrimmed("width", windowWidth)
                arguments.addTrimmed("height", windowHeight)
            }
        }

        if capability.family == .shortcut {
            if capability.id == "mac.shortcut.show" || capability.id == "mac.shortcut.run" {
                arguments.addTrimmed("name", shortcutName)
            }
        }

        return arguments
    }

    private func requestData(
        for capability: MacControlSettingsCapability,
        arguments: [String: String],
        dryRun: Bool,
        approved: Bool
    ) throws -> Data {
        let request = NativeMacActionWireRequest(
            requestId: "macreq_clawix_\(UUID().uuidString.lowercased())",
            capabilityId: capability.id,
            actor: NativeMacActionWireActor(kind: "user_ui", id: "clawix_settings", role: "owner"),
            host: NativeMacActionWireHost(
                hostId: ProcessInfo.processInfo.hostName,
                bundleId: Bundle.main.bundleIdentifier ?? "com.clawix.app",
                signingIdentity: nil,
                teamId: nil,
                appVariant: appVariant,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ),
            arguments: arguments.mapValues { .string($0) },
            dryRun: dryRun,
            reason: "Mac Control Settings",
            approved: approved
        )
        return try JSONEncoder().encode(request)
    }

    private var appVariant: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}

private extension Dictionary where Key == String, Value == String {
    mutating func addTrimmed(_ key: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self[key] = trimmed
    }
}
