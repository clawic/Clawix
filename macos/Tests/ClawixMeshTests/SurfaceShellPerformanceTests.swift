import XCTest
@testable import Clawix

final class SurfaceShellPerformanceTests: XCTestCase {
    func testCriticalShellStartFastPathStaysBoundedWithAllHeavyDependenciesUnavailable() {
        let routes: [SidebarRoute] = [
            .home,
            .search,
            .project,
            .chat(UUID(uuidString: "00000000-0000-0000-0000-000000000010")!),
            .settings,
            .rescue
        ]
        let descriptors = routes.map(\.surfaceDescriptor)
        let unavailableDependencies = Set(SurfaceRouteDependency.allCases)
        let iterations = 10_000

        let start = DispatchTime.now().uptimeNanoseconds
        var readyCount = 0
        for _ in 0..<iterations {
            for descriptor in descriptors {
                if SurfaceShellIsolationPolicy.criticalShellDependencies(for: descriptor).isEmpty,
                   SurfaceShellIsolationPolicy.surfaceDependencies(for: descriptor).isEmpty,
                   SurfaceShellIsolationPolicy.startCriticalShellState(
                        for: descriptor,
                        unavailableDependencies: unavailableDependencies
                   ) == .ready(surfaceID: descriptor.id) {
                    readyCount += 1
                }
            }
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000

        XCTAssertEqual(readyCount, iterations * descriptors.count)
        XCTAssertLessThan(
            elapsedMilliseconds,
            250,
            "Critical shell fast path should stay comfortably below one frame per route batch in synthetic dependency-failure measurement; measured \(elapsedMilliseconds)ms."
        )
    }

    func testExtensionSurfaceStartMeasurementRemainsRouteLocalUnderUnavailableDependencies() {
        let cases: [(SidebarRoute, Set<SurfaceRouteDependency>)] = [
            (.app(UUID(uuidString: "00000000-0000-0000-0000-000000000020")!), [.customApps, .downloads]),
            (.databaseCollection("tasks"), [.databaseBackfill]),
            (.iotHome, [.connectors, .externalProviders]),
            (.agentsHome, [.languageModels]),
            (.publishingHome, [.connectors, .externalProviders])
        ]
        let unavailableDependencies = Set(SurfaceRouteDependency.allCases)
        let iterations = 2_000

        let start = DispatchTime.now().uptimeNanoseconds
        var loadingCount = 0
        var localDependencyCount = 0
        for _ in 0..<iterations {
            for (route, expectedDependencies) in cases {
                let descriptor = route.surfaceDescriptor
                let localDependencies = SurfaceShellIsolationPolicy.unavailableSurfaceDependencies(
                    for: descriptor,
                    unavailableDependencies: unavailableDependencies
                )
                if localDependencies == expectedDependencies {
                    localDependencyCount += 1
                }
                if case .loading = SurfaceRouteSupervisor.start(descriptor: descriptor) {
                    loadingCount += 1
                }
            }
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000

        XCTAssertEqual(localDependencyCount, iterations * cases.count)
        XCTAssertEqual(loadingCount, iterations * cases.count)
        XCTAssertLessThan(
            elapsedMilliseconds,
            250,
            "Extension surface dependency classification should stay bounded and route-local in synthetic heavy-failure measurement; measured \(elapsedMilliseconds)ms."
        )
    }
}
