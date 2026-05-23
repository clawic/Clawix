import Foundation

enum BridgeFrameValidation {
    static let topLevelKeys: Set<String> = ["schemaVersion", "type"]

    static func validate(_ data: Data, maxBytes: Int) throws {
        guard data.count <= maxBytes else {
            throw BridgeDecodingError.oversizedFrame(actualBytes: data.count, maxBytes: maxBytes)
        }

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BridgeDecodingError.invalidJSON(normalize(error))
        }

        guard let object = raw as? [String: Any] else {
            throw BridgeDecodingError.nonObjectFrame
        }

        guard object.keys.contains("schemaVersion") else {
            throw BridgeDecodingError.missingField("schemaVersion")
        }
        guard let schemaVersion = object["schemaVersion"] as? Int else {
            throw BridgeDecodingError.invalidField("schemaVersion")
        }
        guard schemaVersion == bridgeSchemaVersion else {
            throw BridgeDecodingError.unknownSchemaVersion(schemaVersion)
        }

        guard object.keys.contains("type") else {
            throw BridgeDecodingError.missingField("type")
        }
        guard let type = object["type"] as? String, !type.isEmpty else {
            throw BridgeDecodingError.invalidField("type")
        }
        guard let payloadKeys = allowedPayloadKeys(for: type) else {
            throw BridgeDecodingError.unknownType(type)
        }

        let allowed = topLevelKeys.union(payloadKeys)
        if let extra = object.keys.first(where: { !allowed.contains($0) }) {
            throw BridgeDecodingError.unknownField(type: type, field: extra)
        }
    }

    static func wrapDecodeError(_ error: Error, type: String) -> BridgeDecodingError {
        if let bridgeError = error as? BridgeDecodingError {
            return bridgeError
        }
        return .invalidPayload(type: type, message: normalize(error))
    }

    static func frameType(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["type"] as? String
    }

    private static func allowedPayloadKeys(for type: String) -> Set<String>? {
        switch type {
        case "auth":
            return keys(.token, .deviceName, .clientKind, .clientId, .installationId, .deviceId)
        case "listSessions", "pairingStart", "listProjects", "requestRateLimits", "requestClawJSServiceStatuses":
            return []
        case "openSession":
            return keys(.sessionId, .limit)
        case "loadOlderMessages":
            return keys(.sessionId, .beforeMessageId, .limit)
        case "sendMessage", "newSession":
            return keys(.sessionId, .text, .attachments)
        case "interruptTurn", "archiveSession", "unarchiveSession", "pinSession", "unpinSession":
            return keys(.sessionId)
        case "authOk":
            return keys(.hostDisplayName)
        case "authFailed":
            return keys(.reason)
        case "versionMismatch":
            return keys(.serverVersion)
        case "sessionsSnapshot":
            return keys(.sessions)
        case "sessionUpdated":
            return keys(.session)
        case "messagesSnapshot", "messagesPage":
            return keys(.sessionId, .messages, .hasMore)
        case "messageAppended":
            return keys(.sessionId, .message)
        case "messageStreaming":
            return keys(.sessionId, .messageId, .content, .reasoningText, .finished)
        case "errorEvent":
            return keys(.code, .message)
        case "editPrompt":
            return keys(.sessionId, .messageId, .text)
        case "renameSession":
            return keys(.sessionId, .title)
        case "readFile":
            return keys(.path)
        case "pairingPayload":
            return keys(.qrJson, .token, .shortCode)
        case "projectsSnapshot":
            return keys(.projects)
        case "fileSnapshot":
            return keys(.path, .content, .isMarkdown, .error)
        case "transcribeAudio":
            return keys(.requestId, .audioBase64, .mimeType, .language)
        case "transcriptionResult":
            return keys(.requestId, .text, .errorMessage)
        case "requestAudio":
            return keys(.audioId)
        case "audioSnapshot":
            return keys(.audioId, .audioBase64, .mimeType, .errorMessage)
        case "requestGeneratedImage":
            return keys(.path)
        case "generatedImageSnapshot":
            return keys(.path, .dataBase64, .mimeType, .errorMessage)
        case "requestRolloutAttachment":
            return keys(.attachmentId)
        case "rolloutAttachmentSnapshot":
            return keys(.attachmentId, .dataBase64, .mimeType, .errorMessage)
        case "bridgeState":
            return keys(.state, .chatCount, .message)
        case "rateLimitsSnapshot", "rateLimitsUpdated":
            return keys(.rateLimits, .rateLimitsByLimitId)
        case "clawJSServiceStatusesSnapshot":
            return keys(.services)
        case "clawJSServiceStatusUpdated":
            return keys(.service)
        case "audioRegister":
            return keys(.requestId, .request)
        case "audioAttachTranscript":
            return keys(.requestId, .audioId, .transcript)
        case "audioGet", "audioGetBytes", "audioDelete":
            return keys(.requestId, .audioId, .appId)
        case "audioList":
            return keys(.requestId, .filter)
        case "audioRegisterResult":
            return keys(.requestId, .asset, .errorMessage)
        case "audioAttachTranscriptResult":
            return keys(.requestId, .transcript, .errorMessage)
        case "audioGetResult":
            return keys(.requestId, .asset, .errorMessage)
        case "audioBytesResult":
            return keys(.requestId, .audioBase64, .mimeType, .durationMs, .errorMessage)
        case "audioListResult":
            return keys(.requestId, .list, .errorMessage)
        case "audioDeleteResult":
            return keys(.requestId, .deleted, .errorMessage)
        default:
            return nil
        }
    }

    private static func keys(_ keys: BridgePayloadKeys...) -> Set<String> {
        Set(keys.map(\.rawValue))
    }

    private static func normalize(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return normalize(decodingError)
        }
        let nsError = error as NSError
        if !nsError.localizedDescription.isEmpty {
            return nsError.localizedDescription
        }
        return String(describing: error)
    }

    private static func normalize(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "missing field \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }
}
