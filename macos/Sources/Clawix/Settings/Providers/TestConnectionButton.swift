import AIProviders
import SwiftUI

/// "Test connection" button used in `AddAccountSheet` and
/// `EditAccountSheet`. Defaults to the hermetic validation path so
/// app validation does not call real providers unless the caller opts
/// into an approved live probe.
struct TestConnectionButton: View {
    let providerId: ProviderID
    let apiKey: String
    let baseURL: URL?

    @StateObject private var probe: ProviderConnectionProbe

    init(
        providerId: ProviderID,
        apiKey: String,
        baseURL: URL?,
        validationMode: ProviderValidationMode = .hermeticFixture
    ) {
        self.providerId = providerId
        self.apiKey = apiKey
        self.baseURL = baseURL
        _probe = StateObject(wrappedValue: ProviderConnectionProbe(mode: validationMode))
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: run) {
                HStack(spacing: 6) {
                    LucideIcon.auto(stateIcon, size: 11)
                    Text("Test connection")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(probe.state == .running)

            statusLabel
        }
        .onDisappear {
            probe.cancel()
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch probe.state {
        case .idle:
            EmptyView()
        case .running:
            Text("Testing…")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
        case .completed(let report):
            HStack(spacing: 4) {
                Circle().fill(statusColor(for: report)).frame(width: 6, height: 6)
                Text(report.uiStatusText)
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(statusColor(for: report))
                    .lineLimit(2)
            }
        }
    }

    private var stateIcon: String {
        switch probe.state {
        case .completed(let report) where report.isComplete:
            return "check"
        case .completed(let report) where report.providerError != nil:
            return "x"
        case .completed:
            return "clock"
        default: return "zap"
        }
    }

    private func statusColor(for report: ProviderValidationReport) -> Color {
        if report.isComplete {
            return Color.green
        }
        if report.providerError != nil || report.disposition == .blocked {
            return Color.red.opacity(0.9)
        }
        return Color.yellow.opacity(0.9)
    }

    private func run() {
        probe.run(providerId: providerId, apiKey: apiKey, baseURL: baseURL)
    }
}
