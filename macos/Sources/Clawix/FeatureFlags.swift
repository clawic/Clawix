import Foundation
import SwiftUI

// User-facing capability maturity for the v1 surface. New work must not become
// visible by default: stable capabilities are enabled, beta/experimental
// capabilities require explicit opt-in, and incomplete work requires the debug
// developer profile plus allowlisting.
//
// Stored under `appPrefsSuite` so prefs follow the same UserDefaults
// suite as the rest of the app (sidebar prefs, sync settings, language).
//
// Release builds (`#if !DEBUG`) hard-pin developer-only surfaces to `false`
// and drop the persistence backing entirely. The shipped notarized binary
// cannot surface dev tooling regardless of any prior UserDefaults state
// inherited from a sideloaded dev build.

enum FeatureMaturity: Int, Codable, Hashable, Comparable {
    case incomplete = 0
    case experimental = 1
    case beta = 2
    case stable = 3
    case retired = -1

    static func < (lhs: FeatureMaturity, rhs: FeatureMaturity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .incomplete: return "incomplete"
        case .experimental: return "experimental"
        case .beta: return "beta"
        case .stable: return "stable"
        case .retired: return "retired"
        }
    }
}

enum FeatureMaturityProfile: Codable, Hashable {
    case stable
    case beta
    case experimental
    case dev

    var ceiling: FeatureMaturity {
        switch self {
        case .stable: return .stable
        case .beta: return .beta
        case .experimental: return .experimental
        case .dev: return .incomplete
        }
    }
}

enum FeatureActivationPolicy: String, Codable, Hashable {
    case enabled
    case optIn = "opt_in"
    case devAllowlist = "dev_allowlist"
}

enum AppFeature: Equatable, CaseIterable {
    case voiceToText
    case quickAsk
    case secrets
    case mcp
    case localModels
    case browserUsage
    case git
    case remoteMesh
    case publishing
    case apps
    case design
    case life
    case skills
    case skillCollections
    case claw
    case identity
    case telegram
    case screenTools
    case macUtilities
    case macControl
    case databaseWorkbench
    case marketplace
    case calendar
    case contacts
    case database
    case index
    case iotHome
    case agents
    case openCode
    case simulators

    var maturity: FeatureMaturity {
        switch self {
        case .voiceToText, .quickAsk, .secrets, .mcp, .localModels,
             .browserUsage, .git, .remoteMesh, .apps,
             .design, .life, .skills, .skillCollections, .claw,
             .identity, .telegram, .screenTools, .macUtilities, .macControl,
             .databaseWorkbench, .marketplace, .calendar, .contacts,
             .database, .index, .iotHome, .agents, .openCode:
            return .stable
        case .publishing:
            return .beta
        case .simulators:
            return .incomplete
        }
    }

    var activationPolicy: FeatureActivationPolicy {
        switch maturity {
        case .stable:
            return .enabled
        case .beta, .experimental:
            return .optIn
        case .incomplete, .retired:
            return .devAllowlist
        }
    }

    var capabilityID: String {
        switch self {
        case .voiceToText: return "clawix.feature.voiceToText"
        case .quickAsk: return "clawix.feature.quickAsk"
        case .secrets: return "clawix.feature.secrets"
        case .mcp: return "clawix.feature.mcp"
        case .localModels: return "clawix.feature.localModels"
        case .browserUsage: return "clawix.feature.browserUsage"
        case .git: return "clawix.feature.git"
        case .remoteMesh: return "clawix.feature.remoteMesh"
        case .publishing: return "clawix.feature.publishing"
        case .apps: return "clawix.feature.apps"
        case .design: return "clawix.feature.design"
        case .life: return "clawix.feature.life"
        case .skills: return "clawix.feature.skills"
        case .skillCollections: return "clawix.feature.skillCollections"
        case .claw: return "clawix.feature.claw"
        case .identity: return "clawix.feature.identity"
        case .telegram: return "clawix.feature.telegram"
        case .screenTools: return "clawix.feature.screenTools"
        case .macUtilities: return "clawix.feature.macUtilities"
        case .macControl: return "clawix.feature.macControl"
        case .databaseWorkbench: return "clawix.feature.databaseWorkbench"
        case .marketplace: return "clawix.feature.marketplace"
        case .calendar: return "clawix.feature.calendar"
        case .contacts: return "clawix.feature.contacts"
        case .database: return "clawix.feature.database"
        case .index: return "clawix.feature.index"
        case .iotHome: return "clawix.feature.iotHome"
        case .agents: return "clawix.feature.agents"
        case .openCode: return "clawix.feature.openCode"
        case .simulators: return "clawix.feature.simulators"
        }
    }
}

@MainActor
final class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()

#if DEBUG
    @Published var developerSurfaces: Bool {
        didSet { store.set(developerSurfaces, forKey: developerSurfacesKey) }
    }

    private let store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    private let developerSurfacesKey = ClawixPersistentSurfaceKeys.featureFlagsDeveloperSurfaces
    private let enabledCapabilityIDsKey = ClawixPersistentSurfaceKeys.featureFlagsEnabledCapabilityIDs
    private var enabledCapabilityIDs: Set<String>

    private init() {
        let s = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        self.developerSurfaces = s.object(forKey: ClawixPersistentSurfaceKeys.featureFlagsDeveloperSurfaces) as? Bool ?? false
        self.enabledCapabilityIDs = Set(s.stringArray(forKey: enabledCapabilityIDsKey) ?? [])
    }

    var maturityProfile: FeatureMaturityProfile {
        developerSurfaces ? .dev : .stable
    }

    func setCapabilityOptIn(_ enabled: Bool, capabilityID: String) {
        if enabled {
            enabledCapabilityIDs.insert(capabilityID)
        } else {
            enabledCapabilityIDs.remove(capabilityID)
        }
        store.set(enabledCapabilityIDs.sorted(), forKey: enabledCapabilityIDsKey)
    }
#else
    let developerSurfaces: Bool = false
    private let enabledCapabilityIDs: Set<String> = []
    private init() {}

    var maturityProfile: FeatureMaturityProfile {
        .stable
    }
#endif

    func isVisible(_ feature: AppFeature) -> Bool {
        isCapabilityVisible(
            capabilityID: feature.capabilityID,
            maturity: feature.maturity,
            activationPolicy: feature.activationPolicy
        )
    }

    func isCapabilityVisible(
        capabilityID: String,
        maturity: FeatureMaturity,
        activationPolicy: FeatureActivationPolicy
    ) -> Bool {
        guard maturity != .retired else { return false }
        guard maturity.rawValue >= maturityProfile.ceiling.rawValue else { return false }

        switch activationPolicy {
        case .enabled:
            return true
        case .optIn:
            return enabledCapabilityIDs.contains(capabilityID)
        case .devAllowlist:
            return maturityProfile == .dev && developerSurfaces
        }
    }
}
