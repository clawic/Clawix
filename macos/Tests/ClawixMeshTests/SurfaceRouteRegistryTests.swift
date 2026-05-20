import XCTest
@testable import Clawix

final class SurfaceRouteRegistryTests: XCTestCase {
    @MainActor
    func testRegistryEntryDescriptorMatchesSidebarRouteDescriptor() {
        for route in Self.allRepresentativeRoutes {
            let entry = SurfaceRouteRegistry.entry(for: route)

            XCTAssertEqual(entry.descriptor, route.surfaceDescriptor, entry.descriptor.id)
        }
    }

    @MainActor
    func testCoreRoutesStayInCoreRegistryModule() {
        let routes: [SidebarRoute] = [
            .home,
            .search,
            .project,
            .chat(UUID()),
            .settings,
            .rescue
        ]

        for route in routes {
            let entry = SurfaceRouteRegistry.entry(for: route)

            XCTAssertEqual(entry.module, .core, entry.descriptor.id)
            XCTAssertTrue(entry.descriptor.isCoreSurvivalRoute, entry.descriptor.id)
        }
    }

    @MainActor
    func testNonCoreRoutesStayOutsideCoreRegistryModule() {
        for route in Self.allRepresentativeRoutes where !route.surfaceDescriptor.isCoreSurvivalRoute {
            let entry = SurfaceRouteRegistry.entry(for: route)

            XCTAssertNotEqual(entry.module, .core, entry.descriptor.id)
        }
    }

    @MainActor
    func testRegistryKeepsProtectedSecretsSeparateFromOrdinaryModules() {
        let entry = SurfaceRouteRegistry.entry(for: .secretsHome)

        XCTAssertEqual(entry.module, .protected)
        XCTAssertEqual(entry.descriptor.criticality, .protected)
    }

    @MainActor
    func testCustomAppRoutesUseChildReportedReadiness() {
        let entry = SurfaceRouteRegistry.entry(for: .app(UUID()))

        XCTAssertEqual(entry.readinessMode, .childReported)
        XCTAssertEqual(entry.module, .apps)
    }

    @MainActor
    func testBuiltInRoutesUseImmediateReadiness() {
        let routes: [SidebarRoute] = [
            .databaseCollection("tasks"),
            .driveAdmin,
            .iotHome,
            .agentsHome,
            .networkControl,
            .publishingHome
        ]

        for route in routes {
            let entry = SurfaceRouteRegistry.entry(for: route)

            XCTAssertEqual(entry.readinessMode, .immediateAfterFirstRender, entry.descriptor.id)
        }
    }

    @MainActor
    func testActiveCustomVariantForcesChildReportedReadiness() {
        let builtInEntry = SurfaceRouteRegistry.entry(for: .databaseCollection("tasks"))
        let directAppEntry = SurfaceRouteRegistry.entry(for: .app(UUID()))

        XCTAssertEqual(
            SurfaceRouteReadinessPolicy.mode(
                for: builtInEntry,
                hasActiveCustomVariant: false
            ),
            .immediateAfterFirstRender
        )
        XCTAssertEqual(
            SurfaceRouteReadinessPolicy.mode(
                for: builtInEntry,
                hasActiveCustomVariant: true
            ),
            .childReported
        )
        XCTAssertEqual(
            SurfaceRouteReadinessPolicy.mode(
                for: directAppEntry,
                hasActiveCustomVariant: false
            ),
            .childReported
        )
    }

    private static let allRepresentativeRoutes: [SidebarRoute] = [
        .home,
        .search,
        .plugins,
        .automations,
        .project,
        .appsHome,
        .app(UUID()),
        .chat(UUID()),
        .settings,
        .rescue,
        .secretsHome,
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
}
