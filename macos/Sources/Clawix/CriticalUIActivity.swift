import Foundation

@MainActor
enum CriticalUIActivity {
    private static var lastMarkedAt: Date?

    static func mark(_ name: String) {
        lastMarkedAt = Date()
        RenderProbe.markPassive(
            "CriticalUIActivity",
            fields: ["name": name]
        )
    }

    static func shouldDeferBackgroundWork(now: Date = Date(), graceSeconds: TimeInterval) -> Bool {
        Self.shouldDeferBackgroundWork(
            now: now,
            lastMarkedAt: lastMarkedAt,
            graceSeconds: graceSeconds
        )
    }

    nonisolated static func shouldDeferBackgroundWork(
        now: Date,
        lastMarkedAt: Date?,
        graceSeconds: TimeInterval
    ) -> Bool {
        guard let lastMarkedAt else { return false }
        return now.timeIntervalSince(lastMarkedAt) < graceSeconds
    }
}
