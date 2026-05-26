import Foundation

enum ClawJSRuntimeLensID: String, CaseIterable, Identifiable {
    case openclaw
    case hermes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openclaw: return "OpenClaw"
        case .hermes: return "Hermes"
        }
    }
}

struct ClawJSRuntimeLensSnapshot: Decodable, Equatable {
    static let canonicalDomains = [
        "sessions",
        "skills",
        "memory",
        "channels",
        "providers",
        "auth",
        "models",
        "scheduler",
        "plugins",
        "gateway",
        "doctorCompat",
        "sandboxPermissions",
        "configuration"
    ]

    let runtimeId: String
    let runtimeName: String
    let officialSnapshot: OfficialSnapshot?
    let support: Support?
    let status: Status
    let session: SessionDescriptor?
    let workspace: Workspace?
    let runtimeResources: RuntimeResources?
    let domains: [Domain]
    let domainData: DomainData?
    let commands: CommandMatrix?
    let supportAudit: SupportAudit?

    enum CodingKeys: String, CodingKey {
        case runtimeId
        case runtimeName
        case officialSnapshot
        case support
        case status
        case session
        case workspace
        case runtimeResources = "resources"
        case domains
        case domainData
        case commands
        case supportAudit
    }

    var missingCanonicalDomains: [String] {
        let present = Set(domains.map(\.domain))
        return Self.canonicalDomains.filter { !present.contains($0) }
    }

    struct OfficialSnapshot: Decodable, Equatable {
        let capturedAt: String?
        let sourceSnapshotDate: String?
        let sourceType: String?
        let sources: [String]?
        let driftPolicy: String?
        let manifestSource: String?
    }

    struct Support: Decodable, Equatable {
        let scope: String?
        let stability: String?
        let supportLevel: String?
        let recommended: Bool?
        let adapter: Adapter?
        let ecosystem: Ecosystem?

        struct Adapter: Decodable, Equatable {
            let scope: String?
            let stability: String?
            let supportLevel: String?
            let recommended: Bool?
        }

        struct Ecosystem: Decodable, Equatable {
            struct Provenance: Decodable, Equatable {
                let source: String?
                let runtimeId: String?
            }

            let scope: String?
            let supportStage: String?
            let recommended: Bool?
            let production: Bool?
            let uiParityClaim: String?
            let summary: String?
            let blockingReasons: [String]?
            let officialSnapshot: OfficialSnapshot?
            let blockedWriteBackDomains: [String]?
            let externalPendingDomains: [String]?
            let evidenceRequirements: [EvidenceRequirement]?
            let claimSource: String?
            let provenance: Provenance?
        }
    }

    struct SupportAudit: Decodable, Equatable {
        struct Provenance: Decodable, Equatable {
            let source: String?
            let runtimeId: String?
            let officialSnapshotSource: String?
            let sourceSnapshotDate: String?
        }

        let scope: String?
        let closureState: String?
        let supportComplete: Bool?
        let allDomainsAccountedFor: Bool?
        let supportStage: String?
        let recommended: Bool?
        let production: Bool?
        let uiParityClaim: String?
        let officialSnapshot: OfficialSnapshot?
        let summary: String?
        let blockingReasons: [String]?
        let blockerSummary: BlockerSummary?
        let evidenceRequirements: [EvidenceRequirement]?
        let domains: [DomainAudit]?
        let syncPolicySummary: SyncPolicySummary?
        let projectionSummary: ProjectionSummary?
        let evidenceReadinessSummary: EvidenceReadinessSummary?
        let closureChecklist: [ClosureChecklistItem]?
        let closureChecklistSummary: [String: Int]?
        let commandCoverageSummary: CommandCoverageSummary?
        let promotionGate: String?
        let finalPromotionReview: FinalPromotionReview?
        let finalSupportClaimDecision: FinalSupportClaimDecision?
        let evidenceReentryPackets: [EvidenceReentryPacket]?
        let provenance: Provenance?

        struct BlockerSummary: Decodable, Equatable {
            let byBlockerClass: [String: Int]?
            let directBlockerDomains: [String]?
            let externalPendingDomains: [String]?
            let blockedWriteBackDomains: [String]?
            let ecosystemExternalPendingDomains: [String]?
            let evidenceRequirementCount: Int?
            let productBlockedRequirementCount: Int?
        }

        struct DomainAudit: Decodable, Equatable, Identifiable {
            var id: String { domain }
            let domain: String
            let claim: String?
            let status: String?
            let canonicalAuthority: String?
            let nativeAuthority: String?
            let writeBackPolicy: String?
            let writeBackAllowed: Bool?
            let writeBackApprovalGated: Bool?
            let approvalGateFixtureStatus: String?
            let approvalGateFixtureReceipt: ApprovalGateFixtureReceipt?
            let validation: String?
            let externalPending: Bool?
            let persistence: String?
            let relation: String?
            let lossPolicy: String?
            let freshness: String?
            let readProjectionStatus: String?
            let implementedFacets: [String]?
            let blockingFacets: [String]?
            let blockerClasses: [String]?
            let evidenceDispositions: [String]?
            let supportResolutions: [String]?
            let evidenceRequirementIds: [String]?
        }

        struct ClosureChecklistItem: Decodable, Equatable, Identifiable {
            var id: String { domain }
            let domain: String
            let closureStatus: String?
            let claim: String?
            let status: String?
            let readProjectionStatus: String?
            let implementedFacets: [String]?
            let blockingFacets: [String]?
            let projectionDisposition: String?
            let writeBackPolicy: String?
            let validation: String?
            let blockerClasses: [String]?
            let evidenceRequirementIds: [String]?
            let supportResolutions: [String]?
            let safeDefault: String?
            let nextAction: String?
        }

        struct ProjectionSummary: Decodable, Equatable {
            let byReadProjectionStatus: [String: Int]?
            let implementedFacetCounts: [String: Int]?
            let blockingFacetCounts: [String: Int]?
            let projectedDomainCount: Int?
            let unsupportedDomainCount: Int?
            let productBlockedButProjectedDomainCount: Int?
        }

        struct SyncPolicySummary: Decodable, Equatable {
            let domainCount: Int?
            let canonicalAuthorityCounts: [String: Int]?
            let nativeAuthorityCounts: [String: Int]?
            let persistenceCounts: [String: Int]?
            let relationCounts: [String: Int]?
            let writeBackPolicyCounts: [String: Int]?
            let lossPolicyCounts: [String: Int]?
            let freshnessCounts: [String: Int]?
            let readOnlyProjectionDomains: [String]?
            let writeBackAllowedDomains: [String]?
            let blockedWriteBackDomains: [String]?
            let externalPendingDomains: [String]?
            let localOverlayDomains: [String]?
            let localOverlayActions: [String]?
            let noSilentOverwrite: Bool?
            let defaultSyncMode: String?
            let safeDefault: String?
        }

        struct EvidenceReadinessSummary: Decodable, Equatable {
            let statusCounts: [String: Int]?
            let blockerClassCounts: [String: Int]?
            let safeDefaultCounts: [String: Int]?
            let totalRequirementCount: Int?
            let approvalRequiredCount: Int?
            let externalPendingCount: Int?
            let upstreamContractBlockedCount: Int?
            let approvalGateBlockedCount: Int?
            let tuiGatewayBlockedCount: Int?
            let tuiGatewayWrapperBlockedCount: Int?
            let tuiGatewayFixtureBackedCount: Int?
            let productionTransportBlockedCount: Int?
            let writeBackContractBlockedCount: Int?
            let productBlockedCount: Int?
            let unresolvedNativeRequirementCount: Int?
            let approvalRequiredRequirementIds: [String]?
            let externalPendingRequirementIds: [String]?
            let upstreamContractRequirementIds: [String]?
            let approvalGateRequirementIds: [String]?
            let tuiGatewayRequirementIds: [String]?
            let tuiGatewayWrapperRequirementIds: [String]?
            let tuiGatewayFixtureBackedRequirementIds: [String]?
            let productionTransportRequirementIds: [String]?
            let writeBackContractRequirementIds: [String]?
            let productBlockedRequirementIds: [String]?
            let unresolvedNativeRequirementIds: [String]?
            let nextRequiredActions: [String]?
            let reentryPolicy: String?
            let safeDefault: String?
        }

