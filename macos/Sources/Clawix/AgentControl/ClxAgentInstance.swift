import AppKit
import Foundation

/// Per-instance agent runtime. An "agent instance" is a Clawix process launched
/// by the dev provisioner (the private development provisioner) to be driven
/// programmatically and in parallel, isolated from the canonical app and from
/// other instances. Everything here is gated on CLAWIX_AGENT_INSTANCE=1 and is
/// inert in normal user builds.
enum ClxAgentInstance {
    static var isAgent: Bool {
        ProcessInfo.processInfo.environment["CLAWIX_AGENT_INSTANCE"] == "1"
    }

    static var instanceId: String {
        ProcessInfo.processInfo.environment["CLAWIX_AGENT_ID"] ?? "agent"
    }

    /// Bridge `open -n --args …` launch arguments into the environment BEFORE
    /// any isolation seam reads it. LaunchServices strips a custom environment,
    /// so the provisioner passes config as argv; we translate it back into the
    /// CLAWIX_* / CLAW_HOST_HOME vars the rest of the app already understands.
    /// A safe no-op on normal launches (no agent flags present). Must run first
    /// thing in `main`, before `appPrefsSuite` or `StatePaths` are touched.
    static func applyLaunchArguments(_ arguments: [String] = CommandLine.arguments) {
        let flagToEnv: [String: String] = [
            "--clawix-agent-id": "CLAWIX_AGENT_ID",
            "--clawix-state-root": "CLAWIX_STATE_ROOT",
            "--clawix-defaults-suite": "CLAWIX_DEFAULTS_SUITE",
            "--clawix-host-home": "CLAW_HOST_HOME",
            "--clawix-control-port": "CLAWIX_CONTROL_PORT",
            "--clawix-control-token": "CLAWIX_CONTROL_TOKEN",
            "--clawix-bridge-port": "CLAWIX_BRIDGE_PORT",
            "--clawix-bridge-http-port": "CLAWIX_BRIDGE_HTTP_PORT",
        ]
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            if arg == "--clawix-agent-instance" {
                setenv("CLAWIX_AGENT_INSTANCE", "1", 1)
                index += 1
                continue
            }
            if let envKey = flagToEnv[arg], index + 1 < arguments.count {
                setenv(envKey, arguments[index + 1], 1)
                index += 2
                continue
            }
            index += 1
        }
    }

    @MainActor private static var server: ClxControlServer?
    @MainActor private static var heartbeatTimer: Timer?

    /// Start the loopback control server and the heartbeat writer. Gated on
    /// CLAWIX_AGENT_INSTANCE so it never runs in a user build.
    @MainActor
    static func startIfAgent() {
        guard isAgent else { return }
        startHeartbeat()
        let environment = ProcessInfo.processInfo.environment
        if let portString = environment["CLAWIX_CONTROL_PORT"], let port = UInt16(portString),
           let token = environment["CLAWIX_CONTROL_TOKEN"], !token.isEmpty {
            let server = ClxControlServer(port: port, token: token)
            server.start()
            self.server = server
        }
    }

    @MainActor
    private static func startHeartbeat() {
        writeHeartbeat()
        let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            ClxAgentInstance.writeHeartbeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    /// Touch `<stateRoot>/.clawix/agent-heartbeat`; the provisioner's reaper
    /// treats a stale or missing-process heartbeat as a dead instance.
    static func writeHeartbeat() {
        let url = ClawixPersistentSurfacePaths.homeChild("agent-heartbeat", isDirectory: false)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stamp = String(Int(Date().timeIntervalSince1970))
        try? Data(stamp.utf8).write(to: url)
    }
}
