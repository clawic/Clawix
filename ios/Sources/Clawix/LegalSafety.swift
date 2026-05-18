import Foundation
import Observation

enum IOSLegalSafetyPolicy {
    static let termsVersion = "2026-05-18"
    static let privacyVersion = "2026-05-18"
    static let eulaVersion = "2026-05-18"
    static let safetyVersion = "2026-05-18"
    static let regulatedDomainsVersion = "2026-05-18"
    static let disclaimerVersion = "2026-05-18"
    static let minimumAge = 18
    static let defaultOutputLabels = [
        "draft_not_final",
        "not_professional_advice",
        "human_review_required",
        "sources_and_gaps_required",
        "regulated_domain"
    ]
    static let regulatedDecisionDisclaimer = "Clawix can help organize, search, summarize, label, and draft sensitive material, but it is not professional advice and must not be used as the final authority for regulated decisions."

    static var sensitiveCopyReviewMessage: String {
        "Clawix outputs are drafts, not professional advice. Review sources, gaps, recipients, and consequences before copying or sharing sensitive material."
    }

    static func reviewedSensitiveOutputText(_ text: String) -> String {
        let labels = defaultOutputLabels.joined(separator: ", ")
        return """
        <!-- Clawix export labels: \(labels); disclaimer_version=\(disclaimerVersion); not professional advice; draft not final. -->
        \(text)
        """
    }

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
            "autolesion",
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

enum IOSLegalSafetyDefaultsKeys {
    static let acceptedTermsVersion = "Legal.AcceptedTermsVersion"
    static let acceptedPrivacyVersion = "Legal.AcceptedPrivacyVersion"
    static let acceptedEULAVersion = "Legal.AcceptedEULAVersion"
    static let acceptedAt = "Legal.AcceptedAt"
    static let adultConfirmed = "Legal.AdultConfirmed"
}

@Observable
final class IOSLegalSafetyStore {
    static let shared = IOSLegalSafetyStore()

    private let defaults: UserDefaults
    private(set) var acceptedTermsVersion: String?
    private(set) var acceptedPrivacyVersion: String?
    private(set) var acceptedEULAVersion: String?
    private(set) var acceptedAt: Date?
    var adultConfirmed: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        acceptedTermsVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedTermsVersion)
        acceptedPrivacyVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedPrivacyVersion)
        acceptedEULAVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedEULAVersion)
        acceptedAt = defaults.object(forKey: IOSLegalSafetyDefaultsKeys.acceptedAt) as? Date
        adultConfirmed = defaults.object(forKey: IOSLegalSafetyDefaultsKeys.adultConfirmed) as? Bool ?? false
    }

    var hasAcceptedCurrentLegal: Bool {
        acceptedTermsVersion == IOSLegalSafetyPolicy.termsVersion &&
        acceptedPrivacyVersion == IOSLegalSafetyPolicy.privacyVersion &&
        acceptedEULAVersion == IOSLegalSafetyPolicy.eulaVersion &&
        adultConfirmed
    }

    func acceptCurrentLegal(adultConfirmed: Bool = true) {
        let now = Date()
        self.adultConfirmed = adultConfirmed
        acceptedTermsVersion = IOSLegalSafetyPolicy.termsVersion
        acceptedPrivacyVersion = IOSLegalSafetyPolicy.privacyVersion
        acceptedEULAVersion = IOSLegalSafetyPolicy.eulaVersion
        acceptedAt = now
        defaults.set(IOSLegalSafetyPolicy.termsVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedTermsVersion)
        defaults.set(IOSLegalSafetyPolicy.privacyVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedPrivacyVersion)
        defaults.set(IOSLegalSafetyPolicy.eulaVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedEULAVersion)
        defaults.set(now, forKey: IOSLegalSafetyDefaultsKeys.acceptedAt)
        defaults.set(adultConfirmed, forKey: IOSLegalSafetyDefaultsKeys.adultConfirmed)
    }
}
