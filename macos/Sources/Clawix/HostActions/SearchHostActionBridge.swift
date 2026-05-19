import ClawHostKit
import Foundation

struct SearchHostActionExecutionPlan: Decodable, Equatable {
    let id: String
    let resultId: String
    let actionId: String
    let hostRequest: SearchHostActionRequestTemplate?
}

struct SearchHostActionRequestTemplate: Decodable, Equatable {
    struct Actor: Decodable, Equatable {
        let kind: String
        let id: String
        let role: String?
    }

    struct Target: Decodable, Equatable {
        let kind: String
        let id: String?
        let name: String?
        let selector: [String: String]?
    }

    struct Command: Decodable, Equatable {
        let resource: String
        let action: String
        let requestJsonFlag: String
    }

    let system: String
    let schemaVersion: Int
    let requestId: String
    let capabilityId: String
    let actor: Actor
    let target: Target?
    let arguments: [String: String]
    let dryRun: Bool
    let reason: String?
    let approved: Bool
    let hostApprovalId: String?
    let command: Command
}

enum SearchHostActionBridgeError: Error, Equatable, LocalizedError {
    case missingHostRequest
    case unsupportedSystem(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedCommand(resource: String, action: String)

    var errorDescription: String? {
        switch self {
        case .missingHostRequest:
            return "Search action plan does not include a signed-host request template."
        case .unsupportedSystem(let system):
            return "Unsupported Search host action system: \(system)."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported Search host action schemaVersion \(version)."
        case .unsupportedCommand(let resource, let action):
            return "Unsupported Search host action command \(resource) \(action)."
        }
    }
}

enum SearchHostActionBridge {
    static func nativeRequestData(
        from planData: Data,
        host: NativeMacActionWireHost
    ) throws -> Data {
        let request = try nativeRequest(from: planData, host: host)
        return try JSONEncoder().encode(request)
    }

    static func nativeRequest(
        from planData: Data,
        host: NativeMacActionWireHost
    ) throws -> NativeMacActionWireRequest {
        let plan = try JSONDecoder().decode(SearchHostActionExecutionPlan.self, from: planData)
        guard let template = plan.hostRequest else {
            throw SearchHostActionBridgeError.missingHostRequest
        }
        guard template.system == "mac-control" else {
            throw SearchHostActionBridgeError.unsupportedSystem(template.system)
        }
        guard template.schemaVersion == 1 else {
            throw SearchHostActionBridgeError.unsupportedSchemaVersion(template.schemaVersion)
        }
        guard template.command.resource == "mac",
              template.command.action == (template.dryRun ? "plan" : "execute") else {
            throw SearchHostActionBridgeError.unsupportedCommand(
                resource: template.command.resource,
                action: template.command.action
            )
        }

        return NativeMacActionWireRequest(
            requestId: template.requestId,
            capabilityId: template.capabilityId,
            actor: NativeMacActionWireActor(
                kind: template.actor.kind,
                id: template.actor.id,
                role: template.actor.role
            ),
            host: host,
            target: template.target.map {
                NativeMacActionWireTarget(
                    kind: $0.kind,
                    id: $0.id,
                    name: $0.name,
                    selector: ($0.selector ?? [:]).mapValues { .string($0) }
                )
            },
            arguments: template.arguments.mapValues { .string($0) },
            dryRun: template.dryRun,
            reason: template.reason,
            approved: template.approved
        )
    }
}
