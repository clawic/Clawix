import SwiftUI

struct ClawJSRuntimeLensSection: View {

    @State var runtimeLensSelection: ClawJSRuntimeLensID = .openclaw
    @State var runtimeLensSnapshots: [ClawJSRuntimeLensID: ClawJSRuntimeLensSnapshot] = [:]
    @State var runtimeLensLoading = false
    @State var runtimeLensError: String?
    @State var runtimeLensActionError: String?
    @State var runtimeLensActionResult: String?
    @State var runtimeLensActionSessionId = ""
    @State var runtimeLensActionMessage = ""
    @State var runtimeLensActionTitle = ""
    @State var runtimeLensActionGatewayURL = ""
    @State var runtimeLensPendingConfirmedAction: String?
    @State var runtimeLensSessionActionsInFlight: Set<String> = []
    @State var runtimeLensPages: [ClawJSRuntimeLensPageKey: Int] = [:]

    let runtimeLensClient = ClawJSRuntimeLensClient()
    static let pageSize = 24

    var body: some View {
        SectionCard(title: "Runtime lenses") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $runtimeLensSelection) {
                    ForEach(ClawJSRuntimeLensID.allCases) { runtime in
                        Text(runtime.label).tag(runtime)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                let presentation = runtimeLensPresentation
                ForEach(Array(presentation.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider().background(Color.overlay(0.07))
                    }
                    runtimeLensPresentationSection(section)
                }

                runtimeLensDetailedInventory()

                HStack {
                    Button("Refresh") {
                        Task { await refreshRuntimeLens(runtimeLensSelection) }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .disabled(runtimeLensLoading)
                    Spacer()
                }
            }
            .accessibilityIdentifier("runtime-lens-section-\(runtimeLensSelection.rawValue)")
            .accessibilityLabel(Text(runtimeLensPresentation.validationAccessibilityLabel))
        }
        .task {
            await refreshRuntimeLens(runtimeLensSelection)
        }
        .onChange(of: runtimeLensSelection) { _, selectedRuntime in
            runtimeLensPages.removeAll()
            runtimeLensActionResult = nil
            runtimeLensActionError = nil
            runtimeLensPendingConfirmedAction = nil
            Task { await refreshRuntimeLens(selectedRuntime) }
        }
        .confirmationDialog(
            "Run Hermes session action?",
            isPresented: Binding(
                get: { runtimeLensPendingConfirmedAction != nil },
                set: { isPresented in
                    if !isPresented {
                        runtimeLensPendingConfirmedAction = nil
                    }
                }
            ),
            presenting: runtimeLensPendingConfirmedAction
        ) { action in
            Button("Run \(action)", role: .destructive) {
                Task { await runRuntimeLensSessionAction(action: action, confirmRuntimeWrite: true) }
            }
            Button("Cancel", role: .cancel) {
                runtimeLensPendingConfirmedAction = nil
            }
        } message: { _ in
            Text("This writes through a loopback Hermes TUI Gateway fixture.")
        }
    }

    var runtimeLensPresentation: ClawJSRuntimeLensSettingsPresentation {
        ClawJSRuntimeLensSettingsPresentation.make(
            runtime: runtimeLensSelection,
            isRefreshing: runtimeLensLoading,
            loadError: runtimeLensError,
            actionError: runtimeLensActionError,
            snapshot: runtimeLensSnapshots[runtimeLensSelection]
        )
    }

    @MainActor
    func refreshRuntimeLens(_ runtime: ClawJSRuntimeLensID) async {
        runtimeLensLoading = true
        runtimeLensError = nil
        defer { runtimeLensLoading = false }

        let plan = ClawJSRuntimeLensRefreshPlan.scoped(to: runtime)
        for target in plan.runtimes {
            do {
                runtimeLensSnapshots[target] = try await runtimeLensClient.load(runtime: target)
            } catch {
                if target == runtimeLensSelection {
                    runtimeLensError = SettingsUtilities.failureMessage(for: error, surface: "settings.runtimeLens.refresh")
                }
            }
        }
    }

    @MainActor
    func runRuntimeLensSessionAction(action: String, confirmRuntimeWrite: Bool) async {
        let presentation = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: runtimeLensSelection,
            action: action,
            sessionId: runtimeLensActionSessionId,
            message: runtimeLensActionMessage,
            title: runtimeLensActionTitle,
            gatewayURL: runtimeLensActionGatewayURL,
            inFlightKeys: runtimeLensSessionActionsInFlight
        )
        guard presentation.canCheckGate else { return }
        if confirmRuntimeWrite {
            guard presentation.canRunConfirmedFixture else { return }
            runtimeLensPendingConfirmedAction = nil
        }

        runtimeLensActionError = nil
        runtimeLensActionResult = nil
        runtimeLensSessionActionsInFlight.insert(presentation.actionKey)
        defer { runtimeLensSessionActionsInFlight.remove(presentation.actionKey) }

        do {
            let result = try await runtimeLensClient.runSessionAction(
                runtime: runtimeLensSelection,
                action: action,
                sessionId: presentation.requiresSession ? trimmedRuntimeLensInput(runtimeLensActionSessionId) : nil,
                message: presentation.requiresMessage ? trimmedRuntimeLensInput(runtimeLensActionMessage) : nil,
                title: presentation.requiresTitle ? trimmedRuntimeLensInput(runtimeLensActionTitle) : nil,
                gatewayURL: trimmedRuntimeLensInput(runtimeLensActionGatewayURL),
                confirmRuntimeWrite: confirmRuntimeWrite
            )
            runtimeLensActionResult = runtimeLensSessionActionResultLabel(result)
            if result.writesRuntime == true {
                await refreshRuntimeLens(runtimeLensSelection)
            }
        } catch {
            runtimeLensActionError = SettingsUtilities.failureMessage(for: error, surface: "settings.runtimeLens.sessionAction")
        }
    }

    func trimmedRuntimeLensInput(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func runtimeLensSessionActionResultLabel(_ result: ClawJSRuntimeLensClient.SessionNativeActionResult) -> String {
        [
            result.action,
            result.status,
            result.officialMethod,
            result.result?.id,
            result.result?.roundTripVerification?.status.map { "round-trip \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

}
