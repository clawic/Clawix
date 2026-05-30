import SwiftUI

enum SettingsLimitsFormatter {
    static func windowLabel(for window: RateLimitWindow) -> String {
        guard let mins = window.windowDurationMins, mins > 0 else { return "" }
        if mins == 10080 {
            return String(localized: "Weekly", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 1440 {
            return String(localized: "Daily", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins % 60 == 0 {
            return "\(mins / 60)h"
        }
        return "\(mins)min"
    }

    static func percentLabel(for window: RateLimitWindow) -> String {
        "\(window.usedPercent)%"
    }

    static func resetLabel(for window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        if Calendar.current.isDateInToday(date) {
            // Force 24h "HH:mm" regardless of locale's AM/PM convention.
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        }
        return formatter.string(from: date)
    }

    /// Long-form variant used by the Settings → Usage page.
    static func detailedWindowLabel(for window: RateLimitWindow) -> String {
        guard let mins = window.windowDurationMins, mins > 0 else {
            return String(localized: "Usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 10080 {
            return String(localized: "Weekly usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 1440 {
            return String(localized: "Daily usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins % 60 == 0 {
            let template = String(localized: "%lld-hour usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
            return String(format: template, locale: AppLocale.current, Int(mins / 60))
        }
        let template = String(localized: "%lld-minute usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, locale: AppLocale.current, Int(mins))
    }

    /// Long-form reset label, e.g. "Resets at 18:39" / "Resets on 5 mayo".
    static func detailedResetLabel(for window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        if Calendar.current.isDateInToday(date) {
            // Force 24h "HH:mm" regardless of locale's AM/PM convention.
            formatter.dateFormat = "HH:mm"
            let template = String(localized: "Resets at %@", bundle: AppLocale.bundle, locale: AppLocale.current)
            return String(format: template, formatter.string(from: date))
        }
        // Full month name (MMMM) so Spanish reads "5 mayo" instead of "5 may.".
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        let template = String(localized: "Resets on %@", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, formatter.string(from: date))
    }

    static func perModelSectionTitle(name: String) -> String {
        let template = String(localized: "Usage limits for %@", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, name)
    }

    static func creditTitle(for credits: CreditsSnapshot) -> String {
        if credits.unlimited {
            return String(localized: "Unlimited credit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        let balance = credits.balance ?? "0"
        let template = String(localized: "%@ credit remaining", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, balance)
    }
}
