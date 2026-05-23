import Foundation

/// Materialises inline image attachments coming off the bridge as
/// on-disk files. The Codex backend accepts image inputs as `localImage`
/// items keyed by absolute path, so every attachment that arrives over
/// the WS bridge has to be written to a file before we can hand it to a
/// `turn/start` call.
///
/// Files live under
/// `NSTemporaryDirectory()/clawix-attachments/<thread-or-chat-id>/<attachment-id>.<ext>`
/// so they are easy to spot, easy to delete, and grouped together if
/// debugging is needed. Call `cleanup(scope:)` only for drafts or simulated
/// sends whose references are no longer needed; resumed threads may still
/// point at the materialized paths.
public enum AttachmentSpooler {
    public static let directoryName = "clawix-attachments"

    /// Writes the attachments to disk and returns the absolute paths in
    /// the same order the inputs were provided. Decoding/IO failures are
    /// silently skipped: a missing image is preferable to bringing the
    /// whole turn down on a single corrupt blob.
    @discardableResult
    public static func write(
        attachments: [WireAttachment],
        scope: String,
        log: ((String) -> Void)? = nil
    ) -> [String] {
        guard !attachments.isEmpty else { return [] }
        let root = scopedDirectory(scope: scope)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            log?("attachment directory unavailable")
            return []
        }
        var paths: [String] = []
        for attachment in attachments {
            guard let dataBase64 = attachment.dataBase64,
                  let data = Data(base64Encoded: dataBase64) else {
                log?("attachment decode failed")
                continue
            }
            let ext = preferredExtension(filename: attachment.filename, mimeType: attachment.mimeType)
            let url = root.appendingPathComponent("\(safePathComponent(attachment.id)).\(ext)")
            do {
                try data.write(to: url, options: .atomic)
                paths.append(url.path)
            } catch {
                log?("attachment write failed")
            }
        }
        return paths
    }

    @discardableResult
    public static func cleanup(
        scope: String,
        log: ((String) -> Void)? = nil
    ) -> Bool {
        let root = scopedDirectory(scope: scope)
        guard FileManager.default.fileExists(atPath: root.path) else { return true }
        do {
            try FileManager.default.removeItem(at: root)
            return true
        } catch {
            log?("attachment cleanup failed")
            return false
        }
    }

    public static func scopedDirectory(scope: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(safePathComponent(scope), isDirectory: true)
    }

    private static func preferredExtension(filename: String?, mimeType: String) -> String {
        if let filename, let dotRange = filename.range(of: ".", options: .backwards) {
            let candidate = String(filename[dotRange.upperBound...]).lowercased()
            if !candidate.isEmpty, candidate.count <= 5 { return candidate }
        }
        switch mimeType.lowercased() {
        case "image/png":  return "png"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/webp": return "webp"
        case "image/gif":  return "gif"
        default:           return "jpg"
        }
    }

    private static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "attachment" : sanitized
    }
}
