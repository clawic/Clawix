import Combine
import Foundation
import ClawixCore

/// Main-thread facade for ClawJS service state consumed by SwiftUI.
/// Process supervision lives in `ClawJSServiceSupervisor`; this type only
/// publishes compact snapshots and keeps synchronous compatibility helpers.
@MainActor
final class ClawJSServiceManager: ObservableObject {

    static let shared = ClawJSServiceManager()

    @Published private(set) var snapshots: [ClawJSService: ClawJSServiceSnapshot]

    private let statePublisher: ClawJSServiceStatePublisher
    private let processRegistry: ClawJSProcessRegistry
    private let supervisor: ClawJSServiceSupervisor
    private let demandBroker: ServiceDemandBroker
    private let bridgeServiceOverride: BackgroundBridgeService?

    private var sessionAdminTokens: [ClawJSService: String] = [:]
    private var sessionSignedHostTokens: [ClawJSService: String] = [:]
    private var sessionHostAssertionKeys: [ClawJSService: String] = [:]

    private init(bridgeService: BackgroundBridgeService? = nil) {
        self.bridgeServiceOverride = bridgeService
        let seed = Self.initialSnapshots()
        self.snapshots = seed

        let publisher = ClawJSServiceStatePublisher()
        let registry = ClawJSProcessRegistry()
        self.statePublisher = publisher
        self.processRegistry = registry
        self.supervisor = ClawJSServiceSupervisor(
            snapshots: seed,
            publisher: publisher,
            processRegistry: registry
        )
        self.demandBroker = ServiceDemandBroker()
        publisher.manager = self
    }

    func startStartupCore() async {
        _ = await acquire(
            services: ClawJSServiceDemandPolicy.startupCoreServices,
            reason: .startupCore,
            consumer: "startup.core"
        )
    }

    func start(_ services: Set<ClawJSService>, reason: ClawJSServiceStartReason) async {
        await supervisor.start(
            services,
            reason: reason,
            daemonReachable: activeBridgeService.isDaemonReachable
        )
        await refreshFromSupervisor()
    }

    func acquire(
        services: Set<ClawJSService>,
        reason: ClawJSServiceStartReason,
        consumer: String
    ) async -> ServiceDemandLease {
        let result = await demandBroker.acquire(
            services: services,
            reason: reason,
            consumer: consumer
        )
        await supervisor.markServicesAvailableOnDemand(excluding: result.activeServices)
        await supervisor.start(
            result.servicesToStart,
            reason: reason,
            daemonReachable: activeBridgeService.isDaemonReachable
        )
        await refreshFromSupervisor()
        return result.lease
    }

    func release(_ lease: ServiceDemandLease) async {
        let result = await demandBroker.release(lease)
        await supervisor.stop(result.servicesToStop)
        await supervisor.markServicesAvailableOnDemand(excluding: result.activeServices)
        await refreshFromSupervisor()
    }

    func activeServices() async -> Set<ClawJSService> {
        await demandBroker.activeServices()
    }

    func consumers(for service: ClawJSService) async -> Set<String> {
        await demandBroker.consumers(for: service)
    }

    func demandDebugSnapshot() async -> ServiceDemandDebugSnapshot {
        await demandBroker.debugSnapshot()
    }

    static func holdDemandUntilCancelled() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                break
            }
        }
    }

    func markServicesAvailableOnDemand(excluding activeServices: Set<ClawJSService>) {
        Task { [supervisor] in
            await supervisor.markServicesAvailableOnDemand(excluding: activeServices)
            await refreshFromSupervisor()
        }
    }

    func startupIssue(for services: Set<ClawJSService>) -> String? {
        for service in orderedServices(from: services) {
            guard let state = snapshots[service]?.state else { continue }
            switch state {
            case .blocked(let reason), .crashed(let reason), .daemonUnavailable(let reason):
                return "\(service.displayName): \(reason)"
            case .idle, .availableOnDemand, .starting, .ready, .readyFromDaemon:
                break
            }
        }
        return nil
    }

    func restart(_ service: ClawJSService) async {
        await supervisor.restart(service, daemonReachable: activeBridgeService.isDaemonReachable)
        await refreshFromSupervisor()
    }

    func applyDaemonServiceStatuses(_ services: [WireClawJSServiceSnapshot]) {
        Task { [supervisor, demandBroker] in
            let activeServices = await demandBroker.activeServices()
            await supervisor.applyDaemonServiceStatuses(services, activeDemand: activeServices)
            await refreshFromSupervisor()
        }
    }

    nonisolated func terminateAllSynchronously() {
        MainActor.assumeIsolated {
            supervisor.terminateAllSynchronously()
        }
    }

    func tearDown() async {
        await supervisor.tearDown()
        await refreshFromSupervisor()
    }

    func adminTokenIfSpawned(for service: ClawJSService) -> String? {
        sessionAdminTokens[service]
    }

    func signedHostTokenIfSpawned(for service: ClawJSService) -> String? {
        sessionSignedHostTokens[service]
    }

    func hostAssertionKeyIfSpawned(for service: ClawJSService) -> String? {
        sessionHostAssertionKeys[service]
    }

    static var workspaceURL: URL {
        ClawJSServiceSupervisor.workspaceURL
    }

    static func logFileURL(for service: ClawJSService) -> URL {
        ClawJSServiceSupervisor.logFileURL(for: service)
    }

    static func cliEnvironment() -> [String: String] {
        ClawJSServiceSupervisor.cliEnvironment()
    }

    static func adminTokenFromTokenFile(for service: ClawJSService) throws -> String {
        try ClawJSServiceSupervisor.adminTokenFromTokenFile(for: service)
    }

    private var activeBridgeService: BackgroundBridgeService {
        bridgeServiceOverride ?? BackgroundBridgeService.shared
    }

    private func refreshFromSupervisor() async {
        snapshots = await supervisor.currentSnapshots()
        apply(await supervisor.sessionTokens())
    }

    private func apply(_ tokenSnapshot: ClawJSSessionTokenSnapshot) {
        sessionAdminTokens = tokenSnapshot.adminTokens
        sessionSignedHostTokens = tokenSnapshot.signedHostTokens
        sessionHostAssertionKeys = tokenSnapshot.hostAssertionKeys
    }

    fileprivate func applyPublishedSnapshots(_ snapshots: [ClawJSService: ClawJSServiceSnapshot]) {
        self.snapshots = snapshots
    }

    private func orderedServices(from services: Set<ClawJSService>) -> [ClawJSService] {
        ClawJSService.allCases.filter { services.contains($0) }
    }

    private static func initialSnapshots() -> [ClawJSService: ClawJSServiceSnapshot] {
        let now = Date()
        var seed: [ClawJSService: ClawJSServiceSnapshot] = [:]
        for service in ClawJSService.allCases {
            seed[service] = ClawJSServiceSnapshot(
                service: service,
                state: .idle,
                lastTransitionAt: now,
                restartCount: 0,
                lastError: nil
            )
        }
        return seed
    }
}

@MainActor
final class ClawJSServiceStatePublisher {
    weak var manager: ClawJSServiceManager?

    func publish(_ snapshots: [ClawJSService: ClawJSServiceSnapshot]) {
        manager?.applyPublishedSnapshots(snapshots)
    }
}

struct ClawJSSessionTokenSnapshot {
    var adminTokens: [ClawJSService: String]
    var signedHostTokens: [ClawJSService: String]
    var hostAssertionKeys: [ClawJSService: String]
}
