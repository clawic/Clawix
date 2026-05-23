import SwiftUI

/// Blocking sheet for catastrophic-risk approvals (constitution VII.4:
/// catastrophic = the framework interrupts the user). Presented from
/// `IoTScreen` whenever a new `ApprovalRecord` with a restricted-risk
/// reason lands in the queue. The user can approve, deny, or open the
/// queue to inspect the full request shape before committing.
struct IoTCatastrophicApprovalModal: View {
    let approval: ApprovalRecord
    @EnvironmentObject private var manager: IoTManager
    @Environment(\.dismiss) private var dismiss
    @State private var inFlight = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(spacing: 0) {
                detailRow(label: "Action", value: approval.action.action, mono: true)
                rowDivider
                detailRow(label: "Target", value: targetLabel, mono: true)
                rowDivider
                detailRow(label: "Capability", value: approval.action.capability ?? "(default)", mono: true)
                rowDivider
                detailRow(label: "Reason", value: approval.reason, mono: false, trailing: approval.createdAt)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.overlay(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.overlay(0.10), lineWidth: 0.5)
                    )
            )

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.danger)
            }

            actions
        }
        .padding(22)
        .frame(minWidth: 440, idealWidth: 480, maxWidth: 540)
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.danger.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay(
                    LucideIcon.auto("triangle-alert", size: 20)
                        .foregroundColor(Palette.danger)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.danger.opacity(0.3), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    Text(verbatim: "Approval required")
                        .font(BodyFont.system(size: 16, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    statusPill
                }
                Text(verbatim: "Needs explicit approval before it reaches the device.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.danger).frame(width: 6, height: 6)
            Text(verbatim: "Catastrophic")
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.danger)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(Palette.danger.opacity(0.14)))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: { Text(verbatim: "Later") }
                .buttonStyle(SheetCancelButtonStyle())
            Spacer(minLength: 8)
            Button { Task { await deny() } } label: { Text(verbatim: "Deny") }
                .buttonStyle(SheetCancelButtonStyle())
                .disabled(inFlight)
            Button { Task { await approve() } } label: {
                HStack(spacing: 6) {
                    if inFlight {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .tint(.white)
                    }
                    Text(verbatim: "Approve and run")
                }
                .font(BodyFont.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.danger.opacity(inFlight ? 0.6 : 0.9))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(inFlight)
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String, mono: Bool, trailing: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 92, alignment: .leading)
            Text(verbatim: value)
                .font(mono ? .system(size: 12, design: .monospaced) : BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let trailing {
                Text(verbatim: trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.overlay(0.07)).frame(height: 0.5).padding(.horizontal, 14)
    }

    private var targetLabel: String {
        approval.action.selector
            ?? approval.action.targets?.first
            ?? approval.action.family
            ?? "(unknown)"
    }

    private func approve() async {
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await manager.approveApproval(approval)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deny() async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await manager.denyApproval(approval)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
