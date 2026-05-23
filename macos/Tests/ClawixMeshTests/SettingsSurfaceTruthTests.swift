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

    func testConfigurationScopeIsPersistedAndProjectConfigIsDisabledWithoutProject() throws {
        let source = try readSource("Settings/SettingsView+ConfigurationPage.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertFalse(source.contains("@State private var configScope"))
        XCTAssertTrue(source.contains("@AppStorage(ClawixPersistentSurfaceKeys.settingsConfigurationScope)"))
        XCTAssertTrue(source.contains("projectConfigUnavailable"))
        XCTAssertTrue(source.contains(".disabled(openingConfig || projectConfigUnavailable)"))
        XCTAssertTrue(registry.contains("clawix.prefs.settings.configurationScope"))
        XCTAssertTrue(registry.contains("settingsConfigurationScope"))
    }

    func testClawJSAdvancedDisclosureIsPersistedAndRegistered() throws {
        let source = try readSource("Settings/ClawJSSettingsPage.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertFalse(source.contains("@State private var advancedExpanded = false"))
        XCTAssertTrue(source.contains("@AppStorage(ClawixPersistentSurfaceKeys.clawJSAdvancedExpanded)"))
        XCTAssertTrue(registry.contains("clawix.prefs.clawjs.advancedExpanded"))
        XCTAssertTrue(registry.contains("clawJSAdvancedExpanded"))
    }

    func testClawJSSettingsActionsExposeDisabledAndLoadingState() throws {
        let source = try readSource("Settings/ClawJSSettingsPage.swift")

        XCTAssertTrue(source.contains("@State private var serviceActionsInFlight: Set<ClawJSService>"))
        XCTAssertTrue(source.contains("serviceActionsInFlight.contains(service)"))
        XCTAssertTrue(source.contains("ProgressView()"))
        XCTAssertTrue(source.contains(".disabled(inFlight || isServiceActionDisabled(service, state: state))"))
        XCTAssertTrue(source.contains("guard !serviceActionsInFlight.contains(service),"))
        XCTAssertTrue(source.contains("serviceActionsInFlight.insert(service)"))
        XCTAssertTrue(source.contains("defer { serviceActionsInFlight.remove(service) }"))
        XCTAssertTrue(source.contains("private func logFileExists(for service: ClawJSService) -> Bool"))
        XCTAssertTrue(source.contains(".disabled(!logFileExists(for: service))"))
        XCTAssertTrue(source.contains("let statusJSONValue = statusJSON(for: service)"))
        XCTAssertTrue(source.contains(".disabled(statusJSONValue == nil)"))
    }

    func testProviderToggleWritesFrameworkTruthWithLoadingAndErrorState() throws {
        let detail = try readSource("Settings/Providers/ProviderDetailPane.swift")
        let routing = try readSource("Providers/FeatureRouting.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")
        let paths = try readSource("Persistence/ClawixPersistentSurfacePaths.swift")

        XCTAssertTrue(detail.contains("providerToggleSaving"))
        XCTAssertTrue(detail.contains("providerToggleUnavailable"))
        XCTAssertTrue(detail.contains("providerToggleError"))
        XCTAssertTrue(detail.contains("ProgressView()"))
        XCTAssertTrue(detail.contains("InfoBanner(text: providerToggleError, kind: .error)"))
        XCTAssertTrue(detail.contains(".disabled(providerToggleSaving || providerToggleUnavailable)"))
        XCTAssertTrue(routing.contains("static func providerEnabled(_ provider: ProviderID) throws -> Bool"))
        XCTAssertTrue(routing.contains("static func setProviderEnabledOrThrow(_ provider: ProviderID, enabled: Bool) throws"))
        XCTAssertTrue(paths.contains("provider_routing"))
        XCTAssertTrue(paths.contains("provider_settings"))
        XCTAssertFalse(registry.contains("clawix.prefs.provider.enabled"))
    }

    func testProviderAccountMutationsSurfaceErrorsBeforeDismissal() throws {
        let store = try readSource("Settings/Providers/AIAccountStoreObservable.swift")
        let detail = try readSource("Settings/Providers/ProviderDetailPane.swift")
        let edit = try readSource("Settings/Providers/EditAccountSheet.swift")

        XCTAssertTrue(store.contains("func updateLabel(id: UUID, label: String) -> Bool"))
        XCTAssertTrue(store.contains("func setEnabled(id: UUID, enabled: Bool) -> Bool"))
        XCTAssertTrue(store.contains("func setBaseURL(id: UUID, url: URL?) -> Bool"))
        XCTAssertTrue(store.contains("func delete(id: UUID) -> Bool"))
        XCTAssertTrue(detail.contains("if let error = store.lastError"))
        XCTAssertTrue(detail.contains("InfoBanner(text: error, kind: .error)"))
        XCTAssertTrue(edit.contains("@State private var mutationError: String?"))
        XCTAssertTrue(edit.contains("guard store.updateLabel(id: account.id, label: trimmedLabel) else"))
        XCTAssertTrue(edit.contains("guard store.setBaseURL(id: account.id, url: newURL) else"))
        XCTAssertTrue(edit.contains("if store.delete(id: account.id)"))
        XCTAssertTrue(edit.contains("InfoBanner(text: mutationError, kind: .error)"))
    }

    func testSkillsSettingsDoesNotExposeUnconsumedAutoImportOrInMemoryTargetMutations() throws {
        let source = try readSource("Skills/SkillsSettingsPage.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertFalse(source.contains("@AppStorage(ClawixPersistentSurfaceKeys.skillsAutoImport)"))
        XCTAssertFalse(source.contains("Toggle(\"Auto-import on startup\""))
        XCTAssertFalse(source.contains("store?.removeSyncTarget(id:"))
        XCTAssertFalse(source.contains("store?.registerSyncTarget(target)"))
        XCTAssertFalse(source.contains("ships in the next iteration"))

        XCTAssertTrue(source.contains("SkillsCapabilityStatusRow"))
        XCTAssertTrue(source.contains("Settings does not start skill scans directly."))
        XCTAssertTrue(source.contains("Settings only reports whether they exist; no import or symlink operation runs from this page."))
        XCTAssertTrue(source.contains("Blocked until target create/remove writes through a persisted framework record"))
        XCTAssertFalse(registry.contains("clawix.prefs.skills.autoImport"))
        XCTAssertFalse(registry.contains("skillsAutoImport"))
    }

    func testAppsSettingsMutationsExposeErrorAndBusyState() throws {
        let source = try readSource("Settings/AppsSettingsPage.swift")

        XCTAssertFalse(source.contains("try? appsStore.delete(record)"))
        XCTAssertFalse(source.contains("try? appsStore.update(copy)"))
        XCTAssertFalse(source.contains("try? appsStore.update(updated)"))
        XCTAssertFalse(source.contains("sync that folder"))

        XCTAssertTrue(source.contains("@State private var actionInFlight: Set<UUID>"))
        XCTAssertTrue(source.contains("@State private var appsError: String?"))
        XCTAssertTrue(source.contains("InfoBanner(text: appsError, kind: .error)"))
        XCTAssertTrue(source.contains("runAppMutation(record)"))
        XCTAssertTrue(source.contains("isBusy: actionInFlight.contains(record.id)"))
        XCTAssertTrue(source.contains(".disabled(isBusy)"))
        XCTAssertTrue(source.contains("ProgressView()"))
        XCTAssertTrue(source.contains("Settings only opens and edits the local managed folder."))
    }

    func testIdentitySettingsIsReadOnlyUntilMarketplaceMutationRoutesExist() throws {
        let source = try readSource("Settings/IdentitySettingsPage.swift")

        XCTAssertFalse(source.contains("Create your identity"))
        XCTAssertFalse(source.contains("Recovery phrase restores"))
        XCTAssertTrue(source.contains("statusSection"))
        XCTAssertTrue(source.contains("ProgressView()"))
        XCTAssertTrue(source.contains("Settings is read-only for identity records."))
        XCTAssertTrue(source.contains("signed identity-create route"))
        XCTAssertTrue(source.contains("signed registration route"))
        XCTAssertTrue(source.contains("marketplace mutation routes"))
        XCTAssertTrue(source.contains("signed restore receipts"))
    }

    func testMacUtilitiesSettingsExposeExecutionStatusAndDisableConcurrentActions() throws {
        let page = try readSource("MacUtilities/MacUtilitiesSettingsPage.swift")
        let controller = try readSource("MacUtilities/MacUtilitiesController.swift")

        XCTAssertTrue(page.contains("controller.lastStatusMessage"))
        XCTAssertTrue(page.contains("InfoBanner(text: message, kind: controller.lastStatusIsError ? .error : .ok)"))
        XCTAssertTrue(page.contains("activeAction: controller.activeAction"))
        XCTAssertTrue(page.contains(".disabled(activeAction != nil)"))
        XCTAssertTrue(page.contains("ProgressView()"))

        XCTAssertTrue(controller.contains("@Published private(set) var activeAction: MacUtilityActionID?"))
        XCTAssertTrue(controller.contains("@Published private(set) var lastStatusMessage: String?"))
        XCTAssertTrue(controller.contains("@Published private(set) var lastStatusIsError = false"))
        XCTAssertTrue(controller.contains("publishStatus(\"Mac Utilities are disabled by feature flags.\", isError: true)"))
        XCTAssertTrue(controller.contains("publishStatus(message, isError: true)"))
        XCTAssertTrue(controller.contains("publishStatus(\"\\(action.title) done\", isError: false)"))
        XCTAssertTrue(controller.contains("publishStatus(error.localizedDescription, isError: true)"))
    }

    func testMacControlSettingsDisableLocallyInvalidRuns() throws {
        let source = try readSource("HostActions/MacControlSettingsPage.swift")

        XCTAssertTrue(source.contains("localRunBlockReason(for: capability)"))
        XCTAssertTrue(source.contains("canRunAction: localBlockReason == nil"))
        XCTAssertTrue(source.contains(".disabled(!canRunAction)"))
        XCTAssertTrue(source.contains("Wi-Fi connect requires an explicit SSID."))
        XCTAssertTrue(source.contains("Window move requires integer x and y arguments."))
        XCTAssertTrue(source.contains("Window resize requires positive integer width and height arguments."))
        XCTAssertTrue(source.contains("Shortcut run requires a shortcut name."))
        XCTAssertTrue(source.contains("accessibilityHint(Text(localBlockReason ??"))
        XCTAssertTrue(source.contains("macControlPositiveInteger"))
    }

    func testMemorySettingsDoctorDoesNotSwallowDaemonFailures() throws {
        let page = try readSource("Memory/MemorySettingsView.swift")
        let store = try readSource("Memory/MemoryStore.swift")

        XCTAssertFalse(store.contains("doctor = try? await doctorOperation()"))
        XCTAssertTrue(store.contains("@Published private(set) var isDoctorLoading = false"))
        XCTAssertTrue(store.contains("@Published private(set) var doctorError: String?"))
        XCTAssertTrue(store.contains("guard !isDoctorLoading else { return }"))
        XCTAssertTrue(store.contains("doctor = try await doctorOperation()"))
        XCTAssertTrue(store.contains("doctorError = Self.failureMessage(for: error, surface: \"memory.doctor\")"))
        XCTAssertTrue(store.contains("UserFacingFailure.displayMessage(for: rawMessage, surface: surface)"))

        XCTAssertTrue(page.contains("store.isDoctorLoading"))
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains(".disabled(store.isDoctorLoading)"))
        XCTAssertTrue(page.contains("InfoBanner(text: error, kind: .error)"))
    }

    func testScreenToolsSettingsExposePermissionStatusAndActionState() throws {
        let source = try readSource("ScreenTools/ScreenToolsSettingsPage.swift")

        XCTAssertTrue(source.contains("@State private var activeScreenToolAction: String?"))
        XCTAssertTrue(source.contains("@State private var screenToolActionMessage: String?"))
        XCTAssertTrue(source.contains("@State private var screenRecordingStatus = NativeMacPermissionBroker.status(for: .screenRecording)"))
        XCTAssertTrue(source.contains("InfoBanner("))
        XCTAssertTrue(source.contains("Screen Tools are disabled by feature flags"))
        XCTAssertTrue(source.contains("NativeMacPermissionBroker.requestScreenRecording()"))
        XCTAssertTrue(source.contains("NativeMacPermissionBroker.openSettings(for: .screenRecording)"))
        XCTAssertTrue(source.contains("screenRecordingStatus.displayLabel"))
        XCTAssertTrue(source.contains("screenRecordingStatus.blockedReason"))
        XCTAssertTrue(source.contains("ProgressView()"))
        XCTAssertTrue(source.contains(".disabled(activeScreenToolAction != nil || !service.featureVisible)"))
        XCTAssertTrue(source.contains("runScreenToolAction(id: id, action: action)"))
        XCTAssertTrue(source.contains("host-policy blocks through the app status channel"))
    }

    func testTelegramSettingsExposeReloadStateAndCommandValidation() throws {
        let page = try readSource("Settings/TelegramSettingsPage.swift")
        let store = try readSource("Telegram/TelegramBotsStore.swift")

        XCTAssertTrue(store.contains("@Published private(set) var reloadingCommands: Set<String> = []"))
        XCTAssertTrue(store.contains("@Published private(set) var reloadingChats: Set<String> = []"))
        XCTAssertTrue(store.contains("reloadingCommands.insert(bot.id)"))
        XCTAssertTrue(store.contains("reloadingChats.insert(bot.id)"))
        XCTAssertTrue(store.contains("reloadingCommands.remove(bot.id)"))
        XCTAssertTrue(store.contains("reloadingChats.remove(bot.id)"))

        XCTAssertTrue(page.contains("private var commandsReloading: Bool { store.reloadingCommands.contains(bot.id) }"))
        XCTAssertTrue(page.contains("private var chatsReloading: Bool { store.reloadingChats.contains(bot.id) }"))
        XCTAssertTrue(page.contains("private var commandRowsAreValid: Bool"))
        XCTAssertTrue(page.contains("private var canSyncCommands: Bool"))
        XCTAssertTrue(page.contains("Commands must be 1-32 letters, numbers, or underscores"))
        XCTAssertTrue(page.contains(".disabled(!canSyncCommands)"))
        XCTAssertTrue(page.contains(".disabled(inflight || commandsReloading)"))
        XCTAssertTrue(page.contains(".disabled(inflight || chatsReloading)"))
        XCTAssertTrue(page.contains("ProgressView().controlSize(.small)"))
        XCTAssertTrue(page.contains("private func connect() async {\n        guard !inflight else { return }"))
        XCTAssertTrue(page.contains("private func send() async {\n        guard !inflight else { return }"))
        XCTAssertTrue(page.contains("TextEditor(text: $text)"))
        XCTAssertTrue(page.contains(".disabled(inflight)"))
    }

    func testDictationAdvancedDefaultsUseRegisteredAppStorage() throws {
        let page = try readSource("DictationSettingsPage.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertFalse(page.contains("UserDefaults.standard.string(forKey: DictationCoordinator.backendKey)"))
        XCTAssertFalse(page.contains("UserDefaults.standard.object(forKey: DictationCoordinator.livePreviewEnabledKey)"))
        XCTAssertFalse(page.contains("UserDefaults.standard.bool(forKey: DictationCoordinator.vadEnabledKey)"))
        XCTAssertTrue(page.contains("@AppStorage(DictationCoordinator.backendKey) private var backendRaw"))
        XCTAssertTrue(page.contains("@AppStorage(DictationCoordinator.livePreviewEnabledKey) private var livePreviewEnabled = true"))
        XCTAssertTrue(page.contains("@AppStorage(DictationCoordinator.vadEnabledKey) private var vadEnabled = true"))
        XCTAssertTrue(page.contains("selection: $backendRaw"))
        XCTAssertTrue(page.contains("isOn: $livePreviewEnabled"))
        XCTAssertTrue(page.contains("isOn: $vadEnabled"))
        XCTAssertTrue(registry.contains("clawix.prefs.dictation.backend"))
        XCTAssertTrue(registry.contains("clawix.prefs.dictation.livePreview"))
        XCTAssertTrue(registry.contains("clawix.prefs.dictation.vadEnabled"))
    }

    func testDatabaseWorkbenchProfilesExposePersistenceErrors() throws {
        let page = try readSource("Database/DatabaseWorkbenchSettingsPage.swift")
        let store = try readSource("Database/DatabaseConnectionProfiles.swift")

        XCTAssertFalse(store.contains("let decoded = try? decoder.decode([DatabaseConnectionProfile].self"))
        XCTAssertFalse(store.contains("guard let data = try? encoder.encode(profiles) else { return }"))
        XCTAssertTrue(store.contains("@Published private(set) var lastPersistenceError: String?"))
        XCTAssertTrue(store.contains("lastPersistenceError = \"Connection profiles could not be loaded:"))
        XCTAssertTrue(store.contains("lastPersistenceError = \"Connection profiles could not be saved:"))
        XCTAssertTrue(page.contains("profiles.lastPersistenceError"))
        XCTAssertTrue(page.contains("InfoBanner(text: error, kind: .error)"))
    }

    func testDatabaseWorkbenchSettingsDefaultsAreRegistered() throws {
        let prefs = try readSource("Database/DatabaseWorkbenchPreferences.swift")
        let profiles = try readSource("Database/DatabaseConnectionProfiles.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        for key in [
            "showItemList",
            "showConsoleLog",
            "showRowDetail",
            "autoSaveQueries",
            "uppercaseKeywords",
            "insertClosingPairs",
            "indentWithTabs",
            "indentWidth",
            "completeKey",
            "alternatingRows",
            "autoHideTableScrollers",
            "estimateCountThreshold",
            "csvDelimiter",
            "csvLineBreak",
            "defaultEncoding",
            "queryTimeoutSeconds",
            "keepConnectionAlive",
            "safeMode",
            "passcodeEnabled",
            "openTarget",
            "assistantSidebar",
        ] {
            XCTAssertTrue(prefs.contains("static let \(key) = \"clawix.databaseWorkbench.\(key)\""), "missing preference key \(key)")
            XCTAssertTrue(registry.contains("clawix.prefs.databaseWorkbench.\(key)"), "missing registered key \(key)")
        }

        XCTAssertTrue(profiles.contains("private let key = \"clawix.databaseWorkbench.connectionProfiles.v1\""))
        XCTAssertTrue(registry.contains("clawix.prefs.databaseWorkbench.connectionProfiles"))
    }

    func testRemoteAccessSettingsValidatesInputsBeforeExternalActions() throws {
        let source = try readSource("Settings/RemoteAccessSettingsPage.swift")

        XCTAssertTrue(source.contains("private var trimmedCoordinatorURL: String"))
        XCTAssertTrue(source.contains("private var coordinatorURLValid: Bool"))
        XCTAssertTrue(source.contains("private var canSendMagicLink: Bool"))
        XCTAssertTrue(source.contains("private var canRegisterMac: Bool"))
        XCTAssertTrue(source.contains("RemoteAccessSettingsStore.isCoordinatorURLValid(trimmedCoordinatorURL)"))
        XCTAssertTrue(source.contains("InfoBanner(text: L10n.t(\"Invalid coordinator URL\"), kind: .error)"))
        XCTAssertTrue(source.contains(".disabled(!canSendMagicLink)"))
        XCTAssertTrue(source.contains(".disabled(!canRegisterMac)"))
        XCTAssertTrue(source.contains(".disabled(store.inFlight)"))
        XCTAssertTrue(source.contains("static func isCoordinatorURLValid(_ raw: String) -> Bool"))
        XCTAssertFalse(source.contains("Button(\"Forget this Mac on the coordinator\")"))
        XCTAssertTrue(source.contains("Button(\"Forget local pairing\")"))
        XCTAssertTrue(source.contains("L10n.t(\"Magic link sent to %@. Open it on this Mac, then paste the token below.\")"))
        XCTAssertTrue(source.contains("L10n.t(\"This Mac is registered as %@. Refresh token stored locally.\")"))
        XCTAssertTrue(source.contains("L10n.t(\"Local pairing forgotten. Revoke the device from the coordinator's Devices page to fully unpair.\")"))
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

    func testBrowserUsageSettingsUseRegisteredConsumedPoliciesAndGuardConcurrentClears() throws {
        let page = try readSource("Settings/SettingsView+BrowserPage.swift")
        let policy = try readSource("Browser/BrowserPermissionPolicy.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("@AppStorage(BrowserPermissionPolicy.approvalStorageKey)"))
        XCTAssertTrue(page.contains("BrowserPermissionPolicy.blockedDomains"))
        XCTAssertTrue(page.contains("BrowserPermissionPolicy.allowedDomains"))
        XCTAssertTrue(page.contains("guard !clearingBrowsingData else { return }"))
        XCTAssertTrue(page.contains(".disabled(clearingBrowsingData)"))
        XCTAssertFalse(page.contains("\\(selected.rawValue) completed."))
        XCTAssertTrue(page.contains("L10n.t(\"Browsing data cleared.\")"))

        XCTAssertTrue(policy.contains("static func decision(for url: URL) -> BrowserNavigationDecision"))
        XCTAssertTrue(policy.contains("if hostMatches(url, domains: blockedDomains) { return .block }"))
        XCTAssertTrue(policy.contains("if hostMatches(url, domains: allowedDomains) { return .allow }"))
        XCTAssertTrue(policy.contains("static func clearBrowserStorage(_ kind: BrowserStorageKind"))

        XCTAssertTrue(registry.contains("clawix.prefs.browser.websiteApproval"))
        XCTAssertTrue(registry.contains("clawix.prefs.browser.blockedDomains"))
        XCTAssertTrue(registry.contains("clawix.prefs.browser.allowedDomains"))
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
        XCTAssertTrue(source.contains("!isWorking && vault.store != nil && passphrase.count >= 8 && passphrase == passphraseConfirm"))
        XCTAssertTrue(source.contains("!isWorking && vault.store != nil && !passphrase.isEmpty"))
        XCTAssertTrue(source.contains("private func requestExportReview() {\n        guard !isWorking else { return }"))
        XCTAssertTrue(source.contains("private func exportReviewedBackup() {\n        guard !isWorking else { return }"))
        XCTAssertTrue(source.contains("private func restore() {\n        guard !isWorking else { return }"))
    }

    func testSecretsOperationsAreDisabledUntilVaultIsUnlocked() throws {
        let source = try readSource("Secrets/SecretsSettingsPage.swift")

        XCTAssertTrue(source.contains("private var secretsUnlocked: Bool"))
        XCTAssertTrue(source.contains("vault.store != nil"))
        XCTAssertTrue(source.contains("Unlock Secrets before importing external files."))
        XCTAssertTrue(source.contains("Unlock Secrets before choosing a backup file."))
        XCTAssertTrue(source.contains("Unlock Secrets before exporting a backup."))
        XCTAssertTrue(source.contains("Unlock Secrets before restoring a backup."))
        XCTAssertTrue(source.contains(".disabled(!secretsUnlocked)"))
        XCTAssertTrue(source.contains("symlinkResultIsError"))
        XCTAssertTrue(source.contains("InfoBanner(text: symlinkResult, kind: symlinkResultIsError ? .error : .ok)"))
        XCTAssertTrue(source.contains("isEnabled: canExport"))
        XCTAssertTrue(source.contains("isEnabled: canRestore"))
    }

    func testSecretsPermissionsSaveDoesNotSilentlyNoopWhenLocked() throws {
        let source = try readSource("Secrets/PermissionsTab.swift")

        XCTAssertTrue(source.contains("private var canSave: Bool"))
        XCTAssertTrue(source.contains("vault.store != nil"))
        XCTAssertTrue(source.contains(".disabled(!canSave)"))
        XCTAssertTrue(source.contains("guard let store = vault.store else {"))
        XCTAssertTrue(source.contains("Unlock Secrets before saving permissions."))
        XCTAssertTrue(source.contains("saved = nil"))
    }

    func testSecretsGrantSurfaceUsesRegisteredLocalizedCopy() throws {
        let grants = try readSource("Secrets/GrantsTab.swift")
        let detail = try readSource("Secrets/SecretDetailPane.swift")
        let catalog = try readResource("Localizable.xcstrings")

        let legacyGrantCopy = "No agent " + "grants for this secret yet."

        XCTAssertFalse(grants.contains(legacyGrantCopy))
        XCTAssertTrue(grants.contains("No grants for agents on this secret yet."))
        XCTAssertTrue(detail.contains("Grants for agents"))
        XCTAssertTrue(catalog.contains("\"No grants for agents on this secret yet.\""))
        XCTAssertFalse(catalog.contains("\"\(legacyGrantCopy)\""))
        XCTAssertTrue(catalog.contains("\"Grants for agents\""))
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

    func testLegalSafetySettingsUseRegisteredPersistentDefaults() throws {
        let page = try readSource("Settings/LegalSafetySettingsPage.swift")
        let store = try readSource("LegalSafety.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("@ObservedObject private var legal = LegalSafetyStore.shared"))
        XCTAssertTrue(store.contains("didSet { defaults.set(remoteSyncOptIn"))
        XCTAssertTrue(store.contains("didSet { defaults.set(providerDisclosureOptIn"))
        XCTAssertTrue(store.contains("didSet { defaults.set(supportDiagnosticsOptIn"))
        XCTAssertTrue(store.contains("didSet { defaults.set(sensitiveExportConfirmationRequired"))
        XCTAssertTrue(store.contains("didSet { defaults.set(localAuditRetentionDays"))
        XCTAssertTrue(registry.contains("clawix.prefs.legal.remoteSyncOptIn"))
        XCTAssertTrue(registry.contains("clawix.prefs.legal.providerDisclosureOptIn"))
        XCTAssertTrue(registry.contains("clawix.prefs.legal.supportDiagnosticsOptIn"))
        XCTAssertTrue(registry.contains("clawix.prefs.legal.sensitiveExportConfirmationRequired"))
        XCTAssertTrue(registry.contains("clawix.prefs.legal.localAuditRetentionDays"))
    }

    func testAppearanceSettingsDoNotExposeUnpersistedThemeControls() throws {
        let source = try readSource("Settings/SettingsView+AppearancePage.swift")
        let router = try readSource("SettingsView.swift")

        XCTAssertFalse(source.contains("@State private var theme"))
        XCTAssertFalse(source.contains("ThemeChip"))
        XCTAssertFalse(source.contains("ThemeSubSection"))
        XCTAssertFalse(source.contains("Copy theme"))
        XCTAssertFalse(source.contains("ColorRow"))
        XCTAssertFalse(source.contains("SliderRow(title: \"Contrast\""))

        XCTAssertTrue(source.contains("hidden until Settings has a persisted theme contract"))
        XCTAssertTrue(source.contains("Blocked until theme mode is backed by a registered preference"))
        XCTAssertTrue(source.contains("import, export, validation, and persistence routes exist"))
        XCTAssertTrue(source.contains("Settings must receive success or failure from the renderer"))
        XCTAssertTrue(router.contains("// case appearance  // hidden temporarily"))
        XCTAssertTrue(router.contains("// case .appearance:      AppearancePage()"))
    }

    func testHostsWorkspaceAddExposesLoadingStateAndRegisteredPersistence() throws {
        let page = try readSource("Settings/HostsPage.swift")
        let detail = try readSource("Settings/HostDetailView.swift")
        let editor = try readSource("Settings/HostEditorSheet.swift")
        let store = try readSource("Bridge/MeshStore.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("@State private var workspaceAddInFlight = false"))
        XCTAssertTrue(page.contains("guard !workspaceAddInFlight else { return }"))
        XCTAssertTrue(page.contains("workspaceAddInFlight = true"))
        XCTAssertTrue(page.contains("defer { workspaceAddInFlight = false }"))
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains(".disabled(workspaceAddInFlight)"))
        XCTAssertTrue(page.contains("accessibilityHint(Text(workspaceAddInFlight ?"))
        XCTAssertTrue(store.contains("nonisolated static let workspacesDefaultsKey"))
        XCTAssertTrue(store.contains("Self.saveRemoteWorkspaces(defaultRemoteWorkspaces)"))
        XCTAssertTrue(registry.contains("clawix.prefs.mesh.remoteWorkspaces"))

        XCTAssertTrue(detail.contains("@State private var actionError: String?"))
        XCTAssertTrue(detail.contains("InfoBanner(text: actionError, kind: .error)"))
        XCTAssertTrue(detail.contains("guard !actionInFlight else { return }"))
        XCTAssertTrue(detail.contains("SettingsUtilities.failureMessage(for: error, surface: \"settings.hosts.revoke\")"))
        XCTAssertTrue(detail.contains("SettingsUtilities.failureMessage(for: error, surface: \"settings.hosts.unrevoke\")"))
        XCTAssertTrue(editor.contains("guard canCommit else { return }"))
        XCTAssertTrue(editor.contains("guard !pairingInFlight else { return }"))
        XCTAssertTrue(editor.contains("guard !sshInFlight else { return }"))
    }

    func testShortcutSettingsExposeOnlyPersistedRegisteredBindings() throws {
        let page = try readSource("ShortcutsSettingsPage.swift")
        let root = try readSource("HostActions/SearchEntrypointShortcutsInstaller.swift")
        let terminal = try readSource("Terminal/TerminalKeyboardShortcuts.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("KeyboardShortcuts.Recorder(for: name)"))
        XCTAssertTrue(root.contains("SearchEntrypointShortcutBroker.rootBindingId"))
        XCTAssertTrue(terminal.contains("static let terminalToggle"))
        XCTAssertTrue(terminal.contains("static let terminalSplitHorizontal"))
        XCTAssertTrue(registry.contains("KeyboardShortcuts_search.root.global"))
        XCTAssertTrue(registry.contains("KeyboardShortcuts_terminal.toggle"))
        XCTAssertTrue(registry.contains("KeyboardShortcuts_terminal.newTab"))
        XCTAssertTrue(registry.contains("KeyboardShortcuts_terminal.closeTab"))
        XCTAssertTrue(registry.contains("KeyboardShortcuts_terminal.splitVertical"))
        XCTAssertTrue(registry.contains("KeyboardShortcuts_terminal.splitHorizontal"))
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

    private func readResource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Clawix")
            .appendingPathComponent("Resources")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
