    enum BridgePayloadKeys: String, CodingKey {
        case token, deviceName, clientKind, clientId, installationId, deviceId
        case sessionId, text, messageId, title
        case hostDisplayName, reason, serverVersion
        case sessions, session, messages, message
        case content, reasoningText, finished
        case code
        case qrJson, shortCode
        case projects
        case path, isMarkdown, error
        case attachments
        case requestId, audioBase64, mimeType, language, errorMessage
        case audioId, attachmentId
        case dataBase64
        case limit, beforeMessageId, hasMore
        case state, chatCount
        case rateLimits, rateLimitsByLimitId
        case services, service
        // Audio catalog
        case appId, request, transcript, asset, list, filter, durationMs, deleted
    }
