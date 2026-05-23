import SwiftUI
import AppKit
import Combine
import Darwin

// MARK: - Performance trace
//
// A user-facing performance capture: while recording, a small floating
// indicator shows elapsed time and lets the user stop; on stop a lightweight
// resource-sample trace (memory footprint + timestamps) is written under
// ~/.clawix/traces/ and revealed in Finder. This is a self-contained capture
// for sharing/inspection, separate from the always-on internal diagnostics.

@MainActor
final class PerfTraceController: ObservableObject {
    static let shared = PerfTraceController()

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var startedAt: Date?
    private var timer: Timer?
    private var samples: [[String: Any]] = []
    private var panel: NSPanel?

    private init() {}

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard !isRecording else { return }
        samples.removeAll()
        elapsed = 0
        startedAt = Date()
        isRecording = true
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        showIndicator()
    }

    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        timer?.invalidate(); timer = nil
        isRecording = false
        panel?.orderOut(nil); panel = nil
        let url = writeTrace()
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        return url
    }

    private func tick() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        samples.append([
            "t": round(elapsed * 100) / 100,
            "rssMB": round(Self.residentMemoryMB() * 10) / 10,
        ])
    }

    private func writeTrace() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clawix/traces", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let url = dir.appendingPathComponent("trace-\(stamp).json", isDirectory: false)
        let payload: [String: Any] = [
            "startedAtMs": (startedAt?.timeIntervalSince1970 ?? 0) * 1000,
            "durationSeconds": elapsed,
            "sampleCount": samples.count,
            "samples": samples,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return nil }
        try? data.write(to: url)
        return url
    }

    private func showIndicator() {
        let hosting = NSHostingView(rootView: PerfTraceIndicator())
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 188, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: visible.midX - 94, y: visible.maxY - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    static func residentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024.0 / 1024.0
    }
}

private struct PerfTraceIndicator: View {
    @ObservedObject private var controller = PerfTraceController.shared
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.92, green: 0.32, blue: 0.32))
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.45 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
                }
            Text(L10n.t("Recording"))
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(formatted(controller.elapsed))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Palette.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 4)
            Button(L10n.t("Stop")) { controller.stop() }
                .buttonStyle(.plain)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Color(white: 0.06))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(white: 0.94)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
        )
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }
}
