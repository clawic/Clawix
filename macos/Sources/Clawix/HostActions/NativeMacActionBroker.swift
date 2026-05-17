import Foundation

struct NativeMacActionRequest: Equatable {
    var requestId: String
    var capabilityId: String
    var actorId: String
    var origin: HostActionOrigin
    var arguments: [String: String]
    var dryRun: Bool
    var approved: Bool

    init(
        requestId: String = "macreq_\(UUID().uuidString)",
        capabilityId: String,
        actorId: String,
        origin: HostActionOrigin,
        arguments: [String: String] = [:],
        dryRun: Bool = false,
        approved: Bool = false
    ) {
        self.requestId = requestId
        self.capabilityId = capabilityId
        self.actorId = actorId
        self.origin = origin
        self.arguments = arguments
        self.dryRun = dryRun
        self.approved = approved
    }
}

struct NativeMacActionPlan: Equatable {
    enum Risk: String, Equatable {
        case read
        case low
        case medium
        case high
        case critical
    }

    enum RevertLevel: String, Equatable {
        case guaranteed
        case bestEffort = "best_effort"
        case none
    }

    struct Step: Equatable {
        enum Kind: String, Equatable {
            case process
            case appleScript
        }

        var kind: Kind
        var executable: String?
        var arguments: [String]
        var script: String?
        var preview: String
        var redacted: Bool
    }

    var planId: String
    var requestId: String
    var capabilityId: String
    var risk: Risk
    var requiredPermissionIds: [NativeMacPermissionBroker.PermissionID]
    var requiresApproval: Bool
    var continuityBreaker: Bool
    var revertLevel: RevertLevel
    var steps: [Step]
    var blockedReason: String?

    var isBlocked: Bool {
        blockedReason != nil
    }
}

struct NativeMacActionReceipt: Equatable {
    enum Outcome: String, Equatable {
        case planned
        case approvalRequired = "approval_required"
        case blocked
        case executed
        case failed
    }

    var receiptId: String
    var requestId: String
    var planId: String
    var capabilityId: String
    var outcome: Outcome
    var outputs: [String]
    var error: String?
}

protocol NativeMacActionCommandRunning {
    func runProcess(_ executable: String, arguments: [String]) throws -> String
    func runAppleScript(_ source: String) throws -> String
}

struct NativeMacActionProcessRunner: NativeMacActionCommandRunning {
    func runProcess(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NativeMacActionBroker.Error.commandFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    func runAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NativeMacActionBroker.Error.commandFailed("Could not prepare AppleScript action")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript action failed"
            throw NativeMacActionBroker.Error.commandFailed(message)
        }
        return result.stringValue ?? ""
    }
}