        struct CommandCoverageSummary: Decodable, Equatable {
            let status: String?
            let runtimeId: String?
            let exactCommand: String?
            let totalCommandCount: Int?
            let topLevelCommandCount: Int?
            let domainCommandCount: Int?
            let resourceCommandCount: Int?
            let scopedReadCommandCount: Int?
            let sessionActionCommandCount: Int?
            let manifestDomainCount: Int?
            let sessionActions: [String]?
            let includesAllManifestDomains: Bool?
            let includesAllDocumentedSessionActions: Bool?
            let executableMatrixCommandCount: Int?
            let promotionSignal: Bool?
            let supportClaim: String?
            let supportStage: String?
            let supportImpact: String?
            let safeDefault: String?
        }

        struct FinalPromotionReview: Decodable, Equatable {
            let status: String?
            let finalPromotionAllowed: Bool?
            let commandCoverageSummary: CommandCoverageSummary?
            let claimDisposition: String?
            let productBlockedByDecisionCount: Int?
            let externalPendingCount: Int?
            let unresolvedNativeRequirementCount: Int?
            let productBlockedRequirementIds: [String]?
            let externalPendingRequirementIds: [String]?
            let unresolvedNativeRequirementIds: [String]?
            let requiredForPromotion: [String]?
            let userVisibleStatus: String?
        }

        struct FinalSupportClaimDecision: Decodable, Equatable {
            let status: String?
            let decision: String?
            let effectiveSupportStage: String?
            let recommended: Bool?
            let production: Bool?
            let uiParityClaim: String?
            let commandCoverageSummary: CommandCoverageSummary?
            let uiParityDisposition: String?
            let claimDisposition: String?
            let blockedPromotionClaims: [String]?
            let blockerClasses: [String]?
            let productBlockedRequirementIds: [String]?
            let externalPendingRequirementIds: [String]?
            let unresolvedNativeRequirementIds: [String]?
            let promotionEvidenceRequired: [String]?
            let reentryPolicy: String?
            let safeDefault: String?
            let userVisibleStatus: String?
        }

        struct EvidenceReentryPacket: Decodable, Equatable, Identifiable {
            let id: String
            let requirementId: String?
            let blockerClass: String?
            let status: String?
            let approvalRequired: Bool?
            let commandShape: String?
            let exactCommand: String?
            let preflightCommand: String?
            let approvalScope: String?
            let evidenceSafetyPolicy: String?
            let expectedEvidence: [String]?
            let expectedRedactedEvidence: [String]?
            let riskControls: [String]?
            let reentryCondition: String?
            let claimEffect: String?
            let claimBlockedUntil: String?
            let supportResolution: String?
            let productDecision: String?
            let userVisibleContract: String?
            let officialProtocol: String?
            let officialMethod: String?
            let officialContractSource: String?
            let transportPolicyId: String?
            let officialTransportSurface: String?
            let officialTransportClasses: [String]?
            let officialTransportSource: String?
            let productionTransportStatus: String?
            let productionTransportBlocker: String?
            let lifecycleStatus: String?
            let productionTransportCommandShape: String?
            let doNotRunWithoutApproval: Bool?
            let safeDefault: String?
        }
    }

    struct Status: Decodable, Equatable {
        let adapter: String?
        let runtimeName: String?
        let version: String?
        let installed: Bool?
        let cliAvailable: Bool?
        let gatewayAvailable: Bool?
        let capabilities: [String: Bool]?
        let capabilityMap: [String: Capability]?
        let diagnostics: Diagnostics?

        struct Capability: Decodable, Equatable {
            let supported: Bool?
            let status: String?
            let strategy: String?
            let limitations: [String]?
            let diagnostics: DomainData.RuntimeCapability.Diagnostics?
        }

        struct Diagnostics: Decodable, Equatable {
            let lastError: String?
            let locations: Locations?
        }

        struct Locations: Decodable, Equatable {
            let homeDir: String?
            let workspacePath: String?
            let configPath: String?
            let authStorePath: String?
            let gatewayConfigPath: String?
        }
    }

    struct Workspace: Decodable, Equatable {
        let canonicalPaths: [String: String]?
        let managedFiles: [String]?
    }

    struct RuntimeResources: Decodable, Equatable {
        let providers: [RuntimeResource]?
        let models: [RuntimeResource]?
        let defaultModel: DomainData.Bucket.DefaultModel?
        let auth: [String: DomainData.AuthBucket.AuthState]?
        let schedulers: [RuntimeResource]?
        let memory: [RuntimeResource]?
        let skills: [RuntimeResource]?
        let channels: [RuntimeResource]?
    }

    struct TransportPolicy: Decodable, Equatable {
        let id: String?
        let protocolName: String?
        let officialTransportSurface: String?
        let officialTransportClasses: [String]?
        let officialTransportSource: String?
        let fixtureTransport: String?
        let productionTransportStatus: String?
        let productionTransportBlocker: String?
        let lifecycleStatus: String?
        let lifecycleOwner: String?
        let configuredEndpointClass: String?
        let endpointConfigured: Bool?
        let loopbackConfigured: Bool?
        let confirmationPolicy: String?
        let startupPolicy: String?
        let mutationPolicy: String?
        let credentialPolicy: String?
        let safeDefault: String?
        let supportClaimEffect: String?
        let requiredEvidence: [String]?
        let reentryCondition: String?

        enum CodingKeys: String, CodingKey {
            case id
            case protocolName = "protocol"
            case officialTransportSurface
            case officialTransportClasses
            case officialTransportSource
            case fixtureTransport
            case productionTransportStatus
            case productionTransportBlocker
            case lifecycleStatus
            case lifecycleOwner
            case configuredEndpointClass
            case endpointConfigured
            case loopbackConfigured
            case confirmationPolicy
            case startupPolicy
            case mutationPolicy
            case credentialPolicy
            case safeDefault
            case supportClaimEffect
            case requiredEvidence
            case reentryCondition
        }
    }

    struct Domain: Decodable, Equatable, Identifiable {
        struct Provenance: Decodable, Equatable {
            let source: String?
            let runtimeId: String?
            let domain: String?
        }

        var id: String { domain }
        let domain: String
        let supported: Bool?
        let status: String?
        let runtimeCapabilityStatus: String?
        let runtimeCapabilitySupported: Bool?
        let runtimeCapabilityStrategy: String?
        let readProjectionStatus: String?
        let strategy: String?
        let count: Int?
        let authority: String?
        let claim: String?
        let canonicalAuthority: String?
        let nativeAuthority: String?
        let persistence: String?
        let relation: String?
        let lossPolicy: String?
        let writeBackPolicy: String?
        let writeBackAllowed: Bool?
        let writeBackApprovalGated: Bool?
        let approvalGateFixtureStatus: String?
        let approvalGateFixtureReceipt: ApprovalGateFixtureReceipt?
        let validation: String?
        let externalPending: Bool?
        let freshness: String?
        let officialCommands: [String]?
        let evidenceRequirements: [EvidenceRequirement]?
        let limitations: [String]?
        let provenance: Provenance?

        var displayLabel: String {
            ClawJSRuntimeLensSnapshot.displayLabel(for: domain)
        }
    }

    final class DomainData: Decodable, Equatable {
        let sessions: SessionBucket?
        let skills: Bucket?
        let memory: Bucket?
        let channels: Bucket?
        let providers: Bucket?
        let auth: AuthBucket?
        let models: Bucket?
        let scheduler: Bucket?
        let plugins: Bucket?
        let gateway: OperationalBucket?
        let doctorCompat: OperationalBucket?
        let sandboxPermissions: OperationalBucket?
        let configuration: ConfigurationBucket?

