import Combine
import XCTest
@testable import Clawix

@MainActor
final class FeatureFlagsTests: XCTestCase {
    func test_currentProductSurfacesHaveExpectedMaturity() {
        let incomplete = AppFeature.allCases.filter { $0.maturity == .incomplete }
        XCTAssertEqual(incomplete, [.simulators])
        XCTAssertEqual(AppFeature.openCode.maturity, .stable)
        XCTAssertEqual(AppFeature.screenTools.maturity, .stable)
        XCTAssertEqual(AppFeature.macUtilities.maturity, .stable)
        XCTAssertEqual(AppFeature.macControl.maturity, .stable)
        XCTAssertEqual(AppFeature.publishing.maturity, .beta)
        XCTAssertEqual(
            Set(AppFeature.allCases.filter { $0.maturity == .experimental }),
            [
                .tools,
                .networkControl,
                .secrets,
                .mcp,
                .databaseWorkbench,
                .marketplace,
                .calendar,
                .contacts,
                .database,
                .index,
                .iotHome,
                .composerExperiments,
                .remoteMesh,
                .agents,
                .apps,
                .design,
                .life,
                .skills,
                .skillCollections,
                .claw,
                .telegram
            ]
        )
    }

    func test_featureCapabilityIDsAreExplicitAndStable() {
        XCTAssertEqual(AppFeature.macControl.capabilityID, "clawix.feature.macControl")
        XCTAssertEqual(AppFeature.composerExperiments.capabilityID, "clawix.feature.composerExperiments")
        XCTAssertEqual(AppFeature.tools.capabilityID, "clawix.feature.tools")
        XCTAssertEqual(AppFeature.networkControl.capabilityID, "clawix.feature.networkControl")
        XCTAssertEqual(AppFeature.simulators.capabilityID, "clawix.feature.simulators")
    }

    func test_maturityVisibilityBlocksNonStableWithoutOptIn() {
        let flags = FeatureFlags.shared
        let wasExperimental = flags.experimentalSurfaces
        let wasDeveloper = flags.developerSurfaces
        flags.experimentalSurfaces = false
        flags.developerSurfaces = false
        defer {
            flags.experimentalSurfaces = wasExperimental
            flags.developerSurfaces = wasDeveloper
        }

        XCTAssertTrue(flags.isCapabilityVisible(capabilityID: "clawix.feature.stable", maturity: .stable, activationPolicy: .enabled))
        XCTAssertFalse(flags.isCapabilityVisible(capabilityID: "system.telemetry", maturity: .experimental, activationPolicy: .optIn))
        XCTAssertFalse(flags.isCapabilityVisible(capabilityID: "clawix.feature.incomplete", maturity: .incomplete, activationPolicy: .devAllowlist))
    }

    func test_experimentalModeShowsExperimentalSurfaces() {
        let flags = FeatureFlags.shared
        let wasExperimental = flags.experimentalSurfaces
        let wasDeveloper = flags.developerSurfaces
        flags.experimentalSurfaces = true
        flags.developerSurfaces = false
        defer {
            flags.experimentalSurfaces = wasExperimental
            flags.developerSurfaces = wasDeveloper
        }

        XCTAssertTrue(flags.isVisible(.tools))
        XCTAssertTrue(flags.isVisible(.secrets))
        XCTAssertTrue(flags.isVisible(.mcp))
        XCTAssertTrue(flags.isVisible(.databaseWorkbench))
        XCTAssertTrue(flags.isVisible(.marketplace))
        XCTAssertTrue(flags.isVisible(.calendar))
        XCTAssertTrue(flags.isVisible(.contacts))
        XCTAssertTrue(flags.isVisible(.database))
        XCTAssertTrue(flags.isVisible(.index))
        XCTAssertTrue(flags.isVisible(.iotHome))
        XCTAssertFalse(flags.isVisible(.publishing))
        XCTAssertTrue(flags.isVisible(.composerExperiments))
        XCTAssertTrue(flags.isVisible(.remoteMesh))
        XCTAssertTrue(flags.isVisible(.networkControl))
        XCTAssertTrue(flags.isVisible(.skills))
        XCTAssertTrue(flags.isVisible(.agents))
        XCTAssertTrue(flags.isVisible(.apps))
        XCTAssertTrue(flags.isVisible(.design))
        XCTAssertTrue(flags.isVisible(.life))
        XCTAssertTrue(flags.isVisible(.claw))
        XCTAssertTrue(flags.isVisible(.telegram))
        XCTAssertFalse(flags.isVisible(.simulators))
    }

