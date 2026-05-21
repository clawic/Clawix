import Foundation
import ClawixEngine

enum LocalBridgeDemandReason: String, CaseIterable, Equatable {
    case pairing
    case companion
    case remoteTools
}

@MainActor
final class BridgeDemandLease: Identifiable {
    let id = UUID()
    let reason: LocalBridgeDemandReason

    private weak var owner: AppState?
    private var released = false

    init(reason: LocalBridgeDemandReason, owner: AppState) {
        self.reason = reason
        self.owner = owner
    }

    deinit {
        guard !released else { return }
        let owner = owner
        let id = id
        let reason = reason
        Task { @MainActor in
            owner?.releaseLocalBridge(id: id, reason: reason)
        }
    }

    func release() {
        guard !released else { return }
        released = true
        owner?.releaseLocalBridge(id: id, reason: reason)
    }
}

protocol LocalBridgeHelperLaunching: AnyObject {
    @MainActor var isRunning: Bool { get }
    @MainActor func start() -> Bool
    @MainActor func stop()
}

@MainActor
final class ProcessLocalBridgeHelperLauncher: LocalBridgeHelperLaunching {
    private var process: Process?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start() -> Bool {
        if isRunning { return true }
        guard let helperURL = Self.resolveHelperURL() else {
            BridgeLog.write("demand-bridge-helper-missing")
            return false
        }

        let proc = Process()
        proc.executableURL = helperURL
        var env = ProcessInfo.processInfo.environment
        env["CLAWIX_BRIDGE_DEFAULTS_SUITE"] = ClawixPersistentSurfaceKeys.bridgeDefaultsSuite
        env["CLAWIX_BRIDGE_PORT"] = "\(BridgeAgentControl.bridgePort)"
        env["CLAWIX_BRIDGE_HTTP_PORT"] = "\(MeshClient.defaultHTTPPort)"
        proc.environment = env
        proc.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                guard self?.process === terminated else { return }
                self?.process = nil
                BridgeLog.write("demand-bridge-helper-exited status=\(terminated.terminationStatus)")
            }
        }

        do {
            try proc.run()
            process = proc
            BridgeLog.write("demand-bridge-helper-started pid=\(proc.processIdentifier)")
            return true
        } catch {
            BridgeLog.write("demand-bridge-helper-start-failed \(error)")
            return false
        }
    }

    func stop() {
        guard let proc = process else { return }
        process = nil
        guard proc.isRunning else { return }
        BridgeLog.write("demand-bridge-helper-stop pid=\(proc.processIdentifier)")
        proc.terminate()
    }

    private static func resolveHelperURL() -> URL? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        if let override = env["CLAWIX_BRIDGE_HELPER_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }

        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/clawix-bridge", isDirectory: false)
        if fm.isExecutableFile(atPath: bundled.path) { return bundled }

        if let auxiliary = Bundle.main.url(forAuxiliaryExecutable: "clawix-bridge"),
           fm.isExecutableFile(atPath: auxiliary.path) {
            return auxiliary
        }

        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let adjacent = executableDir.appendingPathComponent("clawix-bridge", isDirectory: false)
            if fm.isExecutableFile(atPath: adjacent.path) { return adjacent }
        }

        return nil
    }
}
