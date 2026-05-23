import Foundation

enum ClawixIOSSimulatorRoutes {
    static let xcrunCLI = ClawixSystemToolRoutes.xcrunCLI
    static let xcodeDeveloperDir = "\(ClawixKnownAppRoutes.xcode.fallbackPath)/Contents/Developer"
    static let simulatorKitFramework = "\(xcodeDeveloperDir)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
    static let coreSimulatorFramework = ClawixAppleFrameworkRoutes.coreSimulatorFramework
    static let ioKitFramework = ClawixAppleFrameworkRoutes.ioKitFramework
    static let screenshotTempPrefix = "clawix-ios-simulator"
    static let toolTempPrefix = "clawix-ios-tool"
    static let stdoutExtension = "out"
    static let stderrExtension = "err"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func screenshotTempURL(
        deviceUDID: String,
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(screenshotTempPrefix)-\(deviceUDID)-\(id).png")
    }

    static func toolStdoutURL(
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(toolTempPrefix)-\(id).\(stdoutExtension)")
    }

    static func toolStderrURL(
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(toolTempPrefix)-\(id).\(stderrExtension)")
    }
}
