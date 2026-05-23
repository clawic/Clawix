import SwiftUI

// MARK: - Usage limit bar
//
// A quiet, functional notice shown above the composer when the account is
// close to or at a usage-window limit. It reads the rate-limit state the
// backend already reports (no network of its own), surfaces the most-consumed
// window with its reset time, and can be dismissed until usage climbs further.
// This is an informational state indicator, not an upsell.

struct UsageLimitBar: View {
    @EnvironmentObject private var appState: AppState
    @State private var dismissedAtPercent: Int = 0

    private struct Worst {
        let percent: Int
        let windowMins: Int64?
        let resetsAt: Int64?
    }

    private var worst: Worst? {
        var candidates: [Worst] = []
        if let p = appState.rateLimits?.primary {
            candidates.append(Worst(percent: p.usedPercent, windowMins: p.windowDurationMins, resetsAt: p.resetsAt))
        }
        if let s = appState.rateLimits?.secondary {
            candidates.append(Worst(percent: s.usedPercent, windowMins: s.windowDurationMins, resetsAt: s.resetsAt))
        }
        return candidates.max(by: { $0.percent < $1.percent })
    }

    private var shouldShow: Bool {
        guard let worst else { return false }
        if worst.percent >= 100 { return true } // always surface a reached limit
        return worst.percent >= 90 && worst.percent > dismissedAtPercent
    }

    var body: some View {
        if shouldShow, let worst {
            let reached = worst.percent >= 100
            let accent = reached
                ? Palette.danger
                : Palette.warning
            HStack(spacing: 8) {
                LucideIcon(.triangleAlert, size: 12)
                    .foregroundColor(accent)
                Text(message(worst, reached: reached))
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textPrimary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !reached {
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { dismissedAtPercent = worst.percent }
                    } label: {
                        XIcon(size: 10)
                            .foregroundColor(Color.overlay(0.5))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Dismiss"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.22), lineWidth: Palette.popupStrokeWidth)
            )
            .padding(.horizontal, 4)
            .transition(.opacity)
        }
    }

    private func message(_ worst: Worst, reached: Bool) -> String {
        let window = windowLabel(worst.windowMins)
        let reset = resetSuffix(worst.resetsAt)
        if reached {
            return "\(L10n.t("Usage limit reached"))\(window.isEmpty ? "" : " · \(window)")\(reset)"
        }
        return "\(worst.percent)% \(L10n.t("of your usage limit"))\(window.isEmpty ? "" : " · \(window)")\(reset)"
    }

    private func windowLabel(_ mins: Int64?) -> String {
        guard let mins, mins > 0 else { return "" }
        if mins % (60 * 24) == 0 { return "\(mins / (60 * 24))d" }
        if mins % 60 == 0 { return "\(mins / 60)h" }
        return "\(mins)m"
    }

    private func resetSuffix(_ resetsAt: Int64?) -> String {
        guard let resetsAt, resetsAt > 0 else { return "" }
        let seconds = resetsAt > 1_000_000_000_000 ? Double(resetsAt) / 1000.0 : Double(resetsAt)
        let remaining = Int(Date(timeIntervalSince1970: seconds).timeIntervalSinceNow)
        guard remaining > 0 else { return "" }
        let hours = remaining / 3600
        if hours >= 1 { return " · \(L10n.t("resets in")) \(hours)h" }
        return " · \(L10n.t("resets in")) \(max(1, remaining / 60))m"
    }
}
