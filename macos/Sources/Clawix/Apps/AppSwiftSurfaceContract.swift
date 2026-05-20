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
    var arguments: [String: AppSwiftSurfaceJSONValue]?

    init(
        invocation: Invocation,
        capabilityId: String,
        operation: String,
        arguments: [String: AppSwiftSurfaceJSONValue]? = nil
    ) {
        self.invocation = invocation
        self.capabilityId = capabilityId
        self.operation = operation
        self.arguments = arguments
    }
}

enum AppSwiftSurfaceJSONValue: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AppSwiftSurfaceJSONValue])
    case object([String: AppSwiftSurfaceJSONValue])

    var foundationValue: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.foundationValue)
        case .object(let values):
            return values.mapValues(\.foundationValue)
        }
    }

    init(_ value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(value)
        case let value as Int64:
            self = .int(Int(value))
        case let value as Double:
            self = .double(value)
        case let value as Float:
            self = .double(Double(value))
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(AppSwiftSurfaceJSONValue.init))
        case let value as [String: Any]:
            self = .object(value.mapValues(AppSwiftSurfaceJSONValue.init))
        default:
            self = .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AppSwiftSurfaceJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AppSwiftSurfaceJSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
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
    var stdout: String

    init(
        pid: Int32? = nil,
        exitCode: Int32? = nil,
        timedOut: Bool = false,
        cancelled: Bool = false,
        stderr: String = "",
        stdout: String = ""
    ) {
        self.pid = pid
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.stderr = stderr
        self.stdout = stdout
    }
}

struct AppSwiftSurfaceRunnerRenderMessage: Codable, Equatable, Hashable {
    var schemaVersion: Int
    var type: String
    var root: AppSwiftSurfaceNode
    var requestedCapabilities: [String]

    init(
        schemaVersion: Int = AppSwiftSurfaceContract.protocolVersion,
        type: String = "render",
        root: AppSwiftSurfaceNode,
        requestedCapabilities: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.type = type
        self.root = root
        self.requestedCapabilities = requestedCapabilities
    }
}

struct AppSwiftSurfaceRenderPresentation: Equatable, Hashable {
    var title: String
    var capabilitiesSummary: String
    var root: AppSwiftSurfaceRenderedNode

    init(
        record: AppRecord,
        manifest: AppSwiftSurfaceManifest,
        plan: AppSwiftSurfaceRunnerPlan
    ) {
        title = record.name
        capabilitiesSummary = plan.allowedCapabilities.isEmpty
            ? "No declared capabilities"
            : plan.allowedCapabilities.joined(separator: ", ")
        root = AppSwiftSurfaceRenderedNode(node: manifest.root, path: "root")
    }
}

struct AppSwiftSurfaceRenderedNode: Equatable, Hashable, Identifiable {
    enum Kind: String, Equatable, Hashable {
        case text
        case button
        case list
        case stack
    }

    var id: String
    var kind: Kind
    var label: String
    var dataSource: String?
    var action: AppSwiftSurfaceRenderedAction?
    var children: [AppSwiftSurfaceRenderedNode]

    init(node: AppSwiftSurfaceNode, path: String) {
        let trimmedID = node.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        id = trimmedID?.isEmpty == false ? trimmedID! : path
        kind = Kind(rawValue: node.kind.rawValue) ?? .stack
        dataSource = Self.nonEmpty(node.dataSource)
        action = node.action.map(AppSwiftSurfaceRenderedAction.init(action:))
        children = node.children.enumerated().map { index, child in
            AppSwiftSurfaceRenderedNode(node: child, path: "\(path).\(index)")
        }
        label = Self.displayLabel(for: node, fallback: kind.rawValue)
    }

