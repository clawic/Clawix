import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var appState: AppState
    /// Observe browser chrome one-shot signals directly so `.onChange`
    /// (reload / command) fires without the AppState god-object fan-out (P4).
    @EnvironmentObject private var browserChrome: BrowserChromeStore
    @EnvironmentObject private var flags: FeatureFlags
    @State private var store = BrowserControllerStore()
    @State private var moreMenuOpen = false

    private var activeWeb: SidebarItem.WebPayload? {
        if case .web(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeFile: SidebarItem.FilePayload? {
        if case .file(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeChat: SidebarItem.ChatPayload? {
        if case .chat(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeFileTree: SidebarItem.FileTreePayload? {
        if case .fileTree(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeReview: SidebarItem.ReviewPayload? {
        if case .review(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeSummary: SidebarItem.SummaryPayload? {
        if case .summary(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeIOSSimulator: SidebarItem.IOSSimulatorPayload? {
        if case .iosSimulator(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeAndroidSimulator: SidebarItem.AndroidSimulatorPayload? {
        if case .androidSimulator(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                BrowserTabStrip()
                Divider().background(Color.overlay(0.06))

                if let payload = activeWeb {
                    let controller = store.controller(for: payload, appState: appState)
                    BrowserNavigationBar(controller: controller, moreMenuOpen: $moreMenuOpen)
                        .id(payload.id)
                    Divider().background(Color.overlay(0.06))
                    ZStack {
                        BrowserWebView(controller: controller)
                            .id(payload.id)
                        if let error = controller.lastNavigationError {
                            BrowserErrorOverlay(error: error) {
                                controller.reload()
                            }
                        }
                        BrowserAnnotationOverlay(controller: controller)
                        BrowserWebsiteApprovalCard(controller: controller)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeOut(duration: 0.16), value: controller.pendingWebsiteApproval)
                } else if let payload = activeFile {
                    FileViewerPanel(path: payload.path)
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeChat {
                    ChatView(appState: appState, chatId: payload.id, isSideChat: true)
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeFileTree {
                    SidebarFileTreeView()
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeReview {
                    ReviewChangesPanel()
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeSummary {
                    ThreadSummaryPanel()
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeIOSSimulator {
                    IOSSimulatorPanel(payload: payload) { updated in
                        appState.updateIOSSimulator(updated)
                    }
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeAndroidSimulator {
                    AndroidSimulatorPanel(payload: payload) { updated in
                        appState.updateAndroidSimulator(updated)
                    }
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            }
        }
        .background(Palette.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlayPreferenceValue(BrowserMoreMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if moreMenuOpen, let anchor, let payload = activeWeb {
                    let controller = store.controller(for: payload, appState: appState)
                    let buttonFrame = proxy[anchor]
                    BrowserMoreOptionsMenu(
                        controller: controller,
                        isOpen: $moreMenuOpen
                    )
                    .frame(width: BrowserMoreOptionsMenu.menuWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(moreMenuOpen)
        }
        .animation(MenuStyle.openAnimation, value: moreMenuOpen)
        .onChange(of: appState.sidebarItems.map(\.id)) { _, newIds in
            store.discardOrphans(currentTabIds: Set(newIds))
            if activeWeb == nil { moreMenuOpen = false }
        }
        .onChange(of: browserChrome.pendingReloadTabId) { _, newValue in
            guard let tabId = newValue,
                  let payload = activeWeb,
                  payload.id == tabId
            else { return }
            let controller = store.controller(for: payload, appState: appState)
            controller.reload()
            appState.pendingReloadTabId = nil
        }
        .onChange(of: browserChrome.pendingBrowserCommand) { _, newValue in
            guard let request = newValue else { return }
            handleBrowserCommand(request.action)
            appState.pendingBrowserCommand = nil
        }
        .onDisappear {
            store.teardownAll()
            moreMenuOpen = false
        }
    }

    private func handleBrowserCommand(_ action: BrowserCommandRequest.Action) {
        // newTab is the only action that doesn't require an active tab; the
        // others fall through silently when the panel is empty.
        if action == .newTab {
            appState.newBrowserTab()
            return
        }
        guard let payload = activeWeb else { return }
        let controller = store.controller(for: payload, appState: appState)
        switch action {
        case .newTab:
            return  // already handled above
        case .reload:
            controller.reload()
        case .forceReload:
            controller.hardReload()
        case .focusURLBar:
            BrowserView.focusSequence &+= 1
            appState.pendingFocusURLBar = BrowserFocusURLBarRequest(
                tabId: payload.id,
                sequence: BrowserView.focusSequence
            )
        case .closeActiveTab:
            appState.closeSidebarItem(payload.id)
        case .zoomIn:
            controller.zoomIn()
        case .zoomOut:
            controller.zoomOut()
        case .zoomReset:
            controller.resetZoom()
        }
    }

    private static var focusSequence: UInt64 = 0

    private var emptyState: some View {
        SidePanelLauncher()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
    }
}

private struct BrowserErrorOverlay: View {
    let error: BrowserTabController.NavigationError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            LucideIcon(.circleAlert, size: 22.5)
                .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
            Text("Cannot load page")
                .font(BodyFont.system(size: 14, wght: 600))
                .foregroundColor(Color.gray(light: 0.20, dark: 0.85))
            Text(error.message)
                .font(BodyFont.system(size: 12, wght: 400))
                .foregroundColor(Color.gray(light: 0.42, dark: 0.60))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let url = error.failedURL {
                Text(url.absoluteString)
                    .font(BodyFont.system(size: 11, wght: 400))
                    .foregroundColor(Color.gray(light: 0.50, dark: 0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)
            }
            Button(action: onRetry) {
                Text("Try again")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.gray(light: 0.88, dark: 0.20))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
