import XCTest
@testable import Clawix

final class AppVariantDefaultsTests: AppCustomSurfaceCapabilityTestCase {
    private static let reviewedProtectedRoutePolicyRawValues: Set<String> = [
        "blocked",
        "none",
        "variantOnly"
    ]

    @MainActor
    func testVariantDefaultsResolveWorkspaceBeforeUserDefaultAndPreserveOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let defaults = try makeDefaults()
        let store = AppVariantDefaultsStore(userDefaults: defaults)
        let workspaceId = UUID()

        let userVariant = AppRecord(
            slug: "tasks-user-variant",
            name: "Tasks User Variant",
            routeTarget: "database/tasks",
            variant: AppVariantMetadata(originalRoute: "database/tasks", defaultScope: "user"),
            protectedRoutePolicy: .variantOnly
        )
        let workspaceVariant = AppRecord(
            slug: "tasks-workspace-variant",
            name: "Tasks Workspace Variant",
            routeTarget: "database/tasks",
            variant: AppVariantMetadata(originalRoute: "database/tasks", defaultScope: "workspace"),
            protectedRoutePolicy: .variantOnly
        )
        try appsStore.update(userVariant)
        try appsStore.update(workspaceVariant)

        try store.setDefault(app: userVariant, scope: .user)
        try store.setDefault(app: workspaceVariant, scope: .workspace, workspaceId: workspaceId)

        let scoped = store.resolution(
            for: "database/tasks",
            workspaceId: workspaceId,
            appsStore: appsStore
        )
        XCTAssertEqual(scoped?.appId, workspaceVariant.id)
        XCTAssertEqual(scoped?.scope, .workspace)
        XCTAssertEqual(scoped?.originalRouteAvailable, true)

        let fallback = store.resolution(for: "database/tasks", appsStore: appsStore)
        XCTAssertEqual(fallback?.appId, userVariant.id)
        XCTAssertEqual(fallback?.scope, .user)

