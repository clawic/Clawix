import Foundation

struct ClawJSRuntimeLensSessionInventoryPresentation: Equatable {
    let projectedCount: Int
    let visibleCount: Int
    let hasInventoryError: Bool
    let inventoryError: String?
    let statusLabel: String
    let detailLabel: String?

    var accessibilityLabel: String {
        [
            "Runtime session inventory",
            "status \(statusLabel)",
            "projected \(projectedCount)",
            "visible \(visibleCount)",
            "inventory error \(hasInventoryError)",
            inventoryError.map { "error \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        bucket: ClawJSRuntimeLensSnapshot.DomainData.SessionBucket
    ) -> ClawJSRuntimeLensSessionInventoryPresentation {
        let resources = bucket.sessions ?? []
        let projected = bucket.totalProjected ?? resources.count
        let error = normalizedInventoryError(bucket.inventoryError)

        return ClawJSRuntimeLensSessionInventoryPresentation(
            projectedCount: projected,
            visibleCount: resources.count,
            hasInventoryError: error != nil,
            inventoryError: error,
            statusLabel: error == nil ? "projected" : "degraded",
            detailLabel: error
        )
    }

    private static func normalizedInventoryError(_ error: String?) -> String? {
        guard let error else { return nil }
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
