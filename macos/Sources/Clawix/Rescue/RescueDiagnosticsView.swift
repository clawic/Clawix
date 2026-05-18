import SwiftUI

struct RescueDiagnosticsView: View {
    @EnvironmentObject var appState: AppState

    private var summary: RescueRepairStatusSummary? {
        RescueRepairStatusSummary(decision: appState.rescueDecision)
    }

    private var modeLabel: String {
        switch appState.rescueDecision.mode {
        case .normal: return "Ready"
        case .degraded: return "Repair pending"
        case .ephemeralChat: return "Temporary chat"
        case .diagnosticsOnly: return "Diagnostics only"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    title: "Repair",
                    subtitle: "Local diagnostics and repair context"
                )

                SettingsCard {
                    HStack(alignment: .center, spacing: 12) {
                        LucideIcon.auto("circle-alert", size: 14)
                            .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.30))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary?.title ?? modeLabel)
                                .font(BodyFont.system(size: 13, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                            Text(summary?.detail ?? "No pending repair work")
                                .font(BodyFont.system(size: 12, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        }
                        Spacer()
                        Text(modeLabel)
                            .font(BodyFont.system(size: 12, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    CardDivider()
                    ActionPillRow(
                        title: "Open diagnostics",
                        detail: "Save the current rescue context and open local diagnostic files",
                        primaryLabel: "Open",
                        onPrimary: { SettingsUtilities.revealDiagnosticsFolder() }
                    )
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
