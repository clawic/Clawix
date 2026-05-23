import SwiftUI

struct AppearancePage: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Appearance",
                subtitle: "Choose how the interface looks. Light follows the same design language as dark."
            )

            SectionLabel(title: "Theme")
            SettingsCard {
                SegmentedRow(
                    title: "Appearance",
                    detail: "System follows your macOS setting. Light and dark force the matching palette.",
                    options: AppAppearance.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { appState.appearance },
                        set: { appState.appearance = $0 }
                    ),
                    width: 220
                )
            }
        }
    }
}
