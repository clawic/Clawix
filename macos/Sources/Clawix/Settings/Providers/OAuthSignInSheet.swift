import AIProviders
import SwiftUI

/// Hosts `OAuthCoordinator` and shows a spinner while the system web
/// session runs. Closes itself on success or failure.
struct OAuthSignInSheet: View {
    let provider: ProviderDefinition
    let flavor: OAuthFlavor

    @Environment(\.dismiss) private var dismiss
    @StateObject private var flow = OAuthSignInFlowCoordinator()
    @State private var didStart = false

    var body: some View {
        VStack(spacing: 18) {
            ProviderBrandIcon(brand: provider.brand, size: 40)
            Text("Sign in with \(provider.displayName)")
                .font(BodyFont.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            switch flow.state {
            case .running:
                Text("Complete the flow in your browser…")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                ProgressView()
                    .controlSize(.small)
            case .failed(let error):
                Text(error)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Button("Try again") { startFlow() }
                    .buttonStyle(.bordered)
            case .idle:
                Text("A browser window will open shortly.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            case .done:
                Text("Connected.")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Color.green)
            }
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 360)
        .background(Palette.background)
        .onAppear {
            if !didStart {
                didStart = true
                startFlow()
            }
        }
        .onDisappear {
            flow.cancel()
        }
    }

    private func startFlow() {
        flow.start(flavor: flavor) {
            dismiss()
        }
    }
}
