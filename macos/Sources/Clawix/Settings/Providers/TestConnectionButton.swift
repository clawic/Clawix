import AIProviders
import SwiftUI

/// "Test connection" button used in `AddAccountSheet` and
/// `EditAccountSheet`. Builds an `AIClient` from the provided draft
/// and runs `testConnection()`. Result is shown inline.
struct TestConnectionButton: View {
    let providerId: ProviderID
    let apiKey: String
    let baseURL: URL?

    @StateObject private var probe = ProviderConnectionProbe()

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
        case .ok:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Connected")
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Color.green)
            }
        case .failed(let detail):
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(detail)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Color.red.opacity(0.9))
                    .lineLimit(2)
            }
        }
    }

    private var stateIcon: String {
        switch probe.state {
        case .ok: return "check"
        case .failed: return "x"
        default: return "zap"
        }
    }

    private func run() {
        probe.run(providerId: providerId, apiKey: apiKey, baseURL: baseURL)
    }
}
