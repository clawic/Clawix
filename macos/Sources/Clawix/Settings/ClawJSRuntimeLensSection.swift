import SwiftUI

struct ClawJSRuntimeLensSection: View {

    @State var runtimeLensSelection: ClawJSRuntimeLensID = .openclaw
    @State var runtimeLensSnapshots: [ClawJSRuntimeLensID: ClawJSRuntimeLensSnapshot] = [:]
    @State var runtimeLensLoading = false
    @State var runtimeLensError: String?
    @State var runtimeLensActionError: String?
    @State var runtimeLensActionResult: String?
    @State var runtimeLensActionResultDetails: [String] = []
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
            runtimeLensActionResultDetails = []
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
        runtimeLensActionResultDetails = []
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
            runtimeLensActionResultDetails = runtimeLensSessionActionResultDetails(result)
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

    func runtimeLensSessionActionResultDetails(_ result: ClawJSRuntimeLensClient.SessionNativeActionResult) -> [String] {
        var details: [String] = []

        let contractFields = [
            "runtime \(result.runtimeId)",
            "domain \(result.domain)",
            result.authority.map { "authority \($0)" },
            "writes runtime \(result.writesRuntime)",
            result.wouldWriteRuntime.map { "would write runtime \($0)" },
            result.writesLocalOverlay.map { "writes local overlay \($0)" },
            result.reason.map { "reason \($0)" },
            result.degradedReason.map { "degraded reason \($0)" },
            result.roundTripVerificationStatus.map { "round-trip verification \($0)" },
            result.blockerClass.map { "blocker \($0)" },
            result.requiredFlag.map { "required flag \($0)" },
            result.officialProtocol.map { "protocol \($0)" },
            result.officialMethod.map { "method \($0)" }
        ].compactMap { $0 }
        if !contractFields.isEmpty {
            details.append("action contract " + contractFields.joined(separator: ", "))
        }

        var policyFields: [String] = []
        if let endpointPolicy = result.endpointPolicy {
            policyFields.append("endpoint policy \(endpointPolicy)")
        }
        if let approvalScope = result.approvalScope {
            policyFields.append("approval scope \(approvalScope)")
        }
        if let requiredEndpoint = result.requiredEndpoint {
            policyFields.append("required endpoint \(requiredEndpoint)")
        }
        if let transportPolicyId = result.transportPolicyId {
            policyFields.append("transport policy \(transportPolicyId)")
        }
        if let configuredEndpointClass = result.transportPolicy?.configuredEndpointClass {
            policyFields.append("endpoint class \(configuredEndpointClass)")
        }
        if let productionTransportStatus = result.productionTransportStatus {
            policyFields.append("production transport \(productionTransportStatus)")
        }
        if let lifecycleStatus = result.lifecycleStatus {
            policyFields.append("lifecycle \(lifecycleStatus)")
        }
        if let safeDefault = result.safeDefault {
            policyFields.append("safe default \(safeDefault)")
        }
        if let productionTransportCommandShape = result.productionTransportCommandShape {
            policyFields.append("command shape \(productionTransportCommandShape)")
        }
        if let doNotRunWithoutApproval = result.doNotRunWithoutApproval {
            policyFields.append("do not run without approval \(doNotRunWithoutApproval)")
        }
        if let claimBlockedUntil = result.claimBlockedUntil {
            policyFields.append("claim blocked until \(claimBlockedUntil)")
        }
        if let userVisibleContract = result.userVisibleContract {
            policyFields.append("user visible contract \(userVisibleContract)")
        }
        if let productDecision = result.productDecision {
            policyFields.append("product decision \(productDecision)")
        }
        if !policyFields.isEmpty {
            details.append("transport policy " + policyFields.joined(separator: ", "))
        }

        if let gatewayReceipt = result.result?.gatewayReceipt {
            let gatewayFields = [
                gatewayReceipt.method,
                gatewayReceipt.transport.map { "via \($0)" },
                gatewayReceipt.requestId.map { "request \($0)" },
                gatewayReceipt.endpoint
            ].compactMap { $0 }
            if !gatewayFields.isEmpty {
                details.append("gateway " + gatewayFields.joined(separator: ", "))
            }
        }

        if let titleGatewayReceipt = result.result?.titleGatewayReceipt {
            let gatewayFields = [
                titleGatewayReceipt.method,
                titleGatewayReceipt.transport.map { "via \($0)" },
                titleGatewayReceipt.requestId.map { "request \($0)" },
                titleGatewayReceipt.endpoint
            ].compactMap { $0 }
            if !gatewayFields.isEmpty {
                details.append("title gateway " + gatewayFields.joined(separator: ", "))
            }
        }

        let resultFields = [
            result.result?.found.map { "found \($0)" },
            result.result?.contentIncluded.map { "content included \($0)" },
            result.result?.totalProjected.map { "total projected \($0)" }
        ].compactMap { $0 }
        if !resultFields.isEmpty {
            details.append("result " + resultFields.joined(separator: ", "))
        }

        if let verification = result.result?.roundTripVerification {
            let verificationFields = [
                verification.status.map { "status \($0)" },
                verification.action.map { "action \($0)" },
                verification.matchedBy.map { "matched by \($0)" },
                verification.id.map { "id \($0)" },
                verification.title.map { "title \($0)" },
                verification.endedAt.map { "ended at \($0)" },
                verification.endReason.map { "end reason \($0)" },
                verification.messageRole.map { "message role \($0)" },
                verification.messageIndex.map { "message index \($0)" },
                verification.totalAvailableInStore.map { "store total \($0)" },
                verification.writesRuntime.map { "writes runtime \($0)" }
            ].compactMap { $0 }
            if !verificationFields.isEmpty {
                details.append("round-trip " + verificationFields.joined(separator: ", "))
            }

            let checkedLabel: String?
            if let checked = verification.checked, !checked.isEmpty {
                checkedLabel = "checked \(checked.joined(separator: ", "))"
            } else {
                checkedLabel = nil
            }
            let provenanceFields = [
                verification.provenance?.source,
                verification.provenance?.runtimeId.map { "runtime \($0)" },
                verification.provenance?.table.map { "table \($0)" },
                checkedLabel,
                verification.safeDefault.map { "safe default \($0)" }
            ].compactMap { $0 }
            if !provenanceFields.isEmpty {
                details.append("provenance " + provenanceFields.joined(separator: ", "))
            }
        }

        if let contractSource = result.officialContractSource {
            details.append("contract \(contractSource)")
        }

        return details
    }

}
