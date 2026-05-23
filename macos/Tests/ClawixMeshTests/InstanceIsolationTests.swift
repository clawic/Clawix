import XCTest
@testable import Clawix

/// Phase 0 isolation seams. Parallel agent instances launched by the dev
/// provisioner must redirect every writable surface via environment so they
/// never collide on storage, ports, or prefs. These lock the env reads.
final class InstanceIsolationTests: XCTestCase {
    func testInstanceStateRootIsNilWhenUnsetOrEmpty() {
        XCTAssertNil(ClawixPersistentSurfacePaths.instanceStateRoot(environment: [:]))
        XCTAssertNil(ClawixPersistentSurfacePaths.instanceStateRoot(
            environment: ["CLAWIX_STATE_ROOT": ""]
        ))
    }

    func testInstanceStateRootResolvesAbsolutePath() {
        let root = ClawixPersistentSurfacePaths.instanceStateRoot(
            environment: ["CLAWIX_STATE_ROOT": "/tmp/clawix-instance-7"]
        )
        XCTAssertEqual(root?.path, "/tmp/clawix-instance-7")
    }

    func testInstanceStateRootExpandsTilde() {
        let root = ClawixPersistentSurfacePaths.instanceStateRoot(
            environment: ["CLAWIX_STATE_ROOT": "~/clawix-instances/abc"]
        )
        let expected = ("~/clawix-instances/abc" as NSString).expandingTildeInPath
        XCTAssertEqual(root?.path, expected)
    }

    func testApplicationSupportRootRedirectsUnderStateRoot() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-iso-\(UUID().uuidString)", isDirectory: true)
        setenv("CLAWIX_STATE_ROOT", tmp.path, 1)
        defer {
            unsetenv("CLAWIX_STATE_ROOT")
            try? FileManager.default.removeItem(at: tmp)
        }
        let support = try ClawixPersistentSurfacePaths.applicationSupportRoot()
        XCTAssertTrue(
            support.path.hasPrefix(tmp.path),
            "expected \(support.path) to live under the instance state root \(tmp.path)"
        )
        XCTAssertTrue(support.path.hasSuffix("Library/Application Support/Clawix"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: support.path),
            "applicationSupportRoot should create the directory under the override"
        )
    }

    func testHTTPPortEnvOverrideWins() {
        XCTAssertEqual(
            MeshClient.resolvedHTTPPort(environment: ["CLAWIX_BRIDGE_HTTP_PORT": "24999"]),
            24999
        )
    }

    func testHTTPPortFallsBackToDefaultWhenEnvAbsent() {
        UserDefaults.standard.removeObject(forKey: MeshClient.httpPortDefaultsKey)
        XCTAssertEqual(MeshClient.resolvedHTTPPort(environment: [:]), MeshClient.defaultHTTPPort)
    }

    func testHTTPPortIgnoresInvalidEnv() {
        UserDefaults.standard.removeObject(forKey: MeshClient.httpPortDefaultsKey)
        XCTAssertEqual(
            MeshClient.resolvedHTTPPort(environment: ["CLAWIX_BRIDGE_HTTP_PORT": "0"]),
            MeshClient.defaultHTTPPort
        )
        XCTAssertEqual(
            MeshClient.resolvedHTTPPort(environment: ["CLAWIX_BRIDGE_HTTP_PORT": "notaport"]),
            MeshClient.defaultHTTPPort
        )
    }
}
