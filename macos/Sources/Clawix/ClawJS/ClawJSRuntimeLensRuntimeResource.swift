import Foundation

struct ClawJSRuntimeLensRuntimeResource: Decodable, Equatable, Identifiable {
    struct MetadataValue: Decodable, Equatable {
        init(from decoder: Decoder) throws {
            if (try? decoder.singleValueContainer()) != nil { return }
            _ = try? decoder.container(keyedBy: DynamicCodingKey.self)
            _ = try? decoder.unkeyedContainer()
        }
    }

    struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    struct NativeIdentifier: Decodable, Equatable {
        let name: String?
    }

    struct Provenance: Decodable, Equatable {
        let source: String?
        let runtimeId: String?
        let path: String?
    }

    struct LocalOverlay: Decodable, Equatable {
        let pinned: Bool?
        let authority: String?
        let writesRuntime: Bool?
    }

    struct ProviderAuth: Decodable, Equatable {
        let supportsOAuth: Bool?
        let supportsApiKey: Bool?
        let supportsEnv: Bool?
        let supportsToken: Bool?
    }

    let id: String
    let label: String?
    let status: String?
    let kind: String?
    let path: String?
    let enabled: Bool?
    let summary: String?
    let updatedAt: String?
    let sizeBytes: Int?
    let pinned: Bool?
    let nativeIdentifier: NativeIdentifier?
    let provenance: Provenance?
    let limitations: [String]?
    let attributes: [String]?
    let modelId: String?
    let provider: String?
    let available: Bool?
    let source: String?
    let isDefault: Bool?
    let scope: String?
    let parentSessionId: String?
    let toolCallCount: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let reasoningTokens: Int?
    let billingProvider: String?
    let billingMode: String?
    let estimatedCostUsd: Double?
    let actualCostUsd: Double?
    let costStatus: String?
    let apiCallCount: Int?
    let providerAuth: ProviderAuth?
    let envVars: [String]?
    let lastError: String?
    let metadata: [String: MetadataValue]?
    let pinAuthority: String?
    let divergence: String?
    let localOverlay: LocalOverlay?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case status
        case kind
        case path
        case enabled
        case summary
        case updatedAt
        case sizeBytes
        case pinned
        case nativeIdentifier
        case provenance
        case limitations
        case attributes
        case modelId
        case provider
        case available
        case source
        case isDefault
        case scope
        case parentSessionId
        case toolCallCount
        case inputTokens
        case outputTokens
        case cacheReadTokens
        case cacheWriteTokens
        case reasoningTokens
        case billingProvider
        case billingMode
        case estimatedCostUsd
        case actualCostUsd
        case costStatus
        case apiCallCount
        case providerAuth = "auth"
        case envVars
        case lastError
        case metadata
        case pinAuthority
        case divergence
        case localOverlay
    }

    var displayLabel: String { label ?? id }

    func addingAttributes(_ extraAttributes: [String]) -> ClawJSRuntimeLensRuntimeResource {
        let mergedAttributes = (attributes ?? []) + extraAttributes
        return ClawJSRuntimeLensRuntimeResource(
            id: id,
            label: label,
            status: status,
            kind: kind,
            path: path,
            enabled: enabled,
            summary: summary,
            updatedAt: updatedAt,
            sizeBytes: sizeBytes,
            pinned: pinned,
            nativeIdentifier: nativeIdentifier,
            provenance: provenance,
            limitations: limitations,
            attributes: mergedAttributes.isEmpty ? nil : mergedAttributes,
            modelId: modelId,
            provider: provider,
            available: available,
            source: source,
            isDefault: isDefault,
            scope: scope,
            parentSessionId: parentSessionId,
            toolCallCount: toolCallCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            reasoningTokens: reasoningTokens,
            billingProvider: billingProvider,
            billingMode: billingMode,
            estimatedCostUsd: estimatedCostUsd,
            actualCostUsd: actualCostUsd,
            costStatus: costStatus,
            apiCallCount: apiCallCount,
            providerAuth: providerAuth,
            envVars: envVars,
            lastError: lastError,
            metadata: metadata,
            pinAuthority: pinAuthority,
            divergence: divergence,
            localOverlay: localOverlay
        )
    }
}
