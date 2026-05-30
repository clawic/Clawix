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
        XCTAssertEqual(
            Set(AppFeature.allCases.filter { $0.maturity == .experimental }),
            [
                .tools,
                .networkControl,
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

    func test_settingsHideExperimentalConfigurationByDefault() {
        let visible = SettingsCategory.visibleCases { feature in
            feature.maturity == .stable
        }

        XCTAssertFalse(visible.contains(.skills))
        XCTAssertFalse(visible.contains(.apps))
        XCTAssertFalse(visible.contains(.claw))
        XCTAssertFalse(visible.contains(.machines))
        XCTAssertFalse(visible.contains(.secrets))
        XCTAssertFalse(visible.contains(.databaseWorkbench))
        XCTAssertFalse(visible.contains(.telegram))
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

    private func restore(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
