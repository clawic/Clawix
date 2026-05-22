import Foundation

struct ClawJSRuntimeLensSessionOverlayPresentation: Equatable {
    static let noSilentOverwritePolicy = "no_silent_overwrite"

    struct Row: Equatable, Identifiable {
        let id: String
        let sessionLabel: String
        let conflictStatus: String?
        let writesRuntime: Bool?
        let authority: String?
        let pinned: Bool?
        let nativeFound: Bool?

        var accessibilityLabel: String {
            [
                "session overlay \(sessionLabel)",
                conflictStatus.map { "conflict \($0)" },
                writesRuntime.map { "writes runtime \($0)" },
                authority.map { "authority \($0)" },
                pinned.map { "pinned \($0)" },
                nativeFound.map { "native found \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let runtimeId: String?
    let overlayAuthority: String?
    let writesRuntime: Bool
    let writeBackStatus: String?
    let conflictPolicy: String?
    let totalOverlays: Int
    let totalConflicts: Int
    let detailLabel: String?
    let conflictStatusLabel: String?
    let rows: [Row]

    var accessibilityLabel: String {
        [
            "Runtime session overlays",
            runtimeId.map { "runtime \($0)" },
            "overlays \(totalOverlays)",
            "conflicts \(totalConflicts)",
            "writes runtime \(writesRuntime)",
            overlayAuthority.map { "authority \($0)" },
            conflictPolicy.map { "conflict policy \($0)" },
            writeBackStatus.map { "write back \($0)" },
            conflictStatusLabel.map { "conflict statuses \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        state: ClawJSRuntimeLensSnapshot.SessionOverlayState
    ) -> ClawJSRuntimeLensSessionOverlayPresentation {
        let allRows = state.overlays ?? []
        let rows = allRows.prefix(3).map { overlay in
            Row(
                id: overlay.id,
                sessionLabel: overlay.sessionId ?? overlay.overlayThreadId ?? "session",
                conflictStatus: overlay.conflictStatus,
                writesRuntime: overlay.writesRuntime,
                authority: overlay.authority,
                pinned: overlay.pinned,
                nativeFound: overlay.nativeFound
            )
        }
        let detailValues = [state.overlayAuthority, state.conflictPolicy, state.writeBackStatus].compactMap { $0 }

        return ClawJSRuntimeLensSessionOverlayPresentation(
            runtimeId: state.runtimeId,
            overlayAuthority: state.overlayAuthority,
            writesRuntime: state.writesRuntime == true,
            writeBackStatus: state.writeBackStatus,
            conflictPolicy: state.conflictPolicy,
            totalOverlays: state.totalOverlays ?? allRows.count,
            totalConflicts: state.totalConflicts ?? allRows.filter { $0.conflictStatus != nil }.count,
            detailLabel: detailValues.isEmpty ? nil : detailValues.joined(separator: ", "),
            conflictStatusLabel: countLabel(allRows.compactMap(\.conflictStatus)),
            rows: rows
        )
    }

    private static func countLabel(_ values: [String]) -> String? {
        let counts = values.reduce(into: [String: Int]()) { result, value in
            result[value, default: 0] += 1
        }
        let pairs = counts.sorted { $0.key < $1.key }
        guard !pairs.isEmpty else { return nil }
        return pairs.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }
}
