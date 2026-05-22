extension BridgeBody {
    var typeTag: String {
        // Split into base bridge and audio helpers
        // so the Swift type-checker doesn't time out on a single
        // ~70-case switch ("compiler is unable to type-check this
        // expression in reasonable time"). Each helper covers a
        // disjoint set; the dispatcher tries audio -> base.
        if let tag = audioTypeTag { return tag }
        return baseTypeTag
    }

    private var baseTypeTag: String {
        switch self {
        case .auth:               return "auth"
        case .listSessions:          return "listSessions"
        case .openSession:           return "openSession"
        case .loadOlderMessages:  return "loadOlderMessages"
        case .sendMessage:         return "sendMessage"
        case .newSession:            return "newSession"
        case .interruptTurn:      return "interruptTurn"
        case .authOk:             return "authOk"
        case .authFailed:         return "authFailed"
        case .versionMismatch:    return "versionMismatch"
        case .sessionsSnapshot:      return "sessionsSnapshot"
        case .sessionUpdated:        return "sessionUpdated"
        case .messagesSnapshot:   return "messagesSnapshot"
        case .messagesPage:       return "messagesPage"
        case .messageAppended:    return "messageAppended"
        case .messageStreaming:   return "messageStreaming"
        case .errorEvent:         return "errorEvent"
        case .editPrompt:         return "editPrompt"
        case .archiveSession:        return "archiveSession"
        case .unarchiveSession:      return "unarchiveSession"
        case .pinSession:            return "pinSession"
        case .unpinSession:          return "unpinSession"
        case .renameSession:         return "renameSession"
        case .pairingStart:       return "pairingStart"
        case .pairingPayload:     return "pairingPayload"
        case .listProjects:       return "listProjects"
        case .projectsSnapshot:   return "projectsSnapshot"
        case .readFile:           return "readFile"
        case .fileSnapshot:       return "fileSnapshot"
        case .transcribeAudio:    return "transcribeAudio"
        case .transcriptionResult: return "transcriptionResult"
        case .requestAudio:       return "requestAudio"
        case .audioSnapshot:      return "audioSnapshot"
        case .requestGeneratedImage: return "requestGeneratedImage"
        case .generatedImageSnapshot: return "generatedImageSnapshot"
        case .requestRolloutAttachment: return "requestRolloutAttachment"
        case .rolloutAttachmentSnapshot: return "rolloutAttachmentSnapshot"
        case .bridgeState:        return "bridgeState"
        case .requestRateLimits:  return "requestRateLimits"
        case .rateLimitsSnapshot: return "rateLimitsSnapshot"
        case .rateLimitsUpdated:  return "rateLimitsUpdated"
        case .requestClawJSServiceStatuses: return "requestClawJSServiceStatuses"
        case .clawJSServiceStatusesSnapshot: return "clawJSServiceStatusesSnapshot"
        case .clawJSServiceStatusUpdated: return "clawJSServiceStatusUpdated"
        default:
            // Unreachable: every base bridge case is enumerated above
            // and audio cases are handled by `audioTypeTag` before this branch.
            // If a new case is added without updating either helper this
            // will trip in tests, which is the desired behaviour.
            preconditionFailure("BridgeBody.baseTypeTag missing case for \(self)")
        }
    }

    private var audioTypeTag: String? {
        switch self {
        case .audioRegister:               return "audioRegister"
        case .audioAttachTranscript:       return "audioAttachTranscript"
        case .audioGet:                    return "audioGet"
        case .audioGetBytes:               return "audioGetBytes"
        case .audioList:                   return "audioList"
        case .audioDelete:                 return "audioDelete"
        case .audioRegisterResult:         return "audioRegisterResult"
        case .audioAttachTranscriptResult: return "audioAttachTranscriptResult"
        case .audioGetResult:              return "audioGetResult"
        case .audioBytesResult:            return "audioBytesResult"
        case .audioListResult:             return "audioListResult"
        case .audioDeleteResult:           return "audioDeleteResult"
        default:
            return nil
        }
    }
}
