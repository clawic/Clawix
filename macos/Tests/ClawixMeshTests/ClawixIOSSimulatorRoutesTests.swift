import XCTest
@testable import Clawix

final class ClawixIOSSimulatorRoutesTests: XCTestCase {
    func testIOSSimulatorRoutesCentralizeXcodeAndSimulatorToolPaths() throws {
        let routesSource = try readSource("ClawixIOSSimulatorRoutes.swift")
        let framebufferSource = try readSource("IOSSimulatorFramebufferController.swift")
        let tempDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(ClawixIOSSimulatorRoutes.xcrunCLI, "/usr/bin/xcrun")
        XCTAssertEqual(ClawixSystemToolRoutes.xcrunCLI, "/usr/bin/xcrun")
        XCTAssertEqual(ClawixIOSSimulatorRoutes.xcodeDeveloperDir, "/Applications/Xcode.app/Contents/Developer")
        XCTAssertEqual(ClawixKnownAppRoutes.xcode.fallbackPath, "/Applications/Xcode.app")
        XCTAssertEqual(
            ClawixIOSSimulatorRoutes.simulatorKitFramework,
            "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
        )
        XCTAssertEqual(
            ClawixIOSSimulatorRoutes.coreSimulatorFramework,
            "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
        )
        XCTAssertEqual(
            ClawixAppleFrameworkRoutes.coreSimulatorFramework,
            "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
        )
        XCTAssertEqual(
            ClawixIOSSimulatorRoutes.ioKitFramework,
            "/System/Library/Frameworks/IOKit.framework/IOKit"
        )
        XCTAssertEqual(
            ClawixAppleFrameworkRoutes.ioKitFramework,
            "/System/Library/Frameworks/IOKit.framework/IOKit"
        )
        XCTAssertEqual(ClawixIOSSimulatorRoutes.screenshotTempPrefix, "clawix-ios-simulator")
        XCTAssertEqual(ClawixIOSSimulatorRoutes.toolTempPrefix, "clawix-ios-tool")
        XCTAssertEqual(
            ClawixIOSSimulatorRoutes.screenshotTempURL(
                deviceUDID: "SIM-1",
                id: "capture",
                temporaryDirectory: tempDirectory
            ).path,
            "/tmp/clawix-ios-simulator-SIM-1-capture.png"
        )
        XCTAssertEqual(
            ClawixIOSSimulatorRoutes.toolStdoutURL(id: "run", temporaryDirectory: tempDirectory).path,
            "/tmp/clawix-ios-tool-run.out"
        )
        XCTAssertEqual(
            ClawixIOSSimulatorRoutes.toolStderrURL(id: "run", temporaryDirectory: tempDirectory).path,
            "/tmp/clawix-ios-tool-run.err"
        )
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertTrue(routesSource.contains("static let xcrunCLI = ClawixSystemToolRoutes.xcrunCLI"))
        XCTAssertTrue(routesSource.contains("static let xcodeDeveloperDir = \"\\(ClawixKnownAppRoutes.xcode.fallbackPath)/Contents/Developer\""))
        XCTAssertTrue(routesSource.contains("static let coreSimulatorFramework = ClawixAppleFrameworkRoutes.coreSimulatorFramework"))
        XCTAssertTrue(routesSource.contains("static let ioKitFramework = ClawixAppleFrameworkRoutes.ioKitFramework"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertFalse(routesSource.contains("static let xcrunCLI = \"/usr/bin/xcrun\""))
        XCTAssertFalse(routesSource.contains("static let xcodeDeveloperDir = \"/Applications/Xcode.app/Contents/Developer\""))
        XCTAssertFalse(routesSource.contains("static let coreSimulatorFramework = \"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator\""))
        XCTAssertFalse(routesSource.contains("static let ioKitFramework = \"/System/Library/Frameworks/IOKit.framework/IOKit\""))
        XCTAssertTrue(framebufferSource.contains("ClawixIOSSimulatorRoutes.screenshotTempURL"))
        XCTAssertTrue(framebufferSource.contains("ClawixIOSSimulatorRoutes.toolStdoutURL"))
        XCTAssertTrue(framebufferSource.contains("ClawixIOSSimulatorRoutes.toolStderrURL"))
        XCTAssertFalse(framebufferSource.contains("clawix-ios-simulator-\\(device.udid)"))
        XCTAssertFalse(framebufferSource.contains("clawix-ios-tool-\\(UUID().uuidString)"))
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
