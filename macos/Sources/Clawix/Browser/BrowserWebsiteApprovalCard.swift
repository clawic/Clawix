import SwiftUI

/// One pending website-access decision for the in-app browser. Raised when
/// the permission policy resolves a navigation to `.ask`, so the user can
/// allow the page once, allow the site forever, or allow every site.
struct BrowserWebsiteApprovalRequest: Equatable {
    let url: URL
    /// Host shown in the prompt and added to the allow list when the user
    /// picks "this site".
    let origin: String
}

enum BrowserWebsiteApprovalDecision {
    case cancel
    case allowOnce
    case allowSite
    case allowAnyWebsite
}

/// Floating approval card shown over the browser content while a website
/// is waiting for access. Observes the tab controller so it appears the
/// moment a navigation needs consent and dismisses once resolved. Mirrors
/// the modal chrome used elsewhere (`sheetStandardBackground`, sheet button
/// styles) so it reads as part of the same surface family.
struct BrowserWebsiteApprovalCard: View {
    @ObservedObject var controller: BrowserTabController

    var body: some View {
        if let request = controller.pendingWebsiteApproval {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { controller.resolveWebsiteApproval(.cancel) }

                CardBody(request: request) { decision in
                    controller.resolveWebsiteApproval(decision)
                }
                .padding(.top, 18)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .transition(.opacity)
        }
    }
}

private struct CardBody: View {
    let request: BrowserWebsiteApprovalRequest
    let onDecide: (BrowserWebsiteApprovalDecision) -> Void

    /// User's chosen scope. Defaults to the safest option ("just this
    /// time"); the Allow button resolves to whichever row is selected.
    @State private var choice: BrowserWebsiteApprovalDecision = .allowOnce

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 11) {
                LucideIcon(.globe, size: 16)
                    .foregroundColor(Color.gray(light: 0.14, dark: 0.92))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.overlay(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Color.overlay(0.10), lineWidth: 0.5)
                            )
                    )
                (Text("Allow Clawix to open ")
                    + Text(verbatim: request.origin).font(.system(size: 13, design: .monospaced))
                    + Text("?"))
                    .font(BodyFont.system(size: 14.5, weight: .medium))
                    .foregroundColor(Color.gray(light: 0.09, dark: 0.97))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            VStack(spacing: 7) {
                scopeOption(.allowOnce, title: "Just this time")
                scopeOption(.allowSite, title: "Always for this site")
                scopeOption(.allowAnyWebsite, title: "Always for any website",
                            warning: "The agent won't ask again before opening other sites.")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onDecide(.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SheetCancelButtonStyle())
                Button("Allow") { onDecide(choice) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(SheetPrimaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 440)
        .sheetStandardBackground()
    }

    @ViewBuilder
    private func scopeOption(
        _ option: BrowserWebsiteApprovalDecision,
        title: LocalizedStringKey,
        warning: LocalizedStringKey? = nil
    ) -> some View {
        let selected = choice == option
        Button { choice = option } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .stroke(selected ? Palette.pastelBlue : Color.overlay(0.22),
                                    lineWidth: selected ? 5 : 1.5)
                            .frame(width: 16, height: 16)
                    }
                    Text(title)
                        .font(BodyFont.system(size: 12.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Spacer(minLength: 0)
                }
                if let warning, selected {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.warning).frame(width: 6, height: 6)
                        Text(warning)
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.warning)
                    }
                    .padding(.leading, 27)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Palette.pastelBlue.opacity(0.08) : Color.overlay(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? Palette.pastelBlue.opacity(0.35) : Color.overlay(0.10),
                                    lineWidth: 0.5)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: selected)
    }
}
