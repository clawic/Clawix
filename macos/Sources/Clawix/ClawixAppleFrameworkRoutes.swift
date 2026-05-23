import Foundation

enum ClawixAppleFrameworkRoutes {
    static let libraryDeveloperPrivateFrameworksDirectory = "/Library/Developer/PrivateFrameworks"
    static let systemLibraryFrameworksDirectory = "/System/Library/Frameworks"

    static let coreSimulatorFramework = developerPrivateFramework("CoreSimulator", binaryName: "CoreSimulator")
    static let ioKitFramework = systemFramework("IOKit", binaryName: "IOKit")

    static func developerPrivateFramework(_ name: String, binaryName: String) -> String {
        "\(libraryDeveloperPrivateFrameworksDirectory)/\(name).framework/\(binaryName)"
    }

    static func systemFramework(_ name: String, binaryName: String) -> String {
        "\(systemLibraryFrameworksDirectory)/\(name).framework/\(binaryName)"
    }
}
