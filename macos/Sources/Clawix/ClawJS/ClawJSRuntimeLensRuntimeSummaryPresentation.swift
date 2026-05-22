import Foundation

struct ClawJSRuntimeLensRuntimeSummaryPresentation: Equatable {
    struct CapabilityRow: Equatable, Identifiable {
        let id: String
        let label: String
        let status: String
        let strategy: String?
        let supported: Bool
        let limitationsLabel: String?

        var accessibilityLabel: String {
            [
                "\(label) \(status)",
                "supported \(supported)",
                strategy.map { "strategy \($0)" },
                limitationsLabel.map { "limitations \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    struct LocationRow: Equatable, Identifiable {
        let id: String
        let label: String
        let value: String

        var accessibilityLabel: String {
            "\(label) \(value)"
        }
    }

    let runtimeId: String
    let runtimeName: String
    let adapter: String?
    let version: String?
    let installed: Bool
    let cliAvailable: Bool
    let gatewayAvailable: Bool
    let installedLabel: String
    let cliLabel: String
    let gatewayLabel: String
    let homeDir: String?
    let workspacePath: String?
    let configPath: String?
    let authStorePath: String?
    let gatewayConfigPath: String?
    let lastError: String?
    let locationRows: [LocationRow]
    let locationCount: Int
    let workspaceCanonicalPathCount: Int
    let workspaceManagedFileCount: Int
    let workspaceFilesLabel: String?
    let runtimeResourceAggregateDomainCount: Int
    let runtimeResourceCount: Int
    let runtimeResourcesLabel: String?
    let hasHomeDir: Bool
    let hasLastError: Bool
    let supportPresent: Bool
    let supportAuditPresent: Bool
    let rawCapabilityCount: Int
    let rawCapabilityEnabledCount: Int
    let capabilityCount: Int
    let readyCapabilityCount: Int
    let degradedCapabilityCount: Int
    let errorCapabilityCount: Int
    let unsupportedCapabilityCount: Int
    let capabilityRows: [CapabilityRow]
    let capabilityStatusLabel: String?

    var accessibilityLabel: String {
        [
            "Runtime summary",
            runtimeName,
            adapter.map { "adapter \($0)" },
            version.map { "version \($0)" },
            "installed \(installed)",
            "cli \(cliLabel)",
            "gateway \(gatewayLabel)",
            "locations \(locationCount)",
            locationRows.isEmpty ? nil : "location details \(locationRows.map(\.accessibilityLabel).joined(separator: ", "))",
            "workspace canonical paths \(workspaceCanonicalPathCount)",
            "workspace managed files \(workspaceManagedFileCount)",
            workspaceFilesLabel.map { "workspace files \($0)" },
            "runtime resource aggregate domains \(runtimeResourceAggregateDomainCount)",
            "runtime resources \(runtimeResourceCount)",
            runtimeResourcesLabel.map { "runtime resource details \($0)" },
            "home \(hasHomeDir)",
            "error \(hasLastError)",
            "support \(supportPresent)",
            "support audit \(supportAuditPresent)",
            "raw capabilities \(rawCapabilityCount)",
            "enabled capabilities \(rawCapabilityEnabledCount)",
            "capability map \(capabilityCount)",
            capabilityStatusLabel.map { "capability status \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(snapshot: ClawJSRuntimeLensSnapshot) -> ClawJSRuntimeLensRuntimeSummaryPresentation {
        let locations = snapshot.status.diagnostics?.locations
        let homeDir = normalized(locations?.homeDir)
        let workspacePath = normalized(locations?.workspacePath)
        let configPath = normalized(locations?.configPath)
        let authStorePath = normalized(locations?.authStorePath)
        let gatewayConfigPath = normalized(locations?.gatewayConfigPath)
        let lastError = normalized(snapshot.status.diagnostics?.lastError)
        let installed = snapshot.status.installed == true
        let cliAvailable = snapshot.status.cliAvailable == true
        let gatewayAvailable = snapshot.status.gatewayAvailable == true
        let rawCapabilities = snapshot.status.capabilities ?? [:]
        let capabilityRows = capabilityRows(snapshot.status.capabilityMap)
        let statusCounts = Dictionary(grouping: capabilityRows, by: \.status)
            .mapValues { $0.count }
        let workspaceCanonicalPathCount = snapshot.workspace?.canonicalPaths?.count ?? 0
        let workspaceManagedFileCount = snapshot.workspace?.managedFiles?.count ?? 0
        let runtimeResourceCounts = resourceAggregateCounts(snapshot.runtimeResources)
        let locationCount = [
            homeDir,
            workspacePath,
            configPath,
            authStorePath,
            gatewayConfigPath
        ].compactMap { $0 }.count
        let locationRows = [
            makeLocationRow(id: "home", label: "Home", value: homeDir),
            makeLocationRow(id: "workspace", label: "Workspace", value: workspacePath),
            makeLocationRow(id: "config", label: "Config", value: configPath),
            makeLocationRow(id: "auth-store", label: "Auth store", value: authStorePath),
            makeLocationRow(id: "gateway-config", label: "Gateway config", value: gatewayConfigPath)
        ].compactMap { $0 }

        return ClawJSRuntimeLensRuntimeSummaryPresentation(
            runtimeId: snapshot.runtimeId,
            runtimeName: snapshot.runtimeName,
            adapter: normalized(snapshot.status.adapter),
            version: normalized(snapshot.status.version),
            installed: installed,
            cliAvailable: cliAvailable,
            gatewayAvailable: gatewayAvailable,
            installedLabel: installed ? "Installed" : "Not installed",
            cliLabel: cliAvailable ? "Available" : "Unavailable",
            gatewayLabel: gatewayAvailable ? "Available" : "Degraded",
            homeDir: homeDir,
            workspacePath: workspacePath,
            configPath: configPath,
            authStorePath: authStorePath,
            gatewayConfigPath: gatewayConfigPath,
            lastError: lastError,
            locationRows: locationRows,
            locationCount: locationCount,
            workspaceCanonicalPathCount: workspaceCanonicalPathCount,
            workspaceManagedFileCount: workspaceManagedFileCount,
            workspaceFilesLabel: workspaceFilesLabel(snapshot.workspace),
            runtimeResourceAggregateDomainCount: runtimeResourceCounts.filter { $0.count > 0 }.count,
            runtimeResourceCount: runtimeResourceCounts.reduce(0) { $0 + $1.count },
            runtimeResourcesLabel: runtimeResourcesLabel(runtimeResourceCounts),
            hasHomeDir: homeDir != nil,
            hasLastError: lastError != nil,
            supportPresent: snapshot.support != nil,
            supportAuditPresent: snapshot.supportAudit != nil,
            rawCapabilityCount: rawCapabilities.count,
            rawCapabilityEnabledCount: rawCapabilities.values.filter { $0 }.count,
            capabilityCount: capabilityRows.count,
            readyCapabilityCount: statusCounts["ready"] ?? 0,
            degradedCapabilityCount: statusCounts["degraded"] ?? 0,
            errorCapabilityCount: statusCounts["error"] ?? 0,
            unsupportedCapabilityCount: statusCounts["unsupported"] ?? 0,
            capabilityRows: capabilityRows,
            capabilityStatusLabel: countLabel(statusCounts)
        )
    }

    private static func capabilityRows(
        _ capabilityMap: [String: ClawJSRuntimeLensSnapshot.Status.Capability]?
    ) -> [CapabilityRow] {
        (capabilityMap ?? [:])
            .keys
            .sorted()
            .compactMap { id in
                guard let capability = capabilityMap?[id] else { return nil }
                return CapabilityRow(
                    id: id,
                    label: label(for: id),
                    status: normalized(capability.status) ?? "unknown",
                    strategy: normalized(capability.strategy),
                    supported: capability.supported == true,
                    limitationsLabel: listLabel(capability.limitations, limit: 2)
                )
            }
    }

    private static func makeLocationRow(id: String, label: String, value: String?) -> LocationRow? {
        guard let value else { return nil }
        return LocationRow(id: id, label: label, value: value)
    }

    private static func workspaceFilesLabel(_ workspace: ClawJSRuntimeLensSnapshot.Workspace?) -> String? {
        let canonicalKeys = workspace?.canonicalPaths?.keys.sorted() ?? []
        let managedFiles = workspace?.managedFiles ?? []
        let parts = [
            canonicalKeys.isEmpty ? nil : "canonical \(canonicalKeys.prefix(5).joined(separator: ", "))",
            managedFiles.isEmpty ? nil : "managed \(managedFiles.count)"
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private static func resourceAggregateCounts(
        _ resources: ClawJSRuntimeLensSnapshot.RuntimeResources?
    ) -> [(label: String, count: Int)] {
        [
            ("providers", resources?.providers?.count ?? 0),
            ("models", (resources?.models?.count ?? 0) + (resources?.defaultModel == nil ? 0 : 1)),
            ("auth", resources?.auth?.count ?? 0),
            ("scheduler", resources?.schedulers?.count ?? 0),
            ("memory", resources?.memory?.count ?? 0),
            ("skills", resources?.skills?.count ?? 0),
            ("channels", resources?.channels?.count ?? 0)
        ]
    }

    private static func runtimeResourcesLabel(
        _ counts: [(label: String, count: Int)]
    ) -> String? {
        let parts = counts
            .filter { $0.count > 0 }
            .map { "\($0.label) \($0.count)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func countLabel(_ counts: [String: Int]) -> String? {
        let parts = counts
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }

    private static func label(for id: String) -> String {
        id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
