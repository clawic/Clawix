import Foundation

struct ClawJSRuntimeLensViewStatePresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let kind: String
        let message: String
        let severity: String

        var accessibilityLabel: String {
            "runtime lens state \(kind), severity \(severity), message \(message)"
        }
    }

    let runtimeId: String
    let runtimeLabel: String
    let hasSnapshot: Bool
    let isRefreshing: Bool
    let hasLoadError: Bool
    let hasActionError: Bool
    let rowCount: Int
    let rows: [Row]

    var hasRows: Bool {
        !rows.isEmpty
    }

    var accessibilityLabel: String {
        [
            "Runtime lens view state",
            runtimeLabel,
            "snapshot \(hasSnapshot)",
            "refreshing \(isRefreshing)",
            "load error \(hasLoadError)",
            "action error \(hasActionError)",
            "rows \(rowCount)"
        ]
        .joined(separator: ", ")
    }

    static func make(
        runtime: ClawJSRuntimeLensID,
        isRefreshing: Bool,
        loadError: String?,
        actionError: String?,
        hasSnapshot: Bool
    ) -> ClawJSRuntimeLensViewStatePresentation {
        var rows: [Row] = []
        if isRefreshing {
            rows.append(Row(
                id: "refreshing",
                kind: "refreshing",
                message: "Refreshing",
                severity: "status"
            ))
        }
        if let message = normalized(loadError) {
            rows.append(Row(
                id: "load-error",
                kind: "load_error",
                message: message,
                severity: "warning"
            ))
        }
        if let message = normalized(actionError) {
            rows.append(Row(
                id: "action-error",
                kind: "action_error",
                message: message,
                severity: "warning"
            ))
        }
        if !hasSnapshot && !isRefreshing && normalized(loadError) == nil {
            rows.append(Row(
                id: "empty",
                kind: "empty",
                message: "\(runtime.label) snapshot pending",
                severity: "status"
            ))
        }

        return ClawJSRuntimeLensViewStatePresentation(
            runtimeId: runtime.rawValue,
            runtimeLabel: runtime.label,
            hasSnapshot: hasSnapshot,
            isRefreshing: isRefreshing,
            hasLoadError: normalized(loadError) != nil,
            hasActionError: normalized(actionError) != nil,
            rowCount: rows.count,
            rows: rows
        )
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