@MainActor
enum NativeMacActionBroker {
    enum Error: LocalizedError, Equatable {
        case unsupportedCapability(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedCapability(let capability):
                return "Unsupported Mac action capability: \(capability)"
            case .commandFailed(let message):
                return message.isEmpty ? "Mac action command failed" : message
            }
        }
    }

    static func plan(for request: NativeMacActionRequest) throws -> NativeMacActionPlan {
        let blockedReason = plaintextPasswordBlock(for: request)
        switch request.capabilityId {
        case "mac.wifi.status":
            return processPlan(
                request,
                risk: .read,
                permissions: [],
                steps: [
                    .process("/usr/sbin/networksetup", ["-getairportpower", wifiDevice(from: request)], "Read Wi-Fi power state"),
                    .process("/usr/sbin/networksetup", ["-getairportnetwork", wifiDevice(from: request)], "Read current Wi-Fi network"),
                ],
                blockedReason: blockedReason
            )
        case "mac.wifi.list":
            return processPlan(
                request,
                risk: .read,
                permissions: [],
                steps: [
                    .process("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", wifiDevice(from: request)], "List preferred Wi-Fi networks"),
                ],
                blockedReason: blockedReason
            )
        case "mac.wifi.connect":
            guard let ssid = request.arguments["ssid"], !ssid.isEmpty else {
                return blockedPlan(request, reason: "Wi-Fi connect requires an explicit SSID.")
            }
            return processPlan(
                request,
                risk: .high,
                permissions: [],
                steps: [
                    .process("/usr/sbin/networksetup", ["-setairportnetwork", wifiDevice(from: request), ssid], "Connect Wi-Fi to \(redactedNetworkName(ssid))", redacted: true),
                ],
                requiresApproval: true,
                continuityBreaker: true,
                revertLevel: .bestEffort,
                blockedReason: blockedReason
            )
        case "mac.wifi.disconnect":
            return blockedPlan(request, reason: "Wi-Fi disconnect needs the CoreWLAN implementation before it can execute safely.")
        case "mac.wifi.power.on":
            return wifiPowerPlan(request, power: "on", risk: .medium, blockedReason: blockedReason)
        case "mac.wifi.power.off":
            return wifiPowerPlan(request, power: "off", risk: .critical, blockedReason: blockedReason)
        case "mac.window.list":
            return appleScriptPlan(
                request,
                risk: .read,
                permissions: [.accessibility],
                script: Self.windowListScript,
                preview: "List visible application windows",
                blockedReason: blockedReason
            )
        case "mac.window.close":
            return appleScriptPlan(
                request,
                risk: .high,
                permissions: [.accessibility],
                script: Self.closeFocusedWindowScript,
                preview: "Close the focused window",
                requiresApproval: true,
                revertLevel: .none,
                blockedReason: blockedReason
            )
        case "mac.window.minimize":
            return appleScriptPlan(
                request,
                risk: .medium,
                permissions: [.accessibility],
                script: Self.minimizeFocusedWindowScript,
                preview: "Minimize the focused window",
                requiresApproval: true,
                revertLevel: .bestEffort,
                blockedReason: blockedReason
            )
        case "mac.shortcut.list":
            return processPlan(
                request,
                risk: .read,
                permissions: [],
                steps: [.process("/usr/bin/shortcuts", ["list"], "List Shortcuts")],
                blockedReason: blockedReason
            )
        case "mac.shortcut.show":
            guard let name = request.arguments["name"], !name.isEmpty else {
                return blockedPlan(request, reason: "Shortcut show requires a shortcut name.")
            }
            return processPlan(
                request,
                risk: .low,
                permissions: [],
                steps: [.process("/usr/bin/shortcuts", ["view", name], "Show Shortcut \(redactedShortcutName(name))", redacted: true)],
                blockedReason: blockedReason
            )
        case "mac.shortcut.run":
            guard let name = request.arguments["name"], !name.isEmpty else {
                return blockedPlan(request, reason: "Shortcut run requires a shortcut name.")
            }
            return processPlan(
                request,
                risk: .high,
                permissions: [.automationAppleEvents],
                steps: [.process("/usr/bin/shortcuts", ["run", name], "Run Shortcut \(redactedShortcutName(name))", redacted: true)],
                requiresApproval: true,
                revertLevel: .none,
                blockedReason: blockedReason
            )
        default:
            throw Error.unsupportedCapability(request.capabilityId)
        }
    }

    static func evaluate(
        _ request: NativeMacActionRequest,
        defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard,
        auditURL: URL? = nil,
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner()
    ) -> NativeMacActionReceipt {
        let plan: NativeMacActionPlan
        do {
            plan = try Self.plan(for: request)
        } catch {
            return receipt(for: request, planId: "macplan_invalid", outcome: .blocked, error: error.localizedDescription)
        }
        if let blockedReason = plan.blockedReason {
            return receipt(for: request, plan: plan, outcome: .blocked, error: blockedReason)
        }
        if request.dryRun {
            return receipt(for: request, plan: plan, outcome: .planned)
        }
        if plan.requiresApproval {
            let authorization = HostActionPolicy.authorize(
                surface: .macControl,
                action: request.capabilityId,
                origin: request.origin,
                defaults: defaults,
                auditURL: auditURL,
                approvedOverride: request.approved
            )
            guard authorization.allowed else {
                let outcome: NativeMacActionReceipt.Outcome = authorization.outcome == "blocked" ? .blocked : .approvalRequired
                return receipt(for: request, plan: plan, outcome: outcome, error: authorization.reason)
            }
        }

        do {
            var outputs: [String] = []
            for step in plan.steps {
                switch step.kind {
                case .process:
                    guard let executable = step.executable else { continue }
                    outputs.append(try runner.runProcess(executable, arguments: step.arguments))
                case .appleScript:
                    guard let script = step.script else { continue }
                    outputs.append(try runner.runAppleScript(script))
                }
            }
            return receipt(for: request, plan: plan, outcome: .executed, outputs: outputs)
        } catch {
            return receipt(for: request, plan: plan, outcome: .failed, error: error.localizedDescription)
        }
    }

    private static func processPlan(
        _ request: NativeMacActionRequest,
        risk: NativeMacActionPlan.Risk,
        permissions: [NativeMacPermissionBroker.PermissionID],
        steps: [NativeMacActionPlan.Step],
        requiresApproval: Bool = false,
        continuityBreaker: Bool = false,
        revertLevel: NativeMacActionPlan.RevertLevel = .none,
        blockedReason: String? = nil
    ) -> NativeMacActionPlan {
        NativeMacActionPlan(
            planId: "macplan_\(request.requestId)",
            requestId: request.requestId,
            capabilityId: request.capabilityId,
            risk: risk,
            requiredPermissionIds: permissions,
            requiresApproval: requiresApproval,
            continuityBreaker: continuityBreaker,
            revertLevel: revertLevel,
            steps: steps,
            blockedReason: blockedReason
        )
    }

    private static func appleScriptPlan(
        _ request: NativeMacActionRequest,
        risk: NativeMacActionPlan.Risk,
        permissions: [NativeMacPermissionBroker.PermissionID],
        script: String,
        preview: String,
        requiresApproval: Bool = false,
        revertLevel: NativeMacActionPlan.RevertLevel = .none,
        blockedReason: String? = nil
    ) -> NativeMacActionPlan {
        processPlan(
            request,
            risk: risk,
            permissions: permissions,
            steps: [
                NativeMacActionPlan.Step(
                    kind: .appleScript,
                    executable: nil,
                    arguments: [],
                    script: script,
                    preview: preview,
                    redacted: false
                ),
            ],
            requiresApproval: requiresApproval,
            revertLevel: revertLevel,
            blockedReason: blockedReason
        )
    }

    private static func blockedPlan(_ request: NativeMacActionRequest, reason: String) -> NativeMacActionPlan {
        processPlan(request, risk: .high, permissions: [], steps: [], blockedReason: reason)
    }

    private static func wifiPowerPlan(
        _ request: NativeMacActionRequest,
        power: String,
        risk: NativeMacActionPlan.Risk,
        blockedReason: String?
    ) -> NativeMacActionPlan {
        processPlan(
            request,
            risk: risk,
            permissions: [],
            steps: [
                .process("/usr/sbin/networksetup", ["-setairportpower", wifiDevice(from: request), power], "Turn Wi-Fi \(power)"),
            ],
            requiresApproval: true,
            continuityBreaker: power == "off",
            revertLevel: .bestEffort,
            blockedReason: blockedReason
        )
    }

    private static func receipt(
        for request: NativeMacActionRequest,
        plan: NativeMacActionPlan,
        outcome: NativeMacActionReceipt.Outcome,
        outputs: [String] = [],
        error: String? = nil
    ) -> NativeMacActionReceipt {
        receipt(for: request, planId: plan.planId, outcome: outcome, outputs: outputs, error: error)
    }

    private static func receipt(
        for request: NativeMacActionRequest,
        planId: String,
        outcome: NativeMacActionReceipt.Outcome,
        outputs: [String] = [],
        error: String? = nil
    ) -> NativeMacActionReceipt {
        NativeMacActionReceipt(
            receiptId: "macact_\(UUID().uuidString)",
            requestId: request.requestId,
            planId: planId,
            capabilityId: request.capabilityId,
            outcome: outcome,
            outputs: outputs,
            error: error
        )
    }

    private static func wifiDevice(from request: NativeMacActionRequest) -> String {
        request.arguments["device"].flatMap { $0.isEmpty ? nil : $0 } ?? "en0"
    }

    private static func plaintextPasswordBlock(for request: NativeMacActionRequest) -> String? {
        request.arguments["password"] == nil ? nil : "Plaintext Wi-Fi passwords are not accepted by the Mac Action Broker. Use a secret reference."
    }

    private static func redactedNetworkName(_ ssid: String) -> String {
        ssid.isEmpty ? "<ssid>" : "<ssid:\(ssid.count) chars>"
    }

    private static func redactedShortcutName(_ name: String) -> String {
        name.isEmpty ? "<shortcut>" : "<shortcut:\(name.count) chars>"
    }

    private static let windowListScript = """
    tell application "System Events"
        set rows to {}
        repeat with appProcess in application processes
            try
                repeat with appWindow in windows of appProcess
                    try
                        set end of rows to (name of appProcess) & "\t" & (name of appWindow)
                    end try
                end repeat
            end try
        end repeat
        set AppleScript's text item delimiters to linefeed
        return rows as text
    end tell
    """

    private static let closeFocusedWindowScript = """
    tell application "System Events"
        set frontProcess to first application process whose frontmost is true
        try
            click button 1 of window 1 of frontProcess
        on error
            keystroke "w" using command down
        end try
    end tell
    """

    private static let minimizeFocusedWindowScript = """
    tell application "System Events"
        set frontProcess to first application process whose frontmost is true
        set value of attribute "AXMinimized" of window 1 of frontProcess to true
    end tell
    """
}

private extension NativeMacActionPlan.Step {
    static func process(
        _ executable: String,
        _ arguments: [String],
        _ preview: String,
        redacted: Bool = false
    ) -> NativeMacActionPlan.Step {
        NativeMacActionPlan.Step(
            kind: .process,
            executable: executable,
            arguments: arguments,
            script: nil,
            preview: preview,
            redacted: redacted
        )
    }
}
