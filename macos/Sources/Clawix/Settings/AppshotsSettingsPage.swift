import SwiftUI
import AppKit

/// Settings → Appshots. Mirrors the appshot surface: an enable toggle with
/// the descriptive card copy, the double-modifier hotkey picker, and the
/// permissions appshots depend on (screen pixels, window text, the global
/// trigger).
struct AppshotsSettingsPage: View {
    @AppStorage(AppshotSettings.enabledKey) private var enabled = false
    @AppStorage(AppshotSettings.hotkeyKey) private var hotkeyRaw = AppshotHotkey.commandCommand.rawValue

    @State private var screenRecordingStatus = NativeMacPermissionBroker.status(for: .screenRecording)
    @State private var accessibilityStatus = NativeMacPermissionBroker.status(for: .accessibility)
    @State private var inputMonitoringStatus = NativeMacPermissionBroker.status(for: .inputMonitoring)
    @State private var appshotSettingsMessage: String?

    private var captureBlockedReason: String? {
        if let reason = screenRecordingStatus.blockedReason {
            return "Screen Recording: \(reason)"
        }
        if let reason = accessibilityStatus.blockedReason {
            return "Accessibility: \(reason)"
        }
        return nil
    }

    private var hotkeyBlockedReason: String? {
        guard hotkeyBinding.wrappedValue != .none,
              let reason = inputMonitoringStatus.blockedReason else {
            return nil
        }
        return "Input Monitoring: \(reason)"
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            enabled
        } set: { newValue in
            if newValue, let reason = captureBlockedReason {
                enabled = false
                appshotSettingsMessage = String(
                    format: L10n.t("Appshots are blocked until permission is granted. %@"),
                    locale: AppLocale.current,
                    reason
                )
                AppshotHotkeyMonitor.shared.refreshRegistration()
                return
            }
            enabled = newValue
            appshotSettingsMessage = nil
            AppshotHotkeyMonitor.shared.refreshRegistration()
        }
    }

    private var hotkeyBinding: Binding<AppshotHotkey> {
        Binding {
            AppshotHotkey(rawValue: hotkeyRaw) ?? .commandCommand
        } set: { newValue in
            hotkeyRaw = newValue.rawValue
            if newValue != .none, let reason = hotkeyBlockedReason {
                appshotSettingsMessage = String(
                    format: L10n.t("The global appshot hotkey is inactive until permission is granted. %@"),
                    locale: AppLocale.current,
                    reason
                )
            } else if appshotSettingsMessage?.hasPrefix("The global appshot hotkey is inactive") == true {
                appshotSettingsMessage = nil
            }
            AppshotHotkeyMonitor.shared.refreshRegistration()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Appshots",
                subtitle: "Attach your frontmost window to Clawix, including text scrolled offscreen."
            )

            SectionLabel(title: "Appshots")
            SettingsCard {
                ToggleRow(
                    title: "Enable appshots",
                    detail: "Take an appshot to show Clawix your frontmost window. Appshots include visual and text content, including text scrolled offscreen.",
                    isOn: enabledBinding
                )
                CardDivider()
                DropdownRow(
                    title: "Hotkey",
                    detail: "Press both keys at once to capture your frontmost window.",
                    options: AppshotHotkey.allCases.map { ($0, $0.label) },
                    selection: hotkeyBinding,
                    descriptionForOption: { $0.optionDescription },
                    minWidth: 150
                )
                if let message = appshotSettingsMessage ?? captureBlockedReason ?? hotkeyBlockedReason {
                    CardDivider()
                    InfoBanner(text: message, kind: .error)
                }
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                permissionRow(
                    title: "Screen Recording",
                    detail: "Required to capture the picture of the frontmost window.",
                    status: screenRecordingStatus,
                    request: {
                        _ = NativeMacPermissionBroker.requestScreenRecording()
                        refreshPermissions()
                    },
                    open: { NativeMacPermissionBroker.openSettings(for: .screenRecording) }
                )
                CardDivider()
                permissionRow(
                    title: "Accessibility",
                    detail: "Required to read all window text, including content scrolled offscreen.",
                    status: accessibilityStatus,
                    request: {
                        _ = NativeMacPermissionBroker.requestAccessibility()
                        refreshPermissions()
                    },
                    open: { NativeMacPermissionBroker.openSettings(for: .accessibility) }
                )
                CardDivider()
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Required for the keyboard shortcut to fire while another app is in front.",
                    status: inputMonitoringStatus,
                    request: {
                        _ = NativeMacPermissionBroker.requestInputMonitoring()
                        refreshPermissions()
                    },
                    open: { NativeMacPermissionBroker.openSettings(for: .inputMonitoring) }
                )
            }
        }
        .onAppear {
            refreshPermissions()
            AppshotHotkeyMonitor.shared.refreshRegistration()
            if enabled, let reason = captureBlockedReason {
                appshotSettingsMessage = String(
                    format: L10n.t("Appshots are enabled but blocked until permission is granted. %@"),
                    locale: AppLocale.current,
                    reason
                )
            }
        }
        .onChange(of: enabled) {
            AppshotHotkeyMonitor.shared.refreshRegistration()
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        status: NativeMacPermissionBroker.Status,
        request: @escaping () -> Void,
        open: @escaping () -> Void
    ) -> some View {
        SettingsRow {
            RowLabel(title: title, detail: detail)
        } trailing: {
            HStack(spacing: 8) {
                Text(verbatim: status.displayLabel)
                    .font(BodyFont.system(size: 11, wght: 700))
                    .foregroundColor(status.isGranted ? Color.green : Color.orange)
                IconChipButton(symbol: "arrow.triangle.2.circlepath", label: "Request", action: request)
                    .disabled(status.isGranted)
                IconChipButton(symbol: "gear", label: "Open", action: open)
            }
        }
    }

    private func refreshPermissions() {
        screenRecordingStatus = NativeMacPermissionBroker.status(for: .screenRecording)
        accessibilityStatus = NativeMacPermissionBroker.status(for: .accessibility)
        inputMonitoringStatus = NativeMacPermissionBroker.status(for: .inputMonitoring)
        if enabled, let reason = captureBlockedReason {
            appshotSettingsMessage = String(
                format: L10n.t("Appshots are enabled but blocked until permission is granted. %@"),
                locale: AppLocale.current,
                reason
            )
        } else if let reason = hotkeyBlockedReason {
            appshotSettingsMessage = String(
                format: L10n.t("The global appshot hotkey is inactive until permission is granted. %@"),
                locale: AppLocale.current,
                reason
            )
        } else {
            appshotSettingsMessage = nil
        }
    }
}