        let original = store.resolution(
            for: "database/tasks",
            workspaceId: workspaceId,
            appsStore: appsStore,
            preferOriginal: true
        )
        XCTAssertNil(original)
    }

    @MainActor
    func testVariantDefaultsExposeDefaultAppIdsForSettingsUI() throws {
        let defaults = try makeDefaults()
        let store = AppVariantDefaultsStore(userDefaults: defaults)
        let workspaceId = UUID()
        let variant = AppRecord(
            slug: "database-workbench-focus",
            name: "Database Workbench Focus",
            routeTarget: "database-workbench",
            variant: AppVariantMetadata(originalRoute: "database-workbench", defaultScope: "workspace"),
            protectedRoutePolicy: .variantOnly
        )

        XCTAssertNil(store.defaultAppId(routeTarget: "database-workbench", scope: .workspace, workspaceId: workspaceId))
        XCTAssertFalse(store.isDefault(app: variant, scope: .workspace, workspaceId: workspaceId))

        try store.setDefault(app: variant, scope: .workspace, workspaceId: workspaceId)

        XCTAssertEqual(
            store.defaultAppId(routeTarget: " database-workbench ", scope: .workspace, workspaceId: workspaceId),
            variant.id
        )
        XCTAssertTrue(store.isDefault(app: variant, scope: .workspace, workspaceId: workspaceId))

        store.clearDefault(routeTarget: "database-workbench", scope: .workspace, workspaceId: workspaceId)

        XCTAssertNil(store.defaultAppId(routeTarget: "database-workbench", scope: .workspace, workspaceId: workspaceId))
    }

    func testAppsSettingsVariantDefaultPresentationAllowsUserAndWorkspaceManagement() {
        let workspaceId = UUID()
        let variant = AppRecord(
            slug: "database-focus",
            name: "Database Focus",
            routeTarget: "database",
            variant: AppVariantMetadata(originalRoute: "database", defaultScope: "user"),
            protectedRoutePolicy: .variantOnly
        )

        let settable = AppsSettingsVariantDefaultPresentation(
            record: variant,
            workspaceId: workspaceId,
            userDefaultActive: false,
            workspaceDefaultActive: false
        )
        XCTAssertTrue(settable.isVariant)
        XCTAssertTrue(settable.canManageDefaults)
        XCTAssertTrue(settable.canSetWorkspaceDefault)
        XCTAssertEqual(settable.statusLabel, "Set")
        XCTAssertEqual(settable.symbolName, "square.grid.2x2")

        let workspaceDefault = AppsSettingsVariantDefaultPresentation(
            record: variant,
            workspaceId: workspaceId,
            userDefaultActive: true,
            workspaceDefaultActive: true
        )
        XCTAssertEqual(workspaceDefault.statusLabel, "Workspace")
        XCTAssertEqual(workspaceDefault.symbolName, "building.2")

        let noWorkspace = AppsSettingsVariantDefaultPresentation(
            record: variant,
            workspaceId: nil,
            userDefaultActive: false,
            workspaceDefaultActive: false
        )
        XCTAssertTrue(noWorkspace.canManageDefaults)
        XCTAssertFalse(noWorkspace.canSetWorkspaceDefault)
    }

    func testAppsSettingsVariantDefaultPresentationBlocksInvalidVariants() {
        let invalid = AppRecord(
            slug: "invalid-database-focus",
            name: "Invalid Database Focus",
            routeTarget: "database",
            variant: AppVariantMetadata(originalRoute: "memory", defaultScope: "user"),
            protectedRoutePolicy: .variantOnly
        )

        let presentation = AppsSettingsVariantDefaultPresentation(
            record: invalid,
            workspaceId: nil,
            userDefaultActive: true,
            workspaceDefaultActive: false
        )

        XCTAssertTrue(presentation.isVariant)
        XCTAssertFalse(presentation.canManageDefaults)
        XCTAssertFalse(presentation.canSetWorkspaceDefault)
        XCTAssertEqual(presentation.statusLabel, "Blocked")
        XCTAssertEqual(presentation.symbolName, "exclamationmark.triangle")
    }

    func testVariantOriginalRouteControlPresentsExplicitFallbackAffordance() {
        let variantActive = AppVariantOriginalRouteControlPresentation(
            appName: "Tasks Focus",
            scope: .workspace,
            isShowingOriginal: false
        )
        XCTAssertEqual(variantActive.symbolName, "arrow.uturn.backward")
        XCTAssertEqual(variantActive.primaryLabel, "Original")
        XCTAssertEqual(variantActive.scopeLabel, "workspace")
        XCTAssertEqual(variantActive.helpText, "Show original surface")

        let originalActive = AppVariantOriginalRouteControlPresentation(
            appName: "Tasks Focus",
            scope: .workspace,
            isShowingOriginal: true
        )
        XCTAssertEqual(originalActive.symbolName, "square.grid.2x2")
        XCTAssertEqual(originalActive.primaryLabel, "Tasks Focus")
        XCTAssertEqual(originalActive.scopeLabel, "workspace")
        XCTAssertEqual(originalActive.helpText, "Show custom variant")
    }

    func testVariantOriginalRouteControlFallsBackToGenericVariantName() {
        let presentation = AppVariantOriginalRouteControlPresentation(
            appName: "  ",
            scope: .user,
            isShowingOriginal: true
        )
        XCTAssertEqual(presentation.primaryLabel, "Custom view")
        XCTAssertEqual(presentation.scopeLabel, "user")
    }

    @MainActor
    func testVariantDefaultsRejectProtectedReplacementWithoutVariantPolicy() throws {
        let defaults = try makeDefaults()
        let store = AppVariantDefaultsStore(userDefaults: defaults)
        let unsafe = AppRecord(
            slug: "secrets-replacement",
            name: "Secrets Replacement",
            routeTarget: "secrets",
            protectedRoutePolicy: .none
        )

        XCTAssertThrowsError(try store.setDefault(app: unsafe, scope: .user))
    }

    func testProtectedRoutePolicySetAndDefaultStayExact() throws {
        let reviewedPolicies: [AppProtectedRoutePolicy] = [
            .blocked,
            .none,
            .variantOnly
        ]

        XCTAssertEqual(Set(reviewedPolicies.map(Self.protectedRoutePolicyRawValue)), Self.reviewedProtectedRoutePolicyRawValues)

        let legacy = AppRecord(slug: "legacy-policy-panel", name: "Legacy Policy Panel")
        XCTAssertEqual(legacy.effectiveProtectedRoutePolicy, .blocked)

        for policy in reviewedPolicies {
            let record = AppRecord(
                slug: "policy-\(Self.protectedRoutePolicyRawValue(policy))",
                name: "Policy \(Self.protectedRoutePolicyRawValue(policy))",
                protectedRoutePolicy: policy
            )
            let data = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(AppRecord.self, from: data)

            XCTAssertEqual(decoded.effectiveProtectedRoutePolicy, policy)
        }
    }

    func testProtectedRouteTargetSetIsExactAndVariantOnly() {
        let expectedTargets: Set<String> = [
            "approvals",
            "chat",
            "chat-core",
            "native-permissions",
            "permissions",
            "rescue",
            "secrets"
        ]

        XCTAssertEqual(AppCapabilityCatalog.protectedRouteTargets, expectedTargets)

        for target in expectedTargets {
            let unsafe = AppRecord(
                slug: "unsafe-\(target.replacingOccurrences(of: ":", with: "-"))",
                name: "Unsafe \(target)",
                routeTarget: target,
                protectedRoutePolicy: .none
            )
            XCTAssertFalse(AppCapabilityCatalog.protectedRouteViolations(for: unsafe).isEmpty, target)

            let blocked = AppRecord(
                slug: "blocked-\(target.replacingOccurrences(of: ":", with: "-"))",
                name: "Blocked \(target)",
                routeTarget: target,
                protectedRoutePolicy: .blocked
            )
            XCTAssertFalse(AppCapabilityCatalog.protectedRouteViolations(for: blocked).isEmpty, target)

            let validVariant = AppRecord(
                slug: "variant-\(target.replacingOccurrences(of: ":", with: "-"))",
                name: "Variant \(target)",
                routeTarget: target,
                variant: AppVariantMetadata(originalRoute: target, defaultScope: "user"),
                protectedRoutePolicy: .variantOnly
            )
            XCTAssertEqual(AppCapabilityCatalog.protectedRouteViolations(for: validVariant), [], target)

            let invalidVariant = AppRecord(
                slug: "invalid-\(target.replacingOccurrences(of: ":", with: "-"))",
                name: "Invalid \(target)",
                routeTarget: target,
                variant: AppVariantMetadata(originalRoute: "database", defaultScope: "user"),
                protectedRoutePolicy: .variantOnly
            )
            XCTAssertFalse(AppCapabilityCatalog.protectedRouteViolations(for: invalidVariant).isEmpty, target)
        }
    }

    private static func protectedRoutePolicyRawValue(_ policy: AppProtectedRoutePolicy) -> String {
        switch policy {
        case .blocked:
            return "blocked"
        case .none:
            return "none"
        case .variantOnly:
            return "variantOnly"
        }
    }
}
