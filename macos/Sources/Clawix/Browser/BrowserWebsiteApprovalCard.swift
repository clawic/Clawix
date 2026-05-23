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

    private enum Scope: CaseIterable {
        case thisSite
        case anyWebsite

        var label: LocalizedStringKey {
            switch self {
            case .thisSite:   return "Always allow this site"
            case .anyWebsite: return "Always allow any website"
            }
        }
    }

    @State private var persist = false
    @State private var scope: Scope = .thisSite
    @State private var scopeMenuOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                LucideIcon(.globe, size: 16)
                    .foregroundColor(Color(white: 0.92))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                Text("Allow Clawix to access \(request.origin)?")
                    .font(BodyFont.system(size: 14.5, weight: .medium))
                    .foregroundColor(Color(white: 0.97))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            scopeRow
                .padding(.horizontal, 18)
                .padding(.bottom, scope == .anyWebsite && persist ? 6 : 14)

            if scope == .anyWebsite && persist {
                Text("The agent won't ask again before opening other websites.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color.orange.opacity(0.9))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onDecide(.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SheetCancelButtonStyle())
                Button("Allow") { onDecide(resolvedDecision) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(SheetPrimaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 440)
        .sheetStandardBackground()
    }

    private var resolvedDecision: BrowserWebsiteApprovalDecision {
        guard persist else { return .allowOnce }
        return scope == .thisSite ? .allowSite : .allowAnyWebsite
    }

    private var scopeRow: some View {
        HStack(spacing: 10) {
            Button { persist.toggle() } label: {
                checkbox
            }
            .buttonStyle(.plain)

            Button { scopeMenuOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(scope.label)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(persist ? Color(white: 0.92) : Color(white: 0.62))
                    LucideIcon.auto("chevron.down", size: 10)
                        .foregroundColor(persist ? Color(white: 0.78) : Color(white: 0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                if scopeMenuOpen {
                    scopeMenu.offset(y: 26)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(persist ? Color.white.opacity(0.92) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(persist ? 0 : 0.22), lineWidth: 1)
            )
            .frame(width: 18, height: 18)
            .overlay {
                if persist {
                    CheckIcon(size: 10)
                        .foregroundColor(.black)
                }
            }
    }

    private var scopeMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Scope.allCases, id: \.self) { option in
                Button {
                    scope = option
                    persist = true
                    scopeMenuOpen = false
                } label: {
                    HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                        Text(option.label)
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(MenuStyle.rowText)
                        Spacer(minLength: 12)
                        if scope == option {
                            CheckIcon(size: 10)
                                .foregroundColor(MenuStyle.rowText)
                        }
                    }
                    .padding(.horizontal, MenuStyle.rowHorizontalPadding + 4)
                    .padding(.vertical, MenuStyle.rowVerticalPadding + 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 220, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $scopeMenuOpen))
        .zIndex(1)
    }
}
