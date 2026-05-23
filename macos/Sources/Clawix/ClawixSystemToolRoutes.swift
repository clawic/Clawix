import Foundation

enum ClawixSystemToolRoutes {
    static let optHomebrewDirectory = "/opt/homebrew"
    static let optHomebrewBinDirectory = "\(optHomebrewDirectory)/bin"
    static let optHomebrewShareDirectory = "\(optHomebrewDirectory)/share"
    static let usrLocalBinDirectory = "/usr/local/bin"
    static let usrLocalShareDirectory = "/usr/local/share"
    static let usrBinDirectory = "/usr/bin"
    static let binDirectory = "/bin"
    static let usrSbinDirectory = "/usr/sbin"
    static let sbinDirectory = "/sbin"

    static let envCLI = usrBinTool("env")
    static let gitCLI = usrBinTool("git")
    static let xcrunCLI = usrBinTool("xcrun")
    static let tarCLI = usrBinTool("tar")
    static let shellCLI = binTool("sh")
    static let zshCLI = binTool("zsh")
    static let launchctlCLI = binTool("launchctl")
    static let psCLI = binTool("ps")
    static let lsofCLI = usrSbinTool("lsof")
    static let screencaptureCLI = usrSbinTool("screencapture")

    static func optHomebrewBinTool(_ name: String) -> String {
        "\(optHomebrewBinDirectory)/\(name)"
    }

    static func usrLocalBinTool(_ name: String) -> String {
        "\(usrLocalBinDirectory)/\(name)"
    }

    static func usrBinTool(_ name: String) -> String {
        "\(usrBinDirectory)/\(name)"
    }

    static func binTool(_ name: String) -> String {
        "\(binDirectory)/\(name)"
    }

    static func usrSbinTool(_ name: String) -> String {
        "\(usrSbinDirectory)/\(name)"
    }

    static var envURL: URL {
        URL(fileURLWithPath: envCLI)
    }
}
