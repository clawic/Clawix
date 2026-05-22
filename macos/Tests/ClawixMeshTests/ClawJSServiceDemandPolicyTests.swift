import XCTest
@testable import Clawix

final class ClawJSServiceDemandPolicyTests: XCTestCase {
    func testMainStartupCoreDoesNotStartRuntimeServices() {
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.startupServices(for: .main),
            []
        )
        XCTAssertFalse(ClawJSServiceDemandPolicy.startupServices(for: .main).contains(.sessions))
        XCTAssertFalse(ClawJSServiceDemandPolicy.startupServices(for: .main).contains(.runtime))
    }

    func testToolStartupServicesStayScopedToToolDomain() {
        let reviewed: [(ClawixToolRole, Set<ClawJSService>)] = [
            (.tasks, [.database]),
            (.goals, [.database]),
            (.notes, [.database]),
            (.projects, [.database]),
            (.database, [.database]),
            (.memory, [.memory]),
            (.photos, [.drive]),
            (.documents, [.drive]),
            (.recent, [.drive]),
            (.drive, [.drive]),
            (.secrets, [.secrets]),
        ]

        XCTAssertEqual(Set(reviewed.map(\.0)), Set(ClawixToolRole.allCases))
        for (role, services) in reviewed {
            XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: role), services, role.rawValue)
        }
    }

    func testRouteDemandServicesStayOffCoreSurvivalRoutes() {
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .home), [])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .search), [])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .rescue), [])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .settings), [])
    }

    func testChatRouteDemandsRuntimeAndSessions() {
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .chat(UUID())), [.runtime, .sessions])
    }

    func testRouteDemandServicesCoverHeavyFrameworkSurfaces() {
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .secretsHome), [.secrets])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .databaseCollection("tasks")), [.database])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .databaseWorkbench), [.database])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .memoryHome), [.memory])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .indexHome), [.index])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .marketplaceHome), [.index])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .drivePhotos), [.drive])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .iotDeviceDetail(id: "lamp")), [.iot])
        XCTAssertEqual(ClawJSServiceDemandPolicy.services(for: .publishingComposer(prefillBody: nil, prefillScheduleAt: nil)), [.publishing])
    }

    func testHiddenGatedRoutesDoNotDemandServices() {
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.services(for: .publishingHome, isVisible: { _ in false }),
            []
        )
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.services(for: .iotHome, isVisible: { _ in false }),
            []
        )
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.services(for: .home, isVisible: { _ in false }),
            []
        )
    }

    func testPublishingStaysOnDemandOnly() {
        XCTAssertFalse(ClawJSServiceDemandPolicy.startupCoreServices.contains(.publishing))
        XCTAssertFalse(ClawJSServiceDemandPolicy.startupServices(for: .main).contains(.publishing))
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.services(for: .publishingHome, isVisible: { $0 == .publishing }),
            [.publishing]
        )
        XCTAssertEqual(ClawJSServiceDemandPolicy.onDemandTrigger(for: .publishing), "Publishing opens")
    }

    func testEverySidecarServiceHasExplicitVisibilityGate() {
        let reviewed: [(ClawJSService, ClawJSServiceVisibilityGate)] = [
            (.runtime, .stableCore),
            (.sessions, .stableCore),
            (.database, .appFeature(.database)),
            (.memory, .stableCore),
            (.drive, .stableCore),
            (.secrets, .appFeature(.secrets)),
            (.telegram, .appFeature(.telegram)),
            (.audio, .stableCore),
            (.iot, .appFeature(.iotHome)),
            (.index, .appFeature(.index)),
            (.publishing, .appFeature(.publishing)),
        ]

        XCTAssertEqual(Set(reviewed.map(\.0)), Set(ClawJSService.allCases))
        for (service, gate) in reviewed {
            XCTAssertEqual(ClawJSServiceDemandPolicy.visibilityGate(for: service), gate, service.rawValue)
        }
    }

    func testVisibleServiceFilterBlocksFeatureGatedServices() {
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.visibleServices([.runtime, .publishing, .iot], isVisible: { _ in false }),
            [.runtime]
        )
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.visibleServices([.publishing, .iot], isVisible: { $0 == .publishing }),
            [.publishing]
        )
    }

    func testAvailableOnDemandIsNotReportedAsUnavailable() {
        let state = ClawJSServiceState.availableOnDemand(trigger: "Database opens")

        XCTAssertFalse(state.isReady)
        XCTAssertNil(state.unavailableReason)
    }

    func testApplicationLaunchUsesStartupCoreInsteadOfGlobalServiceStart() throws {
        let source = try readSource("App.swift")

        XCTAssertTrue(source.contains("ClawixStartupCore.run(role: ClawixAppRole.current)"))
        XCTAssertFalse(source.contains("ClawJSServiceManager.shared.start()"))
    }

    func testAppStateInitDoesNotStartPostFirstFrameWork() throws {
        let source = try readSource("AppState.swift")
        let runtimeSessionsSource = try readSource("AppState/RuntimeSessions.swift")
        guard let initStart = source.range(of: "    init(\n") else {
            XCTFail("AppState.init not found")
            return
        }
        guard let nextMethodStart = source.range(of: "    enum ProjectRefreshIntent") else {
            XCTFail("AppState.init end marker not found")
            return
        }

        let initBody = String(source[initStart.lowerBound..<nextMethodStart.lowerBound])

        XCTAssertFalse(initBody.contains("FaviconCache.shared.primeDiskCache()"))
        XCTAssertFalse(initBody.contains("clawix.startIfNeeded("))
        XCTAssertTrue(runtimeSessionsSource.contains("startPostFirstFramePersistence()"))
        XCTAssertTrue(runtimeSessionsSource.contains("startPostFirstFrameFaviconCache()"))
        XCTAssertTrue(source.contains("Bridge transport is no longer opened on app launch"))
    }

    func testManagerStartAPIDelegatesOnlyRequestedServices() throws {
        let managerSource = try readSource("ClawJS/ClawJSServiceManager.swift")
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertTrue(managerSource.contains("func start(_ services: Set<ClawJSService>, reason: ClawJSServiceStartReason) async"))
        XCTAssertTrue(managerSource.contains("func acquire("))
        XCTAssertTrue(managerSource.contains("func release(_ lease: ServiceDemandLease) async"))
        XCTAssertTrue(managerSource.contains("await supervisor.start("))
        XCTAssertTrue(managerSource.contains("await supervisor.stop(result.servicesToStop)"))
        XCTAssertTrue(supervisorSource.contains("await startDaemonAwareServices(services)"))
        XCTAssertTrue(supervisorSource.contains("for service in orderedServices(from: services)"))
        XCTAssertFalse(supervisorSource.contains("for service in ClawJSService.allCases {\n            await launchLocal(service)"))
    }

    func testCanonicalSessionsBootstrapUsesManagedLeaseBeforeHttpClient() throws {
        let source = try readSource("AppState/RuntimeSessions.swift")

        XCTAssertTrue(source.contains("await ensureClawJSSessionsCanonicalLease()"))
        XCTAssertTrue(source.contains("services: [.sessions]"))
        XCTAssertTrue(source.contains("consumer: \"clawjs.sessions.canonical\""))
        XCTAssertTrue(source.contains("await releaseClawJSSessionsCanonicalLease()"))
    }

    func testPublishingIsNotStartedByHardCodedServiceArray() throws {
        let routerSource = try readSource("SurfaceRouterView.swift")
        let publishingHomeSource = try readSource("Publishing/PublishingHomeView.swift")
        let appSource = try readSource("App.swift")
        let chatSource = try readSource("ChatView.swift")
        let registrySource = try readSource("SurfaceRouteRegistry.swift")
        let rootSource = try readSource("Publishing/PublishingRootView.swift")

        XCTAssertTrue(routerSource.contains("ClawJSServiceDemandPolicy.services("))
        XCTAssertFalse(appSource.contains("PublishingWorkspaceStore()"))
        XCTAssertFalse(chatSource.contains("PublishingWorkspaceStore"))
        XCTAssertTrue(chatSource.contains("flags.isVisible(.publishing)"))
        XCTAssertTrue(registrySource.contains("PublishingRootView { PublishingHomeView() }"))
        XCTAssertTrue(registrySource.contains("PublishingRootView {\n                    PublishingComposerView"))
        XCTAssertTrue(registrySource.contains("PublishingRootView { PublishingChannelsView() }"))
        XCTAssertTrue(rootSource.contains("@StateObject private var store = PublishingWorkspaceStore()"))
        XCTAssertFalse(publishingHomeSource.contains("ClawJSServiceDemandPolicy.services("))
        XCTAssertFalse(publishingHomeSource.contains("ClawJSServiceManager.shared.acquire("))
        XCTAssertFalse(routerSource.contains("start([.publishing]"))
        XCTAssertFalse(publishingHomeSource.contains("start([.publishing]"))
    }

    func testSettingsSerializesAvailableOnDemandStatus() throws {
        let source = try readSource("Settings/ClawJSSettingsPage.swift")

        XCTAssertTrue(source.contains("case .availableOnDemand(let trigger):"))
        XCTAssertTrue(source.contains("dict[\"state\"] = \"availableOnDemand\""))
        XCTAssertTrue(source.contains("dict[\"trigger\"] = trigger"))
    }

    func testSurfaceRouterStartsRouteDemandedServices() throws {
        let source = try readSource("SurfaceRouterView.swift")

        XCTAssertTrue(source.contains("ClawJSServiceDemandPolicy.services("))
        XCTAssertTrue(source.contains("for: route,"))
        XCTAssertTrue(source.contains("isVisible: FeatureFlags.shared.isVisible"))
        XCTAssertTrue(source.contains("serviceLease = await serviceManager.acquire("))
        XCTAssertTrue(source.contains("await serviceManager.release(serviceLease)"))
        XCTAssertTrue(source.contains("await holdLeaseUntilCancelled()"))
        XCTAssertTrue(source.contains("serviceManager.startupIssue(for: demandedServices)"))
    }

    func testSettingsUsesManualServiceDemandLeases() throws {
        let source = try readSource("Settings/ClawJSSettingsPage.swift")

        XCTAssertTrue(source.contains("@State private var manualServiceLeases: [ClawJSService: ServiceDemandLease] = [:]"))
        XCTAssertTrue(source.contains("manualServiceLeases[service] = await manager.acquire("))
        XCTAssertTrue(source.contains("await manager.release(lease)"))
        XCTAssertTrue(source.contains("await releaseManualServiceLeases()"))
    }

    func testDemandBrokerStartsOnlyNewlyDemandedServices() async {
        let broker = ServiceDemandBroker()

        let first = await broker.acquire(
            services: [.memory],
            reason: .route("memory"),
            consumer: "route.memory"
        )
        XCTAssertEqual(first.servicesToStart, [.memory])
        XCTAssertEqual(first.activeServices, [.memory])

        let second = await broker.acquire(
            services: [.memory],
            reason: .capability("memory refresh"),
            consumer: "capability.memory.refresh"
        )
        XCTAssertEqual(second.servicesToStart, [])
        XCTAssertEqual(second.activeServices, [.memory])
        let memoryConsumers = await broker.consumers(for: .memory)
        XCTAssertEqual(memoryConsumers, ["route.memory", "capability.memory.refresh"])

        let firstRelease = await broker.release(first.lease)
        XCTAssertEqual(firstRelease.servicesToStop, [])
        XCTAssertEqual(firstRelease.activeServices, [.memory])

        let secondRelease = await broker.release(second.lease)
        XCTAssertEqual(secondRelease.servicesToStop, [.memory])
        XCTAssertEqual(secondRelease.activeServices, [])
    }

    func testDemandBrokerTracksMultiServiceConsumers() async {
        let broker = ServiceDemandBroker()

        let route = await broker.acquire(
            services: [.runtime, .sessions],
            reason: .route("chat"),
            consumer: "route.chat"
        )
        XCTAssertEqual(route.servicesToStart, [.runtime, .sessions])
        let activeServices = await broker.activeServices()
        XCTAssertEqual(activeServices, [.runtime, .sessions])

        let runtimeOnly = await broker.acquire(
            services: [.runtime],
            reason: .capability("runtime jobs"),
            consumer: "capability.runtime.jobs"
        )
        XCTAssertEqual(runtimeOnly.servicesToStart, [])

        let routeRelease = await broker.release(route.lease)
        XCTAssertEqual(routeRelease.servicesToStop, [.sessions])
        XCTAssertEqual(routeRelease.activeServices, [.runtime])

        let finalRelease = await broker.release(runtimeOnly.lease)
        XCTAssertEqual(finalRelease.servicesToStop, [.runtime])
        XCTAssertEqual(finalRelease.activeServices, [])
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }
}
