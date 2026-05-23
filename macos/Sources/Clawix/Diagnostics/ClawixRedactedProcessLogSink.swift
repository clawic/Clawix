import Foundation

final class ClawixRedactedProcessLogSink {
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    private let handle: FileHandle
    private let queue = DispatchQueue(label: "com.clawix.redacted-process-log-sink")
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var isClosed = false

    init(logURL: URL, fileManager: FileManager = .default) throws {
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        self.handle = handle
        attachReaders()
    }

    func close() {
        queue.sync {
            guard !isClosed else { return }
            isClosed = true
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            flushLocked(&stdoutBuffer)
            flushLocked(&stderrBuffer)
            try? handle.close()
        }
    }

    private func attachReaders() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            self?.read(fileHandle.availableData, stream: .stdout)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            self?.read(fileHandle.availableData, stream: .stderr)
        }
    }

    private enum Stream {
        case stdout
        case stderr
    }

    private func read(_ data: Data, stream: Stream) {
        queue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            if data.isEmpty {
                switch stream {
                case .stdout:
                    self.flushLocked(&self.stdoutBuffer)
                    self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
                case .stderr:
                    self.flushLocked(&self.stderrBuffer)
                    self.stderrPipe.fileHandleForReading.readabilityHandler = nil
                }
                return
            }
            switch stream {
            case .stdout:
                self.appendLocked(data, to: &self.stdoutBuffer)
            case .stderr:
                self.appendLocked(data, to: &self.stderrBuffer)
            }
        }
    }

    private func appendLocked(_ data: Data, to buffer: inout Data) {
        buffer.append(data)
        flushCompleteLinesLocked(&buffer)
        if buffer.count > 64 * 1024 {
            flushLocked(&buffer)
        }
    }

    private func flushCompleteLinesLocked(_ buffer: inout Data) {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(through: newlineIndex)
            writeLocked(Data(line))
            buffer.removeSubrange(...newlineIndex)
        }
    }

    private func flushLocked(_ buffer: inout Data) {
        guard !buffer.isEmpty else { return }
        writeLocked(buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private func writeLocked(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let redacted = ClawixDiagnosticRedactor.redact(text)
        try? handle.write(contentsOf: Data(redacted.utf8))
    }
}
