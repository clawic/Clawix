import Foundation

// Git working-tree inspection + mutation for the right side-panel "Review /
// Changes" surface. A heavier sibling of `GitInspector` (which only powers
// the composer branch pill): this one enumerates per-file staged/unstaged
// changes with +/- line counts, reads per-file unified diffs, and stages /
// unstages / discards files. Every call shells out to `git` with a short
// timeout. All functions are synchronous and meant to run OFF the main
// thread (the view model hops to a background queue).

struct GitFileChange: Identifiable, Equatable {
    enum Kind: Equatable {
        case added, modified, deleted, renamed, copied, typeChanged, untracked, unmerged

        init(statusChar c: Character) {
            switch c {
            case "A": self = .added
            case "M": self = .modified
            case "D": self = .deleted
            case "R": self = .renamed
            case "C": self = .copied
            case "T": self = .typeChanged
            case "U": self = .unmerged
            case "?": self = .untracked
            default:  self = .modified
            }
        }
    }

    /// Repo-relative path (the new path for renames). Doubles as identity
    /// within a single (staged/unstaged) list.
    let path: String
    let oldPath: String?
    let kind: Kind
    let staged: Bool
    let added: Int
    let removed: Int

    var id: String { (staged ? "s:" : "u:") + path }
}

struct GitChangesSnapshot: Equatable {
    let hasRepo: Bool
    let root: String?
    let branch: String?
    let staged: [GitFileChange]
    let unstaged: [GitFileChange]

    static let empty = GitChangesSnapshot(
        hasRepo: false, root: nil, branch: nil, staged: [], unstaged: []
    )

    var isClean: Bool { staged.isEmpty && unstaged.isEmpty }
    var totalAdded: Int { (staged + unstaged).reduce(0) { $0 + $1.added } }
    var totalRemoved: Int { (staged + unstaged).reduce(0) { $0 + $1.removed } }
}

enum GitChangesService {

    // MARK: - Process plumbing

