import Foundation
import ClawixCore

struct RolloutAttachmentBytes: Sendable {
    let data: Data
    let mimeType: String
}

final class RolloutAttachmentRegistry: @unchecked Sendable {
    static let shared = RolloutAttachmentRegistry()

    private struct Record {
        let url: URL
        let mimeType: String
    }

    private let lock = NSLock()
    private var records: [String: Record] = [:]

    func register(id: String, url: URL, mimeType: String) {
        lock.lock()
        records[id] = Record(url: url.standardizedFileURL, mimeType: mimeType)
        lock.unlock()
    }

    func bytes(for id: String) -> RolloutAttachmentBytes? {
        lock.lock()
        let record = records[id]
        lock.unlock()
        guard let record,
              let data = try? Data(contentsOf: record.url),
              !data.isEmpty else {
            return nil
        }
        return RolloutAttachmentBytes(data: data, mimeType: record.mimeType)
    }

    func resetForTests() {
        lock.lock()
        records.removeAll()
        lock.unlock()
    }
}

final class RolloutCursorRegistry: @unchecked Sendable {
    static let shared = RolloutCursorRegistry()

    private let lock = NSLock()
    private var offsetsByMessageId: [String: UInt64] = [:]

    func register(messageId: String, offset: UInt64) {
        lock.lock()
        offsetsByMessageId[messageId] = offset
        lock.unlock()
    }

    func offset(for messageId: String) -> UInt64? {
        lock.lock()
        let offset = offsetsByMessageId[messageId]
        lock.unlock()
        return offset
    }

    func resetForTests() {
        lock.lock()
        offsetsByMessageId.removeAll()
        lock.unlock()
    }
}
