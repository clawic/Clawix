import SwiftUI
import ClawixEngine
import KeyboardShortcuts

// MARK: - Model row

struct DictationModelRow: View {
    let model: DictationModel
    @ObservedObject var store: DictationModelStore
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        if store.activeModel == model {
                            Text("Active")
                                .font(BodyFont.system(size: 10, wght: 700))
                                .foregroundColor(Palette.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(red: 0.16, green: 0.46, blue: 0.98))
                                )
                        }
                    }
                    Text(sizeLabel)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }

                Spacer(minLength: 12)

                trailingControl
            }

            if let error = store.downloadErrors[model] {
                Text(error)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var sizeLabel: LocalizedStringKey {
        let gb = Double(model.approximateBytes) / 1_000_000_000
        return "~\(String(format: "%.1f", gb)) GB on disk"
    }

    @ViewBuilder
    private var trailingControl: some View {
        let installed = store.installedModels.contains(model)
        let downloading = store.isDownloading(model)
        let deleting = store.isDeleting(model)
        if deleting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
                Text("Deleting…")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textSecondary)
            }
        } else if downloading {
            HStack(spacing: 10) {
                DSPDownloadProgressBar(value: store.downloadProgress[model] ?? 0)
                DSPSecondaryButton(label: "Cancel") {
                    store.cancel(model)
                }
            }
        } else if installed {
            HStack(spacing: 8) {
                if store.activeModel != model {
                    DSPSecondaryButton(label: "Use") {
                        store.setActive(model)
                    }
                }
                DSPSecondaryButton(label: "Delete") {
                    requestDeleteConfirmation()
                }
            }
        } else {
            DSPSecondaryButton(label: "Download") {
                store.download(model)
            }
        }
    }

    private func requestDeleteConfirmation() {
        let gb = String(format: "%.1f", Double(model.approximateBytes) / 1_000_000_000)
        let body = LocalizedStringKey(
            "\(model.displayName) will be removed from disk (~\(gb) GB freed). You can re-download it any time. This cannot be undone."
        )
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Delete this model?",
            body: body,
            confirmLabel: "Delete",
            isDestructive: true,
            onConfirm: { [model, store] in
                store.delete(model)
            }
        )
    }
}

// MARK: - Permission row

struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let status: DictationPermissions.Status
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .granted:
            Text("Granted")
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
        case .notDetermined:
            DSPSecondaryButton(label: "Request Access", action: request)
        case .denied, .restricted, .revoked:
            DSPSecondaryButton(label: "Open Settings", action: openSettings)
        }
    }

    private var dotColor: Color {
        switch status {
        case .granted:       return Palette.success
        case .denied, .restricted, .revoked:
            return Palette.danger
        case .notDetermined: return Color.gray(light: 0.45, dark: 0.55)
        }
    }
}

// MARK: - Local building blocks (page-private)

/// Capsule-on-capsule progress bar so the inner fill keeps its rounded
/// ends instead of inheriting the half-circle look the default
/// `ProgressView(value:)` falls into at low percentages on macOS.
///
/// WhisperKit's progress callback fires once per network chunk, so the
/// raw `value` lands in visible jumps. The fill width is animated with
/// an `easeInOut` curve to interpolate between those steps and keep the
/// motion continuous instead of stuttering.
struct DSPDownloadProgressBar: View {
    let value: Double

    private let trackWidth: CGFloat = 90
    private let trackHeight: CGFloat = 7

    var body: some View {
        let clamped = min(max(value, 0), 1)
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.overlay(0.10))
            Capsule(style: .continuous)
                // Progress fill, not a surface: high-contrast neutral that
                // reads on the track in both modes (a literal white fill
                // disappears against the light-mode track).
                .fill(Color.gray(light: 0.32, dark: 0.95))
                .frame(width: max(trackHeight, trackWidth * clamped))
                .opacity(clamped > 0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: clamped)
        }
        .frame(width: trackWidth, height: trackHeight)
    }
}

struct DSPSecondaryButton: View {
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(hovered ? Color.gray(light: 0.875, dark: 0.21) : Color.gray(light: 0.915, dark: 0.165))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Microphone selector

/// Lists every input device Core Audio sees, with the active one
/// shown as the dropdown's current value. Selecting an entry promotes
/// it to the head of the persisted preferred list, so reconnecting
/// that device on a future launch re-binds dictation to it
/// automatically.
struct MicrophoneSelectorRow: View {
    @ObservedObject var micPrefs: MicrophonePreferences
    @ObservedObject var dictation: DictationCoordinator
    let micPermission: DictationPermissions.Status

