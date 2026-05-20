import XCTest
@testable import Clawix

final class AppCustomSurfaceTrustPolicyTests: AppCustomSurfaceCapabilityTestCase {
    private let reviewedOriginClasses: [AppOriginClass] = [
        .localUserAuthored,
        .imported,
        .marketplace,
        .system
    ]

    func testImportedOrUnknownCapabilitiesRequireReview() {
        let record = AppRecord(
            slug: "imported-panel",
            name: "Imported Panel",
            declaredCapabilities: ["search.query", "unknown.future"],
            originClass: .imported
        )

        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        XCTAssertEqual(riskMap.unknown, ["unknown.future"])
        XCTAssertTrue(riskMap.requiresActivationReview)
    }

    func testImportedAppsRequireReviewBeforeActivation() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "db.query"],
            originClass: .imported
        )

        switch AppCapabilityCatalog.activationGate(for: record) {
        case .reviewRequired(let riskMap):
            XCTAssertTrue(riskMap.requiresActivationReview)
        default:
            XCTFail("Imported app should require review before activation")
        }

        let reviewed = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "db.query"],
            originClass: .imported,
            activationReview: AppActivationReview(approvedBy: "Test", riskMapSource: AppCapabilityCatalog.source)
        )

        XCTAssertEqual(AppCapabilityCatalog.activationGate(for: reviewed), .allowed)
    }

    func testActivationReviewPresentationIncludesPackageProvenance() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "db.query"],
            originClass: .imported,
            packageProvenance: AppPackageProvenance(
                importedAt: Date(timeIntervalSince1970: 0),
                importedBy: "Tester",
                sourcePath: "/tmp/focus-panel",
                sourceSlug: "focus-panel",
                sourceOriginClass: .localUserAuthored,
                packageKind: "folder",
                signatureStatus: .verified,
                signatureKeyId: "local-test-key",
                signatureTrustSource: "host-marketplace-test",
                packageDigestSHA256: "abc123",
                reviewReason: "Imported packages require local review before activation."
            )
        )
        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        let presentation = AppActivationReviewPresentation(record: record, riskMap: riskMap)

        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Imported from", value: "/tmp/focus-panel")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Source slug", value: "focus-panel")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Source origin", value: "localUserAuthored")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Signature", value: "Verified")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Signature key", value: "local-test-key")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Trust source", value: "host-marketplace-test")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Package SHA-256", value: "abc123")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Review reason", value: "Imported packages require local review before activation.")))
    }

    func testAppsSettingsTrustPresentationIncludesPackageProvenance() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            originClass: .imported,
            packageProvenance: AppPackageProvenance(
                importedAt: Date(timeIntervalSince1970: 0),
                importedBy: "Tester",
                sourcePath: "/tmp/focus-panel",
                sourceSlug: "focus-panel",
                sourceOriginClass: .localUserAuthored,
                packageKind: "folder",
                signatureStatus: .verified,
                signatureKeyId: "local-test-key",
                signatureTrustSource: "host-marketplace-test",
                packageDigestSHA256: "abc123"
            )
        )

        let presentation = AppsSettingsTrustPresentation(record: record)

        XCTAssertEqual(presentation.statusLabel, "Imported")
        XCTAssertEqual(presentation.symbolName, "tray.and.arrow.down")
        XCTAssertEqual(presentation.tone, .normal)
        XCTAssertTrue(presentation.helpText.contains("Origin: imported"))
        XCTAssertTrue(presentation.helpText.contains("Signature: Verified"))
        XCTAssertTrue(presentation.helpText.contains("Signature key: local-test-key"))
        XCTAssertTrue(presentation.helpText.contains("Trust source: host-marketplace-test"))
        XCTAssertTrue(presentation.helpText.contains("Package SHA-256: abc123"))
        XCTAssertTrue(presentation.helpText.contains("Source slug: focus-panel"))
        XCTAssertTrue(presentation.helpText.contains("Source path: /tmp/focus-panel"))
    }

    func testAppsSettingsTrustAuditPresentationSortsAndSummarizesEvents() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "iot.device.action.invoke"],
            originClass: .imported,
            packageProvenance: AppPackageProvenance(
                importedAt: Date(timeIntervalSince1970: 0),
                importedBy: "Tester",
                sourcePath: "/tmp/focus-panel",
                sourceSlug: "focus-panel",
                sourceOriginClass: .localUserAuthored,
                packageKind: "folder",
                signatureStatus: .verified,
                signatureKeyId: "local-test-key",
                signatureTrustSource: "host-marketplace-test",
                packageDigestSHA256: "abc123"
            )
        )
        let riskMap = AppCapabilityCatalog.riskMap(for: record)
        let imported = AppTrustAuditEvent(
            id: "import",
            app: record,
            eventType: .packageImported,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 1),
            reason: "Imported package requires review."
        )
        let approved = AppTrustAuditEvent(
            id: "approve",
            app: record,
            eventType: .activationApproved,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 2),
            riskMap: riskMap,
            reason: "Activation approved."
        )

        let model = AppsSettingsTrustAuditSheetModel(record: record, events: [imported, approved])

        XCTAssertEqual(model.title, "Trust audit")
        XCTAssertEqual(model.subtitle, "Imported Known Panel · imported-known-panel")
        XCTAssertEqual(model.emptyMessage, "No trust events recorded for this app.")
        XCTAssertEqual(model.rows.map(\.id), ["approve", "import"])
        XCTAssertEqual(model.rows.first?.title, "Activation approved")
        XCTAssertTrue(model.rows.first?.detail.contains("Risk map: \(AppCapabilityCatalog.source)") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("Ordinary: search.query") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("Approval: iot.device.action.invoke") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("High risk: iot.device.action.invoke") == true)
        XCTAssertEqual(model.rows.last?.title, "Package imported")
        XCTAssertTrue(model.rows.last?.detail.contains("Signature: Verified") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Signature key: local-test-key") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Trust source: host-marketplace-test") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Package SHA-256: abc123") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Source path: /tmp/focus-panel") == true)
    }

    func testAppsSettingsGlobalTrustAuditPresentationSortsAcrossApps() {
        let first = AppRecord(
            slug: "first-panel",
            name: "First Panel",
            declaredCapabilities: ["search.query"],
            originClass: .imported
        )
        let second = AppRecord(
            slug: "second-panel",
            name: "Second Panel",
            declaredCapabilities: ["db.query"],
            originClass: .marketplace
        )
        let firstEvent = AppTrustAuditEvent(
            id: "first-import",
            app: first,
            eventType: .packageImported,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 1),
            reason: "First imported."
        )
        let secondEvent = AppTrustAuditEvent(
            id: "second-approve",
            app: second,
            eventType: .activationApproved,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 3),
            riskMap: AppCapabilityCatalog.riskMap(for: second),
            reason: "Second approved."
        )

        let model = AppsSettingsTrustAuditSheetModel(entries: [
            AppsSettingsTrustAuditEntry(record: first, events: [firstEvent]),
            AppsSettingsTrustAuditEntry(record: second, events: [secondEvent])
        ])

        XCTAssertEqual(model.title, "Trust audit")
        XCTAssertEqual(model.subtitle, "All apps")
        XCTAssertEqual(model.emptyMessage, "No trust events recorded for installed apps.")
        XCTAssertEqual(model.rows.map(\.id), ["second-approve", "first-import"])
        XCTAssertEqual(model.rows.first?.title, "Second Panel · Activation approved")
        XCTAssertTrue(model.rows.first?.detail.contains("Risk map: \(AppCapabilityCatalog.source)") == true)
        XCTAssertEqual(model.rows.last?.title, "First Panel · Package imported")
    }

    func testUnknownCapabilitiesBlockActivation() {
        let record = AppRecord(
            slug: "unknown-panel",
            name: "Unknown Panel",
            declaredCapabilities: ["unknown.future"],
            originClass: .imported
        )

        XCTAssertEqual(AppCapabilityCatalog.activationGate(for: record), .blockedUnknownCapabilities(["unknown.future"]))
    }

    func testOriginClassesAndActivationReviewPolicyStayExact() {
        XCTAssertEqual(reviewedOriginClasses.map(\.rawValue), [
            "localUserAuthored",
            "imported",
            "marketplace",
            "system"
        ])

        for originClass in reviewedOriginClasses {
            let record = AppRecord(
                slug: "origin-\(originClass.rawValue)",
                name: "Origin \(originClass.rawValue)",
                declaredCapabilities: ["search.query"],
                originClass: originClass
            )
            let riskMap = AppCapabilityCatalog.riskMap(for: record)

            switch originClass {
            case .imported, .marketplace:
                XCTAssertTrue(riskMap.requiresActivationReview, originClass.rawValue)
                switch AppCapabilityCatalog.activationGate(for: record) {
                case .reviewRequired:
                    break
                default:
                    XCTFail("\(originClass.rawValue) should require activation review")
                }
            case .localUserAuthored, .system:
                XCTAssertFalse(riskMap.requiresActivationReview, originClass.rawValue)
                XCTAssertEqual(AppCapabilityCatalog.activationGate(for: record), .allowed)
            }

            let unknownCapabilityRecord = AppRecord(
                slug: "origin-unknown-\(originClass.rawValue)",
                name: "Origin Unknown \(originClass.rawValue)",
                declaredCapabilities: ["unknown.future"],
                originClass: originClass
            )

            XCTAssertEqual(
                AppCapabilityCatalog.activationGate(for: unknownCapabilityRecord),
                .blockedUnknownCapabilities(["unknown.future"]),
                originClass.rawValue
            )
        }
    }

    func testRuntimeJobCapabilitiesUseReadAndApprovalTiers() {
        let record = AppRecord(
            slug: "runtime-jobs-panel",
            name: "Runtime Jobs Panel",
            declaredCapabilities: ["jobs.stream", "jobs.start", "jobs.cancel"],
            originClass: .localUserAuthored,
            activationReview: AppActivationReview(approvedBy: "Test", riskMapSource: AppCapabilityCatalog.source)
        )

        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        XCTAssertEqual(riskMap.blocked, [])
        XCTAssertEqual(riskMap.ordinaryAccess, ["jobs.stream"])
        XCTAssertEqual(riskMap.approvalRequired, ["jobs.start", "jobs.cancel"])
        XCTAssertEqual(AppCapabilityCatalog.activationGate(for: record), .allowed)
    }

    func testProtectedRoutesCannotBeReplacedWithoutVariantFallback() {
        let blocked = AppRecord(
            slug: "secrets-panel",
            name: "Secrets Panel",
            routeTarget: "secrets",
            protectedRoutePolicy: .blocked
        )
        XCTAssertFalse(AppCapabilityCatalog.protectedRouteViolations(for: blocked).isEmpty)

        let variant = AppRecord(
            slug: "secrets-variant",
            name: "Secrets Variant",
            routeTarget: "secrets",
            variant: AppVariantMetadata(originalRoute: "secrets", defaultScope: "workspace"),
            protectedRoutePolicy: .variantOnly
        )
        XCTAssertEqual(AppCapabilityCatalog.protectedRouteViolations(for: variant), [])
    }
}
