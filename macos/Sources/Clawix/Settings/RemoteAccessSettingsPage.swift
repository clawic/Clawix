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
                .font(.system(size: 18, weight: .semibold))
            Text("Connect this Mac to a self-hosted clawix-relay so the iPhone and other devices can reach you from outside your LAN.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var coordinatorSection: some View {
        sectionCard(title: "Coordinator", subtitle: "Base URL of your relay deployment.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("https://relay.example.com", text: $coordinatorUrlString)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: coordinatorUrlString) { _, newValue in
                        PairingService.shared.coordinatorURL = URL(string: newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                Text("Stored locally. Used by this Mac to register itself and by future pairings to embed the URL in the QR.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var magicLinkSection: some View {
        sectionCard(title: "Magic-link sign-in", subtitle: "Request a sign-in link via email. The coordinator opens the link and copies a token back.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Send magic link") {
                        store.sendMagicLink(
                            coordinatorUrlString: coordinatorUrlString,
                            email: email,
                            deviceLabel: Host.current().localizedName ?? "Mac"
                        )
                    }
                    .disabled(store.inFlight || coordinatorUrlString.isEmpty || !email.contains("@"))
                    if store.inFlight { ProgressView().controlSize(.small) }
                }
                Divider().padding(.vertical, 4)
                Text("Paste the token from the email confirmation:")
                    .font(.system(size: 12))
                TextField("mlk_…", text: $pasteToken)
                    .textFieldStyle(.roundedBorder)
                Button("Register this Mac") {
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
                .disabled(store.inFlight || pasteToken.isEmpty)
                statusView
            }
        }
    }

    @ViewBuilder
    private var pairedDeviceSection: some View {
        if !savedDeviceId.isEmpty {
            sectionCard(title: "Paired", subtitle: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Device id") { Text(savedDeviceId).font(.system(size: 11, design: .monospaced)) }
                    LabeledContent("Tenant") { Text(savedTenantId).font(.system(size: 11, design: .monospaced)) }
                    Button("Forget this Mac on the coordinator") {
                        store.forget {
                            savedDeviceId = ""
                            savedTenantId = ""
                        }
                    }
                    .controlSize(.small)
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .error(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
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
            status = .error("Invalid coordinator URL")
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
                self.status = .info("Magic link sent to \(trimmedEmail). Open it on this Mac, then paste the token below.")
            } catch is CancellationError {
            } catch {
                guard self.isCurrent(generation) else { return }
                self.status = .error(error.localizedDescription)
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
            status = .error("Invalid coordinator URL")
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
                self.status = .info("This Mac is registered as \(session.deviceId). Refresh token stashed locally.")
            } catch is CancellationError {
            } catch {
                guard self.isCurrent(generation) else { return }
                self.status = .error(error.localizedDescription)
            }
            self.finishIfCurrent(generation)
        }
        self.task = task
        return task
    }

    func forget(_ onForget: @MainActor () -> Void) {
        cancelInFlight()
        onForget()
        status = .info("Local pairing forgotten. Revoke the device from the coordinator's Devices page to fully unpair.")
    }

    func cancelInFlight() {
        generation += 1
        task?.cancel()
        task = nil
        inFlight = false
    }

    private static func coordinatorURL(from raw: String) -> URL? {
        URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
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
