import SwiftUI
import WebKit

/// Center-pane surface for one App. Loads `clawix-app://<slug>/` into a
/// `WKWebView` with three custom hooks:
///
///   1. `AppURLSchemeHandler` resolves all in-app paths via the FS-backed
///      AppsStore (no HTTP, no localhost).
///   2. A `WKUserScript` injects a synchronous `window.__clawixContext`
///      with the app id/name + a few user fields so the SDK init has
///      something to expose without a round trip.
///   3. `AppBridgeMessageHandler` is wired under the message name
///      `clawix` so the SDK can call back into native code.
///
/// The chrome is intentionally absent: no URL bar, no back/forward, no
/// tabs. The app should not feel like a browser.
/// External links (target=_blank or any non-clawix-app navigation) are
/// kicked out to `NSWorkspace.shared.open` instead of being followed
/// inside the WKWebView.
struct AppSurfaceView: View {
    let appId: UUID

    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var databaseManager: DatabaseManager
    @Environment(\.surfaceRouteReporter) private var surfaceReporter
    @ObservedObject private var appsStore: AppsStore = .shared
    @State private var reloadToken: Int = 0
    @State private var loadState: AppSurfaceLoadState = .loading

    private var record: AppRecord? {
        appsStore.record(forId: appId)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let record {
                switch AppCapabilityCatalog.activationGate(for: record) {
                case .allowed:
                    switch record.effectiveSurfaceKind {
                    case .web:
                        AppSurfaceWebView(
                            appId: appId,
                            slug: record.slug,
                            appName: record.name,
                            reloadToken: reloadToken,
                            loadState: $loadState,
                            appsStore: appsStore,
                            appState: appState,
                            databaseManager: databaseManager,
                            surfaceReporter: surfaceReporter
                        )
                        .id("\(record.slug)-\(reloadToken)")

                        surfaceStateOverlay
                    case .swiftDeclarative:
                        AppSwiftSurfaceHostView(
                            record: record,
                            reloadToken: reloadToken,
                            appsStore: appsStore
                        )
                        .id("\(record.slug)-swift-\(reloadToken)")
                    }
                case .reviewRequired(let riskMap):
                    AppActivationReviewGate(
                        record: record,
                        riskMap: riskMap,
                        onActivate: { approve(record, riskMap: riskMap) }
                    )
                case .blockedUnknownCapabilities(let unknown):
                    AppActivationBlockedGate(record: record, unknownCapabilities: unknown)
                }

                surfaceToolbar
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            } else {
                missingAppPlaceholder
            }
        }
        .background(Palette.background)
        .onAppear {
            if let record {
                appsStore.markOpened(record)
                reportRecordState(record)
            } else {
                surfaceReporter.unavailable("App record is unavailable.")
            }
        }
        .onChange(of: loadState) { _, newState in
            reportLoadState(newState)
        }
        .onChange(of: reloadToken) { _, _ in
            loadState = .loading
            surfaceReporter.loading("Reloading app")
        }
        .task(id: reloadToken) {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, loadState == .loading else { return }
            loadState = .failed("The app surface took too long to load.")
        }
    }

    private var missingAppPlaceholder: some View {
        VStack(spacing: 12) {
            Text("App not found")
                .font(BodyFont.system(size: 18, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("This app may have been removed.")
                .font(BodyFont.system(size: 13.5, wght: 400))
                .foregroundColor(Color(white: 0.65))
            Button("Back to home") {
                appState.currentRoute = .home
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var surfaceToolbar: some View {
        HStack(spacing: 8) {
            Button {
                loadState = .loading
                reloadToken &+= 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Reload app")

            Button {
                appState.currentRoute = .appsHome
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("All apps")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        )
        .foregroundColor(Color(white: 0.92))
    }

    private func approve(_ record: AppRecord, riskMap: AppCapabilityRiskMap) {
        var updated = record
        updated.activationReview = AppActivationReview(riskMapSource: riskMap.source)
        try? appsStore.update(updated)
        loadState = .loading
        reloadToken &+= 1
    }

    private func reportRecordState(_ record: AppRecord) {
        switch AppCapabilityCatalog.activationGate(for: record) {
        case .allowed:
            reportLoadState(loadState)
        case .reviewRequired:
            surfaceReporter.partial("Review required before this app can run.")
        case .blockedUnknownCapabilities(let unknown):
            surfaceReporter.unavailable("Unsupported capabilities: \(unknown.joined(separator: ", ")).")
        }
    }

    private func reportLoadState(_ state: AppSurfaceLoadState) {
        switch state {
        case .loading:
            surfaceReporter.loading("Loading app")
        case .ready:
            surfaceReporter.ready()
        case .failed(let message):
            surfaceReporter.error(message)
        }
    }

    @ViewBuilder
    private var surfaceStateOverlay: some View {
        switch loadState {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading app")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.72))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.08).opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            )
            .allowsHitTesting(false)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.30))
                Text("App failed to load")
                    .font(BodyFont.system(size: 17, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(message)
                    .font(BodyFont.system(size: 13.5, wght: 400))
                    .foregroundColor(Color(white: 0.66))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Reload") {
                    loadState = .loading
                    reloadToken &+= 1
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background.opacity(0.92))
        case .ready:
            EmptyView()
        }
    }
}

private struct AppSwiftSurfaceHostView: View {
    let record: AppRecord
    let reloadToken: Int
    let appsStore: AppsStore

    @Environment(\.surfaceRouteReporter) private var surfaceReporter
    @State private var state: AppSwiftSurfaceHostState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading Swift surface")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Color(white: 0.72))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let plan):
                VStack(alignment: .leading, spacing: 12) {
                    Text(record.name)
                        .font(BodyFont.system(size: 22, wght: 650))
                        .foregroundColor(Palette.textPrimary)
                    Text("Swift surface runner exited cleanly.")
                        .font(BodyFont.system(size: 13.5, wght: 400))
                        .foregroundColor(Color(white: 0.66))
                    Text(plan.allowedCapabilities.joined(separator: ", ").nilIfEmpty ?? "No declared capabilities")
                        .font(BodyFont.system(size: 12.5, wght: 400))
                        .foregroundColor(Color(white: 0.56))
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.30))
                    Text("Swift surface unavailable")
                        .font(BodyFont.system(size: 17, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(message)
                        .font(BodyFont.system(size: 13.5, wght: 400))
                        .foregroundColor(Color(white: 0.66))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .cancelled:
                EmptyView()
            }
        }
        .background(Palette.background)
        .onAppear {
            reportHostState(state)
        }
        .onChange(of: state) { _, newState in
            reportHostState(newState)
        }
        .task(id: reloadToken) {
            await load()
        }
    }

    private func load() async {
        state = .loading
        guard let manifestBytes = appsStore.readFile(
            slug: record.slug,
            relativePath: AppSwiftSurfaceContract.manifestFilename
        )?.data else {
            state = .failed("Missing \(AppSwiftSurfaceContract.manifestFilename).")
            return
        }
        do {
            let manifest = try AppSwiftSurfaceContract.decodeManifest(data: manifestBytes)
            let manifestPath = appsStore.directory(forSlug: record.slug)
                .appendingPathComponent(AppSwiftSurfaceContract.manifestFilename)
                .path
            let plan = try AppSwiftSurfaceContract.runnerPlan(
                app: record,
                manifest: manifest,
                manifestPath: manifestPath
            )
            guard let executablePath = AppSwiftSurfaceContract.runnerExecutablePath() else {
                state = .failed("Swift surface runner is not configured.")
                return
            }
            let launch = AppSwiftSurfaceRunnerLaunch(
                plan: plan,
                executablePath: executablePath
            )
            let runnerTask = Task(priority: .userInitiated) {
                AppSwiftSurfaceRunnerSupervisor().launch(launch)
            }
            let runnerState = await withTaskCancellationHandler {
                await runnerTask.value
            } onCancel: {
                runnerTask.cancel()
            }
            guard !Task.isCancelled else {
                state = .cancelled
                return
            }
            state = Self.hostState(for: runnerState, plan: plan)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func reportHostState(_ state: AppSwiftSurfaceHostState) {
        switch state {
        case .loading:
            surfaceReporter.loading("Loading Swift surface")
        case .ready:
            surfaceReporter.ready()
        case .failed(let message):
            surfaceReporter.degraded(message)
        case .cancelled:
            surfaceReporter.cancelled()
        }
    }

    static func hostState(
        for runnerState: AppSwiftSurfaceRunnerState,
        plan: AppSwiftSurfaceRunnerPlan
    ) -> AppSwiftSurfaceHostState {
        switch runnerState {
        case .exited(code: 0):
            return .ready(plan)
        case .exited(let code):
            return .failed("Swift surface runner exited with status \(code).")
        case .crashed(let reason):
            return .failed(reason)
        case .timedOut(let seconds):
            return .failed("Swift surface runner timed out after \(Int(seconds)) seconds.")
        case .cancelled:
            return .cancelled
        case .idle, .launching, .running:
            return .failed("Swift surface runner did not complete.")
        }
    }
}

private enum AppSwiftSurfaceHostState: Equatable {
    case loading
    case ready(AppSwiftSurfaceRunnerPlan)
    case failed(String)
    case cancelled
}

private struct AppSurfaceWebView: NSViewRepresentable {
    let appId: UUID
    let slug: String
    let appName: String
    let reloadToken: Int
    @Binding var loadState: AppSurfaceLoadState
    let appsStore: AppsStore
    let appState: AppState
    let databaseManager: DatabaseManager
    let surfaceReporter: SurfaceRouteReporter

    func makeCoordinator() -> Coordinator {
        Coordinator(loadState: $loadState)
    }

    func makeNSView(context: Context) -> WKWebView {
        loadState = .loading
        let config = WKWebViewConfiguration()
        let preferences = WKPreferences()
        config.preferences = preferences
        config.defaultWebpagePreferences.preferredContentMode = .desktop

        // 1. URL scheme handler so clawix-app://<slug>/<path> hits the FS store.
        let schemeHandler = AppURLSchemeHandler(
            resolveFile: { [weak appsStore] slug, path in
                appsStore?.readFile(slug: slug, relativePath: path)
            },
            allowsInternet: { [weak appsStore] slug in
                appsStore?.record(forSlug: slug)?.permissions.internet ?? false
            }
        )
        config.setURLSchemeHandler(schemeHandler, forURLScheme: AppURLSchemeHandler.scheme)
        context.coordinator.schemeHandler = schemeHandler

        // 2. Inject the synchronous context + the SDK script.
        let contentController = WKUserContentController()
        let contextScript = WKUserScript(
            source: AppSurfaceView.contextBootstrapJS(appId: appId, slug: slug, appName: appName),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        let sdkScript = WKUserScript(
            source: appsStore.sdkScriptJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(contextScript)
        contentController.addUserScript(sdkScript)

        // 3. Bridge handler so window.clawix can post into Swift.
        let bridgeHandler = AppBridgeMessageHandler(
            slug: slug,
            appsStore: appsStore,
            appState: appState,
            databaseManager: databaseManager,
            surfaceReporter: surfaceReporter
        )
        contentController.add(bridgeHandler, name: AppBridgeMessageHandler.messageName)
        context.coordinator.bridgeHandler = bridgeHandler

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        bridgeHandler.webView = webView

        if let url = URL(string: "\(AppURLSchemeHandler.scheme)://\(slug)/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The .id() modifier on the parent view rebuilds the entire
        // WKWebView when reloadToken changes; this hook stays as a
        // no-op so SwiftUI doesn't try to reuse the old web context.
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.bridgeHandler?.cancelAllTrackedRequests()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: AppBridgeMessageHandler.messageName
        )
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.schemeHandler = nil
        coordinator.bridgeHandler = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var schemeHandler: AppURLSchemeHandler?
        var bridgeHandler: AppBridgeMessageHandler?
        var loadState: Binding<AppSurfaceLoadState>

        init(loadState: Binding<AppSurfaceLoadState>) {
            self.loadState = loadState
        }

        // Intercept navigation: anything that isn't `clawix-app://` is
        // shipped to the macOS default browser. Inside-scheme navs
        // (the user clicks a link inside their own app) are allowed.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == AppURLSchemeHandler.scheme {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadState.wrappedValue = .ready
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loadState.wrappedValue = .failed(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loadState.wrappedValue = .failed(error.localizedDescription)
        }

        // target=_blank windows: open in the system browser instead of
        // attempting to instantiate a popup inside the surface.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

private enum AppSurfaceLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

private struct AppActivationReviewGate: View {
    let record: AppRecord
    let riskMap: AppCapabilityRiskMap
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(record.name)
                .font(BodyFont.system(size: 22, wght: 650))
                .foregroundColor(Palette.textPrimary)
            Text("Review this app before activation.")
                .font(BodyFont.system(size: 14, wght: 450))
                .foregroundColor(Color(white: 0.68))

            VStack(alignment: .leading, spacing: 10) {
                riskLine(title: "Origin", value: record.effectiveOriginClass.rawValue)
                riskLine(title: "Ordinary access", value: riskMap.ordinaryAccess.joined(separator: ", ").nilIfEmpty ?? "None")
                riskLine(title: "Approval required", value: riskMap.approvalRequired.joined(separator: ", ").nilIfEmpty ?? "None")
                riskLine(title: "High risk", value: riskMap.highRisk.joined(separator: ", ").nilIfEmpty ?? "None")
            }

            HStack(spacing: 10) {
                Button("Activate") { onActivate() }
                    .buttonStyle(.borderedProminent)
                Text("High-risk actions still require approval when used.")
                    .font(BodyFont.system(size: 12.5, wght: 400))
                    .foregroundColor(Color(white: 0.56))
            }
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    private func riskLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(BodyFont.system(size: 12, wght: 650))
                .foregroundColor(Color(white: 0.82))
            Text(value)
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppActivationBlockedGate: View {
    let record: AppRecord
    let unknownCapabilities: [String]

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.30))
            Text("App cannot be activated")
                .font(BodyFont.system(size: 18, wght: 650))
                .foregroundColor(Palette.textPrimary)
            Text("\(record.name) requests unsupported capabilities: \(unknownCapabilities.joined(separator: ", ")).")
                .font(BodyFont.system(size: 13.5, wght: 400))
                .foregroundColor(Color(white: 0.66))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension AppSurfaceView {
    /// Bootstrap script injected before the SDK so `window.__clawixContext`
    /// is available synchronously when the SDK attaches `window.clawix`.
    /// User fields are intentionally minimal: no email, no chat ids.
    static func contextBootstrapJS(appId: UUID, slug: String, appName: String) -> String {
        let payload: [String: Any] = [
            "app": [
                "id": appId.uuidString,
                "slug": slug,
                "name": appName
            ],
            "user": [
                "name": NSFullUserName(),
                "locale": Locale.current.identifier
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "window.__clawixContext = \(json);"
    }
}
