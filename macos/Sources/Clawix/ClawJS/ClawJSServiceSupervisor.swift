import Foundation
import ClawixCore
import SecretsCrypto

/// Non-main actor that owns ClawJS sidecar process supervision.
///
/// `commandLine(for:)` maps each service to the concrete command that
/// the bundled ClawJS runtime actually exposes. Services whose launch
/// surface is missing publish `.blocked(reason:)` instead of crashing.
///
/// When a background bridge daemon is actually reachable, the GUI first
/// probes daemon-owned ports. If the daemon is alive but does not serve a
/// ClawJS surface, the GUI falls back to owning that surface locally.
actor ClawJSServiceSupervisor {

    private var snapshots: [ClawJSService: ClawJSServiceSnapshot]
    private let publisher: ClawJSServiceStatePublisher
    private nonisolated let processRegistry: ClawJSProcessRegistry

    /// Restart budget per service. After this many crashes inside one
    /// boot the manager gives up and parks the service in `.crashed`
    /// with an explanatory reason instead of looping forever.
    static let restartBudget = 5

    /// Backoff schedule (seconds): 1, 2, 4, 8, 16, capped at 60. Used
    /// when a process crashes; reset to zero after the service stays
    /// healthy for `healthyResetWindow`.
    private static let backoffSchedule: [UInt64] = [1, 2, 4, 8, 16, 32, 60]
    private static let healthyResetWindow: TimeInterval = 60

    private var processes: [ClawJSService: Process] = [:]
    private var logHandles: [ClawJSService: FileHandle] = [:]
    private var monitorTask: Task<Void, Never>?
    private var serviceMonitors: [ClawJSService: ServiceMonitor] = [:]
    private var restartTasks: [ClawJSService: Task<Void, Never>] = [:]
    private var lastReadyAt: [ClawJSService: Date] = [:]

    /// Per-session admin tokens (32-byte URL-safe random) injected to the
    /// daemons that authenticate admin requests. Generated lazily the first
    /// time the GUI spawns each daemon. Replaces the previous Keychain-backed
    /// admin password so the app never touches the system Keychain.
    private var sessionAdminTokens: [ClawJSService: String] = [:]
    private var sessionSignedHostTokens: [ClawJSService: String] = [:]
    private var sessionHostAssertionKeys: [ClawJSService: String] = [:]

    /// Services that need a per-session bearer/shared token. The token is
    /// bootstrapped over anonymous stdin, never process environment or disk.
    private static let adminTokenEnvVar: [ClawJSService: String] = [
        .runtime: "RUNTIME_SHARED_SECRET",
        .database: "CLAW_DATABASE_ADMIN_TOKEN",
        .drive: "CLAW_DRIVE_ADMIN_TOKEN",
        .secrets: "CLAW_SECRETS_ADMIN_TOKEN",
        .audio: "CLAW_AUDIO_SHARED_SECRET",
        .index: "CLAW_SEARCH_ADMIN_TOKEN",
        .sessions: "CLAW_SESSIONS_SHARED_SECRET",
        .publishing: "CLAW_PUBLISHING_TOKEN",
    ]

    private enum ServiceMonitorMode: Equatable {
        case local(pid: pid_t)
        case daemonOwned
    }

    private struct ServiceMonitor: Equatable {
        var mode: ServiceMonitorMode
        var readyDeadline: Date
        var hasReachedReady: Bool
        var consecutiveFailures: Int
        var nextProbeAt: Date
        var lastDaemonUpdateAt: Date?
    }

    private static let localStartupProbeInterval: TimeInterval = 1
    private static let localReadyProbeInterval: TimeInterval = 5
    private static let daemonStartupProbeInterval: TimeInterval = 1
    private static let daemonFallbackProbeInterval: TimeInterval = 15
    private static let daemonPushFreshWindow: TimeInterval = 30

    init(
        snapshots: [ClawJSService: ClawJSServiceSnapshot],
        publisher: ClawJSServiceStatePublisher,
        processRegistry: ClawJSProcessRegistry
    ) {
        self.snapshots = snapshots
        self.publisher = publisher
        self.processRegistry = processRegistry
    }

    // MARK: - Actor API

    func currentSnapshots() -> [ClawJSService: ClawJSServiceSnapshot] {
        snapshots
    }

    func sessionTokens() -> ClawJSSessionTokenSnapshot {
        ClawJSSessionTokenSnapshot(
            adminTokens: sessionAdminTokens,
            signedHostTokens: sessionSignedHostTokens,
            hostAssertionKeys: sessionHostAssertionKeys
        )
    }

    func applyDaemonServiceStatuses(_ services: [WireClawJSServiceSnapshot]) {
        for wire in services {
            guard let service = ClawJSService(rawValue: wire.id) else { continue }
            applyDaemonServiceStatus(wire, to: service)
        }
    }

    /// Boots the requested services. Idempotent: a service in `.starting` or
    /// `.ready` is left alone. When the bridge daemon is reachable the GUI
    /// probes daemon-owned loopback ports first, then falls back locally for
    /// surfaces the daemon does not provide.
    func start(
        _ services: Set<ClawJSService>,
        reason _: ClawJSServiceStartReason,
        daemonReachable: Bool
    ) async {
        guard !services.isEmpty else { return }
        if daemonReachable {
            await startDaemonAwareServices(services)
            return
        }
        for service in orderedServices(from: services) {
            await launchLocal(service)
        }
    }

    func markServicesAvailableOnDemand(excluding activeServices: Set<ClawJSService>) {
        for service in ClawJSService.allCases where !activeServices.contains(service) {
            guard let trigger = ClawJSServiceDemandPolicy.onDemandTrigger(for: service) else { continue }
            update(service) { snap in
                switch snap.state {
                case .idle, .availableOnDemand:
                    snap.state = .availableOnDemand(trigger: trigger)
                    snap.lastError = nil
                case .starting, .ready, .readyFromDaemon, .blocked, .crashed, .daemonUnavailable:
                    break
                }
            }
        }
    }

    /// Forces a single service back through the launch pipeline. Resets
    /// the restart counter so a service in `.crashed (budget exhausted)`
    /// gets another shot. Used by the Settings UI's "Restart" button.
    func restart(_ service: ClawJSService, daemonReachable: Bool) async {
        restartTasks[service]?.cancel()
        restartTasks[service] = nil
        let stoppedLocalProcess = await stopTrackedProcess(for: service)
        update(service) {
            $0.restartCount = 0
            $0.lastError = nil
            $0.state = .idle
        }
        if stoppedLocalProcess {
            await launchLocal(service, force: true)
            return
        }
        if daemonReachable {
            update(service) { $0.state = .starting }
            monitorDaemonOwnedService(service, readyTimeout: 6)
            return
        }
        await launchLocal(service)
    }


    private func stopTrackedProcess(for service: ClawJSService) async -> Bool {
        guard let process = processes.removeValue(forKey: service) else { return false }
        processRegistry.unregister(service)

        process.terminationHandler = nil
        serviceMonitors[service] = nil

        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline, process.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        try? logHandles[service]?.close()
        logHandles[service] = nil
        return true
    }

    /// Synchronous SIGTERM to every running service plus cancellation of
    /// pending restart / healthz tasks. Safe to call from
    /// `applicationWillTerminate` (which cannot `await`). macOS SIGKILLs
    /// any straggler when the parent process exits, so this is enough
    /// for the shutdown path; the `tearDown()` async variant exists for
    /// explicit teardown during tests or hot-reload flows.
    nonisolated func terminateAllSynchronously() {
        processRegistry.terminateAllSynchronously()
        Task { [weak self] in
            await self?.cancelSupervisionTasks()
        }
    }

    private func cancelSupervisionTasks() {
        for task in restartTasks.values { task.cancel() }
        restartTasks.removeAll()
        monitorTask?.cancel()
        monitorTask = nil
        serviceMonitors.removeAll()
    }

    /// SIGTERM with a 3 s grace, then SIGKILL stragglers. Cancels every
    /// pending restart and `/healthz` task so nothing tries to re-spawn
    /// while the app is going down. Used by tests and hot-reload paths;
    /// the production `applicationWillTerminate` uses
    /// `terminateAllSynchronously()` instead because it cannot await.
    func tearDown() async {
        for task in restartTasks.values { task.cancel() }
        restartTasks.removeAll()
        monitorTask?.cancel()
        monitorTask = nil
        serviceMonitors.removeAll()

        let running = processes
        processes.removeAll()
        processRegistry.unregisterAll()

        for process in running.values {
            process.terminate()
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline,
              running.values.contains(where: { $0.isRunning }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for process in running.values where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        for handle in logHandles.values {
            try? handle.close()
        }
        logHandles.removeAll()

        for service in ClawJSService.allCases {
            update(service) { $0.state = .idle }
        }
    }

    // MARK: - Per-service launch

    private func launchLocal(_ service: ClawJSService, force: Bool = false) async {
        if !force {
            switch snapshots[service]?.state {
            case .starting, .ready, .readyFromDaemon:
                return
            default:
                break
            }
        }

        guard await preparePortForLocalLaunch(service) else { return }

        // IoT runs from the clawjs/iot package, not from @clawjs/cli, so
        // it bypasses the bundled-runtime guard below. Development reads
        // the location from a dev pointer dev.sh writes; production builds
        // substitute a bundled copy under Contents/Resources/.
        if service == .iot {
            guard let projectDir = iotProjectDirectory() else {
                update(service) {
                    $0.state = .blocked(reason:
                        "IoT runtime pointer is missing. Re-run dev.sh to wire it.")
                }
                return
            }
            await spawnIot(projectDir: projectDir)
            return
        }

        // Guard 1: the bundled tree must exist. dev.sh / build_release_app.sh
        // call `bundle_clawjs.sh` to plant Contents/Helpers/clawjs/; if that
        // step was skipped or failed, we cannot spawn anything.
        guard ClawJSRuntime.isAvailable else {
            update(service) {
                $0.state = .blocked(reason:
                    "ClawJS bundle is not available in this build. Rebuild with ClawJS bundling enabled.")
            }
            return
        }

        guard commandLine(for: service) != nil else {
            update(service) {
                $0.state = .blocked(reason:
                    "@clawjs/cli@\(ClawJSRuntime.expectedVersion) does not expose a launch command for \(service.displayName)")
            }
            return
        }

        await spawnAndSupervise(service)
    }

    private func preparePortForLocalLaunch(_ service: ClawJSService) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(service.port)\(service.healthPath)")!
        guard await ping(url: url) else { return true }

        if Self.canAdoptExistingService(service) {
            lastReadyAt[service] = Date()
            update(service) {
                $0.state = .readyFromDaemon(port: service.port)
                $0.lastError = nil
            }
            monitorDaemonOwnedService(service, readyTimeout: 6, reachedReady: true)
            return false
        }

        guard let pid = await Self.listenerPID(on: service.port),
              await Self.isClawixSidecar(pid: pid) else {
            let reason = "\(service.displayName) port \(service.port) is already in use by another process."
            update(service) {
                $0.state = .crashed(reason: reason)
                $0.lastError = reason
            }
            return false
        }

        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, Self.isRunning(pid: pid) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if Self.isRunning(pid: pid) {
            kill(pid, SIGKILL)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
    }

    private func orderedServices(from services: Set<ClawJSService>) -> [ClawJSService] {
        ClawJSService.allCases.filter { services.contains($0) }
    }

    private func startDaemonOwnedProbes(_ services: Set<ClawJSService>) {
        for service in orderedServices(from: services) {
            update(service) {
                $0.lastError = nil
                $0.state = .starting
            }
            monitorDaemonOwnedService(service, readyTimeout: 6)
        }
    }

    private func startDaemonAwareServices(_ services: Set<ClawJSService>) async {
        for service in orderedServices(from: services) {
            serviceMonitors[service] = nil
            let url = URL(string: "http://127.0.0.1:\(service.port)\(service.healthPath)")!
            if await ping(url: url) {
                if await Self.reclaimOrphanedSidecarIfPossible(service) {
                    await launchLocal(service, force: true)
                } else if Self.canAdoptExistingService(service) {
                    publishDaemonReady(service)
                } else {
                    markReachableServiceUnavailable(service)
                }
                if snapshots[service]?.state == .readyFromDaemon(port: service.port) {
                    monitorDaemonOwnedService(service, readyTimeout: 6, reachedReady: true)
                }
            } else if ClawJSRuntime.isAvailable, commandLine(for: service) != nil {
                await launchLocal(service, force: true)
            } else {
                let reason = "\(service.displayName) is not reachable on 127.0.0.1:\(service.port) while the bridge daemon is active."
                update(service) {
                    $0.state = .daemonUnavailable(reason: reason)
                    $0.lastError = reason
                }
            }
        }
    }

    private func monitorDaemonOwnedService(
        _ service: ClawJSService,
        readyTimeout: TimeInterval,
        reachedReady: Bool = false
    ) {
        let now = Date()
        serviceMonitors[service] = ServiceMonitor(
            mode: .daemonOwned,
            readyDeadline: now.addingTimeInterval(readyTimeout),
            hasReachedReady: reachedReady,
            consecutiveFailures: 0,
            nextProbeAt: reachedReady
                ? now.addingTimeInterval(Self.daemonFallbackProbeInterval)
                : now,
            lastDaemonUpdateAt: reachedReady ? now : nil
        )
        ensureMonitorTask()
    }

    private func publishDaemonReady(_ service: ClawJSService) {
        lastReadyAt[service] = Date()
        update(service) {
            $0.state = .readyFromDaemon(port: service.port)
            $0.lastError = nil
        }
    }

    private func markReachableServiceUnavailable(_ service: ClawJSService) {
        let reason = "\(service.displayName) answered on 127.0.0.1:\(service.port), but its admin token is not available."
        update(service) {
            $0.state = .daemonUnavailable(reason: reason)
            $0.lastError = reason
        }
    }

    private nonisolated static func reclaimOrphanedSidecarIfPossible(_ service: ClawJSService) async -> Bool {
        guard let pid = await Self.listenerPID(on: service.port),
              await Self.isClawixSidecar(pid: pid) else {
            return false
        }

        let targets: [pid_t]
        if await Self.parentPID(of: pid) == 1 {
            targets = [pid]
        } else if let parent = await Self.parentPID(of: pid),
                  await Self.isClawixSidecar(pid: parent),
                  await Self.parentPID(of: parent) == 1 {
            targets = [pid, parent]
        } else {
            return false
        }

        for target in Self.uniquePIDs(targets) {
            kill(target, SIGTERM)
        }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, Self.uniquePIDs(targets).contains(where: { Self.isRunning(pid: $0) }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for target in Self.uniquePIDs(targets) where Self.isRunning(pid: target) {
            kill(target, SIGKILL)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return true
    }

    /// Argv (without the leading node binary) to launch `service` as a
    /// long-lived HTTP server on `service.port`. Returns `nil` while the
    /// bundled runtime lacks that service's surface.
    private func commandLine(for service: ClawJSService) -> [String]? {
        // IoT does not flow through @clawjs/cli; the dedicated `spawnIot`
        // path owns its argv. Returning nil here keeps the existing
        // `commandLine(for:) != nil` guard a no-op for IoT.
        if service == .iot { return nil }
        // Publishing lives at `node_modules/publishing/dist/server.js`; it has no
        // launcher under `@clawjs/cli/bin/`. Spawn the server entry directly
        // with the bundled node binary so the rest of the supervisor (env,
        // logs, healthz) keeps working as-is.
        if service == .publishing {
            let serverJs = ClawJSRuntime.bundleRootURL
                .appendingPathComponent("node_modules/publishing/dist/server.js", isDirectory: false)
            guard FileManager.default.fileExists(atPath: serverJs.path) else { return nil }
            return [serverJs.path]
        }
        if service == .runtime {
            let packageURL = ClawJSRuntime.bundleRootURL
                .appendingPathComponent("node_modules/@clawjs/runtime/package.json", isDirectory: false)
            guard FileManager.default.fileExists(atPath: packageURL.path) else { return nil }
            return [
                "--input-type=module",
                "--eval",
                """
                import { buildRuntimeApp } from '@clawjs/runtime';
                const app = buildRuntimeApp();
                const host = process.env.RUNTIME_HOST || process.env.HOST || '127.0.0.1';
                const port = Number(process.env.RUNTIME_PORT || process.env.PORT || '24100');
                await app.listen({ host, port });
                """
            ]
        }

        guard Self.bundledLauncherScript(for: service) != nil else { return nil }

        var arguments = [
            ClawJSRuntime.cliScriptURL.path,
            "open", service.rawValue,
            "--host", "127.0.0.1",
            "--port", String(service.port),
            "--workspace", Self.workspaceURL.path,
            "--status-file", Self.statusFileURL(for: service).path,
        ]

        switch service {
        case .runtime:
            return arguments
        case .database:
            arguments += [
                "--data-dir", Self.mainDataDirectoryURL.path,
                "--db-path", Self.mainDatabaseURL.path,
                "--files-dir", Self.mainFilesDirectoryURL.path,
            ]
            return arguments
        case .secrets, .telegram:
            return arguments
        case .memory, .drive, .sessions:
            arguments += ["--data-dir", Self.dataDirectoryURL(for: service).path]
            if service == .sessions {
                arguments += [
                    "--db-path", Self.dataDirectoryURL(for: service)
                        .appendingPathComponent(ClawixPersistentSurfacePaths.components.sessionsDatabase, isDirectory: false).path,
                ]
            }
            return arguments
        case .audio:
            arguments += [
                "--data-dir", Self.dataDirectoryURL(for: service).path,
                "--blobs-dir", Self.dataDirectoryURL(for: service)
                    .appendingPathComponent(ClawixPersistentSurfacePaths.components.blobs, isDirectory: true).path,
            ]
            return arguments
        case .index:
            arguments += [
                "--data-dir", Self.dataDirectoryURL(for: service).path,
                "--db-path", Self.dataDirectoryURL(for: service)
                    .appendingPathComponent(ClawixPersistentSurfacePaths.components.indexDatabase, isDirectory: false).path,
            ]
            return arguments
        case .iot, .publishing:
            // Unreachable: both are guarded above with dedicated launch
            // paths. Kept for switch exhaustiveness.
            return nil
        }
    }

    // MARK: - Spawn + supervise

    /// Full spawn pipeline. Dormant today (commandLine returns nil), but
    /// fully wired so flipping that one method enables the whole flow.
    private func spawnAndSupervise(_ service: ClawJSService) async {
        guard let extraArgs = commandLine(for: service) else { return }
        update(service) { $0.state = .starting; $0.lastError = nil }

        do {
            try Self.prepareDirectories(for: service)

            let adminToken = ensureAdminToken(for: service)
            let signedHostToken = ensureSignedHostToken(for: service)
            let hostAssertionKey = ensureHostAssertionKey(for: service)

            let process = Process()
            process.executableURL = ClawJSRuntime.nodeBinaryURL
            process.arguments = extraArgs
            process.currentDirectoryURL = Self.workspaceURL
            process.environment = Self.environment(
                for: service,
                adminToken: adminToken,
                signedHostToken: signedHostToken
            )
            let bootstrapPipe: Pipe?
            let bootstrapData: Data?
            if service == .secrets {
                bootstrapPipe = Pipe()
                bootstrapData = try Self.secretsBootstrapPayload(
                    adminToken: adminToken,
                    signedHostToken: signedHostToken,
                    hostAssertionKeyBase64: hostAssertionKey,
                    platformKey: try SecretsPlatformKey.loadOrCreate()
                )
                process.standardInput = bootstrapPipe
            } else if let adminToken {
                bootstrapPipe = Pipe()
                bootstrapData = try Self.localAdminBootstrapPayload(adminToken: adminToken)
                process.standardInput = bootstrapPipe
            } else {
                bootstrapPipe = nil
                bootstrapData = nil
            }

            let logURL = Self.logFileURL(for: service)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
            logHandles[service] = handle

            process.terminationHandler = { [weak self] proc in
                Task { [weak self] in
                    await self?.handleTermination(of: service, process: proc)
                }
            }

            try process.run()
            if let bootstrapPipe, let bootstrapData {
                bootstrapPipe.fileHandleForWriting.write(bootstrapData)
                try? bootstrapPipe.fileHandleForWriting.close()
            }
            processes[service] = process
            processRegistry.register(process, for: service)

            // The aggregate monitor flips state to `.ready` once the
            // service responds; it also detects soft hangs (process alive
            // but no longer answering) and triggers a restart.
            monitorLocalService(service, pid: process.processIdentifier)
        } catch {
            update(service) {
                $0.state = .crashed(reason: "spawn failed: \(error.localizedDescription)")
                $0.lastError = error.localizedDescription
            }
            scheduleRestart(service)
        }
    }

    private func handleTermination(of service: ClawJSService, process proc: Process) {
        guard processes[service] === proc else { return }
        processes[service] = nil
        processRegistry.unregister(service)
        try? logHandles[service]?.close()
        logHandles[service] = nil
        serviceMonitors[service] = nil

        let status = proc.terminationStatus
        let signalled = proc.terminationReason == .uncaughtSignal
        if status == 0 || signalled {
            // Clean exit (most likely tearDown). Park as idle, no restart.
            update(service) { $0.state = .idle }
            return
        }
        update(service) {
            $0.state = .crashed(reason: "exit status \(status)")
            $0.lastError = "exit \(status)"
        }
        scheduleRestart(service)
    }

    private func scheduleRestart(_ service: ClawJSService) {
        guard var snap = snapshots[service] else { return }
        // Reset the counter if the service was alive long enough since
        // its last `.ready` transition.
        if let lastReady = lastReadyAt[service],
           Date().timeIntervalSince(lastReady) > Self.healthyResetWindow {
            snap.restartCount = 0
            snapshots[service] = snap
        }
        guard snap.restartCount < Self.restartBudget else {
            update(service) {
                $0.state = .crashed(reason: "restart budget (\(Self.restartBudget)) exhausted; not retrying")
            }
            return
        }
        let delay = Self.backoffSchedule[min(snap.restartCount, Self.backoffSchedule.count - 1)]
        update(service) { $0.restartCount += 1 }

        restartTasks[service]?.cancel()
        restartTasks[service] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.launchLocal(service)
        }
    }

    // MARK: - Aggregate health supervision

    private func monitorLocalService(_ service: ClawJSService, pid: pid_t) {
        let now = Date()
        serviceMonitors[service] = ServiceMonitor(
            mode: .local(pid: pid),
            readyDeadline: now.addingTimeInterval(15),
            hasReachedReady: false,
            consecutiveFailures: 0,
            nextProbeAt: now,
            lastDaemonUpdateAt: nil
        )
        ensureMonitorTask()
    }

    private func ensureMonitorTask() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            await self?.runAggregateMonitor()
        }
    }

    private func runAggregateMonitor() async {
        while !Task.isCancelled {
            let sleepSeconds = await monitorDueServices()
            guard let sleepSeconds else { break }
            let nanoseconds = UInt64(max(0.05, sleepSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
        monitorTask = nil
    }

    private func monitorDueServices() async -> TimeInterval? {
        let now = Date()
        let due = orderedServices(from: Set(serviceMonitors.keys)).filter {
            serviceMonitors[$0]?.nextProbeAt ?? .distantFuture <= now
        }

        if !due.isEmpty {
            PerfSignpost.serviceSupervisor.event("monitor.wakeup")
            PerfSignpost.serviceSupervisor.event("monitor.due_services", due.count)
        }

        for service in due {
            await probeMonitoredService(service, now: Date())
        }

        guard !serviceMonitors.isEmpty else { return nil }
        let next = serviceMonitors.values.map(\.nextProbeAt).min() ?? Date().addingTimeInterval(1)
        return max(0.05, next.timeIntervalSince(Date()))
    }

    private func probeMonitoredService(_ service: ClawJSService, now: Date) async {
        guard let monitor = serviceMonitors[service] else { return }
        let updated: ServiceMonitor?
        switch monitor.mode {
        case .local(let pid):
            updated = await probeLocalService(service, pid: pid, monitor: monitor, now: now)
        case .daemonOwned:
            updated = await probeDaemonOwnedService(service, monitor: monitor, now: now)
        }
        if let updated {
            serviceMonitors[service] = updated
        } else if serviceMonitors[service] == monitor {
            serviceMonitors[service] = nil
        }
    }

    private func probeLocalService(
        _ service: ClawJSService,
        pid: pid_t,
        monitor: ServiceMonitor,
        now: Date
    ) async -> ServiceMonitor? {
        var monitor = monitor
        guard let process = processes[service], process.isRunning else {
            return nil
        }

        let alive = await pingService(service)
        if alive {
            monitor.consecutiveFailures = 0
            if !monitor.hasReachedReady {
                monitor.hasReachedReady = true
                lastReadyAt[service] = now
                update(service) { $0.state = .ready(pid: pid, port: service.port) }
            }
            monitor.nextProbeAt = now.addingTimeInterval(Self.localReadyProbeInterval)
            return monitor
        }

        monitor.consecutiveFailures += 1
        monitor.nextProbeAt = now.addingTimeInterval(Self.localStartupProbeInterval)
        if !monitor.hasReachedReady, now > monitor.readyDeadline {
            update(service) {
                $0.state = .crashed(reason: "did not become ready within 15s")
            }
            process.terminate()
            return nil
        }
        if monitor.hasReachedReady, monitor.consecutiveFailures >= 5 {
            update(service) {
                $0.state = .crashed(reason: "\(service.healthPath) silent for 5 consecutive checks")
            }
            process.terminate()
            return nil
        }
        return monitor
    }

    private func probeDaemonOwnedService(
        _ service: ClawJSService,
        monitor: ServiceMonitor,
        now: Date
    ) async -> ServiceMonitor? {
        var monitor = monitor
        if let lastDaemonUpdateAt = monitor.lastDaemonUpdateAt,
           now.timeIntervalSince(lastDaemonUpdateAt) < Self.daemonPushFreshWindow {
            monitor.nextProbeAt = lastDaemonUpdateAt.addingTimeInterval(Self.daemonPushFreshWindow)
            PerfSignpost.serviceSupervisor.event("monitor.daemon_push_fresh")
            return monitor
        }

        PerfSignpost.serviceSupervisor.event("daemon_fallback_probe")
        let alive = await pingService(service)
        if alive {
            monitor.consecutiveFailures = 0
            monitor.hasReachedReady = true
            if Self.canAdoptExistingService(service) {
                publishDaemonReady(service)
            } else {
                markReachableServiceUnavailable(service)
            }
            monitor.nextProbeAt = now.addingTimeInterval(Self.daemonFallbackProbeInterval)
            return monitor
        }

        monitor.consecutiveFailures += 1
        monitor.nextProbeAt = now.addingTimeInterval(Self.daemonStartupProbeInterval)
        if monitor.hasReachedReady || now > monitor.readyDeadline {
            if ClawJSRuntime.isAvailable, commandLine(for: service) != nil {
                await launchLocal(service, force: true)
                return nil
            }
            let reason = "\(service.displayName) is not reachable on 127.0.0.1:\(service.port) while the bridge daemon is active."
            update(service) {
                $0.state = .daemonUnavailable(reason: reason)
                $0.lastError = reason
            }
        }
        return monitor
    }

    private func pingService(_ service: ClawJSService) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(service.port)\(service.healthPath)")!
        return await ping(url: url)
    }

    private func ping(url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Paths and environment

    /// Single workspace shared by services for process cwd and runtime
    /// artifacts that are not the canonical ClawJS data store.
    nonisolated static var workspaceURL: URL {
        applicationSupportRoot.appendingPathComponent("workspace", isDirectory: true)
    }

    nonisolated static var applicationSupportRoot: URL {
        let env = ProcessInfo.processInfo.environment
        if env[ClawixEnv.dummyMode] == "1", let root = env[ClawixEnv.backendHome], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawjs, isDirectory: true)
    }

    nonisolated static var mainDataDirectoryURL: URL {
        applicationSupportRoot
    }

    nonisolated static var mainDatabaseURL: URL {
        mainDataDirectoryURL.appendingPathComponent(ClawixPersistentSurfacePaths.components.sqlite, isDirectory: false)
    }

    nonisolated static var mainFilesDirectoryURL: URL {
        mainDataDirectoryURL.appendingPathComponent(ClawixPersistentSurfacePaths.components.files, isDirectory: true)
    }

    private nonisolated static var frameworkGlobalRootURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env[ClawEnv.home], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawWorkspace, isDirectory: true)
    }

    private nonisolated static var frameworkSecretsDirectoryURL: URL {
        frameworkGlobalRootURL
            .appendingPathComponent("secrets", isDirectory: true)
    }

    nonisolated static func logFileURL(for service: ClawJSService) -> URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.logs, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return logs.appendingPathComponent("clawjs-\(service.rawValue).log", isDirectory: false)
    }

    nonisolated static func statusFileURL(for service: ClawJSService) -> URL {
        applicationSupportRoot
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.status, isDirectory: true)
            .appendingPathComponent("\(service.rawValue).json", isDirectory: false)
    }

    private nonisolated static func prepareDirectories(for service: ClawJSService) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: logFileURL(for: service).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: statusFileURL(for: service).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: dataDirectoryURL(for: service),
            withIntermediateDirectories: true
        )
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dataDirectoryURL(for: service).path)
        if Self.adminTokenEnvVar[service] != nil {
            for tokenURL in staleAdminTokenURLs(for: service) {
                try? fm.removeItem(at: tokenURL)
            }
        }
        try fm.createDirectory(
            at: mainFilesDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    nonisolated static func cliEnvironment() -> [String: String] {
        environment(for: .database, adminToken: nil, signedHostToken: nil)
    }

    private nonisolated static func environment(
        for service: ClawJSService,
        adminToken: String?,
        signedHostToken: String?
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for tokenEnvVar in adminTokenEnvVar.values {
            env.removeValue(forKey: tokenEnvVar)
        }
        env.removeValue(forKey: "CLAW_SECRETS_TOKEN")
        env.removeValue(forKey: "CLAW_SECRETS_KEK_BASE64")
        env.removeValue(forKey: "CLAW_SECRETS_HOST_ASSERTION_KEY_BASE64")
        env["HOME"] = applicationSupportRoot.appendingPathComponent("home").path
        env["CLAW_WORKSPACE"] = workspaceURL.path
        env["CLAW_HOME"] = frameworkGlobalRootURL.path
        env["CLAW_DATA_DIR"] = mainDataDirectoryURL.path
        env["CLAW_DB_PATH"] = mainDatabaseURL.path
        env["CLAW_FILES_DIR"] = mainFilesDirectoryURL.path
        env["CLAW_SERVICE_PORT"] = String(service.port)
        env["CLAW_SERVICE_NAME"] = service.rawValue
        env["RUNTIME_HOST"] = "127.0.0.1"
        env["RUNTIME_PORT"] = String(ClawJSService.runtime.port)
        env["RUNTIME_DATA_DIR"] = dataDirectoryURL(for: .runtime).path
        env["RUNTIME_DB_PATH"] = dataDirectoryURL(for: .runtime)
            .appendingPathComponent("runtime.sqlite", isDirectory: false).path
        env["CLAW_RUNTIME_SESSIONS_URL"] = "http://127.0.0.1:\(ClawJSService.sessions.port)"
        for (key, value) in ClawJSActorAssertion.environment() {
            env[key] = value
        }
        env["CLAW_SECRETS_PROXY_PATH"] = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("bin/secrets-proxy", isDirectory: false)
            .path
        env["PORT"] = String(service.port)
        env["HOST"] = "127.0.0.1"
        env["CLAW_DATABASE_HOST"] = "127.0.0.1"
        env["CLAW_DATABASE_PORT"] = String(ClawJSService.database.port)
        env["CLAW_DATABASE_DATA_DIR"] = mainDataDirectoryURL.path
        env["CLAW_DATABASE_DB_PATH"] = mainDatabaseURL.path
        env["CLAW_DATABASE_FILES_DIR"] = mainFilesDirectoryURL.path
        env["CLAW_DRIVE_HOST"] = "127.0.0.1"
        env["CLAW_DRIVE_PORT"] = String(ClawJSService.drive.port)
        env["CLAW_DRIVE_DATA_DIR"] = dataDirectoryURL(for: .drive).path
        env["CLAW_SESSIONS_HOST"] = "127.0.0.1"
        env["CLAW_SESSIONS_PORT"] = String(ClawJSService.sessions.port)
        env["CLAW_SESSIONS_DATA_DIR"] = dataDirectoryURL(for: .sessions).path
        env["CLAW_SESSIONS_DB_PATH"] = dataDirectoryURL(for: .sessions)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sessionsDatabase, isDirectory: false).path
        env["CLAW_SECRETS_HOST"] = "127.0.0.1"
        env["CLAW_SECRETS_PORT"] = String(ClawJSService.secrets.port)
        env["CLAW_SECRETS_DATA_DIR"] = dataDirectoryURL(for: .secrets).path
        env["CLAW_SECRETS_DB_PATH"] = dataDirectoryURL(for: .secrets)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.secretsDatabase, isDirectory: false).path
        env["CLAW_SECRETS_BASE_URL"] = "http://127.0.0.1:\(ClawJSService.secrets.port)"
        env["CLAW_SECRETS_TENANT_ID"] = ClawJSSecretsClient.defaultTenantId
        // The Telegram surface reads its own variables (the CLI normally
        // sets these, but pin them here too so a hand-launched `npm start`
        // lines up with what the Swift client expects).
        if service == .telegram {
            env["CLAW_TELEGRAM_PORT"] = String(service.port)
            env["CLAW_TELEGRAM_WORKSPACE"] = workspaceURL.path
        }
        // Publishing reads its own CLAW_PUBLISHING_* env vars. The admin token
        // follows the same stdin bootstrap path as other local services.
        if service == .publishing {
            let publishingData = dataDirectoryURL(for: .publishing).path
            env["CLAW_PUBLISHING_HOST"] = "127.0.0.1"
            env["CLAW_PUBLISHING_PORT"] = String(service.port)
            env["CLAW_PUBLISHING_DATA_DIR"] = publishingData
            env["CLAW_PUBLISHING_STATUS_FILE"] = statusFileURL(for: service).path
        }
        if adminToken != nil, adminTokenEnvVar[service] != nil {
            if service == .runtime {
                env["RUNTIME_SHARED_SECRET"] = adminToken
            } else if service == .secrets {
                env["CLAW_SECRETS_BOOTSTRAP_STDIN"] = "1"
            } else {
                env["CLAW_LOCAL_ADMIN_BOOTSTRAP_STDIN"] = "1"
            }
        }
        if service == .secrets, signedHostToken != nil {
            env["CLAW_SECRETS_BOOTSTRAP_STDIN"] = "1"
        }
        return env
    }

    private nonisolated static func secretsBootstrapPayload(
        adminToken: String?,
        signedHostToken: String?,
        hostAssertionKeyBase64: String?,
        platformKey: Data?
    ) throws -> Data {
        var payload: [String: String] = [:]
        if let adminToken {
            payload["adminToken"] = adminToken
        }
        if let signedHostToken {
            payload["signedHostToken"] = signedHostToken
        }
        if let hostAssertionKeyBase64 {
            payload["hostAssertionKeyBase64"] = hostAssertionKeyBase64
        }
        if let platformKey {
            payload["kekBase64"] = platformKey.base64EncodedString()
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [])
            + Data([0x0a])
    }

    private nonisolated static func localAdminBootstrapPayload(adminToken: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["adminToken": adminToken], options: [])
            + Data([0x0a])
    }

    /// Per-session admin token for `service` if this manager spawned the
    /// daemon. `nil` for services without admin auth, or when the GUI is
    /// not the daemon steward (e.g., background bridge mode).
    func adminTokenIfSpawned(for service: ClawJSService) -> String? {
        sessionAdminTokens[service]
    }

    /// Signed-host token for the Secrets service only when this Clawix
    /// process spawned it. This token is intentionally never written to the
    /// `.admin-token` fallback, because sibling local processes must not gain
    /// host-only lifecycle, reveal, or metadata privileges by reading disk.
    func signedHostTokenIfSpawned(for service: ClawJSService) -> String? {
        sessionSignedHostTokens[service]
    }

    func hostAssertionKeyIfSpawned(for service: ClawJSService) -> String? {
        sessionHostAssertionKeys[service]
    }

    /// Returns the existing per-session token or generates a fresh one and
    /// stores it. `nil` for services that don't authenticate admin via token.
    private func ensureAdminToken(for service: ClawJSService) -> String? {
        guard Self.adminTokenEnvVar[service] != nil else { return nil }
        if let existing = sessionAdminTokens[service] { return existing }
        let token = SecureRandom.bytes(32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        sessionAdminTokens[service] = token
        return token
    }

    private func ensureSignedHostToken(for service: ClawJSService) -> String? {
        guard service == .secrets else { return nil }
        if let existing = sessionSignedHostTokens[service] { return existing }
        let token = SecureRandom.bytes(32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        sessionSignedHostTokens[service] = token
        return token
    }

    private func ensureHostAssertionKey(for service: ClawJSService) -> String? {
        guard service == .secrets else { return nil }
        if let existing = sessionHostAssertionKeys[service] { return existing }
        let key = SecureRandom.bytes(32).base64EncodedString()
        sessionHostAssertionKeys[service] = key
        return key
    }

    /// Filesystem token lookup only for services with an explicit
    /// token-file contract. Services in `adminTokenEnvVar` deliberately
    /// have no disk lookup: same-user local processes can read user files,
    /// so v1 host identity must stay in-memory/native.
    nonisolated static func adminTokenFromTokenFile(for service: ClawJSService) throws -> String {
        if adminTokenEnvVar[service] != nil {
            throw NSError(domain: "ClawJSServiceManager", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "\(service.displayName) admin token is host-session only and is never read from disk."
            ])
        }
        let url = dataDirectoryURL(for: service).appendingPathComponent(".admin-token", isDirectory: false)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let mode = attrs[.posixPermissions] as? NSNumber,
           mode.intValue & 0o077 != 0 {
            throw NSError(domain: "ClawJSServiceManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Admin token at \(url.path) must be readable only by the current user."
            ])
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 32 else {
            throw NSError(domain: "ClawJSServiceManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Admin token at \(url.path) is too short."
        ])
        }
        return raw
    }

    private nonisolated static func canAdoptExistingService(_ service: ClawJSService) -> Bool {
        if adminTokenEnvVar[service] != nil { return false }
        return true
    }

    private nonisolated static func listenerPID(on port: UInt16) async -> pid_t? {
        try? await ClawJSProcessInspector.listenerPID(on: port)
    }

    private nonisolated static func isClawixSidecar(pid: pid_t) async -> Bool {
        (try? await ClawJSProcessInspector.isClawixSidecar(pid: pid)) ?? false
    }

    private nonisolated static func parentPID(of pid: pid_t) async -> pid_t? {
        try? await ClawJSProcessInspector.parentPID(of: pid)
    }

    private nonisolated static func isRunning(pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private nonisolated static func uniquePIDs(_ pids: [pid_t]) -> [pid_t] {
        var seen = Set<pid_t>()
        return pids.filter { seen.insert($0).inserted }
    }

    private nonisolated static func dataDirectoryURL(for service: ClawJSService) -> URL {
        if service == .database {
            return mainDataDirectoryURL
        }
        if service == .secrets {
            return frameworkSecretsDirectoryURL
        }
        return workspaceURL
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawWorkspace, isDirectory: true)
            .appendingPathComponent(service.rawValue, isDirectory: true)
    }

    private nonisolated static func staleAdminTokenURLs(for service: ClawJSService) -> [URL] {
        [
            dataDirectoryURL(for: service),
            workspaceURL
                .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawWorkspace, isDirectory: true)
                .appendingPathComponent(service.rawValue, isDirectory: true),
        ].map { $0.appendingPathComponent(".admin-token", isDirectory: false) }
    }

    private nonisolated static func bundledLauncherScript(for service: ClawJSService) -> URL? {
        let url = ClawJSRuntime.bundleRootURL.appendingPathComponent(
            "node_modules/@clawjs/cli/bin/\(service.rawValue)-server-launcher.mjs",
            isDirectory: false
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - State mutation

    private func applyDaemonServiceStatus(
        _ wire: WireClawJSServiceSnapshot,
        to service: ClawJSService
    ) {
        let transitionDate = Date(timeIntervalSince1970: TimeInterval(wire.updatedAtMs) / 1_000)
        let mappedState = state(fromDaemonStatus: wire, service: service)
        update(service) { snap in
            snap.state = mappedState
            snap.restartCount = wire.restartCount
            snap.lastError = wire.lastError
            snap.lastTransitionAt = transitionDate
        }

        var monitor = serviceMonitors[service] ?? ServiceMonitor(
            mode: .daemonOwned,
            readyDeadline: Date().addingTimeInterval(6),
            hasReachedReady: mappedState.isReady,
            consecutiveFailures: 0,
            nextProbeAt: Date().addingTimeInterval(Self.daemonPushFreshWindow),
            lastDaemonUpdateAt: Date()
        )
        monitor.mode = .daemonOwned
        monitor.hasReachedReady = monitor.hasReachedReady || mappedState.isReady
        monitor.consecutiveFailures = 0
        monitor.lastDaemonUpdateAt = Date()
        monitor.nextProbeAt = Date().addingTimeInterval(Self.daemonPushFreshWindow)
        serviceMonitors[service] = monitor
        ensureMonitorTask()
    }

    private func state(fromDaemonStatus wire: WireClawJSServiceSnapshot, service: ClawJSService) -> ClawJSServiceState {
        switch wire.state {
        case "idle":
            return .idle
        case "availableOnDemand":
            return .availableOnDemand(trigger: ClawJSServiceDemandPolicy.onDemandTrigger(for: service) ?? service.rawValue)
        case "starting":
            return .starting
        case "ready", "readyFromDaemon", "running", "healthy":
            return .readyFromDaemon(port: UInt16(wire.port))
        case "blocked":
            return .blocked(reason: wire.lastError ?? "\(service.displayName) is blocked by the daemon.")
        case "crashed":
            return .crashed(reason: wire.lastError ?? "\(service.displayName) crashed in the daemon.")
        case "daemonUnavailable", "unavailable", "unhealthy":
            return .daemonUnavailable(reason: wire.lastError ?? "\(service.displayName) is unavailable from the daemon.")
        default:
            return .daemonUnavailable(reason: wire.lastError ?? "\(service.displayName) is unavailable from the daemon.")
        }
    }

    private func update(
        _ service: ClawJSService,
        _ mutate: (inout ClawJSServiceSnapshot) -> Void
    ) {
        guard var snap = snapshots[service] else { return }
        let previousState = snap.state
        mutate(&snap)
        if snap.state != previousState {
            snap.lastTransitionAt = Date()
        }
        snapshots[service] = snap
        publishSnapshots()
    }

    private func publishSnapshots() {
        let snapshotCopy = snapshots
        Task { @MainActor [publisher, snapshotCopy] in
            publisher.publish(snapshotCopy)
        }
    }

    // MARK: - IoT launch path

    /// Spawns the clawjs-iot daemon. Distinct from `spawnAndSupervise`
    /// because IoT lives outside @clawjs/cli: its argv, cwd, and the
    /// node binary all differ from the bundled-runtime services.
    private func spawnIot(projectDir: URL) async {
        let serverJs = projectDir.appendingPathComponent("dist/server.js", isDirectory: false)
        update(.iot) { $0.state = .starting; $0.lastError = nil }

        do {
            try Self.prepareDirectories(for: .iot)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", serverJs.path]
            process.currentDirectoryURL = projectDir
            process.environment = Self.iotEnvironment()

            let logURL = Self.logFileURL(for: .iot)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
            logHandles[.iot] = handle

            process.terminationHandler = { [weak self] proc in
                Task { [weak self] in
                    await self?.handleTermination(of: .iot, process: proc)
                }
            }

            try process.run()
            processes[.iot] = process
            processRegistry.register(process, for: .iot)

            monitorLocalService(.iot, pid: process.processIdentifier)
        } catch {
            update(.iot) {
                $0.state = .crashed(reason: "spawn failed: \(error.localizedDescription)")
                $0.lastError = error.localizedDescription
            }
            scheduleRestart(.iot)
        }
    }

    /// Resolves the on-disk clawjs/iot project directory. Development reads
    /// a dev pointer dev.sh writes; production builds substitute a
    /// bundled copy under Contents/Resources/clawjs-iot/. Returns nil
    /// when neither location is present or the dist/server.js is
    /// missing, which keeps the service `.blocked` rather than crashing.
    private func iotProjectDirectory() -> URL? {
        let pointerURL = Self.applicationSupportRoot
            .appendingPathComponent("dev-pointers", isDirectory: true)
            .appendingPathComponent("iot.dir", isDirectory: false)
        if let raw = try? String(contentsOf: pointerURL, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let candidate = URL(fileURLWithPath: trimmed, isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate
                    .appendingPathComponent("dist/server.js").path) {
                    return candidate
                }
            }
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/clawjs-iot", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundled
            .appendingPathComponent("dist/server.js").path) {
            return bundled
        }
        return nil
    }

    /// Environment for the spawned IoT daemon. Pins host+port+data dir
    /// so the supervisor's health probe and downstream clients agree on
    /// the same loopback endpoint. Mirrors the per-service env wiring
    /// `environment(for:adminToken:signedHostToken:)` does for the @clawjs/cli surface
    /// without inheriting workspace-flavoured variables that IoT does
    /// not consume.
    private nonisolated static func iotEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["IOT_HOST"] = "127.0.0.1"
        env["IOT_PORT"] = String(ClawJSService.iot.port)
        let dataDir = dataDirectoryURL(for: .iot)
        env["IOT_DATA_DIR"] = dataDir.path
        env["IOT_DB_PATH"] = dataDir.appendingPathComponent(ClawixPersistentSurfacePaths.components.iotDatabase, isDirectory: false).path
        return env
    }
}
