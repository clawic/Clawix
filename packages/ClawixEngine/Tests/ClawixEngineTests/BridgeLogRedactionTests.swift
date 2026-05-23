import XCTest
@testable import ClawixEngine

final class BridgeLogRedactionTests: XCTestCase {
    func testRedactsSensitiveDiagnosticText() {
        let apiKey = "sk-" + "testtemplate0000000000000000"
        let userPath = "/Users/" + "sensitive/.codex/sessions/2026/05/23/"
        let sessionId = "rollout-" + "2026-05-23T10-11-12-123-" + "01234567-89ab-cdef-0123-456789abcdef.jsonl"
        let input = """
        prompt="Use the user's confidential launch notes"
        Authorization: Bearer \(apiKey)
        secret://provider/openai/main
        \(userPath)\(sessionId)
        """

        let redacted = BridgeLog.redactForDiagnostics(input)

        XCTAssertFalse(redacted.contains("confidential launch notes"))
        XCTAssertFalse(redacted.contains(apiKey))
        XCTAssertFalse(redacted.contains("secret://"))
        XCTAssertFalse(redacted.contains(userPath))
        XCTAssertTrue(redacted.contains("prompt=<redacted:content>"))
        XCTAssertTrue(redacted.contains("Bearer <redacted>"))
    }
}