    private static func displayLabel(for node: AppSwiftSurfaceNode, fallback: String) -> String {
        for value in [
            node.text,
            node.action?.operation,
            node.dataSource,
            node.id
        ] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return fallback.capitalized
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct AppSwiftSurfaceRenderedAction: Equatable, Hashable {
    var invocation: AppSwiftSurfaceAction.Invocation
    var capabilityId: String
    var operation: String
    var arguments: [String: AppSwiftSurfaceJSONValue]
    var riskTier: AppCapabilityRiskTier?
    var requiresApproval: Bool

    init(action: AppSwiftSurfaceAction) {
        invocation = action.invocation
        capabilityId = action.capabilityId
        operation = action.operation
        arguments = action.arguments ?? [:]
        let descriptor = AppCapabilityCatalog.descriptor(id: action.capabilityId)
        riskTier = descriptor?.riskTier
        requiresApproval = descriptor?.interruptiveApproval ?? (action.invocation == .sdkAction)
    }

    var bridgeArguments: [String: Any] {
        arguments.mapValues(\.foundationValue)
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

struct AppSwiftSurfaceRunnerOutcome: Equatable, Hashable {
    var state: AppSwiftSurfaceRunnerState
    var result: AppSwiftSurfaceRunnerResult
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
        launchWithResult(launch).state
    }

    @discardableResult
    func launchWithResult(_ launch: AppSwiftSurfaceRunnerLaunch) -> AppSwiftSurfaceRunnerOutcome {
        guard launch.plan.outOfProcess else {
            state = .crashed(reason: "Swift surface runner must be out-of-process.")
            return AppSwiftSurfaceRunnerOutcome(state: state, result: .init(stderr: "Swift surface runner must be out-of-process."))
        }
        state = .launching
        let result = executor.run(launch)
        state = Self.classify(result: result, timeoutSeconds: launch.timeoutSeconds)
        return AppSwiftSurfaceRunnerOutcome(state: state, result: result)
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
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout

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
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: data, encoding: .utf8) ?? ""
                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                return AppSwiftSurfaceRunnerResult(
                    pid: process.processIdentifier,
                    exitCode: process.terminationStatus,
                    timedOut: false,
                    stderr: stderrText,
                    stdout: stdoutText
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
    static let runnerExecutableName = "ClawixSwiftSurfaceRunner"

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

    static func decodeRunnerRenderMessage(data: Data) throws -> AppSwiftSurfaceRunnerRenderMessage {
        let message = try JSONDecoder().decode(AppSwiftSurfaceRunnerRenderMessage.self, from: data)
        guard message.schemaVersion == protocolVersion else {
            throw AppSwiftSurfaceValidationError.unsupportedSchema(message.schemaVersion)
        }
        guard message.type == "render" else {
            throw AppSwiftSurfaceValidationError.unsupportedRunnerMessage(message.type)
        }
        return message
    }

    static func renderManifest(
        from result: AppSwiftSurfaceRunnerResult,
        fallback manifest: AppSwiftSurfaceManifest,
        plan: AppSwiftSurfaceRunnerPlan,
        app: AppRecord
    ) throws -> AppSwiftSurfaceManifest {
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return manifest
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw AppSwiftSurfaceValidationError.invalidRunnerOutput
        }
        let message = try decodeRunnerRenderMessage(data: data)
        let renderedManifest = AppSwiftSurfaceManifest(
            schemaVersion: message.schemaVersion,
            root: message.root,
            requestedCapabilities: message.requestedCapabilities
        )
        try validateRunnerManifest(renderedManifest, plan: plan, app: app)
        return renderedManifest
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

    static func runnerExecutablePath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledExecutablePath: String? = nil
    ) -> String? {
        let value = environment[ClawixPersistentSurfaceKeys.swiftSurfaceRunnerEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value?.isEmpty == false {
            return value
        }
        if let bundled = bundledExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundled.isEmpty {
            return bundled
        }
        return runnerBundledExecutablePath()
    }

    static func runnerBundledExecutablePath(bundle: Bundle = .main) -> String? {
        var candidates: [URL] = []
        if let auxiliary = bundle.url(forAuxiliaryExecutable: runnerExecutableName) {
            candidates.append(auxiliary)
        }
        candidates.append(bundle.bundleURL.appendingPathComponent("Contents/Helpers/\(runnerExecutableName)", isDirectory: false))
        candidates.append(bundle.bundleURL.appendingPathComponent("Contents/MacOS/\(runnerExecutableName)", isDirectory: false))

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
        return nil
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

    private static func validateRunnerManifest(
        _ manifest: AppSwiftSurfaceManifest,
        plan: AppSwiftSurfaceRunnerPlan,
        app: AppRecord
    ) throws {
        try validate(manifest: manifest, for: app)
        let allowed = Set(plan.allowedCapabilities)
        let requested = Set(manifest.requestedCapabilities)
        let used = Set(usedCapabilities(in: manifest.root))
        for capability in requested.union(used).sorted() {
            guard allowed.contains(capability) else {
                throw AppSwiftSurfaceValidationError.runnerCapabilityNotAllowed(capability)
            }
        }
    }

    private static func usedCapabilities(in node: AppSwiftSurfaceNode) -> [String] {
        var result: [String] = []
        if let action = node.action {
            result.append(action.capabilityId)
        }
        for child in node.children {
            result.append(contentsOf: usedCapabilities(in: child))
        }
        return result
    }
}

enum AppSwiftSurfaceValidationError: LocalizedError, Equatable {
    case notSwiftSurface(String)
    case unsupportedSchema(Int)
    case unsupportedRunnerMessage(String)
    case invalidRunnerOutput
    case unknownCapability(String)
    case capabilityNotDeclared(String)
    case runnerCapabilityNotAllowed(String)
    case highRiskRead(String)
    case actionNotApprovalRequired(String)

    var errorDescription: String? {
        switch self {
        case .notSwiftSurface(let slug):
            return "App is not a Swift declarative surface: \(slug)"
        case .unsupportedSchema(let version):
            return "Unsupported Swift surface schema: \(version)"
        case .unsupportedRunnerMessage(let type):
            return "Unsupported Swift surface runner message: \(type)"
        case .invalidRunnerOutput:
            return "Swift surface runner output is not valid UTF-8."
        case .unknownCapability(let id):
            return "Unknown Swift surface capability: \(id)"
        case .capabilityNotDeclared(let id):
            return "Swift surface manifest does not declare capability: \(id)"
        case .runnerCapabilityNotAllowed(let id):
            return "Swift surface runner used a capability outside its launch plan: \(id)"
        case .highRiskRead(let id):
            return "High-risk capability cannot be used as a read: \(id)"
        case .actionNotApprovalRequired(let id):
            return "SDK action must use an approval-required capability: \(id)"
        }
    }
}
