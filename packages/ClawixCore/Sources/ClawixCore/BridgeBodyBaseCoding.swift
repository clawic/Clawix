extension BridgeBody {
    func encodeBasePayload(into c: inout KeyedEncodingContainer<BridgePayloadKeys>) throws {
        switch self {
        case .auth(let token, let deviceName, let clientKind, let clientId, let installationId, let deviceId):
            try c.encode(token, forKey: .token)
            try c.encodeIfPresent(deviceName, forKey: .deviceName)
            try c.encode(clientKind, forKey: .clientKind)
            try c.encode(clientId, forKey: .clientId)
            try c.encode(installationId, forKey: .installationId)
            try c.encode(deviceId, forKey: .deviceId)
        case .listSessions:
            break
        case .openSession(let sessionId, let limit):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encodeIfPresent(limit, forKey: .limit)
        case .loadOlderMessages(let sessionId, let beforeMessageId, let limit):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(beforeMessageId, forKey: .beforeMessageId)
            try c.encode(limit, forKey: .limit)
        case .sendMessage(let sessionId, let text, let attachments):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(text, forKey: .text)
            if !attachments.isEmpty {
                try c.encode(attachments, forKey: .attachments)
            }
        case .newSession(let sessionId, let text, let attachments):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(text, forKey: .text)
            if !attachments.isEmpty {
                try c.encode(attachments, forKey: .attachments)
            }
        case .interruptTurn(let sessionId):
            try c.encode(sessionId, forKey: .sessionId)
        case .authOk(let hostDisplayName):
            try c.encodeIfPresent(hostDisplayName, forKey: .hostDisplayName)
        case .authFailed(let reason):
            try c.encode(reason, forKey: .reason)
        case .versionMismatch(let serverVersion):
            try c.encode(serverVersion, forKey: .serverVersion)
        case .sessionsSnapshot(let sessions):
            try c.encode(sessions, forKey: .sessions)
        case .sessionUpdated(let session):
            try c.encode(session, forKey: .session)
        case .messagesSnapshot(let sessionId, let messages, let hasMore):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messages, forKey: .messages)
            try c.encodeIfPresent(hasMore, forKey: .hasMore)
        case .messagesPage(let sessionId, let messages, let hasMore):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messages, forKey: .messages)
            try c.encode(hasMore, forKey: .hasMore)
        case .messageAppended(let sessionId, let message):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(message, forKey: .message)
        case .messageStreaming(let sessionId, let messageId, let content, let reasoningText, let finished):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(content, forKey: .content)
            try c.encode(reasoningText, forKey: .reasoningText)
            try c.encode(finished, forKey: .finished)
        case .errorEvent(let code, let message):
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
        case .editPrompt(let sessionId, let messageId, let text):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(text, forKey: .text)
        case .archiveSession(let sessionId), .unarchiveSession(let sessionId),
             .pinSession(let sessionId), .unpinSession(let sessionId):
            try c.encode(sessionId, forKey: .sessionId)
        case .renameSession(let sessionId, let title):
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(title, forKey: .title)
        case .pairingStart, .listProjects:
            break
        case .pairingPayload(let qrJson, let token, let shortCode):
            try c.encode(qrJson, forKey: .qrJson)
            try c.encode(token, forKey: .token)
            try c.encode(shortCode, forKey: .shortCode)
        case .projectsSnapshot(let projects):
            try c.encode(projects, forKey: .projects)
        case .readFile(let path):
            try c.encode(path, forKey: .path)
        case .fileSnapshot(let path, let content, let isMarkdown, let error):
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(content, forKey: .content)
            try c.encode(isMarkdown, forKey: .isMarkdown)
            try c.encodeIfPresent(error, forKey: .error)
        case .transcribeAudio(let requestId, let audioBase64, let mimeType, let language):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioBase64, forKey: .audioBase64)
            try c.encode(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(language, forKey: .language)
        case .transcriptionResult(let requestId, let text, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .requestAudio(let audioId):
            try c.encode(audioId, forKey: .audioId)
        case .audioSnapshot(let audioId, let audioBase64, let mimeType, let errorMessage):
            try c.encode(audioId, forKey: .audioId)
            try c.encodeIfPresent(audioBase64, forKey: .audioBase64)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .requestGeneratedImage(let path):
            try c.encode(path, forKey: .path)
        case .generatedImageSnapshot(let path, let dataBase64, let mimeType, let errorMessage):
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(dataBase64, forKey: .dataBase64)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .requestRolloutAttachment(let attachmentId):
            try c.encode(attachmentId, forKey: .attachmentId)
        case .rolloutAttachmentSnapshot(let attachmentId, let dataBase64, let mimeType, let errorMessage):
            try c.encode(attachmentId, forKey: .attachmentId)
            try c.encodeIfPresent(dataBase64, forKey: .dataBase64)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .bridgeState(let state, let chatCount, let message):
            try c.encode(state, forKey: .state)
            try c.encode(chatCount, forKey: .chatCount)
            try c.encodeIfPresent(message, forKey: .message)
        case .requestRateLimits:
            break
        case .rateLimitsSnapshot(let snapshot, let byLimitId):
            try c.encodeIfPresent(snapshot, forKey: .rateLimits)
            try c.encode(byLimitId, forKey: .rateLimitsByLimitId)
        case .rateLimitsUpdated(let snapshot, let byLimitId):
            try c.encodeIfPresent(snapshot, forKey: .rateLimits)
            try c.encode(byLimitId, forKey: .rateLimitsByLimitId)
        case .requestClawJSServiceStatuses:
            break
        case .clawJSServiceStatusesSnapshot(let services):
            try c.encode(services, forKey: .services)
        case .clawJSServiceStatusUpdated(let service):
            try c.encode(service, forKey: .service)
        default:
            // Audio cases are handled in encodeAudioPayload, called before
            // this method by the encodePayload dispatcher. Unknown base
            // cases would be a programming error caught by round-trip tests.
            break
        }
    }

    static func decodeBase(type: String, from c: KeyedDecodingContainer<BridgePayloadKeys>) throws -> BridgeBody {
        switch type {
        case "auth":
            return .auth(
                token: try c.decode(String.self, forKey: .token),
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName),
                clientKind: try c.decode(ClientKind.self, forKey: .clientKind),
                clientId: try c.decode(String.self, forKey: .clientId),
                installationId: try c.decode(String.self, forKey: .installationId),
                deviceId: try c.decode(String.self, forKey: .deviceId)
            )
        case "listSessions":
            return .listSessions
        case "openSession":
            return .openSession(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                limit: try c.decodeIfPresent(Int.self, forKey: .limit)
            )
        case "loadOlderMessages":
            return .loadOlderMessages(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                beforeMessageId: try c.decode(String.self, forKey: .beforeMessageId),
                limit: try c.decode(Int.self, forKey: .limit)
            )
        case "sendMessage":
            return .sendMessage(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                text: try c.decode(String.self, forKey: .text),
                attachments: try c.decodeIfPresent([WireAttachment].self, forKey: .attachments) ?? []
            )
        case "newSession":
            return .newSession(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                text: try c.decode(String.self, forKey: .text),
                attachments: try c.decodeIfPresent([WireAttachment].self, forKey: .attachments) ?? []
            )
        case "interruptTurn":
            return .interruptTurn(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "authOk":
            return .authOk(hostDisplayName: try c.decodeIfPresent(String.self, forKey: .hostDisplayName))
        case "authFailed":
            return .authFailed(reason: try c.decode(String.self, forKey: .reason))
        case "versionMismatch":
            return .versionMismatch(serverVersion: try c.decode(Int.self, forKey: .serverVersion))
        case "sessionsSnapshot":
            return .sessionsSnapshot(sessions: try c.decode([WireSession].self, forKey: .sessions))
        case "sessionUpdated":
            return .sessionUpdated(session: try c.decode(WireSession.self, forKey: .session))
        case "messagesSnapshot":
            return .messagesSnapshot(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                messages: try c.decode([WireMessage].self, forKey: .messages),
                hasMore: try c.decodeIfPresent(Bool.self, forKey: .hasMore)
            )
        case "messagesPage":
            return .messagesPage(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                messages: try c.decode([WireMessage].self, forKey: .messages),
                hasMore: try c.decode(Bool.self, forKey: .hasMore)
            )
        case "messageAppended":
            return .messageAppended(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                message: try c.decode(WireMessage.self, forKey: .message)
            )
        case "messageStreaming":
            return .messageStreaming(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                messageId: try c.decode(String.self, forKey: .messageId),
                content: try c.decode(String.self, forKey: .content),
                reasoningText: try c.decode(String.self, forKey: .reasoningText),
                finished: try c.decode(Bool.self, forKey: .finished)
            )
        case "errorEvent":
            return .errorEvent(
                code: try c.decode(String.self, forKey: .code),
                message: try c.decode(String.self, forKey: .message)
            )
        case "editPrompt":
            return .editPrompt(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                messageId: try c.decode(String.self, forKey: .messageId),
                text: try c.decode(String.self, forKey: .text)
            )
        case "archiveSession":
            return .archiveSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "unarchiveSession":
            return .unarchiveSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "pinSession":
            return .pinSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "unpinSession":
            return .unpinSession(sessionId: try c.decode(String.self, forKey: .sessionId))
        case "renameSession":
            return .renameSession(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                title: try c.decode(String.self, forKey: .title)
            )
        case "pairingStart":
            return .pairingStart
        case "pairingPayload":
            return .pairingPayload(
                qrJson: try c.decode(String.self, forKey: .qrJson),
                token: try c.decode(String.self, forKey: .token),
                shortCode: try c.decode(String.self, forKey: .shortCode)
            )
        case "listProjects":
            return .listProjects
        case "projectsSnapshot":
            return .projectsSnapshot(projects: try c.decode([WireProject].self, forKey: .projects))
        case "readFile":
            return .readFile(path: try c.decode(String.self, forKey: .path))
        case "fileSnapshot":
            return .fileSnapshot(
                path: try c.decode(String.self, forKey: .path),
                content: try c.decodeIfPresent(String.self, forKey: .content),
                isMarkdown: try c.decodeIfPresent(Bool.self, forKey: .isMarkdown) ?? false,
                error: try c.decodeIfPresent(String.self, forKey: .error)
            )
        case "transcribeAudio":
            return .transcribeAudio(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioBase64: try c.decode(String.self, forKey: .audioBase64),
                mimeType: try c.decode(String.self, forKey: .mimeType),
                language: try c.decodeIfPresent(String.self, forKey: .language)
            )
        case "transcriptionResult":
            return .transcriptionResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                text: try c.decode(String.self, forKey: .text),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "requestAudio":
            return .requestAudio(audioId: try c.decode(String.self, forKey: .audioId))
        case "audioSnapshot":
            return .audioSnapshot(
                audioId: try c.decode(String.self, forKey: .audioId),
                audioBase64: try c.decodeIfPresent(String.self, forKey: .audioBase64),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "requestGeneratedImage":
            return .requestGeneratedImage(path: try c.decode(String.self, forKey: .path))
        case "generatedImageSnapshot":
            return .generatedImageSnapshot(
                path: try c.decode(String.self, forKey: .path),
                dataBase64: try c.decodeIfPresent(String.self, forKey: .dataBase64),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "requestRolloutAttachment":
            return .requestRolloutAttachment(attachmentId: try c.decode(String.self, forKey: .attachmentId))
        case "rolloutAttachmentSnapshot":
            return .rolloutAttachmentSnapshot(
                attachmentId: try c.decode(String.self, forKey: .attachmentId),
                dataBase64: try c.decodeIfPresent(String.self, forKey: .dataBase64),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "bridgeState":
            return .bridgeState(
                state: try c.decode(String.self, forKey: .state),
                chatCount: try c.decode(Int.self, forKey: .chatCount),
                message: try c.decodeIfPresent(String.self, forKey: .message)
            )
        case "requestRateLimits":
            return .requestRateLimits
        case "rateLimitsSnapshot":
            return .rateLimitsSnapshot(
                snapshot: try c.decodeIfPresent(WireRateLimitSnapshot.self, forKey: .rateLimits),
                byLimitId: try c.decodeIfPresent([String: WireRateLimitSnapshot].self, forKey: .rateLimitsByLimitId) ?? [:]
            )
        case "rateLimitsUpdated":
            return .rateLimitsUpdated(
                snapshot: try c.decodeIfPresent(WireRateLimitSnapshot.self, forKey: .rateLimits),
                byLimitId: try c.decodeIfPresent([String: WireRateLimitSnapshot].self, forKey: .rateLimitsByLimitId) ?? [:]
            )
        case "requestClawJSServiceStatuses":
            return .requestClawJSServiceStatuses
        case "clawJSServiceStatusesSnapshot":
            return .clawJSServiceStatusesSnapshot(
                services: try c.decode([WireClawJSServiceSnapshot].self, forKey: .services)
            )
        case "clawJSServiceStatusUpdated":
            return .clawJSServiceStatusUpdated(
                service: try c.decode(WireClawJSServiceSnapshot.self, forKey: .service)
            )
        default:
            throw BridgeDecodingError.unknownType(type)
        }
    }
}
