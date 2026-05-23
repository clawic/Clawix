import SwiftUI

/// Outstanding approval-gate request originating from a running agent.
/// The daemon mints one of these every time an agent with autonomy <
/// `act_full` tries to execute an action that the autonomy slider or
/// the per-action override says "always ask". The sheet shows the
/// action, the agent, and a short detail blurb; the user resolves with
/// allow / deny / always-allow / always-deny so the runtime can plug
/// the response back through `BridgeProtocol.agentApprovalResponse`.
struct AgentApprovalRequest: Identifiable, Equatable {
    var id: String = UUID().uuidString
    /// `agent.id` of the agent that requested approval.
    var agentId: String
    /// Short canonical name of the gated action (e.g. `git.push`,
    /// `shell.rm`, `network.send`). Used both for the headline and as
    /// the key the runtime stores the user's persistent choice under.
    var action: String
    /// Free-form context the agent emitted alongside the request (the
    /// command it wants to run, the URL it wants to hit, etc.).
    var detail: String
}

enum AgentApprovalDecision: String {
    case allow
    case deny
    case allowAlways
    case denyAlways
}

struct AgentApprovalRequestSheet: View {
    let request: AgentApprovalRequest
    let onDecide: (AgentApprovalDecision) -> Void

    /// When set, Deny/Allow resolve to their persistent variants so the
    /// runtime stores the choice under `request.action`. Collapses the
    /// old four-button row into two choices plus one scope toggle.
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !request.detail.isEmpty { detailPanel }
            actions
        }
        .padding(22)
        .frame(width: 500)
        .background(Palette.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.warning.opacity(0.16))
                .frame(width: 42, height: 42)
                .overlay(
                    LucideIcon.auto("shield-check", size: 19)
                        .foregroundColor(Palette.warning)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.warning.opacity(0.28), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Approval required")
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("Agent \(request.agentId) wants to run a gated action.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            actionPill
        }
    }

    private var actionPill: some View {
        HStack(spacing: 6) {
            LucideIcon.auto("git-branch", size: 12)
                .foregroundColor(Color(red: 0.62, green: 0.72, blue: 1.0))
            Text(verbatim: request.action)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(Color.gray(light: 0.18, dark: 0.90))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(Color.overlay(0.05)))
    }

    private var detailPanel: some View {
        ScrollView {
            Text(request.detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.gray(light: 0.20, dark: 0.86))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(minHeight: 70, maxHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.overlay(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.overlay(0.10), lineWidth: 0.5)
                )
        )
        .thinScrollers()
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { remember.toggle() } label: {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(remember ? Palette.pastelBlue.opacity(0.85) : Color.overlay(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.overlay(remember ? 0 : 0.22), lineWidth: 1)
                        )
                        .frame(width: 18, height: 18)
                        .overlay {
                            if remember {
                                LucideIcon.auto("check", size: 11)
                                    .foregroundColor(Palette.background)
                            }
                        }
                    Text("Remember for \(request.action)")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button("Deny") {
                onDecide(remember ? .denyAlways : .deny)
            }
            .buttonStyle(SheetCancelButtonStyle())
            .keyboardShortcut(.cancelAction)

            Button("Allow") {
                onDecide(remember ? .allowAlways : .allow)
            }
            .buttonStyle(SheetPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }
}
