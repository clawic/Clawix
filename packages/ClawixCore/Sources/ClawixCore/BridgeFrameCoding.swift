extension BridgeFrame {
    private enum TopKeys: String, CodingKey {
        case schemaVersion
        case type
    }

    public init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: TopKeys.self)
        self.schemaVersion = try top.decode(Int.self, forKey: .schemaVersion)
        let type = try top.decode(String.self, forKey: .type)
        self.body = try BridgeBody.decode(type: type, from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var top = encoder.container(keyedBy: TopKeys.self)
        try top.encode(schemaVersion, forKey: .schemaVersion)
        try top.encode(body.typeTag, forKey: .type)
        try body.encodePayload(to: encoder)
    }
}
