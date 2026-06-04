import SwiftUI

// MARK: - Status panel
//
// A compact read-out of the current session: which chat is active, how full
// the context window is, the active model, and the account's usage limits when
// the backend has reported them. Opened via the `/status` composer command.

struct StatusPanel: View {
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    /// Observe the focused rate-limit store directly so a status refresh
    /// re-renders the limits section without fanning out through the AppState
    /// god-object (P4).
    @ObservedObject private var rateLimits: RateLimitStore

    init(rateLimitStore: RateLimitStore, onClose: @escaping () -> Void) {
        self.rateLimits = rateLimitStore
        self.onClose = onClose
    }

    private var chatIdShort: String? {
        if case let .chat(id) = appState.currentRoute {
            return String(id.uuidString.prefix(8)).lowercased()
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("Status"))
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { onClose() } label: {
                    XIcon(size: 12)
                        .foregroundColor(Color.overlay(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle().fill(Color.overlay(0.06)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(L10n.t("Session")) {
                        infoRow(L10n.t("Chat"), chatIdShort ?? L10n.t("New chat"))
                        infoRow(L10n.t("Project"), appState.selectedProject?.name ?? L10n.t("None"))
                    }

                    if let usage = appState.currentContextUsage {
                        contextSection(usage)
                    }

                    section(L10n.t("Model")) {
                        infoRow(L10n.t("Model"), "\(appState.selectedModel) · \(appState.selectedIntelligence.label)")
                        infoRow(L10n.t("Speed"), appState.selectedSpeed == .fast ? L10n.t("Fast") : L10n.t("Standard"))
                    }

                    section(L10n.t("Mode")) {
                        infoRow(L10n.t("Permissions"), appState.permissionMode.label)
                        infoRow(L10n.t("Plan mode"), appState.planMode ? L10n.t("On") : L10n.t("Off"))
                    }

                    if let limits = rateLimits.rateLimits {
                        limitsSection(limits)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 380, height: 440)
        .background(Palette.background)
    }

    // MARK: - Sections

    @ViewBuilder
    private func contextSection(_ usage: ContextUsage) -> some View {
        section(L10n.t("Context")) {
            if let window = usage.contextWindow, window > 0 {
                let pct = Int((1.0 - usage.usedFraction) * 100)
                infoRow(L10n.t("Left"), "\(pct)%  ·  \(short(usage.usedTokens))/\(short(window))")
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.overlay(0.08))
                        Capsule()
                            .fill(usage.usedFraction > 0.9 ? Palette.warning : Palette.pastelBlue)
                            .frame(width: max(2, proxy.size.width * usage.usedFraction))
                    }
                }
                .frame(height: 3)
                .padding(.top, 2)
            } else {
                infoRow(L10n.t("Used"), short(usage.usedTokens))
            }
        }
    }

    @ViewBuilder
    private func limitsSection(_ limits: RateLimitSnapshot) -> some View {
        section(L10n.t("Usage limits")) {
            if let primary = limits.primary {
                infoRow(limitLabel(primary), "\(primary.usedPercent)%\(resetSuffix(primary))")
            }
            if let secondary = limits.secondary {
                infoRow(limitLabel(secondary), "\(secondary.usedPercent)%\(resetSuffix(secondary))")
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
            content()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
            Spacer()
            Text(value)
                .font(BodyFont.system(size: 12.5, design: .monospaced))
                .foregroundColor(Palette.textPrimary.opacity(0.9))
                .monospacedDigit()
        }
    }

    private func limitLabel(_ window: RateLimitWindow) -> String {
        guard let mins = window.windowDurationMins, mins > 0 else { return L10n.t("Limit") }
        if mins % (60 * 24) == 0 { return "\(mins / (60 * 24))d" }
        if mins % 60 == 0 { return "\(mins / 60)h" }
        return "\(mins)m"
    }

    private func resetSuffix(_ window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt, resetsAt > 0 else { return "" }
        // Accept either seconds or milliseconds since epoch.
        let seconds = resetsAt > 1_000_000_000_000 ? Double(resetsAt) / 1000.0 : Double(resetsAt)
        let remaining = Int(Date(timeIntervalSince1970: seconds).timeIntervalSinceNow)
        guard remaining > 0 else { return "" }
        let hours = remaining / 3600
        if hours >= 1 { return "  ·  \(L10n.t("resets in")) \(hours)h" }
        return "  ·  \(L10n.t("resets in")) \(max(1, remaining / 60))m"
    }

    private func short(_ n: Int64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
