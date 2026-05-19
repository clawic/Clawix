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

enum AppSwiftSurfaceContract {
    static let protocolVersion = 1

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
