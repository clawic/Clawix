import AIProviders
import SwiftUI

/// Right-hand-side pane shown when the user has selected one provider
/// from the list. Hosts the master toggle, the accounts section, and
/// the catalog of models.
struct ProviderDetailPane: View {
    let provider: ProviderDefinition
    let onBack: () -> Void

    @StateObject private var store = AIAccountStoreObservable.shared
    @State private var addAPIKeyPresented = false
    @State private var oauthPresented: OAuthFlavorBox?
    @State private var devicePresented: DeviceCodeFlavorBox?
    @State private var editingAccount: ProviderAccount?

    @State private var providerEnabled: Bool
    @State private var providerToggleSaving = false
    @State private var providerToggleUnavailable = false
    @State private var providerToggleError: String?

    init(provider: ProviderDefinition, onBack: @escaping () -> Void) {
        self.provider = provider
        self.onBack = onBack
        self._providerEnabled = State(initialValue: FeatureRouting.isProviderEnabled(provider.id))
    }

    private var accounts: [ProviderAccount] {
        store.accounts(for: provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumbHeader
            providerHeader
            mainToggle
            AccountListSection(
                provider: provider,
                accounts: accounts,
                onAddAPIKey: { addAPIKeyPresented = true },
                onSignIn: { oauthPresented = OAuthFlavorBox(flavor: $0) },
                onSignInDeviceCode: { devicePresented = DeviceCodeFlavorBox(flavor: $0) },
                onEdit: { editingAccount = $0 }
            )
            .padding(.top, 8)
            if let error = store.lastError {
                InfoBanner(text: error, kind: .error)
                    .padding(.top, 12)
            }
            ProviderModelsSection(provider: provider)
                .padding(.top, 12)
            if let notes = provider.notes {
                InfoBanner(text: notes, kind: .ok)
                    .padding(.top, 16)
            }
        }
        .sheet(isPresented: $addAPIKeyPresented) {
            AddAccountSheet(provider: provider) { _ in
                store.refresh()
            }
        }
        .sheet(item: $oauthPresented) { box in
            OAuthSignInSheet(provider: provider, flavor: box.flavor)
        }
        .sheet(item: $devicePresented) { box in
            DeviceCodeSignInSheet(provider: provider, flavor: box.flavor)
        }
        .sheet(item: $editingAccount) { account in
            EditAccountSheet(account: account, provider: provider)
        }
        .onAppear {
            reloadProviderEnabled()
        }
    }

    private var breadcrumbHeader: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                LucideIcon.auto("chevron-left", size: 11)
                Text("Model Providers")
                    .font(BodyFont.system(size: 12, wght: 500))
            }
            .foregroundColor(Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
    }

    private var providerHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ProviderBrandIcon(brand: provider.brand, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.displayName)
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(provider.tagline)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
                Link("Documentation", destination: provider.docsURL)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.bottom, 22)
    }

    private var mainToggle: some View {
        SettingsCard {
            ToggleRow(
                title: "Enable provider",
                detail: "When off, this provider is hidden from feature dropdowns even if accounts are configured.",
                isOn: Binding(
                    get: { providerEnabled },
                    set: { setProviderEnabled($0) }
                )
            )
            .disabled(providerToggleSaving || providerToggleUnavailable)
            if providerToggleSaving {
                CardDivider()
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving provider state…")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            if let providerToggleError {
                CardDivider()
                InfoBanner(text: providerToggleError, kind: .error)
                    .padding(14)
            }
        }
        .padding(.bottom, 8)
    }

    private func reloadProviderEnabled() {
        do {
            providerEnabled = try FeatureRouting.providerEnabled(provider.id)
            providerToggleUnavailable = false
            providerToggleError = nil
        } catch {
            providerToggleUnavailable = true
            providerToggleError = providerStateErrorMessage(
                key: "Provider state is unavailable: %@",
                error: error,
                surface: "settings.providers.providerToggle.reload"
            )
        }
    }

    private func setProviderEnabled(_ enabled: Bool) {
        guard enabled != providerEnabled, !providerToggleSaving else { return }
        let previous = providerEnabled
        providerEnabled = enabled
        providerToggleSaving = true
        providerToggleError = nil
        Task { @MainActor in
            do {
                try FeatureRouting.setProviderEnabledOrThrow(provider.id, enabled: enabled)
                providerEnabled = try FeatureRouting.providerEnabled(provider.id)
                providerToggleUnavailable = false
            } catch {
                providerEnabled = previous
                providerToggleUnavailable = false
                providerToggleError = providerStateErrorMessage(
                    key: "Provider state was not saved: %@",
                    error: error,
                    surface: "settings.providers.providerToggle.save"
                )
            }
            providerToggleSaving = false
        }
    }

    private func providerStateErrorMessage(key: String.LocalizationValue, error: Error, surface: String) -> String {
        let message = UserFacingFailure.displayMessage(for: error.localizedDescription, surface: surface)
        return String(format: L10n.t(key), locale: AppLocale.current, message)
    }
}

// SwiftUI `.sheet(item:)` needs `Identifiable`. We'd add the
// conformance to the AIProviders types directly, but the compiler
// rightly warns about retroactive conformance on imported types
// (it'd silently break if the package later adopts Identifiable).
// Wrapping in tiny local IdBox structs avoids the warning.
private struct OAuthFlavorBox: Identifiable, Equatable {
    let flavor: OAuthFlavor
    var id: String { flavor.rawValue }
}
private struct DeviceCodeFlavorBox: Identifiable, Equatable {
    let flavor: DeviceCodeFlavor
    var id: String { flavor.rawValue }
}
