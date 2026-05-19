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

struct NativeSystemSearchIndexResult: Decodable, Equatable {
    struct DataPayload: Decodable, Equatable {
        let rebuilt: Bool
        let reindexed: Int
        let indexedBySource: [String: Int]
        let pendingSources: [String]
    }

    let ok: Bool
    let data: DataPayload
}

enum NativeSystemSearchSourceBridge {
    static let sourceId = "native.system"

    struct ClawSearchCommandRunner {
        var run: ([String]) throws -> Data
    }

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

    @MainActor
    static func rebuildShortcutsIndex(
        actorId: String = "clawix.native-system-search",
        dataDir: String? = nil,
        nativeRunner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        clawRunner: ClawSearchCommandRunner? = nil
    ) throws -> NativeSystemSearchIndexResult {
        let snapshot = shortcutsSnapshot(actorId: actorId, runner: nativeRunner)
        let snapshotJSON = try json(snapshot)
        var args = [
            "search", "rebuild",
            "--source", sourceId,
            "--profile", "full",
            "--native-system-snapshot-json", snapshotJSON,
            "--actor", actorId,
            "--surface", "clawix.native_system_search",
            "--json",
        ]
        if let dataDir, !dataDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--data-dir", dataDir]
        }
        let output = try (clawRunner ?? defaultClawSearchRunner()).run(args)
        return try JSONDecoder().decode(NativeSystemSearchIndexResult.self, from: output)
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

    private static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @MainActor
    private static func defaultClawSearchRunner() -> ClawSearchCommandRunner {
        ClawSearchCommandRunner { args in
            guard ClawJSRuntime.isAvailable else {
                throw NSError(domain: "NativeSystemSearchSourceBridge", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "ClawJS bundle is not available in this build."
                ])
            }
            let process = Process()
            process.executableURL = ClawJSRuntime.nodeBinaryURL
            process.arguments = [ClawJSRuntime.cliScriptURL.path] + args
            process.currentDirectoryURL = ClawJSServiceManager.workspaceURL
            process.environment = ClawJSServiceManager.cliEnvironment()

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "native system Search indexing failed"
                throw NSError(domain: "NativeSystemSearchSourceBridge", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
                ])
            }
            return data
        }
    }
}