        static func == (lhs: DomainData, rhs: DomainData) -> Bool {
            lhs.sessions == rhs.sessions
                && lhs.skills == rhs.skills
                && lhs.memory == rhs.memory
                && lhs.channels == rhs.channels
                && lhs.providers == rhs.providers
                && lhs.auth == rhs.auth
                && lhs.models == rhs.models
                && lhs.scheduler == rhs.scheduler
                && lhs.plugins == rhs.plugins
                && lhs.gateway == rhs.gateway
                && lhs.doctorCompat == rhs.doctorCompat
                && lhs.sandboxPermissions == rhs.sandboxPermissions
                && lhs.configuration == rhs.configuration
        }

        struct Bucket: Decodable, Equatable {
            let skills: [RuntimeResource]?
            let memory: [RuntimeResource]?
            let channels: [RuntimeResource]?
            let providers: [RuntimeResource]?
            let models: [RuntimeResource]?
            let defaultModel: DefaultModel?
            let schedulers: [RuntimeResource]?
            let plugins: [RuntimeResource]?
            let status: RuntimeCapability?
            let supportContract: SupportContract?

            struct DefaultModel: Decodable, Equatable {
                let provider: String?
                let modelId: String?
                let label: String?
            }
        }

        struct SessionBucket: Decodable, Equatable {
            let session: SessionDescriptor?
            let sessions: [RuntimeResource]?
            let totalProjected: Int?
            let inventoryError: String?
            let supportContract: SupportContract?
            let actionContracts: [SessionActionPolicy]?
            let actionPolicy: [SessionActionPolicy]?
            let overlayState: SessionOverlayState?
        }

        struct AuthBucket: Decodable, Equatable {
            let auth: [String: AuthState]?
            let resources: [RuntimeResource]?
            let supportContract: SupportContract?

            struct AuthState: Decodable, Equatable {
                let provider: String?
                let hasAuth: Bool?
                let hasSubscription: Bool?
                let hasApiKey: Bool?
                let hasProfileApiKey: Bool?
                let hasEnvKey: Bool?
                let authType: String?
                let maskedCredential: String?
                let scalarDisposition: String?

                enum CodingKeys: String, CodingKey {
                    case provider
                    case hasAuth
                    case hasSubscription
                    case hasApiKey
                    case hasProfileApiKey
                    case hasEnvKey
                    case authType
                    case maskedCredential
                }

                init(from decoder: Decoder) throws {
                    if let container = try? decoder.container(keyedBy: CodingKeys.self) {
                        provider = try container.decodeIfPresent(String.self, forKey: .provider)
                        hasAuth = try container.decodeIfPresent(Bool.self, forKey: .hasAuth)
                        hasSubscription = try container.decodeIfPresent(Bool.self, forKey: .hasSubscription)
                        hasApiKey = try container.decodeIfPresent(Bool.self, forKey: .hasApiKey)
                        hasProfileApiKey = try container.decodeIfPresent(Bool.self, forKey: .hasProfileApiKey)
                        hasEnvKey = try container.decodeIfPresent(Bool.self, forKey: .hasEnvKey)
                        authType = try container.decodeIfPresent(String.self, forKey: .authType)
                        maskedCredential = try container.decodeIfPresent(String.self, forKey: .maskedCredential)
                        scalarDisposition = nil
                        return
                    }

                    let container = try decoder.singleValueContainer()
                    provider = nil
                    hasAuth = nil
                    hasSubscription = nil
                    hasApiKey = nil
                    hasProfileApiKey = nil
                    hasEnvKey = nil
                    authType = nil
                    maskedCredential = nil

                    if container.decodeNil() {
                        scalarDisposition = "null_value"
                    } else if let value = try? container.decode(Bool.self) {
                        scalarDisposition = "boolean_\(value)"
                    } else if let value = try? container.decode(String.self) {
                        scalarDisposition = Self.safeScalarDisposition(for: value)
                    } else if (try? container.decode(Int.self)) != nil || (try? container.decode(Double.self)) != nil {
                        scalarDisposition = "numeric_value_redacted_by_client"
                    } else {
                        scalarDisposition = "unsupported_scalar_redacted_by_client"
                    }
                }

