import AppKit
import CoreGraphics
import Combine

// MARK: - App snapshot (appshot)
//
// Captures the window of whatever app the user was last in before Clawix and
// attaches it to the composer, so they can hand the agent a picture of another
// app without manual screenshots. We track the last non-Clawix foreground app
// (the menu/composer steals focus, so the live frontmost app is Clawix itself)
// and grab that app's largest on-screen window.

@MainActor
final class AppSnapshotCapture: ObservableObject {
    static let shared = AppSnapshotCapture()

    private var lastForegroundApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

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

    /// Captures the target app's frontmost window into a PNG in the temp
    /// directory and returns its URL, or nil when nothing can be captured.
    /// Uses the system `screencapture` tool (`-l <windowID>`) so it shares the
    /// OS screen-recording permission path the rest of the app already uses.
    func captureToFile() -> URL? {
        guard let app = lastForegroundApp,
              let windowID = frontWindowID(forPID: app.processIdentifier) else { return nil }

        let slug = (app.localizedName ?? "app")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-appshot-\(slug)-\(Int(Date().timeIntervalSince1970)).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x: silent, -o: omit window shadow, -l: capture this window id.
        process.arguments = ["-x", "-o", "-l", String(windowID), url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func frontWindowID(forPID pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var best: (id: CGWindowID, area: Double)?
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int, pid_t(owner) == pid else { continue }
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  let number = window[kCGWindowNumber as String] as? Int else { continue }
            let area = width * height
            if best == nil || area > best!.area { best = (CGWindowID(number), area) }
        }
        return best?.id
    }
}
