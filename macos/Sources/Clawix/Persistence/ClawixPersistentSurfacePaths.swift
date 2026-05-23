import Foundation

enum ClawixPersistentSurfacePaths {
    /// Per-instance state isolation seam. When `CLAWIX_STATE_ROOT` is set it
    /// acts as a private home for this process and every writable state path
    /// resolves under it, so parallel agent instances launched by the dev
    /// provisioner never collide on Application Support, ~/.clawix, ~/.claw,
    /// logs or caches. Unset in normal user builds, where paths resolve to the
    /// real Library/home locations. The display-only `userVisible*` strings
    /// below are intentionally not redirected.
    static func instanceStateRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let raw = environment["CLAWIX_STATE_ROOT"], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func applicationSupportRoot() throws -> URL {
        if let root = instanceStateRoot() {
            let url = root
                .appendingPathComponent(components.library, isDirectory: true)
                .appendingPathComponent(components.applicationSupport, isDirectory: true)
                .appendingPathComponent(components.clawix, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(components.clawix, isDirectory: true)
    }

    static func applicationSupportChild(_ child: String, isDirectory: Bool = true) throws -> URL {
        try applicationSupportRoot().appendingPathComponent(child, isDirectory: isDirectory)
    }

    static func userHomeDirectory() -> URL {
        ClawixUserHomeRoutes.directory()
    }

    static func homeChild(_ child: String, isDirectory: Bool = true) -> URL {
        (instanceStateRoot() ?? userHomeDirectory())
            .appendingPathComponent(components.clawixHome, isDirectory: true)
            .appendingPathComponent(child, isDirectory: isDirectory)
    }

    static func frameworkGlobalRoot() -> URL {
        (instanceStateRoot() ?? userHomeDirectory())
            .appendingPathComponent(components.clawHome, isDirectory: true)
    }

    static func frameworkGlobalChild(_ child: String, isDirectory: Bool = true) -> URL {
        frameworkGlobalRoot().appendingPathComponent(child, isDirectory: isDirectory)
    }

    static func userVisibleHomeChild(_ childComponents: [String]) -> String {
        guard !childComponents.isEmpty else { return "~" }
        return "~/" + childComponents.joined(separator: "/")
    }

    static func userVisibleHomeChild(_ childComponents: String...) -> String {
        userVisibleHomeChild(childComponents)
    }

    static func userVisibleLibraryChild(_ childComponents: String...) -> String {
        userVisibleHomeChild([components.library] + childComponents)
    }

    static func userVisibleClawixHomeRoot() -> String {
        userVisibleHomeChild(components.clawixHome)
    }

    static func userVisibleClawixHomeChild(_ childComponents: String...) -> String {
        userVisibleHomeChild([components.clawixHome] + childComponents)
    }

    static func userVisibleFrameworkRoot() -> String {
        userVisibleHomeChild(components.clawHome)
    }

    static func userVisibleFrameworkChild(_ childComponents: String...) -> String {
        userVisibleHomeChild([components.clawHome] + childComponents)
    }

    static func userVisibleFrameworkChildren(_ children: [String]) -> String {
        children.map { userVisibleFrameworkChild($0) }.joined(separator: ",")
    }

    static func userVisibleFrameworkDatabaseFragment(_ fragments: String...) -> String {
        userVisibleFrameworkChild(components.coreSQLiteFile) + "#" + fragments.joined(separator: ",")
    }

    static func userVisibleCachesChild(_ childComponents: [String]) -> String {
        userVisibleHomeChild([components.library, components.caches] + childComponents)
    }

    static func userVisibleCachesChild(_ childComponents: String...) -> String {
        userVisibleCachesChild(childComponents)
    }

    static func userVisibleClawixCachesChild(_ childComponents: String...) -> String {
        userVisibleCachesChild([components.clawix] + childComponents)
    }

    static func userVisibleApplicationSupportRoot() -> String {
        userVisibleLibraryChild(components.applicationSupport, components.clawix)
    }

    static func userVisibleApplicationSupportChild(_ childComponents: String...) -> String {
        userVisibleHomeChild([components.library, components.applicationSupport, components.clawix] + childComponents)
    }

    static func userVisibleClawixLogsRoot() -> String {
        userVisibleLibraryChild(components.logs, components.clawix)
    }

    static func expandedUserVisiblePath(
        _ value: String,
        userHomeDirectory explicitHomeDirectory: URL? = nil,
        isDirectory: Bool = true
    ) -> URL {
        let homeDirectory = explicitHomeDirectory ?? userHomeDirectory()
        if value == "~" {
            return homeDirectory
        }
        if value.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(value.dropFirst(2)), isDirectory: isDirectory)
        }
        return URL(fileURLWithPath: value, isDirectory: isDirectory)
    }

