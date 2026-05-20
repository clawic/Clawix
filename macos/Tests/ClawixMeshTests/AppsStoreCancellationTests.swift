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
        let store = makeStore { _, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return Self.snapshot(slug: "disk")
        }
        let app = AppRecord(slug: "instant", name: "Instant")

        try store.update(app)

        XCTAssertEqual(store.apps.map(\.slug), ["instant"])
        store.cancelSurfaceWork()
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
}
