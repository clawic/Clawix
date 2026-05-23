import AppKit
import SwiftUI

extension AppState {
    /// Captures the last frontmost app's window and stages it as a composer
    /// attachment. Shared by the "+" menu path (after the enable modal) and
    /// the keyboard double-modifier trigger. Returns silently when there is
    /// no capturable window.
    @MainActor
    func captureAppshotIntoComposer(activateApp: Bool = false) {
        guard AppshotSettings.isEnabled else { return }
        guard let result = AppSnapshotCapture.shared.capture() else { return }

        let attachment = ComposerAttachment(
            url: result.imageURL,
            appshot: AppshotMetadata(
                appName: result.appName,
                bundleId: result.bundleId,
                windowTitle: result.windowTitle,
                windowText: result.windowText
            )
        )

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible })
                ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
        }

        withAnimation(.easeInOut(duration: 0.20)) {
            addComposerAttachment(attachment)
        }
        requestComposerFocus()
    }

    /// Entry point for the global ⌘+⌘ (or ⌥/⇧) trigger. The gesture fires
    /// while another app is frontmost, so we bring Clawix forward before
    /// staging the attachment.
    @MainActor
    func captureAppshotFromHotkey() {
        captureAppshotIntoComposer(activateApp: true)
    }

    /// Append a pre-built attachment (e.g. an appshot carrying window text),
    /// de-duplicating by file path the same way `addComposerAttachments` does.
    @MainActor
    func addComposerAttachment(_ attachment: ComposerAttachment) {
        let path = attachment.url.standardizedFileURL.path
        guard !composer.attachments.contains(where: { $0.url.standardizedFileURL.path == path }) else { return }
        composer.attachments.append(attachment)
    }
}
