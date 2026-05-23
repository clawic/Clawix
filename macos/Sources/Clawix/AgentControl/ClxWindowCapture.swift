import AppKit

/// In-process window capture. Renders a window's content view (or one control's
/// region) to a PNG without the `screencapture` CLI, without bringing the window
/// to the front, and even while the window is occluded or off-screen, so many
/// agent instances can capture in parallel.
enum ClxWindowCapture {
    @MainActor
    static func capturePNG(windowNumber: Int?, controlId: String?) -> Data? {
        let window: NSWindow?
        if let number = windowNumber {
            window = NSApp.windows.first { $0.windowNumber == number }
        } else {
            window = NSApp.keyWindow ?? NSApp.windows.first { $0.contentView != nil }
        }
        guard let window, let view = window.contentView else { return nil }

        var rect = view.bounds
        if let controlId, let controlRect = controlRectInView(controlId, view: view, window: window) {
            rect = controlRect
        }
        guard rect.width > 0, rect.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Convert a control's AX frame (screen coords, top-left origin) into the
    /// content view's coordinate space so a single control can be captured.
    @MainActor
    private static func controlRectInView(_ id: String, view: NSView, window: NSWindow) -> NSRect? {
        guard let element = ClxAX.find(identifier: id),
              let screenRect = ClxAX.frame(element),
              let screen = window.screen ?? NSScreen.screens.first else { return nil }
        let cocoaY = screen.frame.maxY - screenRect.origin.y - screenRect.size.height
        let cocoaScreenRect = NSRect(
            x: screenRect.origin.x,
            y: cocoaY,
            width: screenRect.size.width,
            height: screenRect.size.height
        )
        let windowRect = window.convertFromScreen(cocoaScreenRect)
        let viewRect = view.convert(windowRect, from: nil)
        let clipped = viewRect.intersection(view.bounds)
        return clipped.isEmpty ? nil : clipped
    }
}
