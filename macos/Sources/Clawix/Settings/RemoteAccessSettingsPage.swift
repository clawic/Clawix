import AppKit
import SwiftUI
import ClawixEngine

/// Settings → Remote access. Pairs the Mac with a self-hosted relay
/// coordinator so the iPhone (and other Macs) can reach this host
/// from outside the LAN through MeshKit. The user enters a
/// coordinator URL + their email, requests a magic link, and the page
/// guides them through pasting the resulting token. Everything is
/// opt-in: a Mac without a coordinator configured keeps working
/// exactly as before (LAN + Bonjour + Tailscale).
struct RemoteAccessSettingsPage: View {

    @AppStorage(ClawixPersistentSurfaceKeys.remoteCoordinatorUrl) private var coordinatorUrlString: String = ""
    @AppStorage(ClawixPersistentSurfaceKeys.remoteEmail) private var email: String = ""
    @AppStorage(ClawixPersistentSurfaceKeys.remoteDeviceId) private var savedDeviceId: String = ""
    @AppStorage(ClawixPersistentSurfaceKeys.remoteTenantId) private var savedTenantId: String = ""

    @State private var pasteToken: String = ""
    @StateObject private var store: RemoteAccessSettingsStore

    @MainActor
    init() {
        _store = StateObject(wrappedValue: RemoteAccessSettingsStore())
    }

    @MainActor
    init(store: RemoteAccessSettingsStore) {
        _store = StateObject(wrappedValue: store)
    }