                private static func safeScalarDisposition(for value: String) -> String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        return "empty_string"
                    }
                    if trimmed == "[REDACTED]" || trimmed.allSatisfy({ $0 == "*" }) {
                        return "redacted_value"
                    }
                    return "scalar_value_redacted_by_client"
                }
            }
        }

        struct RuntimeCapability: Decodable, Equatable {
            struct Diagnostics: Decodable, Equatable {
                let source: String?
                let probeMethod: String?
                let transport: String?
                let inventoryFreshness: String?
                let mode: String?
                let diagnostics: [String]?
            }

            let supported: Bool?
            let status: String?
            let strategy: String?
            let limitations: [String]?
            let diagnostics: Diagnostics?
        }

        struct OperationalBucket: Decodable, Equatable {
            let gatewayAvailable: Bool?
            let runtimeVersion: String?
            let diagnostics: Status.Diagnostics?
            let resources: [RuntimeResource]?
            let permissionMode: String?
            let capability: RuntimeCapability?
            let tuiGatewayTransportPolicy: TransportPolicy?
            let supportContract: SupportContract?
        }

        struct ConfigurationBucket: Decodable, Equatable {
            let canonicalPaths: [String: String]?
            let managedFiles: [String]?
            let diagnostics: Status.Diagnostics?
            let redactedConfigSnapshot: RedactedConfigSnapshot?
            let capability: RuntimeCapability?
            let resources: [RuntimeResource]?
            let supportContract: SupportContract?

            struct RedactedConfigSnapshot: Decodable, Equatable {
                let path: String?
                let exists: Bool?
                let valuePolicy: String?
                let secretPolicy: String?
                let entries: [Entry]?
                let totalEntryCount: Int?
                let secretEntryCount: Int?
                let parseMode: String?
                let truncated: Bool?

                struct Entry: Decodable, Equatable, Identifiable {
                    var id: String { key ?? "unknown-config-key" }
                    let key: String?
                    let valueState: String?
                    let valueKind: String?
                    let redaction: String?
                    let secret: Bool?
                    let source: String?
                }
            }
        }
    }

    struct SessionOverlayState: Decodable, Equatable {
        let runtimeId: String?
        let overlayAuthority: String?
        let writesRuntime: Bool?
        let writeBackStatus: String?
        let conflictPolicy: String?
        let overlays: [SessionOverlayEntry]?
        let totalOverlays: Int?
        let totalConflicts: Int?

        struct SessionOverlayEntry: Decodable, Equatable, Identifiable {
            var id: String { overlayThreadId ?? sessionId ?? "unknown-overlay" }
            let sessionId: String?
            let overlayThreadId: String?
            let kind: String?
            let pinned: Bool?
            let authority: String?
            let writesRuntime: Bool?
            let nativeFound: Bool?
            let nativePinned: Bool?
            let conflictStatus: String?

            enum CodingKeys: String, CodingKey {
                case sessionId = "id"
                case overlayThreadId
                case kind
                case pinned
                case authority
                case writesRuntime
                case nativeFound
                case nativePinned
                case conflictStatus
            }
        }
    }

    struct SessionDescriptor: Decodable, Equatable {
        let transport: Transport?
        let supportsGateway: Bool?
        let primaryTransport: String?
        let fallbackTransport: String?
        let sessionPersistence: String?
        let streamingMode: String?
        let sessionPath: String?
        let sessionDatabasePath: String?
        let sessionTranscriptPath: String?
        let sessionIndexPath: String?
        let sessionStorageContract: String?

        struct Transport: Decodable, Equatable {
            let kind: String?
            let streaming: Bool?
        }
    }

    struct SupportContract: Decodable, Equatable {
        struct Provenance: Decodable, Equatable {
            let source: String?
            let runtimeId: String?
            let domain: String?
        }

        let claim: String?
        let authority: String?
        let canonicalAuthority: String?
        let nativeAuthority: String?
        let persistence: String?
        let relation: String?
        let lossPolicy: String?
        let writeBackPolicy: String?
        let writeBackAllowed: Bool?
        let writeBackApprovalGated: Bool?
        let approvalGateFixtureStatus: String?
        let approvalGateFixtureReceipt: ApprovalGateFixtureReceipt?
        let validation: String?
        let externalPending: Bool?
        let freshness: String?
        let officialCommands: [String]?
        let evidenceRequirements: [EvidenceRequirement]?
        let provenance: Provenance?
    }

    final class ApprovalGateFixtureReceipt: Decodable, Equatable {
        let domain: String?
        let receiptId: String?
        let receiptType: String?
        let status: String?
        let command: String?
        let approved: Bool?
        let mutationPerformed: Bool?
        let mutationWithoutApproval: Bool?
        let plaintextSecretLeak: Bool?
        let redacted: Bool?
        let evidenceSafetyPolicy: String?
        let source: String?

        static func == (lhs: ApprovalGateFixtureReceipt, rhs: ApprovalGateFixtureReceipt) -> Bool {
            lhs.domain == rhs.domain
                && lhs.receiptId == rhs.receiptId
                && lhs.receiptType == rhs.receiptType
                && lhs.status == rhs.status
                && lhs.command == rhs.command
                && lhs.approved == rhs.approved
                && lhs.mutationPerformed == rhs.mutationPerformed
                && lhs.mutationWithoutApproval == rhs.mutationWithoutApproval
                && lhs.plaintextSecretLeak == rhs.plaintextSecretLeak
                && lhs.redacted == rhs.redacted
                && lhs.evidenceSafetyPolicy == rhs.evidenceSafetyPolicy
                && lhs.source == rhs.source
        }
    }

    struct EvidenceRequirement: Decodable, Equatable, Identifiable {
        let id: String
        let blockerClass: String?
        let approvalRequired: Bool?
        let commandShape: String?
        let exactCommand: String?
        let preflightCommand: String?
        let approvalScope: String?
        let evidenceSafetyPolicy: String?
        let expectedEvidence: [String]?
        let expectedRedactedEvidence: [String]?
        let riskControls: [String]?
        let evidenceDisposition: String?
        let currentBehavior: String?
        let fallbackPolicy: String?
        let safeDefault: String?
        let claimEffect: String?
        let claimBlockedUntil: String?
        let reentryCondition: String?
        let productDecision: String?
        let supportResolution: String?
        let userVisibleContract: String?
        let promotionGate: String?
        let officialProtocol: String?
        let officialMethod: String?
        let officialContractSource: String?
        let doNotRunWithoutApproval: Bool?
    }

    struct SessionActionPolicy: Decodable, Equatable, Identifiable {
        var id: String { action }
        let action: String
        let status: String?
        let authority: String?
        let writesRuntime: Bool?
        let wouldWriteRuntime: Bool?
        let persistence: String?
        let delegatesTo: String?
        let guardName: String?
        let officialProtocol: String?
        let officialMethod: String?
        let officialContractSource: String?
        let requiredEvidence: [String]?
        let transportPolicy: ClawJSRuntimeLensSnapshot.TransportPolicy?
        let productionTransportStatus: String?
        let lifecycleStatus: String?
        let nativeWriteBackStatus: String?
        let officialRuntimeWriteBackContractRequired: Bool?
        let officialRuntimeWriteBackContractKnown: Bool?
        let nativeWriteBackSafeDefault: String?
        let userVisibleContract: String?
        let claimEffect: String?
        let evidenceRequirementId: String?

        enum CodingKeys: String, CodingKey {
            case action
            case status
            case authority
            case writesRuntime
            case wouldWriteRuntime
            case persistence
            case delegatesTo
            case officialProtocol
            case officialMethod
            case officialContractSource
            case requiredEvidence
            case transportPolicy
            case productionTransportStatus
            case lifecycleStatus
            case nativeWriteBackStatus
            case officialRuntimeWriteBackContractRequired
            case officialRuntimeWriteBackContractKnown
            case nativeWriteBackSafeDefault
            case userVisibleContract
            case claimEffect
            case evidenceRequirementId
            case guardName = "guard"
        }
    }

    struct CommandMatrix: Decodable, Equatable {
        let authority: String?
        let executableByClawCli: [RuntimeCommand]?
        let jsonPortalCommandSet: JsonPortalCommandSet?
        let resourceDomains: [String]?
        let mutationPolicy: String?

        struct JsonPortalCommandSet: Decodable, Equatable {
            let status: String?
            let totalCommandCount: Int?
            let topLevelCommandCount: Int?
            let domainCommandCount: Int?
            let resourceCommandCount: Int?
            let scopedReadCommandCount: Int?
            let sessionActionCommandCount: Int?
            let manifestDomainCount: Int?
            let sessionActions: [String]?
            let includesAllManifestDomains: Bool?
            let includesAllDocumentedSessionActions: Bool?
            let executableMatrixCommandCount: Int?
            let promotionSignal: Bool?
            let supportClaim: String?
            let supportStage: String?
            let safeDefault: String?
        }
    }

    struct RuntimeCommand: Decodable, Equatable, Identifiable {
        var id: String { command }
        let command: String
        let delegatesTo: String?
        let writesRuntime: Bool?
        let wouldWriteRuntime: Bool?
        let writesLocalOverlay: Bool?
        let blockerClass: String?
        let nativeWriteBackStatus: String?
        let nativeWriteBackBlockerClass: String?
        let officialRuntimeWriteBackContractRequired: Bool?
        let officialRuntimeWriteBackContractKnown: Bool?
        let nativeWriteBackFixtureRequired: Bool?
        let nativeWriteBackSafeDefault: String?
        let safeDefault: String?
        let userVisibleContract: String?
        let claimEffect: String?
        let supportResolution: String?
        let evidenceRequirementId: String?
        let requiredEvidence: [String]?
        let transportPolicyId: String?
        let transportPolicy: ClawJSRuntimeLensSnapshot.TransportPolicy?
        let productionTransportStatus: String?
        let lifecycleStatus: String?
        let productionTransportCommandShape: String?
        let doNotRunWithoutApproval: Bool?
        let claimBlockedUntil: String?
        let requiredEndpoint: String?
        let nativeWriteBackContract: NativeWriteBackContract?
        let args: [String]?

        struct NativeWriteBackContract: Decodable, Equatable {
            let status: String?
            let writesRuntime: Bool?
            let wouldWriteRuntime: Bool?
            let officialContractRequired: Bool?
            let officialContractKnown: Bool?
            let fixtureRequired: Bool?
            let safeDefault: String?
            let userVisibleContract: String?
            let claimEffect: String?
            let evidenceRequirementId: String?
        }
    }

    typealias RuntimeResource = ClawJSRuntimeLensRuntimeResource

    static func displayLabel(for domain: String) -> String {
        switch domain {
        case "doctorCompat": return "Doctor"
        case "sandboxPermissions": return "Sandbox"
        case "configuration": return "Config"
        default: return domain.prefix(1).uppercased() + domain.dropFirst()
        }
    }

    func resources(for domain: String) -> [RuntimeResource] {
        switch domain {
        case "sessions": return resourcesWithCommonAttributes(domainData?.sessions?.sessions ?? [])
        case "skills": return resourcesWithCommonAttributes(domainData?.skills?.skills ?? runtimeResources?.skills ?? [])
        case "memory": return resourcesWithCommonAttributes(domainData?.memory?.memory ?? runtimeResources?.memory ?? [])
        case "channels": return resourcesWithCommonAttributes(domainData?.channels?.channels ?? runtimeResources?.channels ?? [])
        case "providers": return resourcesWithCommonAttributes(domainData?.providers?.providers ?? runtimeResources?.providers ?? [])
        case "auth": return authResources()
        case "models": return modelResources()
        case "scheduler": return resourcesWithCommonAttributes(domainData?.scheduler?.schedulers ?? runtimeResources?.schedulers ?? [])
        case "plugins": return pluginResources()
        case "gateway": return operationalResources(domain: domain, bucket: domainData?.gateway)
        case "doctorCompat": return operationalResources(domain: domain, bucket: domainData?.doctorCompat)
        case "sandboxPermissions": return operationalResources(domain: domain, bucket: domainData?.sandboxPermissions)
        case "configuration": return configurationResources()
        default: return []
        }
    }

    private func authResources() -> [RuntimeResource] {
        let portalResources = resourcesWithCommonAttributes(domainData?.auth?.resources ?? [])
        let authStates = domainData?.auth?.auth ?? runtimeResources?.auth ?? [:]
        let portalResourceIds = Set(portalResources.map(\.id))
        let synthesizedResources: [RuntimeResource] = authStates
            .keys
            .sorted()
            .compactMap { provider in
                guard !portalResourceIds.contains(provider) else { return nil }
                guard let state = authStates[provider] else { return nil }
                return RuntimeResource(
                    id: provider,
                    label: state.provider ?? provider,
                    status: state.hasAuth == true ? "configured" : (state.scalarDisposition == nil ? "missing" : "redacted"),
                    kind: state.authType ?? (state.scalarDisposition == nil ? "auth" : "redacted_auth_state"),
                    path: nil,
                    enabled: state.hasAuth,
                    summary: state.maskedCredential,
                    updatedAt: nil,
                    sizeBytes: nil,
                    pinned: nil,
                    nativeIdentifier: nil,
                    provenance: nil,
                    limitations: nil,
                    attributes: Self.authAttributes(state),
                    modelId: nil,
                    provider: nil,
                    available: nil,
                    source: nil,
                    isDefault: nil,
                    scope: nil,
                    parentSessionId: nil,
                    toolCallCount: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    reasoningTokens: nil,
                    billingProvider: nil,
                    billingMode: nil,
                    estimatedCostUsd: nil,
                    actualCostUsd: nil,
                    costStatus: nil,
                    apiCallCount: nil,
                    providerAuth: nil,
                    envVars: nil,
                    lastError: nil,
                    metadata: nil,
                    pinAuthority: nil,
                    divergence: nil,
                    localOverlay: nil
                )
            }
        return portalResources + synthesizedResources
    }

    private static func authAttributes(_ state: DomainData.AuthBucket.AuthState) -> [String] {
        [
            state.hasSubscription.map { "subscription: \($0)" },
            state.hasApiKey.map { "api key: \($0)" },
            state.hasProfileApiKey.map { "profile key: \($0)" },
            state.hasEnvKey.map { "env key: \($0)" },
            state.scalarDisposition.map { "auth scalar: \($0)" }
        ]
        .compactMap { $0 }
    }

    private func operationalResources(
        domain: String,
        bucket: DomainData.OperationalBucket?
    ) -> [RuntimeResource] {
        guard let bucket else { return [] }
        if let resources = bucket.resources, !resources.isEmpty {
            return resourcesWithCommonAttributes(resources)
        }
        let capability = bucket.capability
        let label = Self.displayLabel(for: domain)
        let status: String? = {
            if domain == "gateway", let available = bucket.gatewayAvailable {
                return available ? "ready" : "degraded"
            }
            if let status = capability?.status { return status }
            if capability?.supported == false { return "unsupported" }
            return nil
        }()
        return [
            RuntimeResource(
                id: domain,
                label: label,
                status: status,
                kind: capability?.strategy ?? bucket.supportContract?.claim,
                path: nil,
                enabled: capability?.supported,
                summary: bucket.diagnostics?.lastError ?? bucket.runtimeVersion,
                updatedAt: nil,
                sizeBytes: nil,
                pinned: nil,
                nativeIdentifier: nil,
                provenance: nil,
                limitations: capability?.limitations,
                attributes: Self.capabilityDiagnosticsAttributes(capability?.diagnostics),
                modelId: nil,
                provider: nil,
                available: nil,
                source: nil,
                isDefault: nil,
                scope: nil,
                parentSessionId: nil,
                toolCallCount: nil,
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheWriteTokens: nil,
                reasoningTokens: nil,
                billingProvider: nil,
                billingMode: nil,
                estimatedCostUsd: nil,
                actualCostUsd: nil,
                costStatus: nil,
                apiCallCount: nil,
                providerAuth: nil,
                envVars: nil,
                lastError: nil,
                metadata: nil,
                pinAuthority: nil,
                divergence: nil,
                localOverlay: nil
            )
        ]
    }

    private func resourcesWithCommonAttributes(_ resources: [RuntimeResource]) -> [RuntimeResource] {
        resources.map { resource in
            resource.addingAttributes(Self.commonResourceAttributes(resource))
        }
    }

    private static func commonResourceAttributes(_ resource: RuntimeResource) -> [String] {
        [
            resource.scope.map { "scope: \($0)" },
            resource.provider.map { "provider: \($0)" },
            resource.lastError.map { "last error: \($0)" },
            resource.pinAuthority.map { "pin authority: \($0)" },
            resource.divergence.map { "divergence: \($0)" },
            resource.parentSessionId.map { "parent session: \($0)" },
            resource.toolCallCount.map { "tool calls: \($0)" },
            resource.inputTokens.map { "input tokens: \($0)" },
            resource.outputTokens.map { "output tokens: \($0)" },
            resource.cacheReadTokens.map { "cache read tokens: \($0)" },
            resource.cacheWriteTokens.map { "cache write tokens: \($0)" },
            resource.reasoningTokens.map { "reasoning tokens: \($0)" },
            resource.billingProvider.map { "billing provider: \($0)" },
            resource.billingMode.map { "billing mode: \($0)" },
            resource.estimatedCostUsd.map { "estimated cost usd: \($0)" },
            resource.actualCostUsd.map { "actual cost usd: \($0)" },
            resource.costStatus.map { "cost status: \($0)" },
            resource.apiCallCount.map { "api calls: \($0)" },
            resource.localOverlay?.authority.map { "overlay authority: \($0)" },
            resource.localOverlay?.writesRuntime.map { "overlay writes runtime: \($0)" },
            resource.localOverlay?.pinned.map { "overlay pinned: \($0)" },
            resource.providerAuth?.supportsOAuth.map { "oauth: \($0)" },
            resource.providerAuth?.supportsApiKey.map { "api key auth: \($0)" },
            resource.providerAuth?.supportsEnv.map { "env auth: \($0)" },
            resource.providerAuth?.supportsToken.map { "token auth: \($0)" },
            resource.envVars.map { "env vars: \($0.joined(separator: ", "))" },
            metadataKeysLabel(resource.metadata).map { "metadata keys: \($0)" }
        ]
        .compactMap { $0 }
    }

    private static func metadataKeysLabel(_ metadata: [String: RuntimeResource.MetadataValue]?) -> String? {
        guard let metadata, !metadata.isEmpty else { return nil }
        return metadata.keys.sorted().joined(separator: ", ")
    }

    private func modelResources() -> [RuntimeResource] {
        let modelBucket = domainData?.models
        let defaultModel = modelBucket?.defaultModel ?? runtimeResources?.defaultModel
        var resources = (modelBucket?.models ?? runtimeResources?.models ?? []).map { resource in
            resource.addingAttributes(Self.modelAttributes(resource, defaultModel: defaultModel))
        }
        guard let defaultModel else { return resources }
        let defaultModelId = defaultModel.modelId ?? defaultModel.label ?? "default-model"
        let defaultAlreadyListed = resources.contains { resource in
            if let modelId = defaultModel.modelId, resource.modelId == modelId { return true }
            return resource.id == defaultModelId
        }
        if !defaultAlreadyListed {
            resources.append(
                RuntimeResource(
                    id: "default-model",
                    label: defaultModel.label ?? defaultModelId,
                    status: "default",
                    kind: "default_model",
                    path: nil,
                    enabled: nil,
                    summary: nil,
                    updatedAt: nil,
                    sizeBytes: nil,
                    pinned: nil,
                    nativeIdentifier: nil,
                    provenance: nil,
                    limitations: nil,
                    attributes: Self.defaultModelAttributes(defaultModel),
                    modelId: defaultModel.modelId,
                    provider: defaultModel.provider,
                    available: nil,
                    source: nil,
                    isDefault: true,
                    scope: nil,
                    parentSessionId: nil,
                    toolCallCount: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    reasoningTokens: nil,
                    billingProvider: nil,
                    billingMode: nil,
                    estimatedCostUsd: nil,
                    actualCostUsd: nil,
                    costStatus: nil,
                    apiCallCount: nil,
                    providerAuth: nil,
                    envVars: nil,
                    lastError: nil,
                    metadata: nil,
                    pinAuthority: nil,
                    divergence: nil,
                    localOverlay: nil
                )
            )
        }
        return resources
    }

    private static func modelAttributes(
        _ resource: RuntimeResource,
        defaultModel: DomainData.Bucket.DefaultModel?
    ) -> [String] {
        [
            resource.provider.map { "provider: \($0)" },
            resource.modelId.map { "model id: \($0)" },
            resource.source.map { "source: \($0)" },
            resource.available.map { "available: \($0)" },
            isDefaultModel(resource, defaultModel: defaultModel).map { "default: \($0)" }
        ]
        .compactMap { $0 }
    }

    private static func defaultModelAttributes(_ defaultModel: DomainData.Bucket.DefaultModel) -> [String] {
        [
            defaultModel.provider.map { "provider: \($0)" },
            defaultModel.modelId.map { "model id: \($0)" },
            "default: true"
        ]
        .compactMap { $0 }
    }

    private static func isDefaultModel(
        _ resource: RuntimeResource,
        defaultModel: DomainData.Bucket.DefaultModel?
    ) -> Bool? {
        guard let defaultModel else { return resource.isDefault }
        if let modelId = defaultModel.modelId, resource.modelId == modelId { return true }
        if let modelId = defaultModel.modelId, resource.id == modelId { return true }
        return resource.isDefault
    }

    private func pluginResources() -> [RuntimeResource] {
        let pluginBucket = domainData?.plugins
        var resources = resourcesWithCommonAttributes(pluginBucket?.plugins ?? [])
        guard let status = pluginBucket?.status else { return resources }
        resources.append(
            RuntimeResource(
                id: "plugin-status",
                label: "Plugin status",
                status: status.status,
                kind: status.strategy,
                path: nil,
                enabled: status.supported,
                summary: nil,
                updatedAt: nil,
                sizeBytes: nil,
                pinned: nil,
                nativeIdentifier: nil,
                provenance: nil,
                limitations: status.limitations,
                attributes: Self.pluginStatusAttributes(status) + Self.capabilityDiagnosticsAttributes(status.diagnostics),
                modelId: nil,
                provider: nil,
                available: nil,
                source: nil,
                isDefault: nil,
                scope: nil,
                parentSessionId: nil,
                toolCallCount: nil,
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheWriteTokens: nil,
                reasoningTokens: nil,
                billingProvider: nil,
                billingMode: nil,
                estimatedCostUsd: nil,
                actualCostUsd: nil,
                costStatus: nil,
                apiCallCount: nil,
                providerAuth: nil,
                envVars: nil,
                lastError: nil,
                metadata: nil,
                pinAuthority: nil,
                divergence: nil,
                localOverlay: nil
            )
        )
        return resources
    }

    private static func pluginStatusAttributes(_ status: DomainData.RuntimeCapability) -> [String] {
        [
            status.supported.map { "supported: \($0)" },
            status.strategy.map { "strategy: \($0)" }
        ]
        .compactMap { $0 }
    }

    private static func capabilityDiagnosticsAttributes(
        _ diagnostics: DomainData.RuntimeCapability.Diagnostics?
    ) -> [String] {
        guard let diagnostics else { return [] }
        let diagnosticMessages = diagnostics.diagnostics ?? []
        return [
            diagnostics.source.map { "diagnostic source: \($0)" },
            diagnostics.probeMethod.map { "probe: \($0)" },
            diagnostics.transport.map { "transport: \($0)" },
            diagnostics.inventoryFreshness.map { "inventory freshness: \($0)" },
            diagnostics.mode.map { "diagnostic mode: \($0)" },
            diagnosticMessages.isEmpty ? nil : "diagnostics: \(diagnosticMessages.joined(separator: ", "))"
        ]
        .compactMap { $0 }
    }

    private static func syntheticRuntimeResource(
        id: String,
        label: String,
        status: String?,
        kind: String?,
        path: String? = nil,
        summary: String? = nil,
        enabled: Bool? = nil,
        limitations: [String]? = nil,
        attributes: [String]? = nil
    ) -> RuntimeResource {
        RuntimeResource(
            id: id,
            label: label,
            status: status,
            kind: kind,
            path: path,
            enabled: enabled,
            summary: summary,
            updatedAt: nil,
            sizeBytes: nil,
            pinned: nil,
            nativeIdentifier: nil,
            provenance: nil,
            limitations: limitations,
            attributes: attributes,
            modelId: nil,
            provider: nil,
            available: nil,
            source: nil,
            isDefault: nil,
            scope: nil,
            parentSessionId: nil,
            toolCallCount: nil,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheWriteTokens: nil,
            reasoningTokens: nil,
            billingProvider: nil,
            billingMode: nil,
            estimatedCostUsd: nil,
            actualCostUsd: nil,
            costStatus: nil,
            apiCallCount: nil,
            providerAuth: nil,
            envVars: nil,
            lastError: nil,
            metadata: nil,
            pinAuthority: nil,
            divergence: nil,
            localOverlay: nil
        )
    }

    private static func configurationSnapshotResources(
        _ snapshot: DomainData.ConfigurationBucket.RedactedConfigSnapshot?
    ) -> [RuntimeResource] {
        guard let snapshot else { return [] }
        let summary = syntheticRuntimeResource(
            id: "configuration-redacted-snapshot",
            label: "Redacted config snapshot",
            status: snapshot.exists == true ? "projected" : "degraded",
            kind: "redacted_config_snapshot",
            path: snapshot.path,
            summary: "Config values are redacted; only keys, value kinds, and presence are displayed.",
            attributes: [
                snapshot.valuePolicy.map { "value policy: \($0)" },
                snapshot.secretPolicy.map { "secret policy: \($0)" },
                snapshot.parseMode.map { "parse mode: \($0)" },
                snapshot.totalEntryCount.map { "entries: \($0)" },
                snapshot.secretEntryCount.map { "secret entries: \($0)" },
                snapshot.truncated.map { "truncated: \($0)" }
            ].compactMap { $0 }
        )
        let entries = (snapshot.entries ?? []).map { entry in
            syntheticRuntimeResource(
                id: "configuration-key-\((entry.key ?? "unknown").replacingOccurrences(of: ".", with: "-"))",
                label: entry.key ?? "Config key",
                status: entry.secret == true ? "redacted" : "projected",
                kind: "config_key",
                summary: entry.secret == true ? "Secret key presence only." : "Config value redacted.",
                attributes: [
                    entry.key.map { "key: \($0)" },
                    entry.valueState.map { "value state: \($0)" },
                    entry.valueKind.map { "value kind: \($0)" },
                    entry.redaction.map { "redaction: \($0)" },
                    entry.source.map { "source: \($0)" },
                    entry.secret.map { "secret: \($0)" }
                ].compactMap { $0 }
            )
        }
        return [summary] + entries
    }

    private func configurationResources() -> [RuntimeResource] {
        let portalResources = resourcesWithCommonAttributes(domainData?.configuration?.resources ?? [])
        let canonicalPaths = domainData?.configuration?.canonicalPaths ?? workspace?.canonicalPaths ?? [:]
        let managedFiles = domainData?.configuration?.managedFiles ?? workspace?.managedFiles ?? []
        let pathResources: [RuntimeResource] = canonicalPaths
            .keys
            .sorted()
            .compactMap { key in
                guard let path = canonicalPaths[key] else { return nil }
                return RuntimeResource(
                    id: key,
                    label: key,
                    status: "projected",
                    kind: "canonical_path",
                    path: path,
                    enabled: nil,
                    summary: nil,
                    updatedAt: nil,
                    sizeBytes: nil,
                    pinned: nil,
                    nativeIdentifier: nil,
                    provenance: nil,
                    limitations: nil,
                    attributes: nil,
                    modelId: nil,
                    provider: nil,
                    available: nil,
                    source: nil,
                    isDefault: nil,
                    scope: nil,
                    parentSessionId: nil,
                    toolCallCount: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    reasoningTokens: nil,
                    billingProvider: nil,
                    billingMode: nil,
                    estimatedCostUsd: nil,
                    actualCostUsd: nil,
                    costStatus: nil,
                    apiCallCount: nil,
                    providerAuth: nil,
                    envVars: nil,
                    lastError: nil,
                    metadata: nil,
                    pinAuthority: nil,
                    divergence: nil,
                    localOverlay: nil
                )
            }
        let managedFileResources = managedFiles
            .enumerated()
            .map { index, path in
                RuntimeResource(
                    id: "managed-file-\(index + 1)",
                    label: path.split(separator: "/").last.map(String.init) ?? "managed file",
                    status: "managed",
                    kind: "managed_file",
                    path: path,
                    enabled: nil,
                    summary: nil,
                    updatedAt: nil,
                    sizeBytes: nil,
                    pinned: nil,
                    nativeIdentifier: nil,
                    provenance: nil,
                    limitations: nil,
                    attributes: nil,
                    modelId: nil,
                    provider: nil,
                    available: nil,
                    source: nil,
                    isDefault: nil,
                    scope: nil,
                    parentSessionId: nil,
                    toolCallCount: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    reasoningTokens: nil,
                    billingProvider: nil,
                    billingMode: nil,
                    estimatedCostUsd: nil,
                    actualCostUsd: nil,
                    costStatus: nil,
                    apiCallCount: nil,
                    providerAuth: nil,
                    envVars: nil,
                    lastError: nil,
                    metadata: nil,
                    pinAuthority: nil,
                    divergence: nil,
                    localOverlay: nil
                )
            }
        let redactedSnapshotResources = Self.configurationSnapshotResources(
            domainData?.configuration?.redactedConfigSnapshot
        )
        let diagnosticsResources: [RuntimeResource] = {
            guard let lastError = domainData?.configuration?.diagnostics?.lastError else { return [] }
            return [
                RuntimeResource(
                    id: "configuration-diagnostics",
                    label: "Diagnostics",
                    status: "degraded",
                    kind: "diagnostics",
                    path: nil,
                    enabled: nil,
                    summary: lastError,
                    updatedAt: nil,
                    sizeBytes: nil,
                    pinned: nil,
                    nativeIdentifier: nil,
                    provenance: nil,
                    limitations: nil,
                    attributes: nil,
                    modelId: nil,
                    provider: nil,
                    available: nil,
                    source: nil,
                    isDefault: nil,
                    scope: nil,
                    parentSessionId: nil,
                    toolCallCount: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    reasoningTokens: nil,
                    billingProvider: nil,
                    billingMode: nil,
                    estimatedCostUsd: nil,
                    actualCostUsd: nil,
                    costStatus: nil,
                    apiCallCount: nil,
                    providerAuth: nil,
                    envVars: nil,
                    lastError: nil,
                    metadata: nil,
                    pinAuthority: nil,
                    divergence: nil,
                    localOverlay: nil
                )
            ]
        }()
        let capabilityResources: [RuntimeResource] = {
            guard let capability = domainData?.configuration?.capability else { return [] }
            return [
                RuntimeResource(
                    id: "configuration-capability",
                    label: "Configuration capability",
                    status: capability.status,
                    kind: capability.strategy,
                    path: nil,
                    enabled: capability.supported,
                    summary: nil,
                    updatedAt: nil,
                    sizeBytes: nil,
                    pinned: nil,
                    nativeIdentifier: nil,
                    provenance: nil,
                    limitations: capability.limitations,
                    attributes: Self.pluginStatusAttributes(capability) + Self.capabilityDiagnosticsAttributes(capability.diagnostics),
                    modelId: nil,
                    provider: nil,
                    available: nil,
                    source: nil,
                    isDefault: nil,
                    scope: nil,
                    parentSessionId: nil,
                    toolCallCount: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    reasoningTokens: nil,
                    billingProvider: nil,
                    billingMode: nil,
                    estimatedCostUsd: nil,
                    actualCostUsd: nil,
                    costStatus: nil,
                    apiCallCount: nil,
                    providerAuth: nil,
                    envVars: nil,
                    lastError: nil,
                    metadata: nil,
                    pinAuthority: nil,
                    divergence: nil,
                    localOverlay: nil
                )
            ]
        }()
        return portalResources + pathResources + managedFileResources + redactedSnapshotResources + diagnosticsResources + capabilityResources
    }
}

