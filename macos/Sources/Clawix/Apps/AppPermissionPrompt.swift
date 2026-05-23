import AppKit
import Foundation
import SwiftUI

/// Confirm dialog gating one-off requests from the embedded app that need
/// user approval (calling an agent tool, enabling internet access).
/// Centralized so AppBridgeMessageHandler doesn't have to manage window
/// chrome or threading. Renders the project's own glass approval card in a
/// modal `NSPanel` (not a system `NSAlert`) so the gate reads as Clawix and
/// states exactly what is being granted, while keeping the synchronous
/// completion contract the callers rely on.
@MainActor
final class AppPermissionPrompt {
    static let shared = AppPermissionPrompt()

    enum Decision {
        case denied
        case once
        case always
    }

    private init() {}

    func requestToolApproval(
        appName: String,
        tool: String,
        completion: @escaping (Decision) -> Void
    ) {
        let decision = present(kind: .tool(appName: appName, tool: tool))
        completion(decision)
    }

    func requestInternetApproval(
        appName: String,
        completion: @escaping (Bool) -> Void
    ) {
        let decision = present(kind: .internetAccess(appName: appName))
        completion(decision != .denied)
    }

    // MARK: - Modal hosting

    /// Hosts `AppApprovalCard` in a borderless, clear modal panel and runs
    /// a nested modal session, mirroring the blocking semantics the old
    /// `NSAlert.runModal()` had. The card's buttons resolve a `Decision`
    /// and stop the session.
    private func present(kind: AppApprovalCard.Kind) -> Decision {
        var decision: Decision = .denied

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .modalPanel
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let resolve: (Decision) -> Void = { resolved in
            decision = resolved
            NSApp.stopModal()
        }

        let host = NSHostingView(rootView: AppApprovalCard(kind: kind, onResolve: resolve))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        panel.contentView = host
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return decision
    }
}

// MARK: - Approval card

/// The branded approval surface. One view covers both the tool gate (deny /
/// allow once / always for this app) and the internet gate (keep offline /
/// allow), so the chrome stays identical across the two prompts.
private struct AppApprovalCard: View {
    enum Kind {
        case tool(appName: String, tool: String)
        case internetAccess(appName: String)
    }

    let kind: Kind
    let onResolve: (AppPermissionPrompt.Decision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            requestPanel
            footnote
            actions
        }
        .padding(22)
        .frame(width: 440)
        .sheetStandardBackground()
        // Breathing room so the card's drop shadow renders inside the
        // clear panel instead of being clipped at its bounds.
        .padding(26)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.overlay(0.08))
                .frame(width: 42, height: 42)
                .overlay(
                    LucideIcon.auto(headerSymbol, size: 19)
                        .foregroundColor(Color.gray(light: 0.20, dark: 0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.overlay(0.10), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(subtitle)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
    }

    // MARK: Request panel

    @ViewBuilder
    private var requestPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch kind {
            case .tool(_, let tool):
                detailRow(label: "Tool") {
                    HStack(spacing: 7) {
                        LucideIcon.auto("code", size: 12)
                            .foregroundColor(Color(red: 0.62, green: 0.72, blue: 1.0))
                        Text(verbatim: tool)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color.gray(light: 0.18, dark: 0.90))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous).fill(Color.overlay(0.05))
                    )
                }
                divider
                detailRow(label: "Scope") {
                    Text("Runs one agent tool call. Nothing else.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
            case .internetAccess:
                detailRow(label: "Access") {
                    Text("HTTPS requests to any host.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                divider
                detailRow(label: "Default") {
                    Text("Clawix Apps run offline unless you allow this.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.overlay(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.overlay(0.10), lineWidth: 0.5)
                )
        )
    }

    private func detailRow<Trailing: View>(
        label: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 52, alignment: .leading)
            trailing()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle().fill(Color.overlay(0.07)).frame(height: 0.5).padding(.horizontal, 14)
    }

    // MARK: Footnote

    private var footnote: some View {
        HStack(spacing: 6) {
            LucideIcon.auto("lock", size: 12)
                .foregroundColor(Palette.textTertiary)
            Text("Revoke anytime in Settings · Apps.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textTertiary)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch kind {
        case .tool:
            HStack(spacing: 8) {
                Button("Deny") { onResolve(.denied) }
                    .buttonStyle(SheetCancelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                Button("Allow once") { onResolve(.once) }
                    .buttonStyle(SheetCancelButtonStyle())
                Button("Always for this app") { onResolve(.always) }
                    .buttonStyle(SheetPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        case .internetAccess:
            HStack(spacing: 8) {
                Button("Keep offline") { onResolve(.denied) }
                    .buttonStyle(SheetCancelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                Button("Allow") { onResolve(.once) }
                    .buttonStyle(SheetPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Copy

    private var title: LocalizedStringKey {
        switch kind {
        case .tool(let appName, _):
            return "\(appName) wants to use a tool"
        case .internetAccess(let appName):
            return "\(appName) wants internet access"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch kind {
        case .tool:
            return "Nothing runs until you allow it."
        case .internetAccess:
            return "Granting access lets it reach any host."
        }
    }

    private var headerSymbol: String {
        switch kind {
        case .tool:          return "wrench"
        case .internetAccess: return "globe"
        }
    }
}