    private var trimmedCoordinatorURL: String {
        coordinatorUrlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        pasteToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var coordinatorURLValid: Bool {
        trimmedCoordinatorURL.isEmpty || RemoteAccessSettingsStore.isCoordinatorURLValid(trimmedCoordinatorURL)
    }

    private var canSendMagicLink: Bool {
        !store.inFlight &&
        RemoteAccessSettingsStore.isCoordinatorURLValid(trimmedCoordinatorURL) &&
        trimmedEmail.contains("@")
    }

    private var canRegisterMac: Bool {
        !store.inFlight &&
        RemoteAccessSettingsStore.isCoordinatorURLValid(trimmedCoordinatorURL) &&
        !trimmedToken.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    coordinatorSection
                    magicLinkSection
                    pairedDeviceSection
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollers()
        }
        .onDisappear { store.cancelInFlight() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Remote access")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Connect this Mac to a self-hosted clawix-relay so the iPhone and other devices can reach you from outside your LAN.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var coordinatorSection: some View {
        sectionCard(title: "Coordinator", subtitle: "Base URL of your relay deployment.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("https://relay.example.com", text: $coordinatorUrlString)
                    .sheetTextFieldStyle()
                    .onChange(of: coordinatorUrlString) { _, newValue in
                        PairingService.shared.coordinatorURL = URL(string: newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                if !coordinatorURLValid {
                    InfoBanner(text: L10n.t("Invalid coordinator URL"), kind: .error)
                }
                Text("Stored locally. Used by this Mac to register itself and by future pairings to embed the URL in the QR.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var magicLinkSection: some View {
        sectionCard(title: "Magic-link sign-in", subtitle: "Request a sign-in link via email. The coordinator opens the link and copies a token back.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("you@example.com", text: $email)
                    .sheetTextFieldStyle()
                HStack(spacing: 8) {
                    IconChipButton(symbol: "paperplane", label: "Send magic link", isPrimary: true) {
                        store.sendMagicLink(
                            coordinatorUrlString: coordinatorUrlString,
                            email: email,
                            deviceLabel: Host.current().localizedName ?? "Mac"
                        )
                    }
                    .disabled(!canSendMagicLink)
                    .opacity(canSendMagicLink ? 1 : 0.45)
                    if store.inFlight { ProgressView().controlSize(.small) }
                }
                CardDivider().padding(.vertical, 4)
                Text("Paste the token from the email confirmation:")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                TextField("mlk_…", text: $pasteToken)
                    .sheetTextFieldStyle()
                IconChipButton(symbol: "laptopcomputer", label: "Register this Mac", isPrimary: true) {
                    store.consumeToken(
                        coordinatorUrlString: coordinatorUrlString,
                        token: pasteToken,
                        deviceLabel: Host.current().localizedName ?? "Mac",
                        platformVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                        irohNodeID: PairingService.shared.irohNodeID
                    ) { session in
                        savedDeviceId = session.deviceId
                        savedTenantId = session.tenantId
                        pasteToken = ""
                        RelayCredentialStore.storeRefreshToken(session.refreshToken, forDeviceId: session.deviceId)
                    }
                }
                .disabled(!canRegisterMac)
                .opacity(canRegisterMac ? 1 : 0.45)
                statusView
            }
        }
    }

    @ViewBuilder
    private var pairedDeviceSection: some View {
        if !savedDeviceId.isEmpty {
            sectionCard(title: "Paired", subtitle: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    pairedRow(label: "Device id", value: savedDeviceId)
                    pairedRow(label: "Tenant", value: savedTenantId)
                    IconChipButton(symbol: "trash", label: "Forget local pairing") {
                        store.forget {
                            savedDeviceId = ""
                            savedTenantId = ""
                        }
                    }
                    .disabled(store.inFlight)
                    .opacity(store.inFlight ? 0.45 : 1)
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.status {
        case .idle:
            EmptyView()
        case .info(let message):
            Text(message)
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .error(let message):
            Text(message)
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pairedRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 11, design: .monospaced))
                .foregroundColor(Palette.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray(light: 0.95, dark: 0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.overlay(0.10), lineWidth: 0.5)
        )
    }
}

@MainActor
final class RemoteAccessSettingsStore: ObservableObject {
    typealias RequestMagicLinkOperation = @MainActor (
        _ baseURL: URL,
        _ email: String,
        _ deviceLabel: String?,
        _ platform: String?
    ) async throws -> Void

    typealias ConsumeMagicLinkOperation = @MainActor (
        _ baseURL: URL,
        _ token: String,
        _ deviceLabel: String?,
        _ platform: String?,
        _ platformVersion: String?,
        _ irohNodeID: String?
    ) async throws -> CoordinatorClient.DeviceSession

    typealias SessionHandler = @MainActor (CoordinatorClient.DeviceSession) -> Void

    enum Status: Equatable {
        case idle
        case info(String)
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var inFlight: Bool = false

    private let requestMagicLinkOperation: RequestMagicLinkOperation
    private let consumeMagicLinkOperation: ConsumeMagicLinkOperation
    private var task: Task<Void, Never>?
    private var generation = 0

    init(
        requestMagicLinkOperation: RequestMagicLinkOperation? = nil,
        consumeMagicLinkOperation: ConsumeMagicLinkOperation? = nil
    ) {
        self.requestMagicLinkOperation = requestMagicLinkOperation ?? { baseURL, email, deviceLabel, platform in
            try await CoordinatorClient(baseURL: baseURL).requestMagicLink(
                email: email,
                deviceLabel: deviceLabel,
                platform: platform
            )
        }
        self.consumeMagicLinkOperation = consumeMagicLinkOperation ?? { baseURL, token, deviceLabel, platform, platformVersion, irohNodeID in
            try await CoordinatorClient(baseURL: baseURL).consumeMagicLink(
                token: token,
                deviceLabel: deviceLabel,
                platform: platform,
                platformVersion: platformVersion,
                irohNodeID: irohNodeID
            )
        }
    }

    deinit {
        task?.cancel()
    }

    @discardableResult
    func sendMagicLink(
        coordinatorUrlString: String,
        email: String,
        deviceLabel: String?,
        platform: String? = "macos"
    ) -> Task<Void, Never>? {
        guard let baseURL = Self.coordinatorURL(from: coordinatorUrlString) else {
            status = .error(L10n.t("Invalid coordinator URL"))
            return nil
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = nextGeneration()
        task?.cancel()
        inFlight = true
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.requestMagicLinkOperation(baseURL, trimmedEmail, deviceLabel, platform)
                try Task.checkCancellation()
                guard self.isCurrent(generation) else { return }
                self.status = .info(String(
                    format: L10n.t("Magic link sent to %@. Open it on this Mac, then paste the token below."),
                    locale: AppLocale.current,
                    trimmedEmail
                ))
            } catch is CancellationError {
            } catch {
                guard self.isCurrent(generation) else { return }
                self.status = .error(Self.failureMessage(
                    for: error,
                    surface: "settings.remoteAccess.sendMagicLink"
                ))
            }
            self.finishIfCurrent(generation)
        }
        self.task = task
        return task
    }

    @discardableResult
    func consumeToken(
        coordinatorUrlString: String,
        token: String,
        deviceLabel: String?,
        platform: String? = "macos",
        platformVersion: String?,
        irohNodeID: String?,
        onSession: @escaping SessionHandler
    ) -> Task<Void, Never>? {
        guard let baseURL = Self.coordinatorURL(from: coordinatorUrlString) else {
            status = .error(L10n.t("Invalid coordinator URL"))
            return nil
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = nextGeneration()
        task?.cancel()
        inFlight = true
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await self.consumeMagicLinkOperation(
                    baseURL,
                    trimmedToken,
                    deviceLabel,
                    platform,
                    platformVersion,
                    irohNodeID
                )
                try Task.checkCancellation()
                guard self.isCurrent(generation) else { return }
                onSession(session)
                self.status = .info(String(
                    format: L10n.t("This Mac is registered as %@. Refresh token stored locally."),
                    locale: AppLocale.current,
                    session.deviceId
                ))
            } catch is CancellationError {
            } catch {
                guard self.isCurrent(generation) else { return }
                self.status = .error(Self.failureMessage(
                    for: error,
                    surface: "settings.remoteAccess.consumeToken"
                ))
            }
            self.finishIfCurrent(generation)
        }
        self.task = task
        return task
    }

    func forget(_ onForget: @MainActor () -> Void) {
        cancelInFlight()
        onForget()
        status = .info(L10n.t("Local pairing forgotten. Revoke the device from the coordinator's Devices page to fully unpair."))
    }

    func cancelInFlight() {
        generation += 1
        task?.cancel()
        task = nil
        inFlight = false
    }

    private static func coordinatorURL(from raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    static func isCoordinatorURLValid(_ raw: String) -> Bool {
        coordinatorURL(from: raw) != nil
    }

    private func nextGeneration() -> Int {
        generation += 1
        return generation
    }

    private func isCurrent(_ value: Int) -> Bool {
        generation == value
    }

    private func finishIfCurrent(_ value: Int) {
        guard isCurrent(value) else { return }
        inFlight = false
        task = nil
    }

    private static func failureMessage(for error: Error, surface: String) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return UserFacingFailure.displayMessage(for: message, surface: surface)
    }
}

private enum RelayCredentialStore {
    /// Persist the refresh token using the standard defaults suite.
    /// Long-term storage moves into the bridge daemon, which owns the
    /// credential lifecycle for both the GUI and the CLI; this entry
    /// point is intentionally lightweight so the settings page can be
    /// built without pulling in the keychain.
    static func storeRefreshToken(_ token: String, forDeviceId deviceId: String) {
        UserDefaults.standard.set(token, forKey: ClawixPersistentSurfaceKeys.relayRefreshKey(for: deviceId))
    }
}