    @StateObject private var meter = MicLevelMeterModel()

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Microphone")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            if micPrefs.devices.isEmpty {
                Text("No input devices")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            } else {
                SettingsDropdown(
                    options: dropdownOptions,
                    selection: dropdownBinding,
                    trailingAccessory: {
                        AnyView(
                            MicLevelTinyMeter(meter: meter, active: isMeterActive)
                        )
                    }
                )
            }
        }
        .liftWhenSettingsDropdownOpen()
        .onAppear { syncCapture() }
        .onDisappear { meter.stop() }
        .onChange(of: micPrefs.activeUID) { _, _ in restartCapture() }
        .onChange(of: dictation.state) { _, _ in syncCapture() }
        .onChange(of: micPermission) { _, _ in syncCapture() }
    }

    private var isMeterActive: Bool {
        micPermission == .granted && dictation.state == .idle
    }

    private func syncCapture() {
        if isMeterActive {
            meter.start(deviceID: micPrefs.activeDeviceID())
        } else {
            meter.stop()
        }
    }

    private func restartCapture() {
        meter.stop()
        // AVAudioEngine needs the input node fully torn down before a
        // new device can be bound; 60 ms is the empirical floor that
        // avoids "device in use" on built-in mics without being
        // perceptible to the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if isMeterActive {
                meter.start(deviceID: micPrefs.activeDeviceID())
            }
        }
    }

    private var dropdownOptions: [(String, String)] {
        micPrefs.devices.map { ($0.uid, $0.name) }
    }

    private var dropdownBinding: Binding<String> {
        Binding(
            get: { micPrefs.activeUID ?? "" },
            set: { uid in
                guard !uid.isEmpty else { return }
                micPrefs.selectPreferred(uid: uid)
            }
        )
    }

    private var detailText: LocalizedStringKey {
        "Auto-switches to your last preferred mic when it reconnects; falls back to the system default otherwise"
    }
}

// MARK: - Hotkey observable wrapper

/// `DictationHotkeyMonitor` keeps its mode/trigger in `UserDefaults` so the
/// daemon and the GUI can read the same source of truth, but Settings
/// needs a `@Published` surface for SwiftUI to re-render on change.
/// This thin wrapper republishes whenever the bound `@AppStorage`
/// values move.
@MainActor
final class DictationHotkeySettingsStore: ObservableObject {
    static let shared = DictationHotkeySettingsStore()

    // Slot 1
    @Published var mode: DictationHotkeyMode {
        didSet { DictationHotkeyMonitor.shared.mode = mode }
    }
    @Published var trigger: DictationHotkeyTrigger {
        didSet {
            let previous = oldValue
            DictationHotkeyMonitor.shared.trigger = trigger
            // When the user turns the hotkey on from Settings, drive
            // the Input Monitoring TCC flow explicitly so the consent
            // dialog appears with this Settings sheet on screen. The
            // trigger setter already retries `register()` after we
            // set it, but `register()` silently skips the global
            // monitor on `.notDetermined`/`.denied`. The explicit
            // request below is what surfaces the prompt and/or sends
            // the user to System Settings.
            if previous == .off, trigger != .off {
                DictationHotkeyMonitor.shared.requestPermissionAndRegister(
                    coordinator: DictationCoordinator.shared
                )
            }
        }
    }

    // Slot 2 (optional second binding, opt-in)
    @Published var mode2: DictationHotkeyMode {
        didSet { DictationHotkeyMonitor.shared.mode2 = mode2 }
    }
    @Published var trigger2: DictationHotkeyTrigger {
        didSet {
            let previous = oldValue
            DictationHotkeyMonitor.shared.trigger2 = trigger2
            if previous == .off, trigger2 != .off {
                DictationHotkeyMonitor.shared.requestPermissionAndRegister(
                    coordinator: DictationCoordinator.shared
                )
            }
        }
    }

    private init() {
        self.mode = DictationHotkeyMonitor.shared.mode
        self.trigger = DictationHotkeyMonitor.shared.trigger
        self.mode2 = DictationHotkeyMonitor.shared.mode2
        self.trigger2 = DictationHotkeyMonitor.shared.trigger2
    }
}
