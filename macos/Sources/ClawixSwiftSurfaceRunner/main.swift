import Foundation

private struct SurfaceManifest: Codable {
    var schemaVersion: Int
    var root: SurfaceNode
    var requestedCapabilities: [String]
}

private struct SurfaceNode: Codable {
    enum Kind: String, Codable {
        case text
        case button
        case list
        case stack
    }

    var kind: Kind
    var id: String?
    var text: String?
    var dataSource: String?
    var action: SurfaceAction?
    var children: [SurfaceNode]
}

private struct SurfaceAction: Codable {
    enum Invocation: String, Codable {
        case sdkRead
        case sdkAction
    }

    var invocation: Invocation
    var capabilityId: String
    var operation: String
}

private struct RunnerRenderMessage: Codable {
    var schemaVersion: Int
    var type: String
    var root: SurfaceNode
    var requestedCapabilities: [String]
}

private enum RunnerError: LocalizedError {
    case missingValue(String)
    case unsupportedProtocol(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing required \(flag) value."
        case .unsupportedProtocol(let version):
            return "Unsupported Swift surface protocol version: \(version)."
        }
    }
}

private func argumentValue(_ flag: String) throws -> String {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag),
          index + 1 < arguments.count else {
        throw RunnerError.missingValue(flag)
    }
    let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
        throw RunnerError.missingValue(flag)
    }
    return value
}

do {
    let manifestPath = try argumentValue("--manifest")
    let protocolVersion = try argumentValue("--protocol-version")
    guard protocolVersion == "1" else {
        throw RunnerError.unsupportedProtocol(protocolVersion)
    }
    _ = try argumentValue("--app-slug")

    let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let manifest = try JSONDecoder().decode(SurfaceManifest.self, from: manifestData)
    guard manifest.schemaVersion == 1 else {
        throw RunnerError.unsupportedProtocol(String(manifest.schemaVersion))
    }

    let message = RunnerRenderMessage(
        schemaVersion: manifest.schemaVersion,
        type: "render",
        root: manifest.root,
        requestedCapabilities: manifest.requestedCapabilities
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    let output = try encoder.encode(message)
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    FileHandle.standardError.write(Data("ClawixSwiftSurfaceRunner: \(message)\n".utf8))
    exit(1)
}
