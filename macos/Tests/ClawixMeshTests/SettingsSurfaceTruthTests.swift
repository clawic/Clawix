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

    func testPersonalizationBlocksSaveUntilInstructionsFileLoads() throws {
        let page = try readSource("Settings/SettingsView+PersonalizationPage.swift")
        let instructionsFile = try readSource("CodexInstructionsFile.swift")

        XCTAssertTrue(page.contains("@State private var isSaving: Bool = false"))
        XCTAssertTrue(page.contains("private var canSave: Bool { didLoad && isDirty && !isSaving }"))
        XCTAssertTrue(page.contains("isEditable: didLoad && !isSaving"))
        XCTAssertTrue(page.contains("Button(\"Retry\") { load() }"))
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains(".disabled(!canSave)"))
        XCTAssertTrue(page.contains("guard canSave else { return }"))
        XCTAssertTrue(page.contains("guard didLoad else {"))
        XCTAssertTrue(page.contains("instructions = savedSnapshot"))

        XCTAssertTrue(instructionsFile.contains("let current = try read()"))
        XCTAssertFalse(instructionsFile.contains("(try? read()) ?? \"\""))
    }

    func testCodexInjectionCardsBlockMutationUntilInstructionsFileLoads() throws {
        let memory = try readSource("Memory/MemoryCodexInjectionCard.swift")
        let secrets = try readSource("Secrets/SecretsCodexInjectionCard.swift")

        for source in [memory, secrets] {
            XCTAssertTrue(source.contains("@State private var isWorking = false"))
            XCTAssertTrue(source.contains("private var canMutate: Bool { didLoad && !isWorking }"))
            XCTAssertTrue(source.contains("private var canSave: Bool { canMutate && isDirty }"))
            XCTAssertTrue(source.contains("guard canMutate else { return }"))
            XCTAssertTrue(source.contains("guard canSave else { return }"))
            XCTAssertTrue(source.contains("ProgressView()"))
            XCTAssertTrue(source.contains("Button(\"Retry\") { load() }"))
            XCTAssertTrue(source.contains(".disabled(!canMutate)"))
            XCTAssertTrue(source.contains(".disabled(!canSave)"))
            XCTAssertTrue(source.contains("didLoad = true"))
            XCTAssertTrue(source.contains("didLoad = false"))
        }

        XCTAssertTrue(memory.contains("accessibilityLabel: \"Memory Codex injection\""))
        XCTAssertTrue(memory.contains("Writes or removes the Memory block in AGENTS.md."))
        XCTAssertTrue(secrets.contains(".accessibilityLabel(Text(\"Secrets Codex injection\"))"))
        XCTAssertTrue(secrets.contains(".accessibilityHint(Text(\"Writes or removes the Secrets block in AGENTS.md.\"))"))
    }

    func testConfigurationScopeIsPersistedAndProjectConfigIsDisabledWithoutProject() throws {
        let source = try readSource("Settings/SettingsView+ConfigurationPage.swift")
        let controls = try readSource("Settings/SettingsView+Controls.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertFalse(source.contains("@State private var configScope"))
        XCTAssertTrue(source.contains("@AppStorage(ClawixPersistentSurfaceKeys.settingsConfigurationScope)"))
        XCTAssertTrue(source.contains("@State private var configActionFeedback: SettingsUtilities.ActionFeedback?"))
        XCTAssertTrue(source.contains("InfoBanner(text: configActionFeedback.message, kind: configActionFeedback.kind)"))
        XCTAssertTrue(source.contains("projectConfigUnavailable"))
        XCTAssertTrue(source.contains(".disabled(openingConfig || projectConfigUnavailable)"))
        XCTAssertTrue(source.contains("configActionFeedback = await SettingsUtilities.openConfigToml"))
        XCTAssertTrue(source.contains("configActionFeedback = SettingsUtilities.revealDiagnosticsFolder()"))
        XCTAssertTrue(controls.contains("struct ActionFeedback"))
        XCTAssertTrue(controls.contains("static func openConfigToml(scope: String, selectedProject: Project?) async -> ActionFeedback"))
        XCTAssertTrue(controls.contains("static func revealDiagnosticsFolder() -> ActionFeedback"))
        XCTAssertTrue(controls.contains("failureMessage(for: error, surface: \"settings.config.open\")"))
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
        XCTAssertTrue(source.contains("@State private var appsStatus: String?"))
        XCTAssertTrue(source.contains("@State private var appsStatusKind: InfoBanner.Kind = .ok"))
        XCTAssertTrue(source.contains("InfoBanner(text: appsError, kind: .error)"))
        XCTAssertTrue(source.contains("InfoBanner(text: appsStatus, kind: appsStatusKind)"))
        XCTAssertTrue(source.contains("runAppMutation(record)"))
        XCTAssertTrue(source.contains("isBusy: actionInFlight.contains(record.id)"))
        XCTAssertTrue(source.contains(".disabled(isBusy)"))
        XCTAssertTrue(source.contains("ProgressView()"))
        XCTAssertTrue(source.contains("setAppsStatus(message, kind: .ok)"))
        XCTAssertTrue(source.contains("setAppsStatus(message, kind: .error)"))
        XCTAssertTrue(source.contains("L10n.t(\"Workspace variant default set\")"))
        XCTAssertTrue(source.contains("L10n.t(\"User variant default cleared\")"))
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
        XCTAssertTrue(source.contains("@State private var exportDirectoryPanelInFlight = false"))
        XCTAssertTrue(source.contains("@State private var screenRecordingStatus = NativeMacPermissionBroker.status(for: .screenRecording)"))
        XCTAssertTrue(source.contains("InfoBanner("))
        XCTAssertTrue(source.contains("Screen Tools are disabled by feature flags"))
        XCTAssertTrue(source.contains("NativeMacPermissionBroker.requestScreenRecording()"))
        XCTAssertTrue(source.contains("NativeMacPermissionBroker.openSettings(for: .screenRecording)"))
        XCTAssertTrue(source.contains("screenRecordingStatus.displayLabel"))
        XCTAssertTrue(source.contains("screenRecordingStatus.blockedReason"))
        XCTAssertTrue(source.contains("ProgressView()"))
        XCTAssertTrue(source.contains(".disabled(activeScreenToolAction != nil || !service.featureVisible)"))
        XCTAssertTrue(source.contains(".disabled(exportDirectoryPanelInFlight || !service.featureVisible)"))
        XCTAssertTrue(source.contains("guard !exportDirectoryPanelInFlight else { return }"))
        XCTAssertTrue(source.contains("screenToolActionMessage = L10n.t(\"Export location unchanged.\")"))
        XCTAssertTrue(source.contains("L10n.t(\"Export location updated to %@\")"))
        XCTAssertTrue(source.contains("Choose Screen Tools export location"))
        XCTAssertTrue(source.contains("Stores the local folder used for screenshots, recordings, OCR captures, pins, and capture history."))
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

    func testDictationBackupExportImportExposeBusyErrorAndConfirmation() throws {
        let source = try readSource("Dictation/TranscriptHistoryUI.swift")

        XCTAssertTrue(source.contains("@State private var statusKind: InfoBanner.Kind = .ok"))
        XCTAssertTrue(source.contains("@State private var operationInFlight = false"))
        XCTAssertTrue(source.contains(".disabled(operationInFlight)"))
        XCTAssertTrue(source.contains("ProgressView()"))
        XCTAssertTrue(source.contains("InfoBanner(text: status, kind: statusKind)"))
        XCTAssertTrue(source.contains("guard !operationInFlight else { return }"))
        XCTAssertTrue(source.contains("requestImportConfirmation(chosen)"))
        XCTAssertTrue(source.contains("appState.pendingConfirmation = ConfirmationRequest"))
        XCTAssertTrue(source.contains("Import preview is not available for this legacy dictation settings format."))
        XCTAssertTrue(source.contains("private func importConfirmedJSON(_ chosen: URL)"))
        XCTAssertTrue(source.contains("SettingsUtilities.failureMessage(for: error, surface: \"settings.dictation.exportTranscripts\")"))
        XCTAssertTrue(source.contains("SettingsUtilities.failureMessage(for: error, surface: \"settings.dictation.exportSettings\")"))
        XCTAssertTrue(source.contains("SettingsUtilities.failureMessage(for: error, surface: \"settings.dictation.importSettings\")"))
        XCTAssertTrue(source.contains("SettingsUtilities.failureMessage(for: error, surface: \"settings.dictation.saveExport\")"))
        XCTAssertTrue(source.contains("L10n.t(\"Export failed: %@\")"))
        XCTAssertTrue(source.contains("L10n.t(\"Import failed: %@\")"))
        XCTAssertTrue(source.contains("L10n.t(\"Saved to %@.\")"))
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

    func testDatabaseWorkbenchActionsExposeVisibleStatusAndBusyState() throws {
        let page = try readSource("Database/DatabaseWorkbenchSettingsPage.swift")
        let operations = try readSource("Database/DatabaseWorkbenchOperations.swift")

        XCTAssertTrue(page.contains("@State private var activeProfileAction: UUID?"))
        XCTAssertTrue(page.contains("@State private var activeOperationKind: DatabaseWorkbenchOperationKind?"))
        XCTAssertTrue(page.contains("@State private var databaseWorkbenchMessage: String?"))
        XCTAssertTrue(page.contains("InfoBanner(text: databaseWorkbenchMessage, kind: databaseWorkbenchMessageKind)"))
        XCTAssertTrue(page.contains("guard activeProfileAction == nil, activeOperationKind == nil else { return }"))
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains(".disabled(isDisabled)"))
        XCTAssertTrue(page.contains("databaseWorkbenchMessageKind = .danger"))
        XCTAssertTrue(page.contains("clearActiveProfileAction(profile.id)"))
        XCTAssertTrue(page.contains("clearActiveOperation(kind)"))
        XCTAssertTrue(page.contains("LegalSafetyStore.shared.requestSensitiveActionReview(action: .exportShare"))

        XCTAssertTrue(operations.contains("EXTERNAL PENDING:"))
        XCTAssertTrue(operations.contains("validateLocalImportFile"))
        XCTAssertTrue(operations.contains("localImportMaxBytes"))
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
        XCTAssertTrue(source.contains("label: \"Forget local pairing\""))
        XCTAssertTrue(source.contains("L10n.t(\"Magic link sent to %@. Open it on this Mac, then paste the token below.\")"))
        XCTAssertTrue(source.contains("L10n.t(\"This Mac is registered as %@. Refresh token stored locally.\")"))
        XCTAssertTrue(source.contains("L10n.t(\"Local pairing forgotten. Revoke the device from the coordinator's Devices page to fully unpair.\")"))
    }

    func testRemoteAccessSettingsRendersFullRemoteProjectionReadiness() throws {
        let source = try readSource("Settings/RemoteAccessSettingsPage.swift")

        XCTAssertTrue(source.contains("snapshot.externalReadinessStatus"))
        XCTAssertTrue(source.contains("snapshot.blockedExternalRequirementSummary"))
        XCTAssertTrue(source.contains("snapshot.closureBlockersSummary"))
        XCTAssertTrue(source.contains("snapshot.providerDeviceE2ESummary"))
        XCTAssertFalse(source.contains("/v1/remote/"))
        XCTAssertFalse(source.contains("/v1/gateway/"))
        XCTAssertFalse(source.contains("/v1/sync/"))
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
        let editor = try readSource("MCP/MCPEditorSheet.swift")
        let store = try readSource("MCP/MCPServersStore.swift")

        XCTAssertTrue(source.contains("private var isBusy: Bool { store.isLoading || store.isSaving }"))
        XCTAssertTrue(source.contains("guard !isBusy else { return }"))
        XCTAssertTrue(source.contains("MCPEmptyState(onAdd:"))
        XCTAssertTrue(source.contains(".disabled(isBusy)"))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Enable MCP server\""))
        XCTAssertTrue(source.contains("accessibilityHint: \"Turns this MCP server on or off.\""))

        XCTAssertTrue(editor.contains("@State private var mutationInFlight: Bool = false"))
        XCTAssertTrue(editor.contains("!mutationInFlight, !store.isSaving"))
        XCTAssertTrue(editor.contains("ProgressView()"))
        XCTAssertTrue(editor.contains("let saved = await store.upsertAndWait(draft)"))
        XCTAssertTrue(editor.contains("let deleted = await store.deleteAndWait(initial)"))
        XCTAssertTrue(editor.contains(".disabled(mutationInFlight)"))

        XCTAssertTrue(store.contains("func upsertAndWait(_ server: MCPServerConfig) async -> Bool"))
        XCTAssertTrue(store.contains("func deleteAndWait(_ server: MCPServerConfig) async -> Bool"))
        XCTAssertTrue(store.contains("private func replaceServersAndWait(_ snapshot: [MCPServerConfig]) async -> Bool"))
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
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains("selected.statusLabel"))
        XCTAssertTrue(page.contains("WebKit reported completion for %@. Settings does not receive per-site deletion counts."))
        XCTAssertTrue(page.contains("Browser storage clear completed."))
        XCTAssertTrue(page.contains("@State private var isMutating = false"))
        XCTAssertTrue(page.contains("private var canAddDomain: Bool"))
        XCTAssertTrue(page.contains("guard canAddDomain else { return }"))
        XCTAssertTrue(page.contains("InfoBanner(text: error, kind: .error)"))
        XCTAssertTrue(page.contains(".disabled(isMutating)"))
        XCTAssertTrue(page.contains("accessibilityLabel(Text(\"Add browser domain\"))"))
        XCTAssertTrue(page.contains("Remove %@ from browser permissions"))
        XCTAssertTrue(page.contains("Adds the domain to this persisted browser permission list."))
        XCTAssertTrue(page.contains("Removes the domain from this persisted browser permission list."))
        XCTAssertFalse(page.contains("\\(selected.rawValue) completed."))
        XCTAssertFalse(page.contains("L10n.t(\"Browsing data cleared.\")"))
        XCTAssertTrue(page.contains("private extension BrowserPermissionPolicy.BrowserStorageKind"))
        XCTAssertTrue(page.contains("L10n.t(\"Enter a valid domain such as example.com.\")"))
        XCTAssertTrue(page.contains("L10n.t(\"Added %@\")"))

        XCTAssertTrue(policy.contains("static func decision(for url: URL) -> BrowserNavigationDecision"))
        XCTAssertTrue(policy.contains("if hostMatches(url, domains: blockedDomains) { return .block }"))
        XCTAssertTrue(policy.contains("if hostMatches(url, domains: allowedDomains) { return .allow }"))
        XCTAssertTrue(policy.contains("static func clearBrowserStorage(_ kind: BrowserStorageKind"))

        XCTAssertTrue(registry.contains("clawix.prefs.browser.websiteApproval"))
        XCTAssertTrue(registry.contains("clawix.prefs.browser.blockedDomains"))
        XCTAssertTrue(registry.contains("clawix.prefs.browser.allowedDomains"))
        XCTAssertTrue(registry.contains("clawix.prefs.browser.agentControlEnabled"))
        XCTAssertTrue(registry.contains("clawix.prefs.browser.annotationScreenshots"))
    }

    func testUsageSettingsExposeRuntimeLoadingErrorAndEmptySnapshotStates() throws {
        let page = try readSource("Settings/SettingsView+UsagePage.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("@AppStorage(ClawixPersistentSurfaceKeys.usageDisplayMode)"))
        XCTAssertTrue(page.contains("@State private var usageRefreshInFlight = false"))
        XCTAssertTrue(page.contains("@State private var usageRefreshError: String?"))
        XCTAssertTrue(page.contains("@State private var usageRefreshCompleted = false"))
        XCTAssertTrue(page.contains("usageStatus"))
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains("InfoBanner(text: usageRefreshError, kind: .error)"))
        XCTAssertTrue(page.contains("The runtime did not return a rate-limit snapshot for this account."))
        XCTAssertTrue(page.contains("guard await appState.ensureAgentRuntimeReady(reason: .usageSurface) else"))
        XCTAssertTrue(page.contains("Agent runtime is unavailable: %@"))
        XCTAssertTrue(page.contains("await clawix.refreshBackendMetadata(reason: .usageSurface)"))
        XCTAssertTrue(page.contains("usageRefreshCompleted && !hasAnyUsageData"))
        XCTAssertTrue(page.contains("Usage limits are unavailable because the agent runtime could not be reached."))
        XCTAssertTrue(registry.contains("clawix.prefs.settings.usageDisplayMode"))
        XCTAssertTrue(registry.contains("usageDisplayMode"))
    }

    func testAppshotsSettingsReflectPermissionsAndRegisteredPersistence() throws {
        let page = try readSource("Settings/AppshotsSettingsPage.swift")
        let settings = try readSource("Appshots/AppshotSettings.swift")
        let monitor = try readSource("Appshots/AppshotHotkeyMonitor.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("@AppStorage(AppshotSettings.enabledKey)"))
        XCTAssertTrue(page.contains("@AppStorage(AppshotSettings.hotkeyKey)"))
        XCTAssertTrue(page.contains("private var captureBlockedReason: String?"))
        XCTAssertTrue(page.contains("private var hotkeyBlockedReason: String?"))
        XCTAssertTrue(page.contains("private var enabledBinding: Binding<Bool>"))
        XCTAssertTrue(page.contains("if newValue, let reason = captureBlockedReason"))
        XCTAssertTrue(page.contains("enabled = false"))
        XCTAssertTrue(page.contains("L10n.t(\"Appshots are blocked until permission is granted. %@\")"))
        XCTAssertTrue(page.contains("L10n.t(\"Appshots are enabled but blocked until permission is granted. %@\")"))
        XCTAssertTrue(page.contains("L10n.t(\"The global appshot hotkey is inactive until permission is granted. %@\")"))
        XCTAssertTrue(page.contains("InfoBanner(text: message, kind: .error)"))
        XCTAssertTrue(page.contains("NativeMacPermissionBroker.status(for: .screenRecording)"))
        XCTAssertTrue(page.contains("NativeMacPermissionBroker.status(for: .accessibility)"))
        XCTAssertTrue(page.contains("NativeMacPermissionBroker.status(for: .inputMonitoring)"))
        XCTAssertTrue(monitor.contains("NativeMacPermissionBroker.status(for: .inputMonitoring).isGranted"))
        XCTAssertTrue(settings.contains("static let enabledKey = \"appshots.enabled\""))
        XCTAssertTrue(settings.contains("static let hotkeyKey = \"appshots.hotkey\""))
        XCTAssertTrue(registry.contains("clawix.prefs.appshots.enabled"))
        XCTAssertTrue(registry.contains("clawix.prefs.appshots.hotkey"))
    }

    func testComputerUseSettingsDoNotExposeUnconsumedLockedUseToggle() throws {
        let page = try readSource("HostActions/ComputerUseSettingsPage.swift")
        let store = try readSource("HostActions/ComputerUseSettingsStore.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("@StateObject private var settings = ComputerUseSettings.shared"))
        XCTAssertTrue(page.contains("InfoBanner(text: error, kind: .error)"))
        XCTAssertTrue(page.contains("settings.allowedAppsLoadError"))
        XCTAssertTrue(page.contains("ComputerUseCapabilityStatusRow"))
        XCTAssertTrue(page.contains("Blocked until the signed host consumes lock-screen state and the persisted locked-use policy."))
        XCTAssertFalse(page.contains("isOn: $settings.lockedUseEnabled"))
        XCTAssertTrue(page.contains("isOn: $settings.anyAppEnabled"))
        XCTAssertTrue(page.contains(".accessibilityLabel(Text(\"Remove \\(app.name) from always-allowed apps\"))"))

        XCTAssertTrue(store.contains("@Published private(set) var allowedAppsLoadError: String?"))
        XCTAssertTrue(store.contains("@Published private(set) var policySyncError: String?"))
        XCTAssertFalse(store.contains("let decoded = try? JSONDecoder().decode([AlwaysAllowedApp].self"))
        XCTAssertTrue(store.contains("try JSONDecoder().decode([AlwaysAllowedApp].self, from: data)"))
        XCTAssertTrue(store.contains("surface: \"settings.computerUse.allowedApps.load\""))
        XCTAssertTrue(store.contains("allowedAppsLoadError = nil"))
        XCTAssertTrue(store.contains("try ComputerUsePolicyStore.save(policy, to: ComputerUsePolicyStore.defaultURL())"))
        XCTAssertFalse(store.contains("try? ComputerUsePolicyStore.save"))
        XCTAssertTrue(store.contains("policySyncError = SettingsUtilities.failureMessage(for: error, surface: \"settings.computerUse.policySync\")"))
        XCTAssertTrue(store.contains("enum Keys"))
        XCTAssertTrue(page.contains("L10n.t(\"Remove %@ from always-allowed apps\")"))

        XCTAssertTrue(registry.contains("clawix.prefs.computerUse.anyAppEnabled"))
        XCTAssertTrue(registry.contains("clawix.prefs.computerUse.lockedUseEnabled"))
        XCTAssertTrue(registry.contains("clawix.prefs.computerUse.alwaysAllowedApps"))
    }

    func testLocalModelsAdvancedDisclosureIsPersistedAndRegistered() throws {
        let page = try readSource("LocalModels/LocalModelsPage.swift")
        let diagnostics = try readSource("LocalModels/LocalModelsDiagnosticsSection.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertFalse(page.contains("@State var advancedExpanded"))
        XCTAssertTrue(page.contains("@AppStorage(ClawixPersistentSurfaceKeys.localModelsAdvancedExpanded)"))
        XCTAssertTrue(page.contains("@State private var uninstallInFlight = false"))
        XCTAssertTrue(page.contains("@State private var runtimeActionError: String?"))
        XCTAssertTrue(page.contains("InfoBanner(text: runtimeActionError, kind: .error)"))
        XCTAssertTrue(page.contains("InfoBanner(text: launchAgentError, kind: .error)"))
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains(".disabled(uninstallInFlight || isRuntimeBusy)"))
        XCTAssertTrue(page.contains("guard !isRuntimeBusy else { return }"))
        XCTAssertTrue(page.contains("private func uninstallRuntime() async"))
        XCTAssertTrue(page.contains("try LocalModelsRuntimeInstaller.shared.uninstall()"))
        XCTAssertTrue(page.contains("settings.localModels.runtime.uninstall"))
        XCTAssertFalse(page.contains("try? LocalModelsRuntimeInstaller.shared.uninstall()"))
        XCTAssertTrue(diagnostics.contains("isEnabled: Bool = true"))
        XCTAssertTrue(diagnostics.contains("isWorking: Bool = false"))
        XCTAssertTrue(diagnostics.contains(".disabled(!isEnabled)"))
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

    func testPortableArchiveSettingsExposeOnlySignedHostBlockedStates() throws {
        let source = try readSource("Settings/PortableArchiveSettingsPage.swift")

        XCTAssertTrue(source.contains("private enum PortableArchiveAction: CaseIterable"))
        XCTAssertTrue(source.contains("Portable archive contracts are documented, but Settings cannot execute export, verify, preview, restore, or report actions until a signed host route returns dry-run and result evidence."))
        XCTAssertTrue(source.contains("Blocked until the signed host route returns a dry-run archive plan and approval evidence."))
        XCTAssertTrue(source.contains("Blocked until Settings receives a verification report from the signed host route."))
        XCTAssertTrue(source.contains("Blocked until the signed host route returns an import preview without applying changes."))
        XCTAssertTrue(source.contains("Blocked until import preview, verification, signed-host proof, explicit approval, and exact target confirmation all pass."))
        XCTAssertTrue(source.contains("External pending until a completed restore report exists; Settings does not synthesize one."))
        XCTAssertTrue(source.contains("Source: claw archive plan/export --signed-host"))
        XCTAssertTrue(source.contains("Source: claw archive restore --signed-host"))
        XCTAssertTrue(source.contains("Source: PortableArchiveRestoreReport from signed host"))
        XCTAssertTrue(source.contains(".accessibilityHint(Text(\"\\(reason) \\(source)\"))"))
        XCTAssertFalse(source.contains("PortableArchiveActionStatus(label: \"Pending\")"))
    }

    func testHostsWorkspaceAddExposesLoadingStateAndRegisteredPersistence() throws {
        let page = try readSource("Settings/HostsPage.swift")
        let detail = try readSource("Settings/HostDetailView.swift")
        let editor = try readSource("Settings/HostEditorSheet.swift")
        let store = try readSource("Bridge/MeshStore.swift")
        let registry = try readSource("Persistence/PersistentSurfaceRegistry.swift")

        XCTAssertTrue(page.contains("@State private var workspaceAddInFlight = false"))
        XCTAssertTrue(page.contains("@State private var workspaceAddPanelInFlight = false"))
        XCTAssertTrue(page.contains("@State private var workspaceActionMessage: String?"))
        XCTAssertTrue(page.contains("guard !workspaceAddInFlight, !workspaceAddPanelInFlight else { return }"))
        XCTAssertTrue(page.contains("workspaceAddPanelInFlight = true"))
        XCTAssertTrue(page.contains("workspaceAddPanelInFlight = false"))
        XCTAssertTrue(page.contains("workspaceAddInFlight = true"))
        XCTAssertTrue(page.contains("defer { workspaceAddInFlight = false }"))
        XCTAssertTrue(page.contains("ProgressView()"))
        XCTAssertTrue(page.contains("InfoBanner(text: message, kind: workspaceActionMessageKind)"))
        XCTAssertTrue(page.contains(".disabled(workspaceAddInFlight || workspaceAddPanelInFlight)"))
        XCTAssertTrue(page.contains("accessibilityHint(Text(workspaceAddInFlight || workspaceAddPanelInFlight ?"))
        XCTAssertTrue(page.contains("L10n.t(\"Trusted workspace unchanged.\")"))
        XCTAssertTrue(page.contains("L10n.t(\"Trusted workspace added: %@\")"))
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
        XCTAssertTrue(editor.contains("String(format: L10n.t(\"Linked with %@\")"))
        XCTAssertTrue(editor.contains("String(format: L10n.t(\"Added %@\")"))
        XCTAssertFalse(editor.contains("Hetzner"))
        XCTAssertTrue(editor.contains("accessibilityLabel: L10n.t(\"Pairing token\")"))
        XCTAssertTrue(editor.contains("L10n.t(\"SSH private key\")"))
        XCTAssertTrue(editor.contains("L10n.t(\"SSH password\")"))
        XCTAssertTrue(editor.contains(".accessibilityLabel(Text(accessibilityLabel))"))
        XCTAssertTrue(editor.contains(".accessibilityHint(Text(accessibilityHint))"))
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