struct ClawJSRuntimeLensClient {
    struct CommandResult {
        let data: Data
        let exitCode: Int32
    }

    struct CommandRunner {
        var run: ([String]) async throws -> CommandResult
    }

    struct SessionOverlayActionResult: Decodable, Equatable {
        let runtimeId: String
        let domain: String
        let action: String
        let status: String
        let authority: String?
        let writesRuntime: Bool
        let wouldWriteRuntime: Bool?
        let writesLocalOverlay: Bool?
        let writeBackStatus: String?
        let nativeWriteBackStatus: String?
        let nativeWriteBackBlockerClass: String?
        let officialRuntimeWriteBackContractRequired: Bool?
        let officialRuntimeWriteBackContractKnown: Bool?
        let nativeWriteBackFixtureRequired: Bool?
        let nativeWriteBackSafeDefault: String?
        let userVisibleContract: String?
        let claimEffect: String?
        let supportResolution: String?
        let evidenceRequirementId: String?
        let riskControls: [String]?
        let nativeWriteBackContract: NativeWriteBackContract?
        let result: Result

        struct NativeWriteBackContract: Decodable, Equatable {
            let status: String?
            let writesRuntime: Bool?
            let wouldWriteRuntime: Bool?
            let officialContractRequired: Bool?
            let officialContractKnown: Bool?
            let fixtureRequired: Bool?
            let safeDefault: String?
            let userVisibleContract: String?
            let claimEffect: String?
            let evidenceRequirementId: String?
        }

