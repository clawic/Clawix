import Foundation
import ClawixCore
import ImageIO
import Observation
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class BridgeTranscriptStore {
    private static let inlineAttachmentMaxPixelSize = 512

    var messagesByChat: [String: [WireMessage]] = [:]
    var hasMoreByChat: [String: Bool] = [:]
    var loadingOlderByChat: [String: Bool] = [:]
    var oldestKnownIdByChat: [String: String] = [:]

    #if canImport(UIKit)
    var attachmentImagesByMessageId: [String: [UIImage]] = [:]
    #endif

    var isEmpty: Bool {
        messagesByChat.isEmpty
    }

    func messages(for chatId: String) -> [WireMessage] {
        messagesByChat[chatId] ?? []
    }

    func hasLoadedMessages(_ chatId: String) -> Bool {
        messagesByChat[chatId] != nil
    }

    func isLoadingOlder(_ chatId: String) -> Bool {
        loadingOlderByChat[chatId] == true
    }

    func replaceAll(_ messages: [String: [WireMessage]]) {
        messagesByChat = messages
        hasMoreByChat = [:]
        loadingOlderByChat = [:]
        oldestKnownIdByChat = messages.mapValues { $0.first?.id }.compactMapValues { $0 }
        #if canImport(UIKit)
        attachmentImagesByMessageId = [:]
        for list in messages.values {
            for msg in list where !msg.attachments.isEmpty {
                ingestInlineAttachments(messageId: msg.id, attachments: msg.attachments)
            }
        }
        #endif
    }

    func replaceState(from other: BridgeTranscriptStore) {
        messagesByChat = other.messagesByChat
        hasMoreByChat = other.hasMoreByChat
        loadingOlderByChat = other.loadingOlderByChat
        oldestKnownIdByChat = other.oldestKnownIdByChat
        #if canImport(UIKit)
        attachmentImagesByMessageId = other.attachmentImagesByMessageId
        #endif
    }

    func reset() {
        messagesByChat = [:]
        hasMoreByChat = [:]
        loadingOlderByChat = [:]
        oldestKnownIdByChat = [:]
        #if canImport(UIKit)
        attachmentImagesByMessageId = [:]
        #endif
    }

    func prune(keeping chatIds: Set<String>) {
        messagesByChat = messagesByChat.filter { chatIds.contains($0.key) }
        hasMoreByChat = hasMoreByChat.filter { chatIds.contains($0.key) }
        loadingOlderByChat = loadingOlderByChat.filter { chatIds.contains($0.key) }
        oldestKnownIdByChat = oldestKnownIdByChat.filter { chatIds.contains($0.key) }
    }

    @discardableResult
    func appendOptimisticUserMessage(chatId: String, text: String, attachmentCount: Int = 0) -> String? {
        let preview = previewForUserBubble(text: text, attachmentCount: attachmentCount)
        let messageId = "local-\(UUID().uuidString)"
        let optimistic = WireMessage(
            id: messageId,
            role: .user,
            content: preview,
            timestamp: Date()
        )
        messagesByChat[chatId, default: []].append(optimistic)
        return messageId
    }

    func appendLocalCrisisRefusal(chatId: String, text: String) {
        let refusal = WireMessage(
            id: "local-crisis-\(UUID().uuidString)",
            role: .assistant,
            content: text,
            streamingFinished: true,
            timestamp: Date()
        )
        messagesByChat[chatId, default: []].append(refusal)
    }

    func applyMessagesSnapshot(chatId: String, messages: [WireMessage], hasMore: Bool? = nil) {
        hasMoreByChat[chatId] = hasMore ?? false
        loadingOlderByChat[chatId] = false
        oldestKnownIdByChat[chatId] = messages.first?.id
        if let current = messagesByChat[chatId], current == messages {
            return
        }
        let placeholders = (messagesByChat[chatId] ?? []).filter {
            $0.id.hasPrefix("local-") && $0.role == .user
        }
        let reconciled: [WireMessage]
        if placeholders.isEmpty {
            reconciled = messages
        } else {
            var consumed: Set<String> = []
            reconciled = messages.map { msg in
                guard msg.role == .user,
                      let placeholder = placeholders.first(where: {
                          !consumed.contains($0.id) && $0.content == msg.content
                      })
                else { return msg }
                consumed.insert(placeholder.id)
                return WireMessage(
                    id: placeholder.id,
                    role: msg.role,
                    content: msg.content,
                    reasoningText: msg.reasoningText,
                    streamingFinished: msg.streamingFinished,
                    isError: msg.isError,
                    timestamp: msg.timestamp,
                    timeline: msg.timeline,
                    workSummary: msg.workSummary,
                    audioRef: msg.audioRef,
                    attachments: msg.attachments
                )
            }
        }
        messagesByChat[chatId] = reconciled
        oldestKnownIdByChat[chatId] = reconciled.first?.id
        #if canImport(UIKit)
        for msg in reconciled {
            ingestInlineAttachments(messageId: msg.id, attachments: msg.attachments)
        }
        #endif
    }

    func applyMessagesPage(chatId: String, messages: [WireMessage], hasMore: Bool) {
        loadingOlderByChat[chatId] = false
        hasMoreByChat[chatId] = hasMore
        guard !messages.isEmpty else { return }
        var current = messagesByChat[chatId] ?? []
        let existingIds = Set(current.map(\.id))
        let prepend = messages.filter { !existingIds.contains($0.id) }
        guard !prepend.isEmpty else { return }
        current.insert(contentsOf: prepend, at: 0)
        messagesByChat[chatId] = current
        oldestKnownIdByChat[chatId] = current.first?.id
        #if canImport(UIKit)
        for msg in prepend {
            ingestInlineAttachments(messageId: msg.id, attachments: msg.attachments)
        }
        #endif
    }

    func applyMessageAppended(chatId: String, message: WireMessage) {
        var current = messagesByChat[chatId] ?? []
        if message.role == .user,
           let idx = current.firstIndex(where: {
               $0.id.hasPrefix("local-")
                   && $0.role == .user
                   && $0.content == message.content
           }) {
            let placeholderId = current[idx].id
            current[idx] = WireMessage(
                id: placeholderId,
                role: message.role,
                content: message.content,
                reasoningText: message.reasoningText,
                streamingFinished: message.streamingFinished,
                isError: message.isError,
                timestamp: message.timestamp,
                timeline: message.timeline,
                workSummary: message.workSummary,
                audioRef: message.audioRef,
                attachments: message.attachments
            )
            #if canImport(UIKit)
            ingestInlineAttachments(messageId: placeholderId, attachments: message.attachments)
            #endif
        } else {
            current.append(message)
            #if canImport(UIKit)
            ingestInlineAttachments(messageId: message.id, attachments: message.attachments)
            #endif
        }
        messagesByChat[chatId] = current
    }

    func applyStreamingBatch(_ updates: [PendingStreamUpdate]) {
        for update in updates {
            var current = messagesByChat[update.sessionId] ?? []
            if let idx = current.firstIndex(where: { $0.id == update.messageId }) {
                current[idx].content = update.content
                current[idx].reasoningText = update.reasoning
                current[idx].streamingFinished = update.finished
                messagesByChat[update.sessionId] = current
            }
        }
    }

    func seedLoadedEmpty(chatId: String) {
        messagesByChat[chatId] = []
    }

    func hasLocalOptimisticUserMessage(chatId: String) -> Bool {
        messagesByChat[chatId]?.contains(where: { $0.id.hasPrefix("local-") && $0.role == .user }) ?? false
    }

    func markLoadingOlder(chatId: String) -> String? {
        guard hasMoreByChat[chatId] == true else { return nil }
        guard loadingOlderByChat[chatId] != true else { return nil }
        guard let cursor = oldestKnownIdByChat[chatId] else { return nil }
        loadingOlderByChat[chatId] = true
        return cursor
    }

    func cancelLoadingOlder(chatId: String) {
        loadingOlderByChat[chatId] = false
    }

    func finishOrDropTrailingAssistant(chatId: String) {
        guard var current = messagesByChat[chatId],
              let lastIdx = current.indices.last,
              current[lastIdx].role == .assistant,
              !current[lastIdx].streamingFinished
        else { return }
        let msg = current[lastIdx]
        let isEmpty = msg.content.isEmpty
            && msg.reasoningText.isEmpty
            && msg.timeline.isEmpty
            && (msg.workSummary?.items.isEmpty ?? true)
        if isEmpty {
            current.remove(at: lastIdx)
        } else {
            current[lastIdx].streamingFinished = true
        }
        messagesByChat[chatId] = current
    }

    #if canImport(UIKit)
    func attachLocalImages(messageId: String, images: [UIImage]) {
        guard !images.isEmpty else { return }
        attachmentImagesByMessageId[messageId] = images
    }
    #endif

    private func previewForUserBubble(text: String, attachmentCount: Int) -> String {
        guard attachmentCount > 0 else { return text }
        let label = attachmentCount == 1 ? "[image]" : "[\(attachmentCount) images]"
        return text.isEmpty ? label : "\(label) \(text)"
    }

    #if canImport(UIKit)
    private func ingestInlineAttachments(messageId: String, attachments: [WireAttachment]) {
        guard !attachments.isEmpty else { return }
        if attachmentImagesByMessageId[messageId] != nil { return }
        var images: [UIImage] = []
        for att in attachments where att.kind == .image {
            guard let data = Data(
                    base64Encoded: att.dataBase64,
                    options: .ignoreUnknownCharacters
                  ),
                  let image = Self.downsampledImage(
                    from: data,
                    maxPixelSize: Self.inlineAttachmentMaxPixelSize
                  ) else { continue }
            images.append(image)
        }
        if !images.isEmpty {
            attachmentImagesByMessageId[messageId] = images
        }
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
    #endif
}
