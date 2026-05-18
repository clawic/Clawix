import Foundation
import SwiftUI

enum LegalSafetyPolicy {
    static let termsVersion = "2026-05-18"
    static let privacyVersion = "2026-05-18"
    static let eulaVersion = "2026-05-18"
    static let disclaimerVersion = "2026-05-18"
    static let safetyVersion = "2026-05-18"
    static let regulatedDomainsVersion = "2026-05-18"
    static let minimumAge = 18

    static let regulatedDecisionDisclaimer = "Clawix can help organize, search, summarize, label, and draft sensitive material, but it is not professional advice and must not be used as the final authority for regulated decisions."
    static let crisisDisclaimer = "In an emergency or crisis, contact local emergency services or trusted local resources. Clawix is not an emergency service."

    static let defaultOutputLabels = [
        "draft_not_final",
        "not_professional_advice",
        "human_review_required",
        "sources_and_gaps_required",
        "regulated_domain",
        "disclaimer_version:\(disclaimerVersion)"
    ]

    static func crisisRefusal(for text: String) -> String? {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let crisisSignals = [
            "suicide",
            "kill myself",
            "end my life",
            "harm myself",
            "hurt myself",
            "self harm",
            "self-harm",
            "take my own life",
            "want to die",
            "no quiero vivir",
            "quiero morir",
            "suicid",
            "hacerme dano",
            "hacerme daño",
            "autolesion",
            "autolesión",
            "quitarme la vida"
        ]
        guard crisisSignals.contains(where: { normalized.contains($0) }) else { return nil }

        return """
        I can't help handle a crisis or self-harm situation as an assistant.

        If you or someone nearby may be in immediate danger, contact local emergency services now. In the US you can call or text 988 for crisis support. In the EU you can call 112 for emergency help. If you are outside those areas, contact your local emergency number or a trusted local crisis resource.

        Clawix is not an emergency service and does not provide therapy, diagnosis, treatment, or crisis counseling.
        """
    }
}

enum LegalSensitiveAction: String, CaseIterable, Identifiable {
    case exportShare = "export_share"
    case remoteSync = "remote_sync"
    case providerUse = "provider_use"
    case supportDiagnostics = "support_diagnostics"
    case externalAction = "external_action"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exportShare: return "Export or share sensitive data"
        case .remoteSync: return "Remote or sync sensitive data"
        case .providerUse: return "Send sensitive data to a provider"
        case .supportDiagnostics: return "Share support diagnostics"
        case .externalAction: return "Take an external sensitive action"
        }
    }

    var confirmationLabel: LocalizedStringKey {
        switch self {
        case .exportShare: return "Export"
        case .remoteSync: return "Continue"
        case .providerUse: return "Send"
        case .supportDiagnostics: return "Share"
        case .externalAction: return "Review"
        }
    }
}

struct LegalSensitiveActionReview: Equatable {
    var requiresConfirmation: Bool
    var labels: [String]
    var disclaimerVersion: String
    var reason: String
}

enum LegalSafetyDefaultsKeys {
    static let acceptedTermsVersion = "Legal.AcceptedTermsVersion"
    static let acceptedPrivacyVersion = "Legal.AcceptedPrivacyVersion"
    static let acceptedEULAVersion = "Legal.AcceptedEULAVersion"
    static let acceptedAt = "Legal.AcceptedAt"
    static let adultConfirmed = "Legal.AdultConfirmed"
    static let remoteSyncOptIn = "Legal.RemoteSyncOptIn"
    static let providerDisclosureOptIn = "Legal.ProviderDisclosureOptIn"
    static let supportDiagnosticsOptIn = "Legal.SupportDiagnosticsOptIn"
    static let sensitiveExportConfirmationRequired = "Legal.SensitiveExportConfirmationRequired"
    static let localAuditRetentionDays = "Legal.LocalAuditRetentionDays"
}

@MainActor
final class LegalSafetyStore: ObservableObject {
    static let shared = LegalSafetyStore()

    private let defaults: UserDefaults

    @Published private(set) var acceptedTermsVersion: String?
    @Published private(set) var acceptedPrivacyVersion: String?
    @Published private(set) var acceptedEULAVersion: String?
    @Published private(set) var acceptedAt: Date?
    @Published var adultConfirmed: Bool {
        didSet { defaults.set(adultConfirmed, forKey: LegalSafetyDefaultsKeys.adultConfirmed) }
    }
    @Published var remoteSyncOptIn: Bool {
        didSet { defaults.set(remoteSyncOptIn, forKey: LegalSafetyDefaultsKeys.remoteSyncOptIn) }
    }
    @Published var providerDisclosureOptIn: Bool {
        didSet { defaults.set(providerDisclosureOptIn, forKey: LegalSafetyDefaultsKeys.providerDisclosureOptIn) }
    }
    @Published var supportDiagnosticsOptIn: Bool {
        didSet { defaults.set(supportDiagnosticsOptIn, forKey: LegalSafetyDefaultsKeys.supportDiagnosticsOptIn) }
    }
    @Published var sensitiveExportConfirmationRequired: Bool {
        didSet { defaults.set(sensitiveExportConfirmationRequired, forKey: LegalSafetyDefaultsKeys.sensitiveExportConfirmationRequired) }
    }
    @Published var localAuditRetentionDays: Int {
        didSet { defaults.set(localAuditRetentionDays, forKey: LegalSafetyDefaultsKeys.localAuditRetentionDays) }
    }