        struct Result: Decodable, Equatable {
            let id: String
            let overlayThreadId: String
            let pinned: Bool
            let receipt: Receipt?
        }

        struct Receipt: Decodable, Equatable {
            let requestId: String?
            let hostId: String?
            let status: String?
        }
    }

    struct SessionNativeActionResult: Decodable, Equatable {
        let runtimeId: String
        let domain: String
        let action: String
        let status: String
        let authority: String?
        let writesRuntime: Bool
        let wouldWriteRuntime: Bool?
        let writesLocalOverlay: Bool?
        let reason: String?
        let degradedReason: String?
        let roundTripVerificationStatus: String?
        let blockerClass: String?
        let officialContractRequired: Bool?
        let officialContractKnown: Bool?
        let requiredFlag: String?
        let officialProtocol: String?
        let officialMethod: String?
        let officialContractSource: String?
        let integrationRequired: Bool?
        let fixtureRequired: Bool?
        let requiredEvidence: [String]?
        let riskControls: [String]?
        let writeBackStatus: String?
        let fallbackPolicy: String?
        let supportResolution: String?
        let productDecision: String?
        let userVisibleContract: String?
        let claimEffect: String?
        let promotionGate: String?
        let safeDefault: String?
        let commandShape: String?
        let evidenceRequirementId: String?
        let evidenceReentryStatus: String?
        let transportPolicyId: String?
        let transportPolicy: ClawJSRuntimeLensSnapshot.TransportPolicy?
        let productionTransportStatus: String?
        let lifecycleStatus: String?
        let requiredEndpoint: String?
        let endpointPolicy: String?
        let approvalScope: String?
        let productionTransportCommandShape: String?
        let doNotRunWithoutApproval: Bool?
        let claimBlockedUntil: String?
        let result: Result?

