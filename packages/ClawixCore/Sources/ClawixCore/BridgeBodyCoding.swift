extension BridgeBody {
    func encodePayload(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: BridgePayloadKeys.self)
        // Helpers split by domain so the Swift type-checker doesn't
        // time out on a single ~70-case switch. Try audio -> base.
        if try encodeAudioPayload(into: &c) { return }
        try encodeBasePayload(into: &c)
    }

    static func decode(type: String, from decoder: Decoder) throws -> BridgeBody {
        let c = try decoder.container(keyedBy: BridgePayloadKeys.self)
        // Helpers split by domain. Try audio -> base.
        if let body = try decodeAudio(type: type, from: c) { return body }
        return try decodeBase(type: type, from: c)
    }
}
