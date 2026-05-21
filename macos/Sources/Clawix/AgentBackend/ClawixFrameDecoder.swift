import Foundation

enum ClawixFrameLimits {
    static let warnBytes = 1 * 1024 * 1024
    static let maxBytes = 8 * 1024 * 1024
}

struct ClawixStdoutFramer {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0a) {
            let frame = buffer.subdata(in: 0 ..< newline)
            buffer.removeSubrange(0 ... newline)
            if frame.count > ClawixFrameLimits.maxBytes {
                throw ClawixClientError.frameTooLarge(bytes: frame.count, maxBytes: ClawixFrameLimits.maxBytes)
            }
            if !frame.isEmpty {
                frames.append(frame)
            }
        }
        if buffer.count > ClawixFrameLimits.maxBytes {
            let bytes = buffer.count
            buffer.removeAll(keepingCapacity: false)
            throw ClawixClientError.frameTooLarge(bytes: bytes, maxBytes: ClawixFrameLimits.maxBytes)
        }
        return frames
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}

struct ClawixFrameHeader: Decodable {
    let id: ClawixRPCID?
    let method: String?
}

enum ClawixServerNotification {
    case threadStarted(ThreadStartedEnvelope)
    case threadArchived(ThreadIdNotification)
    case threadUnarchived(ThreadIdNotification)
    case threadNameUpdated(ThreadNameUpdatedNotification)
    case turnStarted(TurnEnvelope)
    case turnCompleted(TurnEnvelope)
    case itemStarted(ItemEnvelope)
    case itemCompleted(ItemEnvelope)
    case agentMessageDelta(AgentMessageDelta)
    case reasoningTextDelta(ReasoningTextDelta)
    case reasoningSummaryTextDelta(ReasoningTextDelta)
    case threadTokenUsage(ThreadTokenUsageEnvelope)
    case accountRateLimitsUpdated(AccountRateLimitsUpdatedNotification)
    case error
    case unknown(method: String)
}

enum ClawixServerRequest {
    case toolUserInput(id: ClawixRPCID, params: ToolRequestUserInputParams)
    case approval(id: ClawixRPCID, method: String)
    case unknown(id: ClawixRPCID, method: String)
}

actor ClawixFrameDecoder {
    private let decoder = JSONDecoder()

    func decodeHeader(_ data: Data) throws -> ClawixFrameHeader {
        try decode(ClawixFrameHeader.self, from: data, intervalName: "decode.header")
    }

    func decodeNotification(method: String, data: Data) throws -> ClawixServerNotification {
        switch method {
        case ClawixMethod.nThreadStarted:
            return .threadStarted(try decodeParams(ThreadStartedEnvelope.self, from: data))
        case ClawixMethod.nThreadArchived:
            return .threadArchived(try decodeParams(ThreadIdNotification.self, from: data))
        case ClawixMethod.nThreadUnarchived:
            return .threadUnarchived(try decodeParams(ThreadIdNotification.self, from: data))
        case ClawixMethod.nThreadNameUpdated:
            return .threadNameUpdated(try decodeParams(ThreadNameUpdatedNotification.self, from: data))
        case ClawixMethod.nTurnStarted:
            return .turnStarted(try decodeParams(TurnEnvelope.self, from: data))
        case ClawixMethod.nTurnCompleted:
            return .turnCompleted(try decodeParams(TurnEnvelope.self, from: data))
        case ClawixMethod.nItemStarted:
            return .itemStarted(try decodeParams(ItemEnvelope.self, from: data))
        case ClawixMethod.nItemCompleted:
            return .itemCompleted(try decodeParams(ItemEnvelope.self, from: data))
        case ClawixMethod.nAgentMsgDelta:
            return .agentMessageDelta(try decodeParams(AgentMessageDelta.self, from: data))
        case ClawixMethod.nReasoningDelta:
            return .reasoningTextDelta(try decodeParams(ReasoningTextDelta.self, from: data))
        case ClawixMethod.nReasoningSumDelta:
            return .reasoningSummaryTextDelta(try decodeParams(ReasoningTextDelta.self, from: data))
        case ClawixMethod.nThreadTokenUsage:
            return .threadTokenUsage(try decodeParams(ThreadTokenUsageEnvelope.self, from: data))
        case ClawixMethod.nAccountRateLimitsUpdated:
            return .accountRateLimitsUpdated(try decodeParams(AccountRateLimitsUpdatedNotification.self, from: data))
        case ClawixMethod.nError:
            return .error
        default:
            return .unknown(method: method)
        }
    }

    func decodeRequest(id: ClawixRPCID, method: String, data: Data) throws -> ClawixServerRequest {
        switch method {
        case ClawixMethod.rToolUserInput:
            return .toolUserInput(id: id, params: try decodeParams(ToolRequestUserInputParams.self, from: data))
        case ClawixMethod.rFileChangeApproval,
             ClawixMethod.rExecApproval,
             ClawixMethod.rPermissionsApproval:
            return .approval(id: id, method: method)
        default:
            return .unknown(id: id, method: method)
        }
    }

    func decodeResponse<R: Decodable>(_ data: Data, expecting: R.Type) throws -> R {
        let response = try decode(ClawixIncomingResponse<R>.self, from: data, intervalName: "decode")
        if let error = response.error {
            throw ClawixClientError.rpcError(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            if R.self == ClawixIgnoredResponse.self {
                return ClawixIgnoredResponse() as! R
            }
            throw ClawixClientError.invalidResponse("Missing result")
        }
        return result
    }

    private func decodeParams<P: Decodable>(_ type: P.Type, from data: Data) throws -> P {
        let message = try decode(ClawixIncomingParamsMessage<P>.self, from: data, intervalName: "decode")
        guard let params = message.params else {
            throw ClawixClientError.invalidResponse("Missing params")
        }
        return params
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, intervalName: StaticString) throws -> T {
        PerfSignpost.ipcClient.event("decode.bytes", data.count)
        do {
            return try PerfSignpost.ipcClient.interval(intervalName) {
                try decoder.decode(type, from: data)
            }
        } catch {
            PerfSignpost.ipcClient.event("decode.failed")
            throw error
        }
    }
}

private struct ClawixIncomingParamsMessage<P: Decodable>: Decodable {
    let params: P?
}

private struct ClawixIncomingResponse<R: Decodable>: Decodable {
    let result: R?
    let error: ClawixErrorBody?
}
