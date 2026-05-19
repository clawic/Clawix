import ClawHostKit
import Foundation

struct NativeSystemSearchSourceAction: Codable, Equatable {
    struct HostBroker: Codable, Equatable {
        struct Target: Codable, Equatable {
            let kind: String
            let name: String?
        }

        let system: String
        let capabilityId: String
        let arguments: [String: String]
        let target: Target?
        let reason: String
    }

    let id: String
    let kind: String
    let label: String
    let requiresApproval: Bool
    let grant: String
    let risk: String
    let hostBroker: HostBroker
}

struct NativeSystemSearchSourceDocument: Codable, Equatable {
    let id: String
    let source: String
    let domain: String
    let type: String
    let title: String
    let subtitle: String
    let resourceId: String
    let metadata: [String: String]
    let actions: [NativeSystemSearchSourceAction]
}

struct NativeSystemSearchSourceSnapshot: Codable, Equatable {
    let source: String
    let domain: String
    let state: String
    let documents: [NativeSystemSearchSourceDocument]
}

enum NativeSystemSearchSourceBridge {
    static let sourceId = "native.system"

    @MainActor
    static func shortcutsSnapshot(
        actorId: String = "clawix.native-system-search",
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner()
    ) -> NativeSystemSearchSourceSnapshot {
        let request = NativeMacActionRequest(
            requestId: "search_native_system_shortcuts_snapshot",
            capabilityId: "mac.shortcut.list",
            actorId: actorId,
            origin: .system,
            actorKind: "framework",
            actorRole: "system"
        )
        let receipt = NativeMacActionBroker.evaluate(request, runner: runner)
        guard receipt.outcome == .executed else {
            return NativeSystemSearchSourceSnapshot(source: sourceId, domain: "native", state: "external_pending", documents: [])
        }
        let names = receipt.outputs
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return NativeSystemSearchSourceSnapshot(
            source: sourceId,
            domain: "native",
            state: "enabled",
            documents: names.map(shortcutDocument)
        )
    }

    private static func shortcutDocument(name: String) -> NativeSystemSearchSourceDocument {
        NativeSystemSearchSourceDocument(
            id: "\(sourceId):shortcut:\(stableSlug(name))",
            source: sourceId,
            domain: "native",
            type: "shortcut",
            title: name,
            subtitle: "Shortcut",
            resourceId: "shortcut:\(name)",
            metadata: [
                "kind": "shortcut",
                "permission": "automation_apple_events",
            ],
            actions: [
                NativeSystemSearchSourceAction(
                    id: "run",
                    kind: "run",
                    label: "Run Shortcut",
                    requiresApproval: true,
                    grant: "native.system.shortcut.run",
                    risk: "system",
                    hostBroker: NativeSystemSearchSourceAction.HostBroker(
                        system: "mac-control",
                        capabilityId: "mac.shortcut.run",
                        arguments: ["name": name],
                        target: NativeSystemSearchSourceAction.HostBroker.Target(kind: "shortcut", name: name),
                        reason: "Run native Shortcut from Search result"
                    )
                )
            ]
        )
    }

    private static func stableSlug(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars
        var output = ""
        var lastWasDash = false
        for scalar in scalars {
            let isAlphaNumeric = CharacterSet.alphanumerics.contains(scalar)
            if isAlphaNumeric {
                output.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                output.append("-")
                lastWasDash = true
            }
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "shortcut" : trimmed
    }
}
