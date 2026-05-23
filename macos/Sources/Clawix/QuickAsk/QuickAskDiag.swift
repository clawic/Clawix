import Foundation

/// Diagnostic-only file logger for the QuickAsk module. NSLog goes
/// through os_log which redacts Swift-interpolated strings as
/// `<private>`, making it impossible to read controller/hotkey state
/// from `log show`. This appends to a known path so we can inspect the
/// hotkey/show flow directly. Remove once the "panel sometimes does
/// not open" bug is understood.
enum QuickAskDiag {

    private static let logURL = ClawixDiagnosticLogRoutes.quickAskLogURL
    private static let rotatedLogURL = logURL.deletingPathExtension().appendingPathExtension("1.log")
    private static let maxLogBytes: UInt64 = 256 * 1024
    private static let queue = DispatchQueue(label: "clawix.quickask.diag")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let safeMessage = ClawixDiagnosticRedactor.redact(message)
        let line = "[\(formatter.string(from: Date()))] \(safeMessage)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded(addingBytes: UInt64(data.count))
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private static func rotateIfNeeded(addingBytes: UInt64) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? NSNumber,
              size.uint64Value + addingBytes > maxLogBytes
        else { return }
        try? fm.removeItem(at: rotatedLogURL)
        try? fm.moveItem(at: logURL, to: rotatedLogURL)
    }
}
