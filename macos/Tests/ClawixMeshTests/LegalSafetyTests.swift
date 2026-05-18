import XCTest
@testable import Clawix

@MainActor
final class LegalSafetyTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        let suite = "LegalSafetyTests-\(UUID().uuidString)"
        suiteName = suite
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        defaults = nil
    }

    func testDefaultStateRequiresCurrentLegalAcceptanceAndSensitiveExportReview() {
        let store = LegalSafetyStore(defaults: defaults)

        XCTAssertFalse(store.hasAcceptedCurrentLegal)
        XCTAssertFalse(store.adultConfirmed)
        XCTAssertFalse(store.remoteSyncOptIn)
        XCTAssertFalse(store.providerDisclosureOptIn)
        XCTAssertFalse(store.supportDiagnosticsOptIn)
        XCTAssertTrue(store.sensitiveExportConfirmationRequired)
        XCTAssertEqual(store.localAuditRetentionDays, 90)
    }

    func testAcceptCurrentLegalPersistsVersionedClickwrapState() {
        let store = LegalSafetyStore(defaults: defaults)

        store.acceptCurrentLegal()

        XCTAssertTrue(store.hasAcceptedCurrentLegal)
        XCTAssertEqual(defaults.string(forKey: LegalSafetyDefaultsKeys.acceptedTermsVersion), LegalSafetyPolicy.termsVersion)
        XCTAssertEqual(defaults.string(forKey: LegalSafetyDefaultsKeys.acceptedPrivacyVersion), LegalSafetyPolicy.privacyVersion)
        XCTAssertEqual(defaults.string(forKey: LegalSafetyDefaultsKeys.acceptedEULAVersion), LegalSafetyPolicy.eulaVersion)
        XCTAssertEqual(defaults.bool(forKey: LegalSafetyDefaultsKeys.adultConfirmed), true)
        XCTAssertNotNil(defaults.object(forKey: LegalSafetyDefaultsKeys.acceptedAt) as? Date)
    }

    func testVersionMismatchForcesReacceptance() {
        defaults.set("old", forKey: LegalSafetyDefaultsKeys.acceptedTermsVersion)
        defaults.set(LegalSafetyPolicy.privacyVersion, forKey: LegalSafetyDefaultsKeys.acceptedPrivacyVersion)
        defaults.set(LegalSafetyPolicy.eulaVersion, forKey: LegalSafetyDefaultsKeys.acceptedEULAVersion)
        defaults.set(true, forKey: LegalSafetyDefaultsKeys.adultConfirmed)

        let store = LegalSafetyStore(defaults: defaults)

        XCTAssertFalse(store.hasAcceptedCurrentLegal)
    }

    func testSensitiveActionReviewCarriesMandatoryLabelsAndDisclaimerVersion() {
        let store = LegalSafetyStore(defaults: defaults)

        let review = store.review(for: .providerUse)

        XCTAssertTrue(review.requiresConfirmation)
        XCTAssertEqual(review.disclaimerVersion, LegalSafetyPolicy.disclaimerVersion)
        XCTAssertTrue(review.labels.contains("draft_not_final"))
        XCTAssertTrue(review.labels.contains("not_professional_advice"))
        XCTAssertTrue(review.labels.contains("human_review_required"))
        XCTAssertTrue(review.labels.contains("sources_and_gaps_required"))
    }

    func testOptInDoesNotBypassManualSupportOrExternalActionReview() {
        let store = LegalSafetyStore(defaults: defaults)
        store.remoteSyncOptIn = true
        store.providerDisclosureOptIn = true
        store.supportDiagnosticsOptIn = true
        store.sensitiveExportConfirmationRequired = false

        XCTAssertFalse(store.review(for: .remoteSync).requiresConfirmation)
        XCTAssertFalse(store.review(for: .providerUse).requiresConfirmation)
        XCTAssertTrue(store.review(for: .supportDiagnostics).requiresConfirmation)
        XCTAssertTrue(store.review(for: .externalAction).requiresConfirmation)
    }

    func testLocalAuditRetentionDaysAreConfigurableAndPersistent() {
        let store = LegalSafetyStore(defaults: defaults)

        store.localAuditRetentionDays = 365

        XCTAssertEqual(defaults.integer(forKey: LegalSafetyDefaultsKeys.localAuditRetentionDays), 365)
        let reloaded = LegalSafetyStore(defaults: defaults)
        XCTAssertEqual(reloaded.localAuditRetentionDays, 365)
    }

    func testCrisisPromptReturnsRefusalAndEmergencyResources() {
        let refusal = LegalSafetyPolicy.crisisRefusal(for: "I want to kill myself")

        XCTAssertNotNil(refusal)
        XCTAssertTrue(refusal?.contains("I can't help handle a crisis") == true)
        XCTAssertTrue(refusal?.contains("988") == true)
        XCTAssertTrue(refusal?.contains("112") == true)
        XCTAssertTrue(refusal?.contains("Clawix is not an emergency service") == true)
    }

    func testNonCrisisPromptDoesNotTriggerCrisisRefusal() {
        XCTAssertNil(LegalSafetyPolicy.crisisRefusal(for: "Summarize these local meeting notes."))
    }
}
