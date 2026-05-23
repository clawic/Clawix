import Foundation

final class ClawJSProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [ClawJSService: Process] = [:]

    func register(_ process: Process, for service: ClawJSService) {
        lock.lock()
        processes[service] = process
        lock.unlock()
    }

    func unregister(_ service: ClawJSService) {
        lock.lock()
        processes[service] = nil
        lock.unlock()
    }

    func unregisterAll() {
        lock.lock()
        processes.removeAll()
        lock.unlock()
    }

    func terminateAllSynchronously() {
        lock.lock()
        let running = Array(processes.values)
        processes.removeAll()
        lock.unlock()

        for process in running where process.isRunning {
            process.terminate()
        }
    }
}

struct ClawJSAsyncProcessResult: Equatable {
    var terminationStatus: Int32
    var standardOutput: Data
}

enum ClawJSAsyncProcessRunner {
    enum Error: Swift.Error, Equatable {
        case missingExecutable(String)
        case timedOut
    }

    static func run(
        executable: String,
        arguments: [String],
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> ClawJSAsyncProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw Error.missingExecutable(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let timeoutState = ClawJSAsyncProcessTimeoutState()

        return try await withThrowingTaskGroup(of: ClawJSAsyncProcessResult.self) { group in
            group.addTask {
                let result = try await waitForExit(process: process, pipe: pipe)
                if timeoutState.didTimeOut {
                    throw Error.timedOut
                }
                return result
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                timeoutState.markTimedOut()
                if process.isRunning {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                throw Error.timedOut
            }

            guard let result = try await group.next() else {
                throw Error.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    private static func waitForExit(process: Process, pipe: Pipe) async throws -> ClawJSAsyncProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ClawJSAsyncProcessResult(
                    terminationStatus: proc.terminationStatus,
                    standardOutput: output
                ))
            }
        }
    }
}

private final class ClawJSAsyncProcessTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

enum ClawJSMacProcessToolRoutes {
    static let shell = ClawixSystemToolRoutes.shellCLI
    static let lsof = ClawixSystemToolRoutes.lsofCLI
    static let ps = ClawixSystemToolRoutes.psCLI
    static let nullDevice = ClawixTemporaryRoutes.nullDevicePath
    static let bundledClawJSSidecarFragment = "/Clawix.app/Contents/Resources/clawjs/"
    static let appSupportClawJSSidecarFragment = "/Application Support/Clawix/clawjs/"

    static func listenerPIDCommand(port: UInt16) -> String {
        "\(lsof) -nP -tiTCP:\(port) -sTCP:LISTEN 2>\(nullDevice) | head -n 1"
    }
}

enum ClawJSProcessInspector {
    static func listenerPID(on port: UInt16) async throws -> pid_t? {
        let result = try await ClawJSAsyncProcessRunner.run(
            executable: ClawJSMacProcessToolRoutes.shell,
            arguments: ["-c", ClawJSMacProcessToolRoutes.listenerPIDCommand(port: port)]
        )
        let raw = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let value = Int32(raw) else { return nil }
        return value
    }

    static func isClawixSidecar(pid: pid_t) async throws -> Bool {
        let result = try await ClawJSAsyncProcessRunner.run(
            executable: ClawJSMacProcessToolRoutes.ps,
            arguments: ["-p", String(pid), "-o", "command="]
        )
        let command = String(data: result.standardOutput, encoding: .utf8) ?? ""
        return command.contains(ClawJSMacProcessToolRoutes.bundledClawJSSidecarFragment)
            || command.contains(ClawJSMacProcessToolRoutes.appSupportClawJSSidecarFragment)
    }

    static func parentPID(of pid: pid_t) async throws -> pid_t? {
        let result = try await ClawJSAsyncProcessRunner.run(
            executable: ClawJSMacProcessToolRoutes.ps,
            arguments: ["-p", String(pid), "-o", "ppid="]
        )
        let raw = String(data: result.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let value = Int32(raw) else { return nil }
        return value
    }
}
