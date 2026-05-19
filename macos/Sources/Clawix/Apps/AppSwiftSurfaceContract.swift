import Foundation

struct AppSwiftSurfaceManifest: Codable, Equatable, Hashable {
    var schemaVersion: Int
    var root: AppSwiftSurfaceNode
    var requestedCapabilities: [String]

    init(
        schemaVersion: Int = 1,
        root: AppSwiftSurfaceNode,
        requestedCapabilities: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.root = root
        self.requestedCapabilities = requestedCapabilities
    }
}

struct AppSwiftSurfaceNode: Codable, Equatable, Hashable {
    enum Kind: String, Codable, Equatable, Hashable {
        case text
        case button
        case list
        case stack
    }

    var kind: Kind
    var id: String?
    var text: String?
    var dataSource: String?
    var action: AppSwiftSurfaceAction?
    var children: [AppSwiftSurfaceNode]

    init(
        kind: Kind,
        id: String? = nil,
        text: String? = nil,
        dataSource: String? = nil,
        action: AppSwiftSurfaceAction? = nil,
        children: [AppSwiftSurfaceNode] = []
    ) {
        self.kind = kind
        self.id = id
        self.text = text
        self.dataSource = dataSource
        self.action = action
        self.children = children
    }
}

struct AppSwiftSurfaceAction: Codable, Equatable, Hashable {
    enum Invocation: String, Codable, Equatable, Hashable {
        case sdkRead
        case sdkAction
    }

    var invocation: Invocation
    var capabilityId: String
    var operation: String

    init(invocation: Invocation, capabilityId: String, operation: String) {
        self.invocation = invocation
        self.capabilityId = capabilityId
        self.operation = operation
    }
}

struct AppSwiftSurfaceRunnerPlan: Equatable, Hashable {
    var appId: UUID
    var appSlug: String
    var manifestPath: String
    var outOfProcess: Bool
    var protocolVersion: Int
    var allowedCapabilities: [String]
}

struct AppSwiftSurfaceRunnerLaunch: Equatable, Hashable {
    var plan: AppSwiftSurfaceRunnerPlan
    var executablePath: String
    var timeoutSeconds: TimeInterval

    init(
        plan: AppSwiftSurfaceRunnerPlan,
        executablePath: String,
        timeoutSeconds: TimeInterval = 10
    ) {
        self.plan = plan
        self.executablePath = executablePath
        self.timeoutSeconds = timeoutSeconds
    }
}

struct AppSwiftSurfaceRunnerResult: Equatable, Hashable {
    var pid: Int32?
    var exitCode: Int32?
    var timedOut: Bool
    var cancelled: Bool
    var stderr: String

    init(
        pid: Int32? = nil,
        exitCode: Int32? = nil,
        timedOut: Bool = false,
        cancelled: Bool = false,
        stderr: String = ""
    ) {
        self.pid = pid
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.stderr = stderr
    }
}

enum AppSwiftSurfaceRunnerState: Equatable, Hashable {
    case idle
    case launching
    case running(pid: Int32)
    case exited(code: Int32)
    case crashed(reason: String)
    case timedOut(seconds: TimeInterval)
    case cancelled
}

protocol AppSwiftSurfaceRunnerExecuting {
    func run(_ launch: AppSwiftSurfaceRunnerLaunch) -> AppSwiftSurfaceRunnerResult
}

final class AppSwiftSurfaceRunnerSupervisor {
    private let executor: AppSwiftSurfaceRunnerExecuting
    private(set) var state: AppSwiftSurfaceRunnerState = .idle

    init(executor: AppSwiftSurfaceRunnerExecuting = AppSwiftSurfaceProcessExecutor()) {
        self.executor = executor
    }

    @discardableResult
    func launch(_ launch: AppSwiftSurfaceRunnerLaunch) -> AppSwiftSurfaceRunnerState {
        guard launch.plan.outOfProcess else {
            state = .crashed(reason: "Swift surface runner must be out-of-process.")
            return state
        }
        state = .launching
        let result = executor.run(launch)
        state = Self.classify(result: result, timeoutSeconds: launch.timeoutSeconds)
        return state
    }

    static func classify(
        result: AppSwiftSurfaceRunnerResult,
        timeoutSeconds: TimeInterval
    ) -> AppSwiftSurfaceRunnerState {
        if result.cancelled {
            return .cancelled
        }
        if result.timedOut {
            return .timedOut(seconds: timeoutSeconds)
        }
        if let exitCode = result.exitCode, exitCode == 0 {
            return .exited(code: exitCode)
        }
        let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exitCode = result.exitCode {
            return .crashed(reason: reason.isEmpty ? "Swift surface runner exited with status \(exitCode)." : reason)
        }
        return .crashed(reason: reason.isEmpty ? "Swift surface runner did not return an exit status." : reason)
    }
}

