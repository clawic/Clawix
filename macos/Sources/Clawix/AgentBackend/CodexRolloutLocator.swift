import Foundation

enum CodexRolloutLocator {
    static func find(
        threadId: String,
        sessionsRoot: URL = ClawixAgentBackendRoutes.codexSessionsDirectory(),
        fileManager: FileManager = .default
    ) -> URL? {
        let needle = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              !needle.contains("/"),
              !needle.contains("\\")
        else { return nil }

        for dayDirectory in likelySessionDayDirectories(
            threadId: needle,
            sessionsRoot: sessionsRoot
        ) {
            if let hit = bestMatch(
                in: dayDirectory,
                threadId: needle,
                recursive: false,
                fileManager: fileManager
            ) {
                return hit
            }
        }

        return bestMatch(
            in: sessionsRoot,
            threadId: needle,
            recursive: true,
            fileManager: fileManager
        )
    }

    static func findLikelyDayMatch(
        threadId: String,
        sessionsRoot: URL = ClawixAgentBackendRoutes.codexSessionsDirectory(),
        fileManager: FileManager = .default
    ) -> URL? {
        let needle = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              !needle.contains("/"),
              !needle.contains("\\")
        else { return nil }

        for dayDirectory in likelySessionDayDirectories(
            threadId: needle,
            sessionsRoot: sessionsRoot
        ) {
            if let hit = bestMatch(
                in: dayDirectory,
                threadId: needle,
                recursive: false,
                fileManager: fileManager
            ) {
                return hit
            }
        }
        return nil
    }

    private static func bestMatch(
        in directory: URL,
        threadId needle: String,
        recursive: Bool,
        fileManager: FileManager
    ) -> URL? {
        var best: (url: URL, modifiedAt: Date?)?
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]

        func consider(_ url: URL) {
            let name = url.lastPathComponent
            guard name.hasSuffix(".jsonl"), name.contains(needle) else { return }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { return }
            let candidate = (url: url, modifiedAt: values?.contentModificationDate)
            guard let current = best else {
                best = candidate
                return
            }
            if (candidate.modifiedAt ?? .distantPast) > (current.modifiedAt ?? .distantPast) {
                best = candidate
            }
        }

        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: []
            ) else { return nil }
            for case let url as URL in enumerator {
                consider(url)
            }
        } else {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return nil }
            for url in urls {
                consider(url)
            }
        }
        return best?.url
    }

    private static func likelySessionDayDirectories(threadId: String, sessionsRoot: URL) -> [URL] {
        let hex = threadId.unicodeScalars.filter { scalar in
            (48...57).contains(scalar.value) ||
                (65...70).contains(scalar.value) ||
                (97...102).contains(scalar.value)
        }
        guard hex.count >= 13 else { return [] }
        let compact = String(String.UnicodeScalarView(hex))
        let versionIndex = compact.index(compact.startIndex, offsetBy: 12)
        guard compact[versionIndex] == "7",
              let milliseconds = UInt64(compact.prefix(12), radix: 16)
        else { return [] }

        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0)
        var calendars = [Calendar(identifier: .gregorian)]
        calendars[0].timeZone = .current
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendars.append(utc)

        var seen = Set<String>()
        var directories: [URL] = []
        for calendar in calendars {
            for offset in -1...1 {
                guard let candidateDate = calendar.date(byAdding: .day, value: offset, to: date) else {
                    continue
                }
                let components = calendar.dateComponents([.year, .month, .day], from: candidateDate)
                guard let year = components.year,
                      let month = components.month,
                      let day = components.day
                else { continue }
                let pathKey = "\(year)/\(month)/\(day)"
                guard seen.insert(pathKey).inserted else { continue }
                directories.append(
                    sessionsRoot
                        .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                        .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                        .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
                )
            }
        }
        return directories
    }
}