    func test_betaSurfacesRequireCapabilityOptIn() {
        let flags = FeatureFlags.shared
        let wasExperimental = flags.experimentalSurfaces
        let wasDeveloper = flags.developerSurfaces
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        let enabledCapabilityIDsKey = ClawixPersistentSurfaceKeys.featureFlagsEnabledCapabilityIDs
        let wasPublishingOptedIn = defaults.stringArray(forKey: enabledCapabilityIDsKey)?.contains(AppFeature.publishing.capabilityID) == true
        flags.experimentalSurfaces = true
        flags.developerSurfaces = false
        flags.setCapabilityOptIn(false, capabilityID: AppFeature.publishing.capabilityID)
        defer {
            flags.experimentalSurfaces = wasExperimental
            flags.developerSurfaces = wasDeveloper
            flags.setCapabilityOptIn(wasPublishingOptedIn, capabilityID: AppFeature.publishing.capabilityID)
        }

        XCTAssertFalse(flags.isVisible(.publishing))
        flags.setCapabilityOptIn(true, capabilityID: AppFeature.publishing.capabilityID)
        XCTAssertTrue(flags.isVisible(.publishing))
    }

    func test_settingsHideExperimentalConfigurationByDefault() {
        let visible = SettingsCategory.visibleCases { feature in
            feature.maturity == .stable
        }

        XCTAssertFalse(visible.contains(.skills))
        XCTAssertFalse(visible.contains(.mcp))
        XCTAssertFalse(visible.contains(.apps))
        XCTAssertFalse(visible.contains(.claw))
        XCTAssertFalse(visible.contains(.machines))
        XCTAssertFalse(visible.contains(.secrets))
        XCTAssertFalse(visible.contains(.databaseWorkbench))
        XCTAssertFalse(visible.contains(.telegram))
    }

    func test_experimentalSurfacesDoNotEagerLoadRootManagers() throws {
        let appSource = try readSource("App.swift")
        let agentStoreSource = try readSource("Agents/AgentStore.swift")
        let databaseManagerSource = try readSource("Database/DatabaseManager.swift")
        let iotManagerSource = try readSource("IoT/IoTManager.swift")
        let routerSource = try readSource("SurfaceRouterView.swift")

        XCTAssertTrue(agentStoreSource.contains("static let shared = AgentStore(autoLoad: FeatureFlags.shared.isVisible(.agents))"))
        XCTAssertTrue(appSource.contains("DatabaseManager(attachSupervisor: FeatureFlags.shared.isVisible(.database))"))
        XCTAssertTrue(appSource.contains("IoTManager(attachSupervisor: FeatureFlags.shared.isVisible(.iotHome))"))
        XCTAssertTrue(databaseManagerSource.contains("func activateSupervisorObserverIfVisible()"))
        XCTAssertTrue(iotManagerSource.contains("func activateSupervisorObserverIfVisible()"))
        XCTAssertTrue(routerSource.contains("if isRouteVisible {"))
        XCTAssertTrue(routerSource.contains("guard FeatureFlags.shared.isVisible(.apps) else { return nil }"))
    }