struct AppSwiftSurfaceProcessExecutor: AppSwiftSurfaceRunnerExecuting {
    func run(_ launch: AppSwiftSurfaceRunnerLaunch) -> AppSwiftSurfaceRunnerResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = [
            "--manifest", launch.plan.manifestPath,
            "--protocol-version", String(launch.plan.protocolVersion),
            "--app-slug", launch.plan.appSlug
        ]

        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return AppSwiftSurfaceRunnerResult(
                pid: nil,
                exitCode: nil,
                timedOut: false,
                stderr: "spawn failed: \(error.localizedDescription)"
            )
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        let deadline = Date().addingTimeInterval(max(0, launch.timeoutSeconds))
        while Date() < deadline {
            if Task.isCancelled {
                process.terminate()
                return AppSwiftSurfaceRunnerResult(
                    pid: process.processIdentifier,
                    exitCode: nil,
                    cancelled: true,
                    stderr: "Swift surface runner cancelled."
                )
            }
            if finished.wait(timeout: .now() + .milliseconds(50)) == .success {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: data, encoding: .utf8) ?? ""
                return AppSwiftSurfaceRunnerResult(
                    pid: process.processIdentifier,
                    exitCode: process.terminationStatus,
                    timedOut: false,
                    stderr: stderrText
                )
            }
        }

        if process.isRunning {
            process.terminate()
        }
        return AppSwiftSurfaceRunnerResult(
            pid: process.processIdentifier,
            exitCode: nil,
            timedOut: true,
            stderr: "Swift surface runner timed out."
        )
    }
}

enum AppSwiftSurfaceContract {
    static let protocolVersion = 1
    static let manifestFilename = "surface.json"

    static func validate(manifest: AppSwiftSurfaceManifest, for app: AppRecord) throws {
        guard app.effectiveSurfaceKind == .swiftDeclarative else {
            throw AppSwiftSurfaceValidationError.notSwiftSurface(app.slug)
        }
        guard manifest.schemaVersion == protocolVersion else {
            throw AppSwiftSurfaceValidationError.unsupportedSchema(manifest.schemaVersion)
        }
        let declared = Set(app.effectiveDeclaredCapabilities)
        for capability in manifest.requestedCapabilities {
            try validateCapability(capability, declared: declared, app: app)
        }
        try validateNode(manifest.root, declared: declared, app: app)
    }

    static func decodeManifest(data: Data) throws -> AppSwiftSurfaceManifest {
        try JSONDecoder().decode(AppSwiftSurfaceManifest.self, from: data)
    }

    static func runnerPlan(
        app: AppRecord,
        manifest: AppSwiftSurfaceManifest,
        manifestPath: String
    ) throws -> AppSwiftSurfaceRunnerPlan {
        try validate(manifest: manifest, for: app)
        return AppSwiftSurfaceRunnerPlan(
            appId: app.id,
            appSlug: app.slug,
            manifestPath: manifestPath,
            outOfProcess: true,
            protocolVersion: protocolVersion,
            allowedCapabilities: manifest.requestedCapabilities.sorted()
        )
    }

    static func runnerExecutablePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let value = environment["CLAWIX_SWIFT_SURFACE_RUNNER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func validateNode(
        _ node: AppSwiftSurfaceNode,
        declared: Set<String>,
        app: AppRecord
    ) throws {
        if let action = node.action {
            try validateAction(action, declared: declared, app: app)
        }
        for child in node.children {
            try validateNode(child, declared: declared, app: app)
        }
    }

    private static func validateAction(
        _ action: AppSwiftSurfaceAction,
        declared: Set<String>,
        app: AppRecord
    ) throws {
        try validateCapability(action.capabilityId, declared: declared, app: app)
        guard let descriptor = AppCapabilityCatalog.descriptor(id: action.capabilityId) else {
            throw AppSwiftSurfaceValidationError.unknownCapability(action.capabilityId)
        }
        switch action.invocation {
        case .sdkRead:
            guard descriptor.customAppAccess == .localWide else {
                throw AppSwiftSurfaceValidationError.highRiskRead(action.capabilityId)
            }
        case .sdkAction:
            guard descriptor.customAppAccess == .approvalRequired else {
                throw AppSwiftSurfaceValidationError.actionNotApprovalRequired(action.capabilityId)
            }
        }
    }

    private static func validateCapability(
        _ capabilityId: String,
        declared: Set<String>,
        app: AppRecord
    ) throws {
        guard AppCapabilityCatalog.descriptor(id: capabilityId) != nil else {
            throw AppSwiftSurfaceValidationError.unknownCapability(capabilityId)
        }
        if declared.isEmpty {
            guard app.effectiveOriginClass == .localUserAuthored || app.effectiveOriginClass == .system else {
                throw AppSwiftSurfaceValidationError.capabilityNotDeclared(capabilityId)
            }
            return
        }
        guard declared.contains(capabilityId) else {
            throw AppSwiftSurfaceValidationError.capabilityNotDeclared(capabilityId)
        }
    }
}

enum AppSwiftSurfaceValidationError: LocalizedError, Equatable {
    case notSwiftSurface(String)
    case unsupportedSchema(Int)
    case unknownCapability(String)
    case capabilityNotDeclared(String)
    case highRiskRead(String)
    case actionNotApprovalRequired(String)

    var errorDescription: String? {
        switch self {
        case .notSwiftSurface(let slug):
            return "App is not a Swift declarative surface: \(slug)"
        case .unsupportedSchema(let version):
            return "Unsupported Swift surface schema: \(version)"
        case .unknownCapability(let id):
            return "Unknown Swift surface capability: \(id)"
        case .capabilityNotDeclared(let id):
            return "Swift surface manifest does not declare capability: \(id)"
        case .highRiskRead(let id):
            return "High-risk capability cannot be used as a read: \(id)"
        case .actionNotApprovalRequired(let id):
            return "SDK action must use an approval-required capability: \(id)"
        }
    }
}
