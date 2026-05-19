import Foundation

enum AppBridgeRedactionPolicy {
    static let policyId = "claw.customApps.redaction.v1"
    static let sensitiveFieldTokens = [
        "secret",
        "password",
        "credential",
        "apikey",
        "accesstoken",
        "refreshtoken",
        "privatetoken",
        "privatekey",
    ]

    static func normalizedFieldName(_ field: String) -> String {
        field
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func isSensitiveField(_ field: String) -> Bool {
        let normalized = normalizedFieldName(field)
        return sensitiveFieldTokens.contains { normalized.contains($0) }
    }
}
