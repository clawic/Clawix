import CryptoKit
import Foundation
import XCTest
@testable import Clawix

@MainActor
final class AppsStoreCancellationTests: XCTestCase {
    func testSecondAppsReloadCancelsFirstStaleSnapshot() async {
        let staleStarted = expectation(description: "Stale apps reload started")
        let staleCancelled = expectation(description: "Stale apps reload cancelled")
        let staleReturned = expectation(description: "Stale apps reload should not return")
        staleReturned.isInverted = true
        let freshReturned = expectation(description: "Fresh apps reload returned")
        var calls = 0
        let store = makeStore { _, _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    staleReturned.fulfill()
                    return Self.snapshot(slug: "stale")
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
            }
            freshReturned.fulfill()
            return Self.snapshot(slug: "fresh")
        }

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)
        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleCancelled, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.apps.map(\.slug), ["fresh"])
        XCTAssertFalse(store.isLoading)
    }

    func testCancelSurfaceWorkCancelsLateAppsReload() async {
        let loadStarted = expectation(description: "Apps reload started")
        let loadCancelled = expectation(description: "Apps reload cancelled after teardown")
        let loadReturned = expectation(description: "Apps reload should not return after teardown")
        loadReturned.isInverted = true
        let store = makeStore { _, _ in
            loadStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
                loadReturned.fulfill()
                return Self.snapshot(slug: "closed")
            } catch is CancellationError {
                loadCancelled.fulfill()
                throw CancellationError()
            }
        }

        let task = Task { await store.refresh() }
        await fulfillment(of: [loadStarted], timeout: 1)
        store.cancelSurfaceWork()

        await fulfillment(of: [loadCancelled, loadReturned], timeout: 1)
        await task.value
        XCTAssertTrue(store.apps.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    func testUpdateRemainsImmediatelyVisibleWhileReloadIsAsync() throws {
        var loadCalls = 0
        let store = makeStore { _, _ in
            loadCalls += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
            return Self.snapshot(slug: "disk")
        }
        let app = AppRecord(slug: "instant", name: "Instant")

        try store.update(app)

        XCTAssertEqual(store.apps.map(\.slug), ["instant"])
        XCTAssertEqual(loadCalls, 0)
        store.cancelSurfaceWork()
    }

    func testFullRefreshLoadsAppsFromDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        try writeManagedManifest(AppRecord(slug: "alpha", name: "Alpha"), root: root, slug: "alpha")
        try writeManagedManifest(AppRecord(slug: "beta", name: "Beta"), root: root, slug: "beta")

        await store.refresh()

        XCTAssertEqual(store.apps.map(\.slug).sorted(), ["alpha", "beta"])
    }

    func testIncrementalManifestChangeReloadsOnlyChangedApp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        try writeManagedManifest(AppRecord(slug: "alpha", name: "Alpha"), root: root, slug: "alpha")
        try writeManagedManifest(AppRecord(slug: "beta", name: "Beta"), root: root, slug: "beta")
        await store.refresh()

        try writeManagedManifest(AppRecord(slug: "alpha", name: "Alpha Updated"), root: root, slug: "alpha")
        await store.reconcileFilesystemChanges(changedSlugs: ["alpha"], needsIndexScan: false)

        XCTAssertEqual(store.record(forSlug: "alpha")?.name, "Alpha Updated")
        XCTAssertEqual(store.record(forSlug: "beta")?.name, "Beta")
        XCTAssertEqual(store.apps.map(\.slug).sorted(), ["alpha", "beta"])
    }

    func testIncrementalManifestDeleteRemovesOnlyThatApp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        try writeManagedManifest(AppRecord(slug: "alpha", name: "Alpha"), root: root, slug: "alpha")
        try writeManagedManifest(AppRecord(slug: "beta", name: "Beta"), root: root, slug: "beta")
        await store.refresh()

        try FileManager.default.removeItem(
            at: root.appendingPathComponent("alpha", isDirectory: true).appendingPathComponent("manifest.json")
        )
        await store.reconcileFilesystemChanges(changedSlugs: ["alpha"], needsIndexScan: false)

        XCTAssertEqual(store.apps.map(\.slug), ["beta"])
    }

    func testMalformedManifestRemovesOnlyThatApp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        try writeManagedManifest(AppRecord(slug: "alpha", name: "Alpha"), root: root, slug: "alpha")
        try writeManagedManifest(AppRecord(slug: "beta", name: "Beta"), root: root, slug: "beta")
        await store.refresh()

        try "{".data(using: .utf8)?.write(
            to: root.appendingPathComponent("alpha", isDirectory: true).appendingPathComponent("manifest.json"),
            options: .atomic
        )
        await store.reconcileFilesystemChanges(changedSlugs: ["alpha"], needsIndexScan: false)

        XCTAssertEqual(store.apps.map(\.slug), ["beta"])
    }

    func testIndexScanFindsCreatedDeletedAndRenamedFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        try writeManagedManifest(AppRecord(slug: "alpha", name: "Alpha"), root: root, slug: "alpha")
        await store.refresh()

        try writeManagedManifest(AppRecord(slug: "beta", name: "Beta"), root: root, slug: "beta")
        await store.reconcileFilesystemChanges(changedSlugs: [], needsIndexScan: true)
        XCTAssertEqual(store.apps.map(\.slug).sorted(), ["alpha", "beta"])

        try FileManager.default.removeItem(at: root.appendingPathComponent("alpha", isDirectory: true))
        let betaURL = root.appendingPathComponent("beta", isDirectory: true)
        let gammaURL = root.appendingPathComponent("gamma", isDirectory: true)
        try FileManager.default.moveItem(at: betaURL, to: gammaURL)
        try writeManagedManifest(AppRecord(slug: "gamma", name: "Gamma"), root: root, slug: "gamma")

        await store.reconcileFilesystemChanges(changedSlugs: [], needsIndexScan: true)

        XCTAssertEqual(store.apps.map(\.slug), ["gamma"])
        XCTAssertEqual(store.record(forSlug: "gamma")?.name, "Gamma")
    }

    func testStartPollingFalseDoesNotTriggerInjectedReloadAfterLocalCreate() throws {
        var loadCalls = 0
        let store = makeStore { _, _ in
            loadCalls += 1
            return Self.snapshot(slug: "disk")
        }

        _ = try store.create(name: "Local", slug: "local")

        XCTAssertEqual(store.apps.map(\.slug), ["local"])
        XCTAssertEqual(loadCalls, 0)
    }

    func testCreatePersistsCodeManifestVariantMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)

        let app = try store.create(
            name: "Database Focus",
            slug: "database-focus",
            declaredCapabilities: ["database.query", "search.query"],
            originClass: .localUserAuthored,
            surfaceKind: .swiftDeclarative,
            routeTarget: "database",
            variant: AppVariantMetadata(originalRoute: "database", defaultScope: "workspace"),
            protectedRoutePolicy: .variantOnly
        )

        XCTAssertEqual(app.routeTarget, "database")
        XCTAssertEqual(app.variant?.originalRoute, "database")
        XCTAssertEqual(app.effectiveSurfaceKind, .swiftDeclarative)
        XCTAssertEqual(app.effectiveDeclaredCapabilities, ["database.query", "search.query"])
        XCTAssertEqual(app.effectiveProtectedRoutePolicy, .variantOnly)

        let manifestURL = store.directory(forSlug: "database-focus").appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppRecord.self, from: data)

        XCTAssertEqual(decoded.id, app.id)
        XCTAssertEqual(decoded.slug, "database-focus")
        XCTAssertEqual(decoded.routeTarget, "database")
        XCTAssertEqual(decoded.variant?.originalRoute, "database")
        XCTAssertEqual(decoded.variant?.defaultScope, "workspace")
        XCTAssertEqual(decoded.effectiveSurfaceKind, .swiftDeclarative)
        XCTAssertEqual(decoded.effectiveDeclaredCapabilities, ["database.query", "search.query"])
        XCTAssertEqual(decoded.effectiveProtectedRoutePolicy, .variantOnly)
    }

    func testImportAppCopiesCodeManifestAndRequiresFreshReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        _ = try store.create(name: "Existing Panel", slug: "focus-panel")

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let sourceManifest = AppRecord(
            slug: "focus-panel",
            name: "Focus Panel",
            declaredCapabilities: ["search.query"],
            originClass: .localUserAuthored,
            surfaceKind: .web,
            routeTarget: "search",
            variant: AppVariantMetadata(originalRoute: "search", defaultScope: "user"),
            protectedRoutePolicy: .variantOnly,
            activationReview: AppActivationReview(approvedBy: "Source", riskMapSource: "stale")
        )
        try writeManifest(sourceManifest, to: sourceRoot)
        try "<main>Focus</main>".data(using: .utf8)?.write(
            to: sourceRoot.appendingPathComponent("index.html"),
            options: .atomic
        )

        let imported = try store.importApp(from: sourceRoot, originClass: .imported)

        XCTAssertEqual(imported.slug, "focus-panel-2")
        XCTAssertEqual(imported.effectiveOriginClass, .imported)
        XCTAssertNil(imported.activationReview)
        XCTAssertEqual(imported.packageProvenance?.sourcePath, sourceRoot.standardizedFileURL.path)
        XCTAssertEqual(imported.packageProvenance?.sourceSlug, "focus-panel")
        XCTAssertEqual(imported.packageProvenance?.sourceOriginClass, .localUserAuthored)
        XCTAssertEqual(imported.packageProvenance?.packageKind, "folder")
        XCTAssertEqual(imported.packageProvenance?.signatureStatus, .notVerified)
        XCTAssertEqual(imported.packageProvenance?.packageDigestSHA256?.count, 64)
        XCTAssertTrue(imported.packageProvenance?.packageDigestSHA256?.allSatisfy(\.isHexDigit) == true)
        XCTAssertEqual(imported.packageProvenance?.reviewReason, "Imported packages require local review before activation.")
        XCTAssertEqual(imported.routeTarget, "search")
        XCTAssertEqual(imported.variant?.originalRoute, "search")
        XCTAssertEqual(store.readFile(slug: imported.slug, relativePath: "index.html")?.mimeType, "text/html; charset=utf-8")
        XCTAssertEqual(store.apps.map(\.slug).sorted(), ["focus-panel", "focus-panel-2"])
        if case .reviewRequired(let riskMap) = AppCapabilityCatalog.activationGate(for: imported) {
            XCTAssertEqual(riskMap.ordinaryAccess, ["search.query"])
        } else {
            XCTFail("Imported app should require a fresh activation review")
        }
        let audit = try AppTrustAudit.read(from: store.trustAuditURL(for: imported))
        XCTAssertEqual(audit.count, 1)
        XCTAssertEqual(audit.first?.eventType, .packageImported)
        XCTAssertEqual(audit.first?.originClass, .imported)
        XCTAssertEqual(audit.first?.sourcePath, sourceRoot.standardizedFileURL.path)
        XCTAssertEqual(audit.first?.sourceSlug, "focus-panel")
        XCTAssertEqual(audit.first?.sourceOriginClass, .localUserAuthored)
        XCTAssertEqual(audit.first?.signatureStatus, .notVerified)
        XCTAssertEqual(audit.first?.packageDigestSHA256, imported.packageProvenance?.packageDigestSHA256)
    }

    func testImportAppVerifiesSignedPackageDigestWithHostTrustPolicy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let signingKey = Curve25519.Signing.PrivateKey()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeTrustPolicy(
            keyId: "local-test-key",
            publicKey: signingKey.publicKey,
            trustSource: "host-marketplace-test",
            to: AppPackageTrustPolicy.defaultURL(forAppsRoot: root)
        )
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try writeManifest(AppRecord(slug: "signed-panel", name: "Signed Panel"), to: sourceRoot)
        try "<main>Signed</main>".data(using: .utf8)?.write(
            to: sourceRoot.appendingPathComponent("index.html"),
            options: .atomic
        )
        let digest = try AppPackageImportValidator.contentDigestSHA256(
            sourceURL: sourceRoot,
            manifestName: "manifest.json"
        )
        try writeSignature(
            digest: digest,
            signingKey: signingKey,
            keyId: "local-test-key",
            to: sourceRoot
        )

        let imported = try store.importApp(
            from: sourceRoot,
            originClass: .marketplace
        )

        XCTAssertEqual(imported.effectiveOriginClass, .marketplace)
        XCTAssertNil(imported.activationReview)
        XCTAssertEqual(imported.packageProvenance?.signatureStatus, .verified)
        XCTAssertEqual(imported.packageProvenance?.signatureKeyId, "local-test-key")
        XCTAssertEqual(imported.packageProvenance?.signatureTrustSource, "host-marketplace-test")
        XCTAssertEqual(imported.packageProvenance?.packageDigestSHA256, digest)
        if case .reviewRequired = AppCapabilityCatalog.activationGate(for: imported) {
            // Signed packages still require the origin/capability/risk ficha.
        } else {
            XCTFail("Signed marketplace package should still require activation review")
        }
        let audit = try AppTrustAudit.read(from: store.trustAuditURL(for: imported))
        XCTAssertEqual(audit.first?.signatureStatus, .verified)
        XCTAssertEqual(audit.first?.signatureKeyId, "local-test-key")
        XCTAssertEqual(audit.first?.signatureTrustSource, "host-marketplace-test")
        XCTAssertEqual(audit.first?.packageDigestSHA256, digest)
    }

    func testImportAppMarksPackageSignatureFailedWhenDigestChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try writeManifest(AppRecord(slug: "tampered-panel", name: "Tampered Panel"), to: sourceRoot)
        let indexURL = sourceRoot.appendingPathComponent("index.html")
        try "<main>Original</main>".data(using: .utf8)?.write(to: indexURL, options: .atomic)
        let signingKey = Curve25519.Signing.PrivateKey()
        let originalDigest = try AppPackageImportValidator.contentDigestSHA256(
            sourceURL: sourceRoot,
            manifestName: "manifest.json"
        )
        try writeSignature(
            digest: originalDigest,
            signingKey: signingKey,
            keyId: "local-test-key",
            to: sourceRoot
        )
        try "<main>Tampered</main>".data(using: .utf8)?.write(to: indexURL, options: .atomic)

        let imported = try store.importApp(
            from: sourceRoot,
            originClass: .imported,
            trustedSignaturePublicKeys: ["local-test-key": signingKey.publicKey]
        )

        XCTAssertEqual(imported.packageProvenance?.signatureStatus, .failed)
        XCTAssertNotEqual(imported.packageProvenance?.packageDigestSHA256, originalDigest)
        let audit = try AppTrustAudit.read(from: store.trustAuditURL(for: imported))
        XCTAssertEqual(audit.first?.signatureStatus, .failed)
    }

    func testImportAppRejectsPackageWithoutRenderEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try writeManifest(AppRecord(slug: "missing-entry", name: "Missing Entry"), to: sourceRoot)

        XCTAssertThrowsError(try store.importApp(from: sourceRoot, originClass: .imported)) { error in
            XCTAssertEqual(error as? AppsStoreImportError, .missingRenderEntry("index.html"))
        }
    }

    func testImportAppRejectsHostOwnedAuditFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try writeManifest(AppRecord(slug: "forged-audit", name: "Forged Audit"), to: sourceRoot)
        try "<main>Forged</main>".data(using: .utf8)?.write(
            to: sourceRoot.appendingPathComponent("index.html"),
            options: .atomic
        )
        try "{}".data(using: .utf8)?.write(
            to: sourceRoot.appendingPathComponent(AppTrustAudit.filename),
            options: .atomic
        )

        XCTAssertThrowsError(try store.importApp(from: sourceRoot, originClass: .imported)) { error in
            guard case .hostOwnedFileNotAllowed(let path) = error as? AppsStoreImportError else {
                return XCTFail("Expected hostOwnedFileNotAllowed, got \(error)")
            }
            XCTAssertTrue(path.hasSuffix(AppTrustAudit.filename))
        }
    }

    func testImportAppRejectsSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try writeManifest(AppRecord(slug: "symlinked", name: "Symlinked"), to: sourceRoot)
        try "<main>Symlinked</main>".data(using: .utf8)?.write(
            to: sourceRoot.appendingPathComponent("index.html"),
            options: .atomic
        )
        try "outside".data(using: .utf8)?.write(to: outside, options: .atomic)
        try FileManager.default.createSymbolicLink(
            at: sourceRoot.appendingPathComponent("outside-link.txt"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try store.importApp(from: sourceRoot, originClass: .imported)) { error in
            guard case .symlinkNotAllowed(let path) = error as? AppsStoreImportError else {
                return XCTFail("Expected symlinkNotAllowed, got \(error)")
            }
            XCTAssertTrue(path.hasSuffix("outside-link.txt"))
        }
    }

    func testManagedAppReadFileRejectsSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)
        let app = try store.create(name: "Safe", slug: "safe")
        try "outside".data(using: .utf8)?.write(to: outside, options: .atomic)
        try FileManager.default.createSymbolicLink(
            at: store.directory(forSlug: app.slug).appendingPathComponent("outside-link.txt"),
            withDestinationURL: outside
        )

        XCTAssertNil(store.readFile(slug: app.slug, relativePath: "outside-link.txt"))
    }

    func testApproveActivationWritesTrustAuditWithRiskMap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let store = AppsStore(rootURL: root, autoLoad: false, startPolling: false)

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let sourceManifest = AppRecord(
            slug: "control-panel",
            name: "Control Panel",
            declaredCapabilities: ["search.query", "iot.device.action.invoke"],
            originClass: .localUserAuthored
        )
        try writeManifest(sourceManifest, to: sourceRoot)
        try "<main>Control</main>".data(using: .utf8)?.write(
            to: sourceRoot.appendingPathComponent("index.html"),
            options: .atomic
        )

        let imported = try store.importApp(from: sourceRoot, originClass: .imported)
        let riskMap = AppCapabilityCatalog.riskMap(for: imported)
        let approved = try store.approveActivation(imported, riskMap: riskMap)

        XCTAssertNotNil(approved.activationReview)
        let audit = try AppTrustAudit.read(from: store.trustAuditURL(for: approved))
        XCTAssertEqual(audit.map(\.eventType), [.packageImported, .activationApproved])
        XCTAssertEqual(audit.last?.riskMapSource, AppCapabilityCatalog.source)
        XCTAssertEqual(audit.last?.ordinaryAccess, ["search.query"])
        XCTAssertEqual(audit.last?.approvalRequired, ["iot.device.action.invoke"])
        XCTAssertEqual(audit.last?.highRisk, ["iot.device.action.invoke"])
    }

    private func makeStore(
        loadOperation: @escaping AppsStore.LoadOperation
    ) -> AppsStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AppsStore(
            rootURL: root,
            autoLoad: false,
            startPolling: false,
            loadOperation: loadOperation
        )
    }

    private static func snapshot(slug: String) -> AppsStore.AppsSnapshot {
        AppsStore.AppsSnapshot(
            apps: [AppRecord(slug: slug, name: slug)],
            mtimes: [slug: Date()]
        )
    }

    private func writeManifest(_ record: AppRecord, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func writeManagedManifest(_ record: AppRecord, root: URL, slug: String) throws {
        let directory = root.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeManifest(record, to: directory)
    }

    private func writeSignature(
        digest: String,
        signingKey: Curve25519.Signing.PrivateKey,
        keyId: String,
        to directory: URL
    ) throws {
        let signature = try signingKey.signature(
            for: AppPackageImportValidator.signaturePayload(packageDigestSHA256: digest)
        )
        let manifest = AppPackageSignatureManifest(
            keyId: keyId,
            digestSHA256: digest,
            signatureBase64: signature.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: directory.appendingPathComponent(AppPackageImportValidator.signatureFilename),
            options: .atomic
        )
    }

    private func writeTrustPolicy(
        keyId: String,
        publicKey: Curve25519.Signing.PublicKey,
        trustSource: String,
        to url: URL
    ) throws {
        let json = """
        {
          "schemaVersion": 1,
          "trustedKeys": [
            {
              "keyId": "\(keyId)",
              "algorithm": "ed25519",
              "publicKeyBase64": "\(publicKey.rawRepresentation.base64EncodedString())",
              "trustSource": "\(trustSource)",
              "issuer": "test"
            }
          ]
        }
        """
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
