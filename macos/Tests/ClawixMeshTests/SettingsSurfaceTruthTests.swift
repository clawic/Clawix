import XCTest

final class SettingsSurfaceTruthTests: XCTestCase {
    func testGitSettingsDoesNotExposeUnwiredMutableDefaults() throws {
        let source = try readSource("Settings/SettingsView+GitPage.swift")

        XCTAssertFalse(source.contains("@State private var prefix"))
        XCTAssertFalse(source.contains("@State private var mergeMethod"))
        XCTAssertFalse(source.contains("@State private var forcePush"))
        XCTAssertFalse(source.contains("@State private var autoRemoveWorktrees"))
        XCTAssertFalse(source.contains("Choose how Clawix merges pull requests"))
        XCTAssertFalse(source.contains("Use --force-with-lease"))

        XCTAssertTrue(source.contains("Disabled until ClawJS exposes a Git defaults route"))
        XCTAssertTrue(source.contains("signed-host approval"))
        XCTAssertTrue(source.contains("GitStatusRow"))
        XCTAssertTrue(source.contains("selectedProject"))
    }

    func testSharedSettingsToggleCarriesAccessibleLabelAndDisabledState() throws {
        let controls = try readSource("Settings/SettingsView+Controls.swift")
        let kit = try readSource("SettingsKit.swift")

        XCTAssertTrue(controls.contains("accessibilityLabel: LocalizedStringKey"))
        XCTAssertTrue(controls.contains("@Environment(\\.isEnabled)"))
        XCTAssertTrue(controls.contains("guard isEnabled else { return }"))
        XCTAssertTrue(kit.contains("PillToggle(isOn: $isOn, accessibilityLabel: title, accessibilityHint: detail)"))
    }

    func testWorkspaceDependenciesSettingsDoNotUseEphemeralToggle() throws {
        let source = try readSource("Settings/SettingsView+ConfigurationPage.swift")

        XCTAssertFalse(source.contains("depsEnabled"))
        XCTAssertFalse(source.contains("Allow Clawix to install and expose"))
        XCTAssertTrue(source.contains("WorkspaceDependencyStatusRow"))
        XCTAssertTrue(source.contains("Settings does not enable or install them directly"))
        XCTAssertTrue(source.contains("signed launcher route"))
    }

    func testQuickAskSettingsPersistentSurfaceKeysAreRegistered() throws {
        let settings = try readSource("QuickAsk/QuickAskSettingsPage.swift")
        let controller = try readSource("QuickAsk/QuickAskController.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(settings.contains("@AppStorage(ClawixPersistentSurfaceKeys.quickAskAdvancedExpanded)"))
        XCTAssertTrue(controller.contains("ClawixPersistentSurfaceKeys.quickAskDefaultModel"))
        XCTAssertTrue(registry.contains("clawix.prefs.quickAsk.defaultModel"))
        XCTAssertTrue(registry.contains("clawix.prefs.quickAsk.advancedExpanded"))
        XCTAssertTrue(registry.contains("quickAskDefaultModel"))
        XCTAssertTrue(registry.contains("quickAskAdvancedExpanded"))
    }

    func testGeneralSettingsDoNotExposeDeveloperOnlyFakeToggles() throws {
        let source = try readSource("Settings/SettingsView+GeneralPage.swift")

        XCTAssertFalse(source.contains("@State private var permDefault"))
        XCTAssertFalse(source.contains("@State private var permAuto"))
        XCTAssertFalse(source.contains("@State private var permFull"))
        XCTAssertFalse(source.contains("@State private var showInMenuBar"))
        XCTAssertFalse(source.contains("@State private var preventSleep"))
        XCTAssertFalse(source.contains("@State private var completionNotify"))
        XCTAssertFalse(source.contains("Full access\","))
        XCTAssertFalse(source.contains("Use --force-with-lease"))

        XCTAssertTrue(source.contains("GeneralCapabilityStatusRow"))
        XCTAssertTrue(source.contains("Hidden until approvals, grants, and audit routes expose a single persisted policy source."))
        XCTAssertTrue(source.contains("@AppStorage(SyncSettings.archiveKey"))
        XCTAssertTrue(source.contains("@AppStorage(SyncSettings.renamesKey"))
        XCTAssertTrue(source.contains("@AppStorage(SyncSettings.autoReloadKey"))
    }

    func testMCPRowsExposeDisabledAndAccessibleToggleState() throws {
        let source = try readSource("Settings/SettingsView+MCPPage.swift")

        XCTAssertTrue(source.contains("isBusy: store.isLoading || store.isSaving"))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Enable MCP server\""))
        XCTAssertTrue(source.contains("accessibilityHint: \"Turns this MCP server on or off.\""))
        XCTAssertTrue(source.contains(".disabled(isBusy)"))
    }

    func testBrowserHistoryPolicyIsBlockedUntilConsumed() throws {
        let source = try readSource("Settings/SettingsView+BrowserPage.swift")

        XCTAssertFalse(source.contains("@AppStorage(ClawixPersistentSurfaceKeys.browserHistoryApproval)"))
        XCTAssertTrue(source.contains("BrowserPolicyStatusRow"))
        XCTAssertTrue(source.contains("Unavailable until a browser-history route consumes this policy and reports approval state."))
        XCTAssertTrue(source.contains("BrowserPermissionPolicy.approvalStorageKey"))
    }

    func testLocalModelsAdvancedDisclosureIsPersistedAndRegistered() throws {
        let page = try readSource("LocalModels/LocalModelsPage.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertFalse(page.contains("@State var advancedExpanded"))
        XCTAssertTrue(page.contains("@AppStorage(ClawixPersistentSurfaceKeys.localModelsAdvancedExpanded)"))
        XCTAssertTrue(registry.contains("clawix.prefs.localModels.advancedExpanded"))
        XCTAssertTrue(registry.contains("localModelsAdvancedExpanded"))
    }

    func testSecretsImportRequiresExplicitConfirmationAfterPreview() throws {
        let source = try readSource("Secrets/SecretsSettingsPage.swift")

        XCTAssertTrue(source.contains("previewImport(contents: text, format: format)"))
        XCTAssertTrue(source.contains("requestImportConfirmation(preview: preview, contents: text, format: format)"))
        XCTAssertTrue(source.contains("appState.pendingConfirmation = ConfirmationRequest"))
        XCTAssertTrue(source.contains("Secret values are not shown in this confirmation."))
        XCTAssertTrue(source.contains("performConfirmedImport(contents: contents, format: format)"))
    }

    func testGeneralSyncSettingsPersistentSurfaceKeysAreRegistered() throws {
        let syncSettings = try readSource("Persistence/SyncSettings.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(syncSettings.contains("static let archiveKey = \"SyncArchiveWithCodex\""))
        XCTAssertTrue(syncSettings.contains("static let renamesKey = \"SyncRenamesWithCodex\""))
        XCTAssertTrue(syncSettings.contains("static let autoReloadKey = \"AutoReloadOnFocus\""))
        XCTAssertTrue(registry.contains("clawix.prefs.sync.archiveWithCodex"))
        XCTAssertTrue(registry.contains("clawix.prefs.sync.renamesWithCodex"))
        XCTAssertTrue(registry.contains("clawix.prefs.sync.autoReloadOnFocus"))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Clawix")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
