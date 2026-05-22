import Foundation

// MARK: - Rate limits wire types

/// Single rate-limit window (primary or secondary). Mirrors the shape
/// returned under `account/rateLimits/read.rateLimits.primary`.
/// `windowDurationMins` and `resetsAt` are optional because the account
/// endpoint can omit window metadata for non-windowed buckets.
public struct WireRateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Int
    public let resetsAt: Int64?
    public let windowDurationMins: Int64?

    public init(usedPercent: Int, resetsAt: Int64?, windowDurationMins: Int64?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
    }
}

/// Credits balance for the account (overage / pay-per-use). The GUI's
/// Settings → Usage page renders a row when this is non-nil.
public struct WireCreditsSnapshot: Codable, Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

/// One bucket of rate-limit state. The general account view ships with
/// `limitId` may be nil for the general bucket; per-model buckets carry
/// their own id and a human label in `limitName`.
public struct WireRateLimitSnapshot: Codable, Equatable, Sendable {
    public let primary: WireRateLimitWindow?
    public let secondary: WireRateLimitWindow?
    public let credits: WireCreditsSnapshot?
    public let limitId: String?
    public let limitName: String?

    public init(
        primary: WireRateLimitWindow?,
        secondary: WireRateLimitWindow?,
        credits: WireCreditsSnapshot?,
        limitId: String?,
        limitName: String?
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.limitId = limitId
        self.limitName = limitName
    }
}