    static func logsRoot() throws -> URL {
        if let root = instanceStateRoot() {
            let url = root
                .appendingPathComponent(components.library, isDirectory: true)
                .appendingPathComponent(components.logs, isDirectory: true)
                .appendingPathComponent(components.clawix, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        return try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(components.logs, isDirectory: true)
            .appendingPathComponent(components.clawix, isDirectory: true)
    }

    static func cacheRoot() throws -> URL {
        if let root = instanceStateRoot() {
            let url = root
                .appendingPathComponent(components.library, isDirectory: true)
                .appendingPathComponent(components.caches, isDirectory: true)
                .appendingPathComponent(components.devCache, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        return try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(components.devCache, isDirectory: true)
    }

    static func picturesChild(_ child: String, isDirectory: Bool = true) -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(child, isDirectory: isDirectory)
    }

    enum components {
        static let clawix = "Clawix"
        static let clawHome = ".claw"
        static let clawixHome = ".clawix"
        static let clawWorkspace = ".claw"
        static let bridgeState = "state"
        static let workspace = "workspace"
        static let mesh = "mesh"
        static let bin = "bin"
        static let library = "Library"
        static let caches = "Caches"
        static let applicationSupport = "Application Support"
        static let logs = "Logs"
        static let devCache = "Clawix-Dev"
        static let apps = "Apps"
        static let resources = "resources"
        static let resourcesStateFile = "resources.json"
        static let design = "Design"
        static let frameworkApps = "apps"
        static let frameworkDesign = "design"
        static let coreSQLiteFile = "core.sqlite"
        static let agents = "agents"
        static let personalities = "personalities"
        static let skillCollections = "skill-collections"
        static let connections = "connections"
        static let snippetsTable = "snippets"
        static let skillsTable = "skills"
        static let providerRoutingTable = "provider_routing"
        static let providerSettingsTable = "provider_settings"
        static let clawjs = "clawjs"
        static let secrets = "secrets"
        static let localModels = "local-models"
        static let favicons = "Favicons"
        static let backendMetadata = "BackendMetadata"
        static let audio = "audio"
        static let dictation = "dictation"
        static let tmp = "tmp"
        static let dictationAudioDebug = "dictation-audio-debug"
        static let dictationSounds = "dictation-sounds"
        static let captures = "Clawix-Captures"
        static let appStorageFile = ".clawix-storage.json"
        static let bundleName = "Clawix_Clawix.bundle"
        static let bridgeStatusFile = "bridge-status.json"
        static let hostActionAuditFile = "host-action-audit.jsonl"
        static let macControlTimelineFile = "mac-control-timeline.jsonl"
        static let macControlPendingApprovalsFile = "mac-control-pending-approvals.json"
        static let sqlite = "clawix.sqlite"
        static let sqliteExtension = "sqlite"
        static let sessionsDatabase = "sessions.sqlite"
        static let indexDatabase = "index.sqlite"
        static let secretsDatabase = "secrets.sqlite"
        static let iotDatabase = "iot.sqlite"
        static let files = "files"
        static let blobs = "blobs"
        static let status = "status"
        static let sources = "Sources"
        static let helpers = "Helpers"
        static let bridged = "Bridged"
    }
}
