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

    func testExtensionSurfacesRequireIndependentDegradationAndTimeout() {
        let routes: [SidebarRoute] = [
            .app(UUID()),
            .appsHome,
            .databaseCollection("tasks"),
            .driveAdmin,
            .calendarHome,
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
    }
}
