import Foundation
import ClawixCore

/// Non-main actor that owns ClawJS sidecar process supervision.
///
/// `ClawJSServiceLaunchAdapter` maps each service to the concrete command
/// that the bundled ClawJS runtime actually exposes. Services whose launch
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
    static let restartBudget = ClawJSServiceSupervisorPolicy.restartBudget

    /// Backoff schedule (seconds): 1, 2, 4, 8, 16, capped at 60. Used
    /// when a process crashes; reset to zero after the service stays
    /// healthy for `healthyResetWindow`.
    private static let backoffSchedule = ClawJSServiceSupervisorPolicy.backoffSchedule
    private static let healthyResetWindow = ClawJSServiceSupervisorPolicy.healthyResetWindow

    private var processes: [ClawJSService: Process] = [:]
    private var logSinks: [ClawJSService: ClawixRedactedProcessLogSink] = [:]
    private var monitorTask: Task<Void, Never>?
    private var serviceMonitors: [ClawJSService: ClawJSServiceMonitor] = [:]
    private var restartTasks: [ClawJSService: Task<Void, Never>] = [:]
    private var lastReadyAt: [ClawJSService: Date] = [:]
    private var tokenVault = ClawJSServiceTokenVault()

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
        tokenVault.snapshot()
    }

    func applyDaemonServiceStatuses(
        _ services: [WireClawJSServiceSnapshot],
        activeDemand: Set<ClawJSService>
    ) {
        for wire in services {
            guard let service = ClawJSService(rawValue: wire.id) else { continue }
            applyDaemonServiceStatus(
                wire,
                to: service,
                hasActiveDemand: activeDemand.contains(service)
            )
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

        logSinks[service]?.close()
        logSinks[service] = nil
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
        for sink in logSinks.values {
            sink.close()
        }
        logSinks.removeAll()

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

        guard ClawJSServiceLaunchAdapter.commandLine(for: service) != nil else {
            update(service) {
                $0.state = .blocked(reason:
                    "@clawjs/cli@\(ClawJSRuntime.expectedVersion) does not expose a launch command for \(service.displayName)")
            }
            return
        }

        await spawnAndSupervise(service)
    }

    private func preparePortForLocalLaunch(_ service: ClawJSService) async -> Bool {
        let url = ClawJSServiceEndpointResolver.healthURL(for: service)
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

    func stop(_ services: Set<ClawJSService>) async {
        for service in orderedServices(from: services) {
            restartTasks[service]?.cancel()
            restartTasks[service] = nil
            serviceMonitors[service] = nil

            _ = await stopTrackedProcess(for: service)
            update(service) {
                $0.lastError = nil
                $0.state = ClawJSServiceSupervisorPolicy.availableOnDemandState(for: service)
            }
        }
        if serviceMonitors.isEmpty {
            monitorTask?.cancel()
            monitorTask = nil
        }
    }

    private func startDaemonAwareServices(_ services: Set<ClawJSService>) async {
        for service in orderedServices(from: services) {
            serviceMonitors[service] = nil
            let url = ClawJSServiceEndpointResolver.healthURL(for: service)
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
            } else if ClawJSRuntime.isAvailable, ClawJSServiceLaunchAdapter.commandLine(for: service) != nil {
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
        serviceMonitors[service] = ClawJSServiceHealthMonitor.daemonMonitor(
            readyTimeout: readyTimeout,
            reachedReady: reachedReady
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

    // MARK: - Spawn + supervise

    /// Full spawn pipeline. Dormant today (commandLine returns nil), but
    /// fully wired so flipping that one method enables the whole flow.
    private func spawnAndSupervise(_ service: ClawJSService) async {
        do {
            guard let plan = try ClawJSServiceLaunchAdapter.plan(for: service, tokenVault: &tokenVault) else { return }
            update(service) { $0.state = .starting; $0.lastError = nil }
            try ClawJSServiceDirectoryResolver.prepareDirectories(for: service)

            let spawned = try ClawJSServiceSpawner.spawn(plan) { [weak self] proc in
                Task { [weak self] in
                    await self?.handleTermination(of: service, process: proc)
                }
            }
            processes[service] = spawned.process
            logSinks[service] = spawned.logSink
            processRegistry.register(spawned.process, for: service)

            // The aggregate monitor flips state to `.ready` once the
            // service responds; it also detects soft hangs (process alive
            // but no longer answering) and triggers a restart.
            monitorLocalService(service, pid: spawned.process.processIdentifier)
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
        logSinks[service]?.close()
        logSinks[service] = nil
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
        let delay = ClawJSServiceSupervisorPolicy.restartDelay(for: snap.restartCount)
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
        serviceMonitors[service] = ClawJSServiceHealthMonitor.localMonitor(pid: pid)
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

        return ClawJSServiceHealthMonitor.nextSleepInterval(monitors: serviceMonitors)
    }

    private func probeMonitoredService(_ service: ClawJSService, now: Date) async {
        guard let monitor = serviceMonitors[service] else { return }
        let updated: ClawJSServiceMonitor?
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
        monitor: ClawJSServiceMonitor,
        now: Date
    ) async -> ClawJSServiceMonitor? {
        let monitor = monitor
        guard let process = processes[service], process.isRunning else {
            return nil
        }

        let alive = await pingService(service)
        let outcome = ClawJSServiceHealthMonitor.probeLocalService(
            service: service,
            pid: pid,
            monitor: monitor,
            now: now,
            alive: alive
        )
        switch outcome.action {
        case .none:
            break
        case .markReady(let pid, let port):
            lastReadyAt[service] = now
            update(service) { $0.state = .ready(pid: pid, port: port) }
        case .terminate(let reason):
            update(service) {
                $0.state = .crashed(reason: reason)
            }
            process.terminate()
        }
        return outcome.monitor
    }

    private func probeDaemonOwnedService(
        _ service: ClawJSService,
        monitor: ClawJSServiceMonitor,
        now: Date
    ) async -> ClawJSServiceMonitor? {
        if let fresh = ClawJSServiceHealthMonitor.daemonPushFreshOutcome(monitor: monitor, now: now) {
            PerfSignpost.serviceSupervisor.event("monitor.daemon_push_fresh")
            return fresh.monitor
        }

        let alive = await pingService(service)
        let outcome = ClawJSServiceHealthMonitor.probeDaemonOwnedService(
            service: service,
            monitor: monitor,
            now: now,
            alive: alive,
            canAdopt: Self.canAdoptExistingService(service),
            canLaunchLocal: ClawJSRuntime.isAvailable && ClawJSServiceLaunchAdapter.commandLine(for: service) != nil
        )
        if outcome.action != .daemonPushFresh {
            PerfSignpost.serviceSupervisor.event("daemon_fallback_probe")
        }
        switch outcome.action {
        case .none:
            break
        case .daemonPushFresh:
            PerfSignpost.serviceSupervisor.event("monitor.daemon_push_fresh")
        case .publishDaemonReady:
            publishDaemonReady(service)
        case .markReachableUnavailable:
            markReachableServiceUnavailable(service)
        case .launchLocal:
            await launchLocal(service, force: true)
            return nil
        case .markDaemonUnavailable(let reason):
            update(service) {
                $0.state = .daemonUnavailable(reason: reason)
                $0.lastError = reason
            }
        }
        return outcome.monitor
    }

    private func pingService(_ service: ClawJSService) async -> Bool {
        let url = ClawJSServiceEndpointResolver.healthURL(for: service)
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
        ClawJSServiceSupervisorRoutes.workspaceURL(applicationSupportRoot: applicationSupportRoot)
    }

    nonisolated static var applicationSupportRoot: URL {
        ClawJSServiceSupervisorRoutes.applicationSupportRoot()
    }

    nonisolated static func workingDirectoryURL(for service: ClawJSService) -> URL {
        ClawJSServiceDirectoryResolver.workingDirectoryURL(for: service)
    }

    nonisolated static var mainDataDirectoryURL: URL {
        ClawJSServiceDirectoryResolver.mainDataDirectoryURL
    }

    nonisolated static var mainDatabaseURL: URL {
        ClawJSServiceSupervisorRoutes.mainDatabaseURL(mainDataDirectoryURL: mainDataDirectoryURL)
    }

    nonisolated static var mainFilesDirectoryURL: URL {
        ClawJSServiceSupervisorRoutes.mainFilesDirectoryURL(mainDataDirectoryURL: mainDataDirectoryURL)
    }

    private nonisolated static var frameworkGlobalRootURL: URL {
        ClawJSServiceSupervisorRoutes.frameworkGlobalRoot()
    }

    private nonisolated static var frameworkSecretsDirectoryURL: URL {
        ClawJSServiceSupervisorRoutes.frameworkSecretsDirectory(frameworkGlobalRoot: frameworkGlobalRootURL)
    }

    nonisolated static func logFileURL(for service: ClawJSService) -> URL {
        ClawJSServiceSupervisorRoutes.logFileURL(service: service)
    }

    nonisolated static func statusFileURL(for service: ClawJSService) -> URL {
        ClawJSServiceSupervisorRoutes.statusFileURL(service: service, applicationSupportRoot: applicationSupportRoot)
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
        if ClawJSServiceSupervisorPolicy.adminTokenEnvVar[service] != nil {
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
        for tokenEnvVar in ClawJSServiceSupervisorPolicy.adminTokenEnvVar.values {
            env.removeValue(forKey: tokenEnvVar)
        }
        env.removeValue(forKey: "CLAW_SECRETS_TOKEN")
        env.removeValue(forKey: "CLAW_SECRETS_KEK_BASE64")
        env.removeValue(forKey: "CLAW_SECRETS_HOST_ASSERTION_KEY_BASE64")
        env["HOME"] = ClawJSServiceSupervisorRoutes.homeURL(applicationSupportRoot: applicationSupportRoot).path
        env["CLAW_WORKSPACE"] = workspaceURL.path
        env["CLAW_HOME"] = frameworkGlobalRootURL.path
        env["CLAW_DATA_DIR"] = mainDataDirectoryURL.path
        env["CLAW_DB_PATH"] = mainDatabaseURL.path
        env["CLAW_FILES_DIR"] = mainFilesDirectoryURL.path
        env["CLAW_SERVICE_PORT"] = String(service.port)
        env["CLAW_SERVICE_NAME"] = service.rawValue
        env["RUNTIME_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["RUNTIME_PORT"] = String(ClawJSService.runtime.port)
        env["RUNTIME_DATA_DIR"] = dataDirectoryURL(for: .runtime).path
        env["RUNTIME_DB_PATH"] = ClawJSServiceSupervisorRoutes.runtimeDatabaseURL(
            runtimeDataDirectoryURL: dataDirectoryURL(for: .runtime)
        ).path
        env["CLAW_RUNTIME_SESSIONS_URL"] = ClawJSServiceEndpointResolver.originString(for: .sessions)
        for (key, value) in ClawJSActorAssertion.environment() {
            env[key] = value
        }
        env["CLAW_SECRETS_PROXY_PATH"] = ClawJSServiceSupervisorRoutes.secretsProxyURL().path
        env["PORT"] = String(service.port)
        env["HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_DATABASE_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_DATABASE_PORT"] = String(ClawJSService.database.port)
        env["CLAW_DATABASE_DATA_DIR"] = mainDataDirectoryURL.path
        env["CLAW_DATABASE_DB_PATH"] = mainDatabaseURL.path
        env["CLAW_DATABASE_FILES_DIR"] = mainFilesDirectoryURL.path
        env["CLAW_DRIVE_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_DRIVE_PORT"] = String(ClawJSService.drive.port)
        env["CLAW_DRIVE_DATA_DIR"] = dataDirectoryURL(for: .drive).path
        env["CLAW_SESSIONS_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_SESSIONS_PORT"] = String(ClawJSService.sessions.port)
        env["CLAW_SESSIONS_DATA_DIR"] = dataDirectoryURL(for: .sessions).path
        env["CLAW_SESSIONS_DB_PATH"] = ClawJSServiceSupervisorRoutes.sessionsDatabaseURL(
            dataDirectoryURL: dataDirectoryURL(for: .sessions)
        ).path
        env["CLAW_SECRETS_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_SECRETS_PORT"] = String(ClawJSService.secrets.port)
        env["CLAW_SECRETS_DATA_DIR"] = dataDirectoryURL(for: .secrets).path
        env["CLAW_SECRETS_DB_PATH"] = ClawJSServiceSupervisorRoutes.secretsDatabaseURL(
            dataDirectoryURL: dataDirectoryURL(for: .secrets)
        ).path
        env["CLAW_SECRETS_BASE_URL"] = ClawJSServiceEndpointResolver.originString(for: .secrets)
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
            env["CLAW_PUBLISHING_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
            env["CLAW_PUBLISHING_PORT"] = String(service.port)
            env["CLAW_PUBLISHING_DATA_DIR"] = publishingData
            env["CLAW_PUBLISHING_STATUS_FILE"] = statusFileURL(for: service).path
        }
        if adminToken != nil, ClawJSServiceSupervisorPolicy.adminTokenEnvVar[service] != nil {
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
        tokenVault.adminTokenIfSpawned(for: service)
    }

    /// Signed-host token for the Secrets service only when this Clawix
    /// process spawned it. This token is intentionally never written to the
    /// `.admin-token` fallback, because sibling local processes must not gain
    /// host-only lifecycle, reveal, or metadata privileges by reading disk.
    func signedHostTokenIfSpawned(for service: ClawJSService) -> String? {
        tokenVault.signedHostTokenIfSpawned(for: service)
    }

    func hostAssertionKeyIfSpawned(for service: ClawJSService) -> String? {
        tokenVault.hostAssertionKeyIfSpawned(for: service)
    }

    /// Filesystem token lookup only for services with an explicit
    /// token-file contract. Services in `adminTokenEnvVar` deliberately
    /// have no disk lookup: same-user local processes can read user files,
    /// so v1 host identity must stay in-memory/native.
    nonisolated static func adminTokenFromTokenFile(for service: ClawJSService) throws -> String {
        try ClawJSServiceDirectoryResolver.adminTokenFromTokenFile(for: service)
    }

    private nonisolated static func canAdoptExistingService(_ service: ClawJSService) -> Bool {
        ClawJSServiceSupervisorPolicy.canAdoptExistingService(service)
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
        return ClawJSServiceSupervisorRoutes.serviceDataDirectoryURL(
            service: service,
            workspaceURL: workspaceURL,
            mainDataDirectoryURL: mainDataDirectoryURL,
            frameworkSecretsDirectoryURL: frameworkSecretsDirectoryURL
        )
    }

    private nonisolated static func staleAdminTokenURLs(for service: ClawJSService) -> [URL] {
        [
            dataDirectoryURL(for: service),
            ClawJSServiceSupervisorRoutes.serviceDataDirectoryURL(
                service: service,
                workspaceURL: workspaceURL,
                mainDataDirectoryURL: mainDataDirectoryURL,
                frameworkSecretsDirectoryURL: frameworkSecretsDirectoryURL
            ),
        ].map { ClawJSServiceSupervisorRoutes.adminTokenURL(dataDirectoryURL: $0) }
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
        to service: ClawJSService,
        hasActiveDemand: Bool
    ) {
        let transitionDate = Date(timeIntervalSince1970: TimeInterval(wire.updatedAtMs) / 1_000)
        let mappedState = state(fromDaemonStatus: wire, service: service)
        update(service) { snap in
            snap.state = mappedState
            snap.restartCount = wire.restartCount
            snap.lastError = wire.lastError
            snap.lastTransitionAt = transitionDate
        }

        guard hasActiveDemand else {
            serviceMonitors[service] = nil
            return
        }

        serviceMonitors[service] = ClawJSServiceHealthMonitor.daemonPushMonitor(
            existing: serviceMonitors[service],
            mappedState: mappedState
        )
        ensureMonitorTask()
    }

    private func state(fromDaemonStatus wire: WireClawJSServiceSnapshot, service: ClawJSService) -> ClawJSServiceState {
        switch wire.state {
        case "idle":
            return .idle
        case "availableOnDemand":
            return ClawJSServiceSupervisorPolicy.availableOnDemandState(for: service)
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
        update(.iot) { $0.state = .starting; $0.lastError = nil }

        do {
            try Self.prepareDirectories(for: .iot)

            let plan = ClawJSServiceLaunchAdapter.iotPlan(projectDir: projectDir)
            let spawned = try ClawJSServiceSpawner.spawn(plan) { [weak self] proc in
                Task { [weak self] in
                    await self?.handleTermination(of: .iot, process: proc)
                }
            }
            processes[.iot] = spawned.process
            logSinks[.iot] = spawned.logSink
            processRegistry.register(spawned.process, for: .iot)

            monitorLocalService(.iot, pid: spawned.process.processIdentifier)
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
        let pointerURL = ClawJSServiceSupervisorRoutes.iotPointerURL(applicationSupportRoot: Self.applicationSupportRoot)
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
        env["IOT_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["IOT_PORT"] = String(ClawJSService.iot.port)
        let dataDir = dataDirectoryURL(for: .iot)
        env["IOT_DATA_DIR"] = dataDir.path
        env["IOT_DB_PATH"] = dataDir.appendingPathComponent(ClawixPersistentSurfacePaths.components.iotDatabase, isDirectory: false).path
        return env
    }
}