        struct Result: Decodable, Equatable {
            let id: String?
            let found: Bool?
            let messagePreview: String?
            let titleRequested: String?
            let titleApplied: Bool?
            let contentIncluded: Bool?
            let totalProjected: Int?
            let nativeIdentifier: NativeIdentifier?
            let gatewayReceipt: GatewayReceipt?
            let titleGatewayReceipt: GatewayReceipt?
            let roundTripVerification: RoundTripVerification?
        }

        struct NativeIdentifier: Decodable, Equatable {
            let name: String?
        }

        struct GatewayReceipt: Decodable, Equatable {
            let `protocol`: String?
            let transport: String?
            let method: String?
            let requestId: String?
            let endpoint: String?
        }

        struct RoundTripVerification: Decodable, Equatable {
            let status: String?
            let id: String?
            let title: String?
            let matchedBy: String?
            let action: String?
            let writesRuntime: Bool?
            let endedAt: String?
            let endReason: String?
            let messageIndex: Int?
            let messageRole: String?
            let totalAvailableInStore: Int?
            let nativeIdentifier: NativeIdentifier?
            let provenance: Provenance?
            let checked: [String]?
            let safeDefault: String?

            struct Provenance: Decodable, Equatable {
                let source: String?
                let runtimeId: String?
                let path: String?
                let table: String?
            }
        }
    }

