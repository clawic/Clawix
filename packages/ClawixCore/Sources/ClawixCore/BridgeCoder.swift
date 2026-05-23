import Foundation

public enum BridgeCoder {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode(_ frame: BridgeFrame) throws -> Data {
        try encoder.encode(frame)
    }

    public static func decode(_ data: Data, maxBytes: Int = bridgeMaxFrameBytes) throws -> BridgeFrame {
        try BridgeFrameValidation.validate(data, maxBytes: maxBytes)
        let type = BridgeFrameValidation.frameType(in: data) ?? "unknown"
        do {
            return try decoder.decode(BridgeFrame.self, from: data)
        } catch {
            throw BridgeFrameValidation.wrapDecodeError(error, type: type)
        }
    }
}
