import SwiftUI

struct ClawJSRuntimeLensSection: View {

    @State var runtimeLensSelection: ClawJSRuntimeLensID = .openclaw
    @State var runtimeLensSnapshots: [ClawJSRuntimeLensID: ClawJSRuntimeLensSnapshot] = [:]
    @State var runtimeLensLoading = false
    @State var runtimeLensError: String?
    @State var runtimeLensActionError: String?
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
                        Divider().background(Color.white.opacity(0.07))
                    }
                    runtimeLensPresentationSection(section)
                }

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
            Task { await refreshRuntimeLens(selectedRuntime) }
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

}
