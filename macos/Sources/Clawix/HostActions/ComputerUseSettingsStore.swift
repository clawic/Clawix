import ClawHostKit
import Combine
import Foundation

/// One app the user has chosen to let the agent control with Computer Use
/// without a per-turn prompt. Matched by bundle id when present, otherwise by
/// display name.
struct AlwaysAllowedApp: Codable, Equatable, Identifiable {
    var bundleId: String?
    var name: String
    var addedAt: Date

    var id: String {
        if let bundleId, !bundleId.isEmpty { return bundleId }
        return name
    }
}

/// Clawix host-operational state for the Computer Use surface: whether the agent
/// may control any app, whether it may run while the Mac is locked, and the list
/// of always-allowed apps that skip the per-app approval card. This is host UI
/// state, so it lives in the app preferences suite, not in a framework store.
@MainActor
final class ComputerUseSettings: ObservableObject {
    static let shared = ComputerUseSettings()

    @Published var anyAppEnabled: Bool {
        didSet { store.set(anyAppEnabled, forKey: Keys.anyApp); syncHostPolicy() }
    }

    @Published var lockedUseEnabled: Bool {
        didSet { store.set(lockedUseEnabled, forKey: Keys.lockedUse); syncHostPolicy() }
    }

    @Published private(set) var alwaysAllowedApps: [AlwaysAllowedApp] {
        didSet { persistAllowed(); syncHostPolicy() }
    }

    private let store: UserDefaults

    private enum Keys {
        static let anyApp = "clawix.computerUse.anyAppEnabled"
        static let lockedUse = "clawix.computerUse.lockedUseEnabled"
        static let allowed = "clawix.computerUse.alwaysAllowedApps"
    }

    init(store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard) {
        self.store = store
        self.anyAppEnabled = (store.object(forKey: Keys.anyApp) as? Bool) ?? true
        self.lockedUseEnabled = store.bool(forKey: Keys.lockedUse)
        if let data = store.data(forKey: Keys.allowed),
           let decoded = try? JSONDecoder().decode([AlwaysAllowedApp].self, from: data) {
            self.alwaysAllowedApps = decoded
        } else {
            self.alwaysAllowedApps = []
        }
        // Mirror current settings into the host-readable policy so the signed
        // host broker enforces them on the next Computer Use action.
        syncHostPolicy()
    }

    /// Write the host-readable Computer Use policy that the signed-host broker
    /// reads to gate `mac.app.*` actions (block when off, auto-approve
    /// always-allowed apps, otherwise require approval).
    private func syncHostPolicy() {
        let policy = ComputerUsePolicy(
            anyApp: anyAppEnabled,
            lockedUse: lockedUseEnabled,
            allowedApps: alwaysAllowedApps.map { ComputerUseAllowedApp(bundleId: $0.bundleId, name: $0.name) }
        )
        try? ComputerUsePolicyStore.save(policy, to: ComputerUsePolicyStore.defaultURL())
    }

    /// Whether the agent may control this app right now without prompting:
    /// either it is on the always-allowed list, or "Any app" is enabled.
    func isAlwaysAllowed(bundleId: String?, name: String) -> Bool {
        alwaysAllowedApps.contains { entry in
            if let bundleId, !bundleId.isEmpty, let entryBundle = entry.bundleId, !entryBundle.isEmpty {
                return entryBundle.caseInsensitiveCompare(bundleId) == .orderedSame
            }
            return entry.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func allow(bundleId: String?, name: String, now: Date = Date()) {
        guard !isAlwaysAllowed(bundleId: bundleId, name: name) else { return }
        alwaysAllowedApps.append(AlwaysAllowedApp(bundleId: bundleId, name: name, addedAt: now))
    }

    func remove(_ app: AlwaysAllowedApp) {
        alwaysAllowedApps.removeAll { $0.id == app.id }
    }

    private func persistAllowed() {
        guard let data = try? JSONEncoder().encode(alwaysAllowedApps) else { return }
        store.set(data, forKey: Keys.allowed)
    }
}