    func test_composerExperimentalControlsAreHiddenBehindFeatureFlags() throws {
        let composerSource = try readSource("ComposerView.swift")

        XCTAssertTrue(composerSource.contains("if flags.isVisible(.composerExperiments) {"))
        XCTAssertTrue(composerSource.contains("IDEContextChip()"))
        XCTAssertTrue(composerSource.contains("AttemptsSelector()"))
        XCTAssertTrue(composerSource.contains("if chatMode, flags.isVisible(.remoteMesh) {"))
        XCTAssertTrue(composerSource.contains("if flags.isVisible(.remoteMesh) {"))

        XCTAssertFalse(composerSource.contains("PlanSuggestionBar"))
        XCTAssertFalse(composerSource.contains("showsPlanSuggestion"))
        XCTAssertFalse(composerSource.contains("draftMentionsPlan"))
        XCTAssertFalse(composerSource.contains("Plan my day"))
        XCTAssertFalse(composerSource.contains("around one goal"))
    }

    func test_openCodeRuntimePersistsAsStableSurface() {
        let appDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        let bridgeDefaults = UserDefaults(suiteName: ClawixPersistentSurfaceKeys.bridgeDefaultsSuite) ?? .standard
        let previousRuntime = appDefaults.object(forKey: AgentRuntimeChoice.runtimeKey)
        let previousBridgeRuntime = bridgeDefaults.object(forKey: AgentRuntimeChoice.runtimeKey)

        defer {
            restore(previousRuntime, key: AgentRuntimeChoice.runtimeKey, defaults: appDefaults)
            restore(previousBridgeRuntime, key: AgentRuntimeChoice.runtimeKey, defaults: bridgeDefaults)
        }

        appDefaults.set(AgentRuntimeChoice.opencode.rawValue, forKey: AgentRuntimeChoice.runtimeKey)

        XCTAssertEqual(AgentRuntimeChoice.loadPersisted(), .opencode)

        AgentRuntimeChoice.persist(
            runtime: .opencode,
            openCodeModel: AgentRuntimeChoice.defaultOpenCodeModel
        )
        XCTAssertEqual(appDefaults.string(forKey: AgentRuntimeChoice.runtimeKey), AgentRuntimeChoice.opencode.rawValue)
        XCTAssertEqual(bridgeDefaults.string(forKey: AgentRuntimeChoice.runtimeKey), AgentRuntimeChoice.opencode.rawValue)
    }

    /// P4 narrowed observation: a no-op flag write (re-applying the same
    /// `developerSurfaces` value, or re-opting into a capability that is already
    /// enabled) must NOT fire `objectWillChange`, so a charter surface observing
    /// FeatureFlags re-evaluates only when the visible feature set actually
    /// changes. A real change still publishes exactly once.
    func test_noOpFlagWriteDoesNotPublish() {
        let flags = FeatureFlags.shared
        let wasDeveloper = flags.developerSurfaces
        let wasExperimental = flags.experimentalSurfaces
        defer {
            flags.developerSurfaces = wasDeveloper
            flags.experimentalSurfaces = wasExperimental
        }

        // Settle to a known state first.
        flags.developerSurfaces = false
        flags.experimentalSurfaces = false

        var publishes = 0
        let cancellable = flags.objectWillChange.sink { _ in publishes += 1 }
        defer { cancellable.cancel() }

        // No-op writes: value is already false / already opted-out.
        flags.developerSurfaces = false
        flags.experimentalSurfaces = false
        XCTAssertEqual(publishes, 0, "Redundant flag writes must not fan objectWillChange out to charter surfaces.")

        // A real change publishes exactly once.
        flags.developerSurfaces = true
        XCTAssertEqual(publishes, 1, "A real developerSurfaces flip publishes once.")
        // Re-applying the same value is again a no-op.
        flags.developerSurfaces = true
        XCTAssertEqual(publishes, 1, "Re-applying the same developerSurfaces value must not publish again.")

        // A real capability opt-in publishes exactly once; a redundant one does not.
        flags.experimentalSurfaces = true
        XCTAssertEqual(publishes, 2, "A real capability opt-in publishes once.")
        flags.experimentalSurfaces = true
        XCTAssertEqual(publishes, 2, "Re-opting into an already-enabled capability must not publish again.")
    }

    private func restore(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func readSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Clawix")
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
