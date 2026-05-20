import XCTest
@testable import Clawix

final class SurfaceRouteDescriptorTests: XCTestCase {
    func testCoreSurvivalRoutesHaveNoSurfaceTimeout() {
        let routes: [SidebarRoute] = [
            .home,
            .search,
            .project,
            .chat(UUID()),
            .settings,
            .rescue
        ]

        for route in routes {
            let descriptor = route.surfaceDescriptor
            XCTAssertEqual(descriptor.criticality, .core, descriptor.id)
            XCTAssertTrue(descriptor.isCoreSurvivalRoute, descriptor.id)
            XCTAssertNil(descriptor.timeoutSeconds, descriptor.id)
            XCTAssertFalse(descriptor.requiresIndependentDegradation, descriptor.id)
        }
    }

    func testCriticalShellRoutesDoNotDependOnHeavySurfaceResources() {
        let routes: [SidebarRoute] = [
            .home,
            .search,
            .project,
            .chat(UUID()),
            .settings,
            .rescue
        ]
        let unavailableDependencies = Set(SurfaceRouteDependency.allCases)

        for route in routes {
            let descriptor = route.surfaceDescriptor

            XCTAssertEqual(SurfaceShellIsolationPolicy.surfaceDependencies(for: descriptor), [], descriptor.id)
            XCTAssertEqual(
                SurfaceShellIsolationPolicy.criticalShellDependencies(for: descriptor),
                [],
                descriptor.id
            )
            XCTAssertEqual(
                SurfaceShellIsolationPolicy.startCriticalShellState(
                    for: descriptor,
                    unavailableDependencies: unavailableDependencies
                ),
                .ready(surfaceID: descriptor.id),
                descriptor.id
            )
        }
    }

    func testNoSidebarSurfaceDeclaresDependenciesThatBlockTheCriticalShell() {
        let routes: [SidebarRoute] = [
            .home,
            .search,
            .project,
            .chat(UUID()),
            .settings,
            .rescue,
            .secretsHome,
            .app(UUID()),
            .appsHome,
            .databaseHome,
            .databaseWorkbench,
            .databaseCollection("tasks"),
            .memoryHome,
            .indexHome,
            .marketplaceHome,
            .driveAdmin,
            .drivePhotos,
            .driveDocuments,
            .driveRecent,
            .driveFolder("folder-1"),
            .calendarHome,
            .contactsHome,
            .networkControl,
            .skills,
            .skillDetail(slug: "summarizer"),
            .iotHome,
            .iotDeviceDetail(id: "lamp-1"),
            .designStylesHome,
            .designStyleDetail(id: "style-1"),
            .designTemplatesHome,
            .designTemplateDetail(id: "template-1"),
            .designReferencesHome,
            .designEditor(documentId: "editor-1"),
            .agentsHome,
            .agentDetail(id: "agent-1"),
            .personalitiesHome,
            .personalityDetail(id: "personality-1"),
            .skillCollectionsHome,
            .skillCollectionDetail(id: "collection-1"),
            .connectionsHome,
            .connectionDetail(id: "connection-1"),
            .publishingHome,
            .publishingComposer(prefillBody: "draft", prefillScheduleAt: nil),
            .publishingChannels,
            .lifeHome,
            .lifeVertical(id: "health"),
            .lifeSettings
        ]

        for route in routes {
            let descriptor = route.surfaceDescriptor

            XCTAssertEqual(
                SurfaceShellIsolationPolicy.criticalShellDependencies(for: descriptor),
                [],
                descriptor.id
            )
        }
    }

    func testExtensionSurfacesRequireIndependentDegradationAndTimeout() {
        let routes: [SidebarRoute] = [
            .app(UUID()),
            .appsHome,
            .databaseCollection("tasks"),
            .driveAdmin,
            .calendarHome,
            .networkControl,
            .iotHome,
            .designTemplatesHome,
            .agentsHome,
            .publishingHome,
            .lifeHome
        ]

        for route in routes {
            let descriptor = route.surfaceDescriptor
            XCTAssertEqual(descriptor.criticality, .extensionSurface, descriptor.id)
            XCTAssertEqual(descriptor.timeoutSeconds, 5, descriptor.id)
            XCTAssertTrue(descriptor.requiresIndependentDegradation, descriptor.id)
        }
    }

    func testExtensionSurfaceDependenciesAreLocalToTheSurface() {
        let cases: [(SidebarRoute, Set<SurfaceRouteDependency>)] = [
            (.app(UUID()), [.customApps, .downloads]),
            (.appsHome, [.customApps, .downloads]),
            (.databaseCollection("tasks"), [.databaseBackfill]),
            (.indexHome, [.searchIndex]),
            (.driveAdmin, [.connectors, .downloads]),
            (.calendarHome, [.connectors, .downloads]),
            (.networkControl, [.connectors]),
            (.iotHome, [.connectors, .externalProviders]),
            (.agentsHome, [.languageModels]),
            (.publishingHome, [.connectors, .externalProviders])
        ]
        let unavailableDependencies = Set(SurfaceRouteDependency.allCases)

        for (route, expectedDependencies) in cases {
            let descriptor = route.surfaceDescriptor

            XCTAssertEqual(
                SurfaceShellIsolationPolicy.surfaceDependencies(for: descriptor),
                expectedDependencies,
                descriptor.id
            )
            XCTAssertEqual(
                SurfaceShellIsolationPolicy.unavailableSurfaceDependencies(
                    for: descriptor,
                    unavailableDependencies: unavailableDependencies
                ),
                expectedDependencies,
                descriptor.id
            )
            XCTAssertEqual(
                SurfaceShellIsolationPolicy.criticalShellDependencies(for: descriptor),
                [],
                descriptor.id
            )
        }
    }

    func testProtectedSurfacesAreNotClassifiedAsOrdinaryExtensions() {
        let descriptor = SidebarRoute.secretsHome.surfaceDescriptor

        XCTAssertEqual(descriptor.criticality, .protected)
        XCTAssertEqual(descriptor.timeoutSeconds, 8)
        XCTAssertTrue(descriptor.requiresIndependentDegradation)
        XCTAssertEqual(descriptor.routeTarget, "secrets")
        XCTAssertTrue(descriptor.canUseCustomVariantDefault)
    }

    func testVariantDefaultSupportRequiresRouteTarget() {
        XCTAssertNil(SidebarRoute.chat(UUID()).surfaceDescriptor.routeTarget)
        XCTAssertFalse(SidebarRoute.chat(UUID()).surfaceDescriptor.canUseCustomVariantDefault)

        let database = SidebarRoute.databaseCollection("tasks").surfaceDescriptor
        XCTAssertEqual(database.routeTarget, "database/tasks")
        XCTAssertTrue(database.canUseCustomVariantDefault)

        let network = SidebarRoute.networkControl.surfaceDescriptor
        XCTAssertEqual(network.routeTarget, "network-control")
        XCTAssertTrue(network.canUseCustomVariantDefault)
    }
}
