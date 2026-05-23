import AppKit
import ApplicationServices
import CoreGraphics
import Combine

// MARK: - App snapshot (appshot)
//
// Captures the window of whatever app the user was last in before Clawix and
// attaches it to the composer, so they can hand the agent a picture of another
// app without manual screenshots. We track the last non-Clawix foreground app
// (the menu/composer steals focus, so the live frontmost app is Clawix itself)
// and grab that app's largest on-screen window — both as a PNG (visual
// content) and as the window's full text via Accessibility (including text
// scrolled out of view).

/// Everything one appshot carries: the window screenshot, the source app's
/// identity (for the chip's app-icon badge), the window title, and the
/// window's text content.
struct AppSnapshotResult {
    let imageURL: URL
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    /// Full window text read over Accessibility, including content scrolled
    /// offscreen. Empty when the Accessibility permission is not granted.
    let windowText: String
}

@MainActor
final class AppSnapshotCapture: ObservableObject {
    static let shared = AppSnapshotCapture()

    private var lastForegroundApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    /// Caps so a pathologically large app (a giant document, a console
    /// with a long scrollback) can't make the AX walk run away.
    private let maxAXNodes = 5_000
    private let maxTextCharacters = 100_000

    private init() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { lastForegroundApp = front }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self?.lastForegroundApp = app
                }
            }
        }
    }

    /// Display name of the app a snapshot would capture, for labels.
    var targetAppName: String? { lastForegroundApp?.localizedName }

    var hasTarget: Bool { lastForegroundApp != nil }

    /// Captures the target app's frontmost window: a PNG screenshot plus the
    /// window's title and full (incl. offscreen) text. Returns nil when
    /// nothing can be captured. Uses the system `screencapture` tool
    /// (`-l <windowID>`) so it shares the OS screen-recording permission path
    /// the rest of the app already uses; the text comes from the Accessibility
    /// API and is omitted (empty) when that permission is unavailable.
    func capture() -> AppSnapshotResult? {
        guard let app = lastForegroundApp else { return nil }
        let pid = app.processIdentifier
        guard let window = frontWindow(forPID: pid) else { return nil }

        let slug = (app.localizedName ?? "app")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let url = ClawixCaptureToolRoutes.appSnapshotURL(appSlug: slug)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ClawixCaptureToolRoutes.screencaptureCLI)
        // -x: silent, -o: omit window shadow, -l: capture this window id.
        process.arguments = ["-x", "-o", "-l", String(window.id), url.path]
        do {
            try process.run()
            // hot-path-ok maxItems=1 reason=single user-triggered screencapture subprocess
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: url.path) else { return nil }

        let ax = readWindowText(pid: pid, fallbackTitle: window.title)
        return AppSnapshotResult(
            imageURL: url,
            appName: app.localizedName ?? L10n.t("app window"),
            bundleId: app.bundleIdentifier,
            windowTitle: ax.title,
            windowText: ax.text
        )
    }

    /// Backward-compatible helper that only needs the PNG.
    func captureToFile() -> URL? { capture()?.imageURL }

    // MARK: - Window geometry

    private struct FrontWindow { let id: CGWindowID; let title: String? }

    private func frontWindow(forPID pid: pid_t) -> FrontWindow? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var best: (id: CGWindowID, title: String?, area: Double)?
        for window in windows {
            guard let pidValue = window[kCGWindowOwnerPID as String] as? Int, pid_t(pidValue) == pid else { continue }
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  let number = window[kCGWindowNumber as String] as? Int else { continue }
            let area = width * height
            if best == nil || area > best!.area {
                let title = (window[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
                best = (CGWindowID(number), title, area)
            }
        }
        guard let best else { return nil }
        return FrontWindow(id: best.id, title: best.title)
    }

    // MARK: - Accessibility text

    /// Reads the focused window's title and full text content via the
    /// Accessibility API. Text-bearing elements expose their entire value
    /// through `AXValue`, so this captures content scrolled out of view too.
    /// Returns `(fallbackTitle, "")` when the permission is missing or the
    /// app exposes no AX tree.
    private func readWindowText(pid: pid_t, fallbackTitle: String?) -> (title: String?, text: String) {
        guard AXIsProcessTrusted() else { return (fallbackTitle, "") }
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = focusedWindow(of: appElement) else { return (fallbackTitle, "") }

        let title = axString(window, kAXTitleAttribute as CFString) ?? fallbackTitle
        var collected: [String] = []
        var visited = 0
        collectText(from: window, into: &collected, visited: &visited)

        var text = collected.joined(separator: "\n")
        if text.count > maxTextCharacters {
            text = String(text.prefix(maxTextCharacters))
        }
        return (title, text)
    }

    private func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        if let focused = axElement(appElement, kAXFocusedWindowAttribute as CFString) {
            return focused
        }
        if let main = axElement(appElement, kAXMainWindowAttribute as CFString) {
            return main
        }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref) == .success,
           let windows = ref as? [AXUIElement] {
            return windows.first
        }
        return nil
    }

    private func collectText(from element: AXUIElement, into out: inout [String], visited: inout Int) {
        guard visited < maxAXNodes else { return }
        visited += 1

        if let value = axString(element, kAXValueAttribute as CFString) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(value) }
        }

        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return }
        for child in children {
            collectText(from: child, into: &out, visited: &visited)
        }
    }

    private func axElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success, let ref else { return nil }
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
    }
}
