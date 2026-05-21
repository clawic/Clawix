import XCTest
@testable import Clawix

@MainActor
final class FeatureFlagsTests: XCTestCase {
    func test_currentProductSurfacesAreStable() {
        let incomplete = AppFeature.allCases.filter { $0.maturity == .incomplete }
        XCTAssertEqual(incomplete, [.simulators])
        XCTAssertEqual(AppFeature.openCode.maturity, .stable)
        XCTAssertEqual(AppFeature.screenTools.maturity, .stable)
        XCTAssertEqual(AppFeature.macUtilities.maturity, .stable)
        XCTAssertEqual(AppFeature.macControl.maturity, .stable)
        XCTAssertEqual(AppFeature.agents.maturity, .stable)
        XCTAssertEqual(AppFeature.skills.maturity, .stable)
    }

    func test_featureCapabilityIDsAreExplicitAndStable() {
        XCTAssertEqual(AppFeature.macControl.capabilityID, "clawix.feature.macControl")
        XCTAssertEqual(AppFeature.simulators.capabilityID, "clawix.feature.simulators")
    }

    func test_maturityVisibilityBlocksNonStableWithoutOptIn() {
        let flags = FeatureFlags.shared

        XCTAssertTrue(flags.isCapabilityVisible(capabilityID: "clawix.feature.stable", maturity: .stable, activationPolicy: .enabled))
        XCTAssertFalse(flags.isCapabilityVisible(capabilityID: "system.telemetry", maturity: .experimental, activationPolicy: .optIn))
        XCTAssertFalse(flags.isCapabilityVisible(capabilityID: "clawix.feature.incomplete", maturity: .incomplete, activationPolicy: .devAllowlist))
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
