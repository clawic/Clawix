extension BridgeBody {
    func encodeAudioPayload(into c: inout KeyedEncodingContainer<BridgePayloadKeys>) throws -> Bool {
        switch self {
        case .audioRegister(let requestId, let request):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(request, forKey: .request)
        case .audioAttachTranscript(let requestId, let audioId, let transcript):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(transcript, forKey: .transcript)
        case .audioGet(let requestId, let audioId, let appId):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(appId, forKey: .appId)
        case .audioGetBytes(let requestId, let audioId, let appId):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(appId, forKey: .appId)
        case .audioList(let requestId, let filter):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(filter, forKey: .filter)
        case .audioDelete(let requestId, let audioId, let appId):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(audioId, forKey: .audioId)
            try c.encode(appId, forKey: .appId)
        case .audioRegisterResult(let requestId, let asset, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(asset, forKey: .asset)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioAttachTranscriptResult(let requestId, let transcript, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(transcript, forKey: .transcript)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioGetResult(let requestId, let asset, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(asset, forKey: .asset)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioBytesResult(let requestId, let audioBase64, let mimeType, let durationMs, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(audioBase64, forKey: .audioBase64)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(durationMs, forKey: .durationMs)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioListResult(let requestId, let list, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(list, forKey: .list)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        case .audioDeleteResult(let requestId, let deleted, let errorMessage):
            try c.encode(requestId, forKey: .requestId)
            try c.encode(deleted, forKey: .deleted)
            try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        default:
            return false
        }
        return true
    }

    static func decodeAudio(type: String, from c: KeyedDecodingContainer<BridgePayloadKeys>) throws -> BridgeBody? {
        switch type {
        case "audioRegister":
            return .audioRegister(
                requestId: try c.decode(String.self, forKey: .requestId),
                request: try c.decode(WireAudioRegisterRequest.self, forKey: .request)
            )
        case "audioAttachTranscript":
            return .audioAttachTranscript(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                transcript: try c.decode(WireAudioAttachTranscriptInput.self, forKey: .transcript)
            )
        case "audioGet":
            return .audioGet(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                appId: try c.decode(String.self, forKey: .appId)
            )
        case "audioGetBytes":
            return .audioGetBytes(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                appId: try c.decode(String.self, forKey: .appId)
            )
        case "audioList":
            return .audioList(
                requestId: try c.decode(String.self, forKey: .requestId),
                filter: try c.decode(WireAudioListFilter.self, forKey: .filter)
            )
        case "audioDelete":
            return .audioDelete(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioId: try c.decode(String.self, forKey: .audioId),
                appId: try c.decode(String.self, forKey: .appId)
            )
        case "audioRegisterResult":
            return .audioRegisterResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                asset: try c.decodeIfPresent(WireAudioAssetWithTranscripts.self, forKey: .asset),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioAttachTranscriptResult":
            return .audioAttachTranscriptResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                transcript: try c.decodeIfPresent(WireAudioTranscript.self, forKey: .transcript),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioGetResult":
            return .audioGetResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                asset: try c.decodeIfPresent(WireAudioAssetWithTranscripts.self, forKey: .asset),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioBytesResult":
            return .audioBytesResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                audioBase64: try c.decodeIfPresent(String.self, forKey: .audioBase64),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                durationMs: try c.decodeIfPresent(Int.self, forKey: .durationMs),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioListResult":
            return .audioListResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                list: try c.decodeIfPresent(WireAudioListResult.self, forKey: .list),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        case "audioDeleteResult":
            return .audioDeleteResult(
                requestId: try c.decode(String.self, forKey: .requestId),
                deleted: try c.decode(Bool.self, forKey: .deleted),
                errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage)
            )
        default:
            return nil
        }
    }
}
