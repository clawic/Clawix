import XCTest
@testable import Clawix

final class SurfaceRouteRegistryTests: XCTestCase {
    private static let reviewedSurfaceRouteModuleKinds: Set<String> = [
        "core",
        "protected",
        "apps",
        "automation",
        "data",
        "drive",
        "time",
        "skills",
        "iot",
        "design",
        "agents",
        "publishing",
        "life",
        "network"
    ]
    private static let reviewedSurfaceReadinessModeKinds = SurfaceRouteMetadataCatalog.manifestReadinessModeKinds
    private static let reviewedDirectChildReportedReadinessRouteCases = SurfaceRouteMetadataCatalog.manifestDirectChildReportedRouteCases
    private static let reviewedDirectChildReportedReadinessRouteIds = SurfaceRouteMetadataCatalog.manifestDirectChildReportedRouteCases

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
    func testSurfaceRouteModuleSetAndRepresentativeRoutingStayExact() {
        let reviewedModuleCases: [(SidebarRoute, SurfaceRouteModule)] = [
            (.home, .core),
            (.secretsHome, .protected),
            (.appsHome, .apps),
            (.automations, .automation),
            (.databaseHome, .data),
            (.macCare, .data),
            (.driveAdmin, .drive),
            (.calendarHome, .time),
            (.skills, .skills),
            (.iotHome, .iot),
            (.designTemplatesHome, .design),
            (.agentsHome, .agents),
            (.publishingHome, .publishing),
            (.lifeHome, .life),
            (.networkControl, .network)
        ]

        let entries = reviewedModuleCases.map { SurfaceRouteRegistry.entry(for: $0.0) }
        XCTAssertEqual(Set(SurfaceRouteModule.allCases.map(\.rawValue)), Self.reviewedSurfaceRouteModuleKinds)
        XCTAssertEqual(Set(entries.map { $0.module.rawValue }), Self.reviewedSurfaceRouteModuleKinds)
        for (route, expectedModule) in reviewedModuleCases {
            XCTAssertEqual(SurfaceRouteRegistry.entry(for: route).module, expectedModule)
        }

        for route in Self.allRepresentativeRoutes {
            let entry = SurfaceRouteRegistry.entry(for: route)

            XCTAssertEqual(entry.module, route.surfaceRouteMetadata.module, entry.descriptor.id)
        }
    }

    func testRepresentativeRoutesCoverManifestRouteCases() {
        XCTAssertEqual(
            Set(Self.allRepresentativeRoutes.map(\.surfaceRouteMetadata.routeCase)),
            SurfaceRouteMetadataCatalog.manifestRouteCases
        )
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

    @MainActor
    func testReadinessModesAndDirectChildReportedRoutesStayExact() {
        let entries = Self.reviewedReadinessRoutes.map { SurfaceRouteRegistry.entry(for: $0) }
        let reviewedModeKinds = Set(
            [
                SurfaceRouteReadinessMode.immediateAfterFirstRender,
                SurfaceRouteReadinessMode.childReported
            ].map(Self.surfaceReadinessModeKind)
        )

        XCTAssertEqual(reviewedModeKinds, Self.reviewedSurfaceReadinessModeKinds)
        XCTAssertEqual(Set(entries.map { Self.surfaceReadinessModeKind($0.readinessMode) }), Self.reviewedSurfaceReadinessModeKinds)
        XCTAssertEqual(
            Set(Self.reviewedReadinessRoutes.filter {
                SurfaceRouteRegistry.entry(for: $0).readinessMode == .childReported
            }.map(\.surfaceRouteMetadata.routeCase)),
            Self.reviewedDirectChildReportedReadinessRouteCases
        )
        XCTAssertEqual(
            Set(Self.reviewedReadinessRoutes.filter {
                SurfaceRouteRegistry.entry(for: $0).readinessMode == .childReported
            }.map(\.surfaceRouteMetadata.routeCase)),
            Self.reviewedDirectChildReportedReadinessRouteIds
        )

        for entry in entries where entry.readinessMode == .immediateAfterFirstRender && entry.descriptor.canUseCustomVariantDefault {
            XCTAssertEqual(
                SurfaceRouteReadinessPolicy.mode(for: entry, hasActiveCustomVariant: false),
                .immediateAfterFirstRender,
                entry.descriptor.id
            )
            XCTAssertEqual(
                SurfaceRouteReadinessPolicy.mode(for: entry, hasActiveCustomVariant: true),
                .childReported,
                entry.descriptor.id
            )
        }
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
            .macCare,
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

    private static let reviewedReadinessRoutes: [SidebarRoute] = [
        .home,
        .search,
        .plugins,
        .automations,
        .project,
        .appsHome,
        .app(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
        .chat(UUID(uuidString: "00000000-0000-0000-0000-000000000004")!),
        .settings,
        .rescue,
        .secretsHome,
        .databaseHome,
        .databaseWorkbench,
            .databaseCollection("tasks"),
            .memoryHome,
            .indexHome,
            .macCare,
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

    private static func surfaceReadinessModeKind(_ readinessMode: SurfaceRouteReadinessMode) -> String {
        switch readinessMode {
        case .immediateAfterFirstRender:
            return "immediateAfterFirstRender"
        case .childReported:
            return "childReported"
        }
    }
}
