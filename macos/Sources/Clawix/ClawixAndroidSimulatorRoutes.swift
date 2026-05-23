import Foundation

enum ClawixAndroidSimulatorRoutes {
    static let androidHomeEnvKey = "ANDROID_HOME"
    static let androidSDKRootEnvKey = "ANDROID_SDK_ROOT"
    static let homeAndroidSDKSuffix = "Library/Android/sdk"
    static let homeAndroidAVDSuffix = ".android/avd"
    static let homebrewCommandLineToolsRoot = "\(ClawixSystemToolRoutes.optHomebrewShareDirectory)/android-commandlinetools"
    static let usrLocalCommandLineToolsRoot = "\(ClawixSystemToolRoutes.usrLocalShareDirectory)/android-commandlinetools"
    static let homebrewADB = ClawixSystemToolRoutes.optHomebrewBinTool("adb")
    static let usrLocalADB = ClawixSystemToolRoutes.usrLocalBinTool("adb")
    static let usrBinADB = ClawixSystemToolRoutes.usrBinTool("adb")
    static let homebrewEmulator = ClawixSystemToolRoutes.optHomebrewBinTool("emulator")
    static let usrLocalEmulator = ClawixSystemToolRoutes.usrLocalBinTool("emulator")
    static let toolTempPrefix = "clawix-android"
    static let stdoutExtension = "stdout"
    static let stderrExtension = "stderr"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func fallbackUserHomePath() -> String {
        ClawixUserHomeRoutes.path()
    }

    static func userHomePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        environment["HOME"] ?? fallbackUserHomePath()
    }

    static func sdkRoots(home: String, environment: [String: String]) -> [String] {
        [
            environment[androidHomeEnvKey],
            environment[androidSDKRootEnvKey],
            URL(fileURLWithPath: home).appendingPathComponent(homeAndroidSDKSuffix).path,
            homebrewCommandLineToolsRoot,
            usrLocalCommandLineToolsRoot,
        ].compactMap { $0 }
    }

    static func adbCandidates(sdkRoots: [String]) -> [String] {
        sdkRoots.map { URL(fileURLWithPath: $0).appendingPathComponent("platform-tools/adb").path } +
            [homebrewADB, usrLocalADB, usrBinADB]
    }

    static func emulatorCandidates(sdkRoots: [String]) -> [String] {
        sdkRoots.map { URL(fileURLWithPath: $0).appendingPathComponent("emulator/emulator").path } +
            [homebrewEmulator, usrLocalEmulator]
    }

    static func avdRoot(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(homeAndroidAVDSuffix)
    }

    static func avdConfig(home: String, name: String) -> URL {
        avdRoot(home: home).appendingPathComponent("\(name).avd/config.ini")
    }

    static func toolStdoutURL(
        token: String,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(toolTempPrefix)-\(token).\(stdoutExtension)")
    }

    static func toolStderrURL(
        token: String,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(toolTempPrefix)-\(token).\(stderrExtension)")
    }
}
