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
        <!-- Clawix export labels: \(labels); disclaimer_version=\(disclaimerVersion); not professional advice; draft not final; human review required; sources and gaps required. -->
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
            "want to die"
        ] + nonEnglishCrisisSignals
        guard crisisSignals.contains(where: { normalized.contains($0) }) else { return nil }
        return """
        I can't help handle a crisis or self-harm situation as an assistant.

        If you or someone nearby may be in immediate danger, contact local emergency services now. In the US you can call or text 988 for crisis support. In the EU you can call 112 for emergency help. If you are outside those areas, contact your local emergency number or a trusted local crisis resource.

        Clawix is not an emergency service and does not provide therapy, diagnosis, treatment, or crisis counseling.
        """
    }

    private static var nonEnglishCrisisSignals: [String] {
        let signals: [[UInt8]] = [
            [110, 111, 32, 113, 117, 105, 101, 114, 111, 32, 118, 105, 118, 105, 114],
            [113, 117, 105, 101, 114, 111, 32, 109, 111, 114, 105, 114],
            [115, 117, 105, 99, 105, 100],
            [104, 97, 99, 101, 114, 109, 101, 32, 100, 97, 110, 111],
            [97, 117, 116, 111, 108, 101, 115, 105, 111, 110],
            [113, 117, 105, 116, 97, 114, 109, 101, 32, 108, 97, 32, 118, 105, 100, 97],
        ]
        return signals.map { String(decoding: $0, as: UTF8.self) }
    }
}

enum IOSLegalSafetyDefaultsKeys {
    static let acceptedTermsVersion = "Legal.AcceptedTermsVersion"
    static let acceptedPrivacyVersion = "Legal.AcceptedPrivacyVersion"
    static let acceptedEULAVersion = "Legal.AcceptedEULAVersion"
    static let acceptedDisclaimerVersion = "Legal.AcceptedDisclaimerVersion"
    static let acceptedSafetyVersion = "Legal.AcceptedSafetyVersion"
    static let acceptedRegulatedDomainsVersion = "Legal.AcceptedRegulatedDomainsVersion"
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
    private(set) var acceptedDisclaimerVersion: String?
    private(set) var acceptedSafetyVersion: String?
    private(set) var acceptedRegulatedDomainsVersion: String?
    private(set) var acceptedAt: Date?
    var adultConfirmed: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        acceptedTermsVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedTermsVersion)
        acceptedPrivacyVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedPrivacyVersion)
        acceptedEULAVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedEULAVersion)
        acceptedDisclaimerVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedDisclaimerVersion)
        acceptedSafetyVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedSafetyVersion)
        acceptedRegulatedDomainsVersion = defaults.string(forKey: IOSLegalSafetyDefaultsKeys.acceptedRegulatedDomainsVersion)
        acceptedAt = defaults.object(forKey: IOSLegalSafetyDefaultsKeys.acceptedAt) as? Date
        adultConfirmed = defaults.object(forKey: IOSLegalSafetyDefaultsKeys.adultConfirmed) as? Bool ?? false
    }

    var hasAcceptedCurrentLegal: Bool {
        acceptedTermsVersion == IOSLegalSafetyPolicy.termsVersion &&
        acceptedPrivacyVersion == IOSLegalSafetyPolicy.privacyVersion &&
        acceptedEULAVersion == IOSLegalSafetyPolicy.eulaVersion &&
        acceptedDisclaimerVersion == IOSLegalSafetyPolicy.disclaimerVersion &&
        acceptedSafetyVersion == IOSLegalSafetyPolicy.safetyVersion &&
        acceptedRegulatedDomainsVersion == IOSLegalSafetyPolicy.regulatedDomainsVersion &&
        adultConfirmed
    }

    func acceptCurrentLegal(adultConfirmed: Bool = true) {
        let now = Date()
        self.adultConfirmed = adultConfirmed
        acceptedTermsVersion = IOSLegalSafetyPolicy.termsVersion
        acceptedPrivacyVersion = IOSLegalSafetyPolicy.privacyVersion
        acceptedEULAVersion = IOSLegalSafetyPolicy.eulaVersion
        acceptedDisclaimerVersion = IOSLegalSafetyPolicy.disclaimerVersion
        acceptedSafetyVersion = IOSLegalSafetyPolicy.safetyVersion
        acceptedRegulatedDomainsVersion = IOSLegalSafetyPolicy.regulatedDomainsVersion
        acceptedAt = now
        defaults.set(IOSLegalSafetyPolicy.termsVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedTermsVersion)
        defaults.set(IOSLegalSafetyPolicy.privacyVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedPrivacyVersion)
        defaults.set(IOSLegalSafetyPolicy.eulaVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedEULAVersion)
        defaults.set(IOSLegalSafetyPolicy.disclaimerVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedDisclaimerVersion)
        defaults.set(IOSLegalSafetyPolicy.safetyVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedSafetyVersion)
        defaults.set(IOSLegalSafetyPolicy.regulatedDomainsVersion, forKey: IOSLegalSafetyDefaultsKeys.acceptedRegulatedDomainsVersion)
        defaults.set(now, forKey: IOSLegalSafetyDefaultsKeys.acceptedAt)
        defaults.set(adultConfirmed, forKey: IOSLegalSafetyDefaultsKeys.adultConfirmed)
    }
}
