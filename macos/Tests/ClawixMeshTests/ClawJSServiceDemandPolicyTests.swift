import XCTest
@testable import Clawix

final class ClawJSServiceDemandPolicyTests: XCTestCase {
    func testMainStartupCoreDoesNotStartRuntimeServices() {
        XCTAssertEqual(
            ClawJSServiceDemandPolicy.startupServices(for: .main),
            []
        )
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

    func testManagerStartAPIDelegatesOnlyRequestedServices() throws {
        let managerSource = try readSource("ClawJS/ClawJSServiceManager.swift")
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertTrue(managerSource.contains("func start(_ services: Set<ClawJSService>, reason: ClawJSServiceStartReason) async"))
        XCTAssertTrue(managerSource.contains("await supervisor.start("))
        XCTAssertTrue(supervisorSource.contains("await startDaemonAwareServices(services)"))
        XCTAssertTrue(supervisorSource.contains("for service in orderedServices(from: services)"))
        XCTAssertFalse(supervisorSource.contains("for service in ClawJSService.allCases {\n            await launchLocal(service)"))
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
        XCTAssertTrue(source.contains("await serviceManager.start(demandedServices, reason: .route(descriptor.id))"))
        XCTAssertTrue(source.contains("serviceManager.startupIssue(for: demandedServices)"))
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
