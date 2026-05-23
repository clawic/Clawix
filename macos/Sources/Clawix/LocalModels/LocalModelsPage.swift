import SwiftUI

/// Settings page for the local LLM runtime. Single sidebar entry, with
/// the visible flow on top (install → daemon toggle → models) and a
/// collapsed `Advanced` disclosure at the bottom.
///
/// View extensions split across files:
/// - `LocalModelsModelsSection.swift` owns the Models card.
/// - `LocalModelsDiagnosticsSection.swift` owns shared row helpers and `SectionCard`.
/// - `LocalModelsAdvancedSection.swift` owns the collapsed Advanced bloc.
/// State and the published-binding wiring live here.
struct LocalModelsPage: View {

    @StateObject var service = LocalModelsService.shared
    @StateObject var launchAgent = LocalModelsLaunchAgent.shared

    @State var pullField: String = ""
    @State var showCatalog = false
    @State var showUninstallConfirm = false
    @State private var uninstallInFlight = false
    @State private var runtimeActionError: String?
    @AppStorage(ClawixPersistentSurfaceKeys.localModelsAdvancedExpanded) var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            runtimeBanners

            runtimeSection
                .padding(.top, 18)

            if case .running = service.daemonState {
                modelsSection
                    .padding(.top, 22)
            }

            advancedSection
                .padding(.top, 22)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showCatalog) {
            LocalModelsCatalogSheet(
                installedModelNames: Set(service.installedModels.map { $0.name }),
                onPick: { name in
                    showCatalog = false
                    Task { await service.pull(model: name) }
                },
                onClose: { showCatalog = false }
            )
        }
        .onAppear {
            launchAgent.refresh()
            LocalModelsRuntimeInstaller.shared.refresh()
        }
    }

    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local models")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Run language models on your Mac. No cloud, no tokens.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    // MARK: - Runtime card

    var runtimeSection: some View {
        SectionCard(title: "Runtime") {
            VStack(alignment: .leading, spacing: 12) {
                runtimeStateRow

                if shouldShowDaemonControls {
                    Divider().background(Color.overlay(0.07))
                    daemonToggleRow
                    Divider().background(Color.overlay(0.07))
                    startAtLoginRow
                }

                if case .installed = service.runtimeState {
                    Divider().background(Color.overlay(0.07))
                    HStack {
                        Spacer()
                        Button("Uninstall runtime") {
                            showUninstallConfirm = true
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(Palette.danger)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .disabled(uninstallInFlight || isRuntimeBusy)
                    }
                }
            }
        }
        .alert("Remove the local runtime?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await uninstallRuntime() }
            }
        } message: {
            Text("Downloaded models stay on disk. You can reinstall the runtime any time.")
        }
    }

    @ViewBuilder
    private var runtimeBanners: some View {
        if let runtimeActionError {
            InfoBanner(text: runtimeActionError, kind: .error)
                .padding(.top, 14)
        }
        if let launchAgentError = launchAgent.lastError {
            InfoBanner(text: launchAgentError, kind: .error)
                .padding(.top, 14)
        }
        if uninstallInFlight {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Removing local runtime")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.top, 14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Removing local runtime"))
        }
    }

    @ViewBuilder
    var runtimeStateRow: some View {
        switch service.runtimeState {
        case .notInstalled:
            actionRow(
                title: "Set up local runtime",
                detail: "Downloads ~133 MB the first time, then runs entirely on this Mac.",
                buttonLabel: "Set up",
                isEnabled: !isRuntimeBusy,
                isWorking: isRuntimeBusy,
                action: { Task { await service.enable() } }
            )
        case .installing(let progress, let downloaded):
            VStack(alignment: .leading, spacing: 6) {
                Text("Setting up local runtime…")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text(progressLabel(
                        downloaded: downloaded,
                        total: LocalModelsRuntimeInstaller.pinnedSizeBytes
                    ))
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    Spacer()
                    Button("Cancel") { service.cancelInstall() }
                        .buttonStyle(.borderless)
                }
            }
        case .extracting:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Unpacking runtime…")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
            }
        case .installed(let v):
            HStack {
                LucideIcon(.circleCheck, size: 11)
                    .foregroundColor(Color(red: 0.40, green: 0.78, blue: 0.55))
                Text("Runtime ready · \(v)")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
            }
        case .updateAvailable(let installed):
            actionRow(
                title: "Update available",
                detail: "Installed \(installed). New: \(LocalModelsRuntimeInstaller.pinnedVersion).",
                buttonLabel: "Update",
                isEnabled: !isRuntimeBusy,
                isWorking: isRuntimeBusy,
                action: { Task { await service.enable() } }
            )
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Setup failed")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.danger)
                Text(message)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(4)
                Button("Retry") { Task { await service.enable() } }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var shouldShowDaemonControls: Bool {
        if case .installed = service.runtimeState { return true }
        return false
    }

    var daemonToggleRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Run local runtime")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(daemonStatusLabel)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            PillToggle(isOn: Binding(
                get: { service.daemonState.isRunning },
                set: { on in
                    guard !isRuntimeBusy else { return }
                    Task {
                        if on { await service.enable() } else { service.disable() }
                    }
                }
            ), accessibilityLabel: "Run local runtime")
            .disabled(isRuntimeBusy)
        }
    }

    var startAtLoginRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Start at login")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(launchAgent.statusLabel)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            PillToggle(isOn: Binding(
                get: { launchAgent.isEnabled },
                set: {
                    guard !isRuntimeBusy else { return }
                    launchAgent.toggle($0)
                }
            ), accessibilityLabel: "Start at login")
            .disabled(isRuntimeBusy)
        }
    }

    var isRuntimeBusy: Bool {
        if uninstallInFlight { return true }
        if case .installing = service.runtimeState { return true }
        if case .extracting = service.runtimeState { return true }
        if case .starting = service.daemonState { return true }
        return false
    }

    private func uninstallRuntime() async {
        guard !uninstallInFlight else { return }
        uninstallInFlight = true
        runtimeActionError = nil
        defer { uninstallInFlight = false }

        service.disable()
        launchAgent.disable()
        do {
            try LocalModelsRuntimeInstaller.shared.uninstall()
        } catch {
            runtimeActionError = SettingsUtilities.failureMessage(
                for: error,
                surface: "settings.localModels.runtime.uninstall"
            )
        }
    }

    var daemonStatusLabel: String {
        switch service.daemonState {
        case .stopped:
            return L10n.t("Stopped")
        case .starting:
            return L10n.t("Starting…")
        case .running:
            let loaded = service.loadedModels.count
            return loaded == 0
                ? String(
                    format: L10n.t("Running on %@ · idle"),
                    locale: AppLocale.current,
                    "127.0.0.1:\(LocalModelsDaemon.port)"
                )
                : String(
                    format: L10n.t("Running on %@ · %lld loaded"),
                    locale: AppLocale.current,
                    "127.0.0.1:\(LocalModelsDaemon.port)",
                    loaded
                )
        case .missingRuntime:
            return L10n.t("Runtime binary missing")
        case .crashed(let m):
            return m
        }
    }
}