    @discardableResult
    private static func run(_ args: [String], cwd: String, timeout: TimeInterval = 4.0) -> (status: Int32, out: Data, err: Data)? {
        let proc = Process()
        proc.launchPath = ClawixAgentBackendRoutes.envCLI
        proc.arguments = ["git"] + args
        proc.currentDirectoryPath = cwd

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // Read both pipes concurrently so a large diff doesn't deadlock on a
        // full pipe buffer while we wait on termination.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try proc.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            usleep(10_000)
        }
        if proc.isRunning {
            proc.terminate()
            return nil
        }
        _ = group.wait(timeout: .now() + 1.0)
        return (proc.terminationStatus, outData, errData)
    }

    private static func runText(_ args: [String], cwd: String, timeout: TimeInterval = 4.0) -> String? {
        guard let r = run(args, cwd: cwd, timeout: timeout), r.status == 0 else { return nil }
        return String(data: r.out, encoding: .utf8)
    }

    // MARK: - Snapshot

    static func snapshot(cwd: String?) -> GitChangesSnapshot {
        guard let cwd, !cwd.isEmpty else { return .empty }
        let expanded = (cwd as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return .empty }

        guard let rootRaw = runText(["rev-parse", "--show-toplevel"], cwd: expanded),
              case let root = rootRaw.trimmingCharacters(in: .whitespacesAndNewlines),
              !root.isEmpty else {
            return .empty
        }

        let branch = runText(["rev-parse", "--abbrev-ref", "HEAD"], cwd: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let statusResult = run(["status", "--porcelain=v1", "-z"], cwd: root),
              statusResult.status == 0 else {
            return GitChangesSnapshot(hasRepo: true, root: root, branch: branch, staged: [], unstaged: [])
        }

        let unstagedCounts = numstat(args: ["diff", "--numstat", "-z"], cwd: root)
        let stagedCounts = numstat(args: ["diff", "--cached", "--numstat", "-z"], cwd: root)

        var staged: [GitFileChange] = []
        var unstaged: [GitFileChange] = []

        let tokens = splitNUL(statusResult.out)
        var i = 0
        while i < tokens.count {
            let entry = tokens[i]; i += 1
            guard entry.count >= 3 else { continue }
            let chars = Array(entry)
            let x = chars[0]
            let y = chars[1]
            let path = String(entry.dropFirst(3))
            if entry.hasPrefix("!!") { continue } // ignored

            var oldPath: String? = nil
            if x == "R" || x == "C" || y == "R" || y == "C" {
                if i < tokens.count { oldPath = tokens[i]; i += 1 }
            }

            // Untracked file (??): a single unstaged entry.
            if x == "?" && y == "?" {
                let added = unstagedCounts[path]?.added ?? lineCount(ofUntracked: path, root: root)
                unstaged.append(GitFileChange(
                    path: path, oldPath: nil, kind: .untracked, staged: false,
                    added: added, removed: 0
                ))
                continue
            }

            // Staged side (index): X is not space and not '?'.
            if x != " " && x != "?" {
                let c = stagedCounts[path] ?? (oldPath.flatMap { stagedCounts[$0] })
                staged.append(GitFileChange(
                    path: path, oldPath: oldPath, kind: GitFileChange.Kind(statusChar: x), staged: true,
                    added: c?.added ?? 0, removed: c?.removed ?? 0
                ))
            }

            // Working-tree side: Y is not space and not '?'.
            if y != " " && y != "?" {
                let c = unstagedCounts[path] ?? (oldPath.flatMap { unstagedCounts[$0] })
                unstaged.append(GitFileChange(
                    path: path, oldPath: oldPath, kind: GitFileChange.Kind(statusChar: y), staged: false,
                    added: c?.added ?? 0, removed: c?.removed ?? 0
                ))
            }
        }

        return GitChangesSnapshot(
            hasRepo: true, root: root, branch: branch, staged: staged, unstaged: unstaged
        )
    }

    /// Parse `git diff [--cached] --numstat -z` into path → (added, removed).
    /// Renames in -z mode emit an empty path field followed by two extra
    /// NUL tokens (old, new); we key the counts under the new path.
    private static func numstat(args: [String], cwd: String) -> [String: (added: Int, removed: Int)] {
        guard let r = run(args, cwd: cwd), r.status == 0 else { return [:] }
        let tokens = splitNUL(r.out)
        var out: [String: (added: Int, removed: Int)] = [:]
        var i = 0
        while i < tokens.count {
            let record = tokens[i]; i += 1
            let parts = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let added = Int(parts[0]) ?? 0          // "-" (binary) → 0
            let removed = Int(parts[1]) ?? 0
            var path = String(parts[2])
            if path.isEmpty {
                // Rename: next two tokens are old then new path.
                if i + 1 < tokens.count {
                    i += 1                          // skip old path
                    path = tokens[i]; i += 1        // use new path
                } else if i < tokens.count {
                    path = tokens[i]; i += 1
                }
            }
            if !path.isEmpty { out[path] = (added, removed) }
        }
        return out
    }

    private static func lineCount(ofUntracked relPath: String, root: String) -> Int {
        let url = URL(fileURLWithPath: root).appendingPathComponent(relPath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.size] as? Int ?? 0) < 1_000_000,
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return 0
        }
        if text.isEmpty { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static func splitNUL(_ data: Data) -> [String] {
        data.split(separator: 0x00, omittingEmptySubsequences: true).map {
            String(decoding: $0, as: UTF8.self)
        }
    }

    // MARK: - Diff text

    /// Unified diff for one file. Untracked files diff against /dev/null so
    /// the whole file shows as added.
    static func diff(for change: GitFileChange, root: String) -> String {
        if change.kind == .untracked {
            // --no-index exits 1 when files differ; output is still valid.
            if let r = run(["diff", "--no-index", "--", "/dev/null", change.path], cwd: root),
               let text = String(data: r.out, encoding: .utf8) {
                return text
            }
            return ""
        }
        let base = change.staged ? ["diff", "--cached"] : ["diff"]
        if let text = runText(base + ["--", change.path], cwd: root) {
            return text
        }
        return ""
    }

    // MARK: - Mutations

    @discardableResult
    static func stage(_ change: GitFileChange, root: String) -> Bool {
        run(["add", "--", change.path], cwd: root)?.status == 0
    }

    @discardableResult
    static func unstage(_ change: GitFileChange, root: String) -> Bool {
        if run(["restore", "--staged", "--", change.path], cwd: root)?.status == 0 {
            return true
        }
        return run(["reset", "-q", "HEAD", "--", change.path], cwd: root)?.status == 0
    }

    @discardableResult
    static func stageAll(root: String) -> Bool {
        run(["add", "-A"], cwd: root)?.status == 0
    }

    @discardableResult
    static func unstageAll(root: String) -> Bool {
        if run(["restore", "--staged", "--", "."], cwd: root)?.status == 0 {
            return true
        }
        return run(["reset", "-q", "HEAD", "--", "."], cwd: root)?.status == 0
    }

    /// Discard a single file's changes (destructive). Untracked files are
    /// removed from disk; tracked files are restored from the index/HEAD on
    /// both the worktree and (when staged) the index.
    @discardableResult
    static func discard(_ change: GitFileChange, root: String) -> Bool {
        if change.kind == .untracked {
            let url = URL(fileURLWithPath: root).appendingPathComponent(change.path)
            return (try? FileManager.default.removeItem(at: url)) != nil
        }
        // Restore worktree (and index when the change was staged) to HEAD.
        if change.staged {
            return run(["restore", "--staged", "--worktree", "--source=HEAD", "--", change.path], cwd: root)?.status == 0
        }
        return run(["restore", "--", change.path], cwd: root)?.status == 0
    }

    /// Discard every change in the working tree and index (destructive):
    /// hard-reset tracked files to HEAD, then remove untracked files and
    /// directories. Always gate this behind a confirmation in the UI.
    @discardableResult
    static func discardAll(root: String) -> Bool {
        let reset = run(["reset", "-q", "--hard", "HEAD"], cwd: root)?.status == 0
        let clean = run(["clean", "-fd"], cwd: root)?.status == 0
        return reset && clean
    }
}
