import SwiftUI

// Elapsed-time disclosure shown above the assistant reply once the
// final answer has started arriving (or the turn has fully completed).
// Always reads "Worked for Xs" — the seconds tick live while the turn
// is still active and freeze on `turn/completed`. Tapping the chevron
// toggles the bound expansion state, which the surrounding bubble uses
// to reveal the upstream reasoning + tool timeline that was hidden the
// moment the final answer began.

struct WorkSummaryHeader: View {
    let summary: WorkSummary
    @Binding var expanded: Bool
    var controlId: String? = nil
    var onToggle: ((_ willExpand: Bool) -> Void)? = nil
    var onExpand: () -> Void = {}
    @State private var tickDate = Date()
    @State private var secondsLease: VisualClock.Lease?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosure
            Rectangle()
                .fill(Color.gray(light: 0.905, dark: 0.18))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var disclosure: some View {
        if let controlId {
            button
                .clxControl(
                    controlId,
                    role: "button",
                    label: "Work summary",
                    activate: toggleExpansion
                )
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: toggleExpansion) {
            Group {
                if summary.isActive {
                    label(asOf: tickDate)
                        .onReceive(VisualClock.shared.secondsPublisher) { tickDate = $0 }
                } else {
                    label(asOf: summary.endedAt ?? Date())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Work summary"))
        .onAppear { updateSecondsLease() }
        .onDisappear { stopSecondsLease() }
        .onChange(of: summary.isActive) { _, _ in
            updateSecondsLease()
        }
    }

    private func toggleExpansion() {
        let willExpand = !expanded
        onToggle?(willExpand)
        withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
        if willExpand { onExpand() }
    }

    private func label(asOf date: Date) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: L10n.workedFor(seconds: summary.elapsedSeconds(asOf: date)))
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
            LucideIcon(.chevronRight, size: 11)
                .foregroundColor(Color.gray(light: 0.52, dark: 0.42))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .animation(.easeOut(duration: 0.16), value: expanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func updateSecondsLease() {
        if summary.isActive {
            tickDate = Date()
            if secondsLease == nil {
                secondsLease = VisualClock.shared.acquire(.seconds)
            }
        } else {
            stopSecondsLease()
        }
    }

    private func stopSecondsLease() {
        secondsLease?.cancel()
        secondsLease = nil
    }
}
