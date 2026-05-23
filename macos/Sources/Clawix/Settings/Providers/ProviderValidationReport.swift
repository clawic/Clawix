import AIProviders
import Foundation

enum ProviderValidationMode: Equatable, Sendable {
    case liveApproved
    case hermeticFixture
}

enum ProviderCredentialValidationState: String, Equatable, Sendable {
    case missing
    case placeholder
    case present
    case expired
}

enum ProviderValidationDisposition: String, Equatable, Sendable {
    case fixturePassed
    case livePassed
    case externalPending
    case providerError
    case blocked
}

struct ProviderValidationReport: Equatable, Sendable {
    let providerId: ProviderID
    let mode: ProviderValidationMode
    let credentialState: ProviderCredentialValidationState
    let disposition: ProviderValidationDisposition
    let summary: String
    let externalPending: [String]
    let evidence: [String]
    let providerError: String?

    var isComplete: Bool {
        disposition == .livePassed && externalPending.isEmpty && providerError == nil
    }

    var validationReportStatus: String {
        if !externalPending.isEmpty {
            return "EXTERNAL PENDING"
        }
        switch disposition {
        case .livePassed:
            return "PASS"
        case .fixturePassed, .externalPending:
            return "EXTERNAL PENDING"
        case .providerError, .blocked:
            return "FAIL"
        }
    }

    var uiStatusText: String {
        switch disposition {
        case .livePassed:
            return isComplete ? L10n.t("Connected") : L10n.t("Live check pending")
        case .fixturePassed:
            return L10n.t("Fixture only")
        case .externalPending:
            return L10n.t("Live validation pending")
        case .providerError:
            return providerError ?? L10n.t("Provider error")
        case .blocked:
            return summary
        }
    }

    static func credentialState(apiKey: String, expiresAt: Date? = nil, now: Date = Date()) -> ProviderCredentialValidationState {
        if let expiresAt, expiresAt <= now {
            return .expired
        }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .missing
        }
        let lowered = trimmed.lowercased()
        let placeholderMarkers = ["fixture", "mock", "placeholder", "dummy", "redacted"]
        if placeholderMarkers.contains(where: { lowered.contains($0) }) {
            return .placeholder
        }
        return .present
    }

    static func livePassed(providerId: ProviderID, apiKey: String) -> ProviderValidationReport {
        ProviderValidationReport(
            providerId: providerId,
            mode: .liveApproved,
            credentialState: credentialState(apiKey: apiKey),
            disposition: .livePassed,
            summary: L10n.t("Approved live provider check passed."),
            externalPending: [],
            evidence: ["approved_live_provider_round_trip"],
            providerError: nil
        )
    }

    static func providerError(
        providerId: ProviderID,
        apiKey: String,
        mode: ProviderValidationMode,
        detail: String
    ) -> ProviderValidationReport {
        let failure = UserFacingFailure.classify(detail)
        failure.log(surface: "settings.providers.connectionProbe")
        return ProviderValidationReport(
            providerId: providerId,
            mode: mode,
            credentialState: credentialState(apiKey: apiKey),
            disposition: .providerError,
            summary: L10n.t("Provider returned an error."),
            externalPending: mode == .liveApproved ? [] : ["live_provider_validation_not_run"],
            evidence: mode == .liveApproved ? ["approved_live_provider_error"] : ["hermetic_provider_error_fixture"],
            providerError: failure.displayMessage
        )
    }
}

enum ProviderValidationFixtureInterceptor {
    static let providerErrorCredential = "fixture-provider-error"
    static let expiredCredential = "fixture-expired"

    @MainActor
    static func validate(providerId: ProviderID, apiKey: String, baseURL: URL?) async throws -> ProviderValidationReport {
        if apiKey == providerErrorCredential {
            return ProviderValidationReport.providerError(
                providerId: providerId,
                apiKey: apiKey,
                mode: .hermeticFixture,
                detail: "HTTP 401: fixture unauthorized"
            )
        }
        if providerId == .openAICompatibleCustom && baseURL == nil {
            return ProviderValidationReport(
                providerId: providerId,
                mode: .hermeticFixture,
                credentialState: ProviderValidationReport.credentialState(apiKey: apiKey),
                disposition: .blocked,
                summary: L10n.t("Base URL is required."),
                externalPending: ["custom_provider_base_url_missing", "live_provider_validation_not_run"],
                evidence: ["hermetic_provider_validation_fixture"],
                providerError: nil
            )
        }

        let credentialState = fixtureCredentialState(apiKey: apiKey)
        let credentialPending: [String]
        switch credentialState {
        case .missing:
            credentialPending = ["provider_credential_missing"]
        case .placeholder:
            credentialPending = ["provider_credential_placeholder"]
        case .expired:
            credentialPending = ["provider_credential_expired"]
        case .present:
            credentialPending = []
        }

        return ProviderValidationReport(
            providerId: providerId,
            mode: .hermeticFixture,
            credentialState: credentialState,
            disposition: credentialPending.isEmpty ? .fixturePassed : .externalPending,
            summary: L10n.t("Hermetic provider validation fixture passed without network."),
            externalPending: credentialPending + ["live_provider_validation_not_run"],
            evidence: ["hermetic_provider_validation_fixture", "network_intercepted_no_provider_call"],
            providerError: nil
        )
    }

    private static func fixtureCredentialState(apiKey: String) -> ProviderCredentialValidationState {
        if apiKey == expiredCredential {
            return .expired
        }
        return ProviderValidationReport.credentialState(apiKey: apiKey)
    }
}
