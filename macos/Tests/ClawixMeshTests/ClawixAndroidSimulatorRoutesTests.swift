import XCTest
@testable import Clawix

final class ClawixAndroidSimulatorRoutesTests: XCTestCase {
    func testAndroidSimulatorRoutesCentralizeToolchainCandidates() throws {
        let routesSource = try readSource("ClawixAndroidSimulatorRoutes.swift")
        let processSource = try readSource("AndroidSimulatorProcess.swift")
        let toolchainSource = try readSource("AndroidSimulatorToolchain.swift")
        let tempDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        let roots = ClawixAndroidSimulatorRoutes.sdkRoots(
            home: "/Users/demo",
            environment: [
                ClawixAndroidSimulatorRoutes.androidHomeEnvKey: "/opt/android-home",
                ClawixAndroidSimulatorRoutes.androidSDKRootEnvKey: "/opt/android-sdk",
            ]
        )

        XCTAssertEqual(
            roots,
            [
                "/opt/android-home",
                "/opt/android-sdk",
                "/Users/demo/Library/Android/sdk",
                "/opt/homebrew/share/android-commandlinetools",
                "/usr/local/share/android-commandlinetools",
            ]
        )
        XCTAssertEqual(
            ClawixAndroidSimulatorRoutes.adbCandidates(sdkRoots: ["/sdk"]),
            ["/sdk/platform-tools/adb", "/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/usr/bin/adb"]
        )
        XCTAssertEqual(
            ClawixAndroidSimulatorRoutes.emulatorCandidates(sdkRoots: ["/sdk"]),
            ["/sdk/emulator/emulator", "/opt/homebrew/bin/emulator", "/usr/local/bin/emulator"]
        )
        XCTAssertEqual(ClawixSystemToolRoutes.optHomebrewBinTool("adb"), "/opt/homebrew/bin/adb")
        XCTAssertEqual(ClawixSystemToolRoutes.usrLocalBinTool("adb"), "/usr/local/bin/adb")
        XCTAssertEqual(ClawixSystemToolRoutes.usrBinTool("adb"), "/usr/bin/adb")
        XCTAssertEqual(ClawixAndroidSimulatorRoutes.avdRoot(home: "/Users/demo").path, "/Users/demo/.android/avd")
        XCTAssertEqual(
            ClawixAndroidSimulatorRoutes.avdConfig(home: "/Users/demo", name: "Pixel").path,
            "/Users/demo/.android/avd/Pixel.avd/config.ini"
        )
        XCTAssertEqual(
            ClawixAndroidSimulatorRoutes.userHomePath(environment: ["HOME": "/Users/demo"]),
            "/Users/demo"
        )
        XCTAssertFalse(ClawixAndroidSimulatorRoutes.fallbackUserHomePath().isEmpty)
        XCTAssertFalse(ClawixUserHomeRoutes.path().isEmpty)
        XCTAssertEqual(ClawixAndroidSimulatorRoutes.toolTempPrefix, "clawix-android")
        XCTAssertEqual(
            ClawixAndroidSimulatorRoutes.toolStdoutURL(token: "run", temporaryDirectory: tempDirectory).path,
            "/tmp/clawix-android-run.stdout"
        )
        XCTAssertEqual(
            ClawixAndroidSimulatorRoutes.toolStderrURL(token: "run", temporaryDirectory: tempDirectory).path,
            "/tmp/clawix-android-run.stderr"
        )
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(processSource.contains("ClawixAndroidSimulatorRoutes.toolStdoutURL"))
        XCTAssertTrue(processSource.contains("ClawixAndroidSimulatorRoutes.toolStderrURL"))
        XCTAssertTrue(toolchainSource.contains("ClawixAndroidSimulatorRoutes.userHomePath(environment: env)"))
        XCTAssertTrue(toolchainSource.contains("ClawixAndroidSimulatorRoutes.userHomePath()"))
        XCTAssertTrue(routesSource.contains("static func fallbackUserHomePath() -> String"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.optHomebrewBinTool(\"adb\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.usrLocalBinTool(\"adb\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.usrBinTool(\"adb\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.optHomebrewBinTool(\"emulator\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.usrLocalBinTool(\"emulator\")"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.path()"))
        XCTAssertTrue(routesSource.contains("environment[\"HOME\"] ?? fallbackUserHomePath()"))
        XCTAssertFalse(routesSource.contains("NSHomeDirectory()"))
        XCTAssertFalse(routesSource.contains("environment[\"HOME\"] ?? NSHomeDirectory()"))
        XCTAssertFalse(routesSource.contains("\"/opt/homebrew/bin/adb\""))
        XCTAssertFalse(routesSource.contains("\"/usr/local/bin/adb\""))
        XCTAssertFalse(routesSource.contains("\"/usr/bin/adb\""))
        XCTAssertFalse(routesSource.contains("\"/opt/homebrew/bin/emulator\""))
        XCTAssertFalse(routesSource.contains("\"/usr/local/bin/emulator\""))
        XCTAssertFalse(processSource.contains("URL(fileURLWithPath: NSTemporaryDirectory()"))
        XCTAssertFalse(processSource.contains("clawix-android-\\(token)"))
        XCTAssertFalse(toolchainSource.contains("env[\"HOME\"] ?? NSHomeDirectory()"))
        XCTAssertFalse(toolchainSource.contains("ProcessInfo.processInfo.environment[\"HOME\"] ?? NSHomeDirectory()"))
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