    private struct Envelope: Decodable {
        let data: ClawJSRuntimeLensSnapshot
    }

    private struct SessionOverlayEnvelope: Decodable {
        let data: SessionOverlayActionResult
    }

    private struct SessionNativeActionEnvelope: Decodable {
        let data: SessionNativeActionResult
    }

    private static let maxRuntimeLensEnvelopeBytes = 1_048_576

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { args in
            try await Self.runClawJS(args: args)
        }
    }

    func load(
        runtime: ClawJSRuntimeLensID,
        homeDir: String? = nil,
        runtimeWorkspace: String? = nil,
        configPath: String? = nil,
        authStore: String? = nil,
        approvalGateFixture: String? = nil,
        gatewayURL: String? = nil
    ) async throws -> ClawJSRuntimeLensSnapshot {
        var args = ["runtime", runtime.rawValue, "domains"]
        appendRuntimeScopeArgs(
            to: &args,
            homeDir: homeDir,
            runtimeWorkspace: runtimeWorkspace,
            configPath: configPath,
            authStore: authStore,
            approvalGateFixture: approvalGateFixture,
            gatewayURL: gatewayURL
        )
        args.append("--json")
        let result = try await runner.run(args)
        guard result.exitCode == 0 || result.exitCode == 2 else {
            let message = String(data: result.data, encoding: .utf8) ?? "runtime lens failed"
            throw NSError(domain: "ClawJSRuntimeLensClient", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        guard result.data.count <= Self.maxRuntimeLensEnvelopeBytes else {
            throw NSError(domain: "ClawJSRuntimeLensClient", code: 413, userInfo: [
                NSLocalizedDescriptionKey: "runtime lens envelope exceeded the bounded decode budget"
            ])
        }
        // hot-path-ok maxBytes=1048576 reason=runtime lens command returns one bounded domains envelope
        return try JSONDecoder().decode(Envelope.self, from: result.data).data
    }

    func setSessionPinned(
        runtime: ClawJSRuntimeLensID,
        sessionId: String,
        pinned: Bool
    ) async throws -> SessionOverlayActionResult {
        let result = try await runner.run([
            "runtime",
            runtime.rawValue,
            "sessions",
            pinned ? "pin" : "unpin",
            "--session-key",
            sessionId,
            "--json"
        ])
        guard result.exitCode == 0 else {
            let message = String(data: result.data, encoding: .utf8) ?? "runtime session overlay failed"
            throw NSError(domain: "ClawJSRuntimeLensClient", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        guard result.data.count <= Self.maxRuntimeLensEnvelopeBytes else {
            throw NSError(domain: "ClawJSRuntimeLensClient", code: 413, userInfo: [
                NSLocalizedDescriptionKey: "runtime session overlay envelope exceeded the bounded decode budget"
            ])
        }
        // hot-path-ok maxBytes=1048576 reason=session overlay command returns one bounded envelope
        return try JSONDecoder().decode(SessionOverlayEnvelope.self, from: result.data).data
    }

    func runSessionAction(
        runtime: ClawJSRuntimeLensID,
        action: String,
        sessionId: String? = nil,
        message: String? = nil,
        title: String? = nil,
        gatewayURL: String? = nil,
        homeDir: String? = nil,
        runtimeWorkspace: String? = nil,
        configPath: String? = nil,
        authStore: String? = nil,
        approvalGateFixture: String? = nil,
        confirmRuntimeWrite: Bool = false
    ) async throws -> SessionNativeActionResult {
        var args = [
            "runtime",
            runtime.rawValue,
            "sessions",
            action
        ]
        if let sessionId, !sessionId.isEmpty {
            args.append(contentsOf: ["--session-key", sessionId])
        }
        if let message, !message.isEmpty {
            args.append(contentsOf: ["--message", message])
        }
        if let title, !title.isEmpty {
            args.append(contentsOf: ["--title", title])
        }
        appendRuntimeScopeArgs(
            to: &args,
            homeDir: homeDir,
            runtimeWorkspace: runtimeWorkspace,
            configPath: configPath,
            authStore: authStore,
            approvalGateFixture: approvalGateFixture,
            gatewayURL: gatewayURL
        )
        if confirmRuntimeWrite {
            args.append("--confirm-runtime-write")
        }
        args.append("--json")

        let result = try await runner.run(args)
        guard result.exitCode == 0 || result.exitCode == 2 else {
            let message = String(data: result.data, encoding: .utf8) ?? "runtime session action failed"
            throw NSError(domain: "ClawJSRuntimeLensClient", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        guard result.data.count <= Self.maxRuntimeLensEnvelopeBytes else {
            throw NSError(domain: "ClawJSRuntimeLensClient", code: 413, userInfo: [
                NSLocalizedDescriptionKey: "runtime session action envelope exceeded the bounded decode budget"
            ])
        }
        // hot-path-ok maxBytes=1048576 reason=session action command returns one bounded envelope
        return try JSONDecoder().decode(SessionNativeActionEnvelope.self, from: result.data).data
    }

    private func appendRuntimeScopeArgs(
        to args: inout [String],
        homeDir: String?,
        runtimeWorkspace: String?,
        configPath: String?,
        authStore: String?,
        approvalGateFixture: String?,
        gatewayURL: String?
    ) {
        if let homeDir, !homeDir.isEmpty {
            args.append(contentsOf: ["--home-dir", homeDir])
        }
        if let runtimeWorkspace, !runtimeWorkspace.isEmpty {
            args.append(contentsOf: ["--runtime-workspace", runtimeWorkspace])
        }
        if let configPath, !configPath.isEmpty {
            args.append(contentsOf: ["--config-path", configPath])
        }
        if let authStore, !authStore.isEmpty {
            args.append(contentsOf: ["--auth-store", authStore])
        }
        if let approvalGateFixture, !approvalGateFixture.isEmpty {
            args.append(contentsOf: ["--approval-gate-fixture", approvalGateFixture])
        }
        if let gatewayURL, !gatewayURL.isEmpty {
            args.append(contentsOf: ["--gateway-url", gatewayURL])
        }
    }

    private static func runClawJS(args: [String]) async throws -> CommandResult {
        let context = await MainActor.run {
            RuntimeLensProcessContext(
                executableURL: ClawJSRuntime.nodeBinaryURL,
                cliScriptURL: ClawJSRuntime.cliScriptURL,
                workspaceURL: ClawJSServiceManager.workspaceURL,
                environment: ClawJSServiceManager.cliEnvironment()
            )
        }
        let cancellation = RuntimeLensProcessCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try runClawJSSynchronously(
                            args: args,
                            context: context,
                            cancellation: cancellation
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    nonisolated private static func runClawJSSynchronously(
        args: [String],
        context: RuntimeLensProcessContext,
        cancellation: RuntimeLensProcessCancellation
    ) throws -> CommandResult {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSRuntimeLensClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ClawJS bundle is not available in this build."
            ])
        }
        let process = Process()
        process.executableURL = context.executableURL
        process.arguments = [context.cliScriptURL.path] + args
        process.currentDirectoryURL = context.workspaceURL
        process.environment = context.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        guard cancellation.attach(process) else { throw CancellationError() }
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if cancellation.isCancelled { throw CancellationError() }
        return CommandResult(data: data.isEmpty ? err : data, exitCode: process.terminationStatus)
    }
}

private struct RuntimeLensProcessContext: Sendable {
    let executableURL: URL
    let cliScriptURL: URL
    let workspaceURL: URL
    let environment: [String: String]
}

private final class RuntimeLensProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        process?.terminate()
    }
}