    init(defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard) {
        self.defaults = defaults
        acceptedTermsVersion = defaults.string(forKey: LegalSafetyDefaultsKeys.acceptedTermsVersion)
        acceptedPrivacyVersion = defaults.string(forKey: LegalSafetyDefaultsKeys.acceptedPrivacyVersion)
        acceptedEULAVersion = defaults.string(forKey: LegalSafetyDefaultsKeys.acceptedEULAVersion)
        acceptedAt = defaults.object(forKey: LegalSafetyDefaultsKeys.acceptedAt) as? Date
        adultConfirmed = defaults.object(forKey: LegalSafetyDefaultsKeys.adultConfirmed) as? Bool ?? false
        remoteSyncOptIn = defaults.object(forKey: LegalSafetyDefaultsKeys.remoteSyncOptIn) as? Bool ?? false
        providerDisclosureOptIn = defaults.object(forKey: LegalSafetyDefaultsKeys.providerDisclosureOptIn) as? Bool ?? false
        supportDiagnosticsOptIn = defaults.object(forKey: LegalSafetyDefaultsKeys.supportDiagnosticsOptIn) as? Bool ?? false
        sensitiveExportConfirmationRequired = defaults.object(forKey: LegalSafetyDefaultsKeys.sensitiveExportConfirmationRequired) as? Bool ?? true
        let retention = defaults.integer(forKey: LegalSafetyDefaultsKeys.localAuditRetentionDays)
        localAuditRetentionDays = retention > 0 ? retention : 90
    }

    var hasAcceptedCurrentLegal: Bool {
        acceptedTermsVersion == LegalSafetyPolicy.termsVersion &&
        acceptedPrivacyVersion == LegalSafetyPolicy.privacyVersion &&
        acceptedEULAVersion == LegalSafetyPolicy.eulaVersion &&
        adultConfirmed
    }

    var acceptedVersionSummary: String {
        guard let acceptedAt else { return "Not accepted" }
        return "Accepted \(LegalSafetyPolicy.termsVersion) on \(Self.dateFormatter.string(from: acceptedAt))"
    }

    func acceptCurrentLegal(adultConfirmed: Bool = true) {
        let now = Date()
        self.adultConfirmed = adultConfirmed
        acceptedTermsVersion = LegalSafetyPolicy.termsVersion
        acceptedPrivacyVersion = LegalSafetyPolicy.privacyVersion
        acceptedEULAVersion = LegalSafetyPolicy.eulaVersion
        acceptedAt = now
        defaults.set(LegalSafetyPolicy.termsVersion, forKey: LegalSafetyDefaultsKeys.acceptedTermsVersion)
        defaults.set(LegalSafetyPolicy.privacyVersion, forKey: LegalSafetyDefaultsKeys.acceptedPrivacyVersion)
        defaults.set(LegalSafetyPolicy.eulaVersion, forKey: LegalSafetyDefaultsKeys.acceptedEULAVersion)
        defaults.set(now, forKey: LegalSafetyDefaultsKeys.acceptedAt)
    }

    func resetAcceptanceForReview() {
        adultConfirmed = false
        acceptedTermsVersion = nil
        acceptedPrivacyVersion = nil
        acceptedEULAVersion = nil
        acceptedAt = nil
        for key in [
            LegalSafetyDefaultsKeys.acceptedTermsVersion,
            LegalSafetyDefaultsKeys.acceptedPrivacyVersion,
            LegalSafetyDefaultsKeys.acceptedEULAVersion,
            LegalSafetyDefaultsKeys.acceptedAt
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    func review(for action: LegalSensitiveAction) -> LegalSensitiveActionReview {
        let optInSatisfied: Bool = {
            switch action {
            case .exportShare: return true
            case .remoteSync: return remoteSyncOptIn
            case .providerUse: return providerDisclosureOptIn
            case .supportDiagnostics: return supportDiagnosticsOptIn
            case .externalAction: return false
            }
        }()
        let requiresConfirmation = sensitiveExportConfirmationRequired || !optInSatisfied || action == .externalAction
        return LegalSensitiveActionReview(
            requiresConfirmation: requiresConfirmation,
            labels: LegalSafetyPolicy.defaultOutputLabels,
            disclaimerVersion: LegalSafetyPolicy.disclaimerVersion,
            reason: optInSatisfied ? "Explicit review required for sensitive action." : "User opt-in is missing or action always requires review."
        )
    }

    func sensitiveActionConfirmationBody(for action: LegalSensitiveAction) -> LocalizedStringKey {
        let labels = review(for: action).labels.joined(separator: ", ")
        return LocalizedStringKey("""
        \(action.title)

        Sensitive data may include health, mental health, legal, finance, banking, insurance, employment, education, government, identity, security, billing, IoT, vehicles, minors, or other regulated domains.

        Clawix does not provide professional advice or make final regulated decisions. Review sources, gaps, recipients, provider terms, and consequences before continuing.

        Labels: \(labels)
        """)
    }

    func requestSensitiveActionReview(
        action: LegalSensitiveAction,
        appState: AppState,
        onConfirm: @escaping () -> Void
    ) {
        appState.pendingConfirmation = ConfirmationRequest(
            title: LocalizedStringKey(action.title),
            body: sensitiveActionConfirmationBody(for: action),
            confirmLabel: action.confirmationLabel,
            isDestructive: action == .externalAction,
            onConfirm: onConfirm
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
