import Foundation

/// Shared stderr logger for the bridge code paths. Writes go through
/// the same `[clawix-bridge]` prefix the daemon already uses so the
/// reader script that watches `/private/tmp/clawix-bridge.err` and
/// `clawix logs` doesn't need to learn a second format. The macOS GUI
/// also calls into this when it spins up an in-process `BridgeServer`,
/// which lands those lines in the GUI's own stderr (visible in
/// Console.app under the `Clawix` process).
public enum BridgeLog {
    public static func write(_ message: String) {
        let safe = redactForDiagnostics(message)
        FileHandle.standardError.write(Data(("[clawix-bridge] \(safe)\n").utf8))
    }

    /// Redact obvious secrets, local paths, and prompt-shaped payloads so logs
    /// copied into screenshots or support reports stay public-safe.
    static func redactForDiagnostics(_ s: String) -> String {
        let replacements: [(String, String)] = [
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{10,}\b"#, "Bearer <redacted>"),
            (#"\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})\b"#, "<redacted>"),
            (#"secret://[^\s"'`)},\]]+"#, "<redacted:secret-ref>"),
            (#"-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----"#, "<redacted:private-key>"),
            (#"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{32,}(?![A-Za-z0-9_-])"#, "<redacted>"),
            (#"\b(prompt|systemPrompt|userPrompt|message|input|transcript|trace)\s*[:=]\s*("[^"\n]{12,}"|'[^'\n]{12,}'|`[^`\n]{12,}`|[^\n]{24,})"#, "$1=<redacted:content>"),
            (NSHomeDirectory().replacingOccurrences(of: "/", with: "\\/"), "~"),
            (#"/Users/(?!example(?:/|\b)|demo(?:/|\b)|me(?:/|\b)|tester(?:/|\b)|alice(?:/|\b)|person(?:/|\b)|private(?:/|\b)|<redacted>(?:/|\b))[A-Za-z0-9._-]+[^\s"'`)},\]]*"#, "<redacted:path>")
        ]
        return replacements.reduce(s) { current, replacement in
            let (pattern, template) = replacement
            guard let re = try? NSRegularExpression(pattern: pattern) else { return current }
            let range = NSRange(current.startIndex..., in: current)
            return re.stringByReplacingMatches(in: current, range: range, withTemplate: template)
        }
    }
}
