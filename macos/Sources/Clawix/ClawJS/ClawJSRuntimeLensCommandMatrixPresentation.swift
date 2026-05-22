import Foundation

struct ClawJSRuntimeLensCommandMatrixPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let command: String
        let delegatesTo: String?
        let writeDisposition: String
        let argumentCount: Int
        let argsLabel: String?

        var accessibilityLabel: String {
            [
                command,
                "disposition \(writeDisposition)",
                "arguments \(argumentCount)",
                argsLabel.map { "args \($0)" },
                delegatesTo.map { "delegates to \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let authority: String?
    let mutationPolicy: String?
    let executableCount: Int
    let writesRuntimeCount: Int
    let wouldWriteRuntimeCount: Int
    let readLocalCount: Int
    let argumentCommandCount: Int
    let argumentCount: Int
    let resourceDomainCount: Int
    let resourceDomainsLabel: String?
    let rows: [Row]

    var accessibilityLabel: String {
        [
            "Runtime command matrix",
            "commands \(executableCount)",
            authority.map { "authority \($0)" },
            "writes runtime \(writesRuntimeCount)",
            "would write runtime \(wouldWriteRuntimeCount)",
            "read local \(readLocalCount)",
            "argument commands \(argumentCommandCount)",
            "arguments \(argumentCount)",
            "resource domains \(resourceDomainCount)",
            resourceDomainsLabel.map { "domains \($0)" },
            mutationPolicy.map { "mutation policy \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        commands: ClawJSRuntimeLensSnapshot.CommandMatrix
    ) -> ClawJSRuntimeLensCommandMatrixPresentation {
        let allCommands = commands.executableByClawCli ?? []
        let rows = visibleCommands(allCommands).map { command in
            Row(
                id: command.command,
                command: command.command,
                delegatesTo: command.delegatesTo,
                writeDisposition: writeDisposition(for: command),
                argumentCount: command.args?.count ?? 0,
                argsLabel: listLabel(command.args, limit: 8)
            )
        }

        return ClawJSRuntimeLensCommandMatrixPresentation(
            authority: commands.authority,
            mutationPolicy: commands.mutationPolicy,
            executableCount: allCommands.count,
            writesRuntimeCount: allCommands.filter { $0.writesRuntime == true }.count,
            wouldWriteRuntimeCount: allCommands.filter { $0.wouldWriteRuntime == true }.count,
            readLocalCount: allCommands.filter { $0.writesRuntime != true && $0.wouldWriteRuntime != true }.count,
            argumentCommandCount: allCommands.filter { command in
                !(command.args ?? []).isEmpty
            }.count,
            argumentCount: allCommands.reduce(0) { count, command in
                count + (command.args?.count ?? 0)
            },
            resourceDomainCount: commands.resourceDomains?.count ?? 0,
            resourceDomainsLabel: listLabel(commands.resourceDomains, limit: 5),
            rows: rows
        )
    }

    private static func visibleCommands(
        _ allCommands: [ClawJSRuntimeLensSnapshot.RuntimeCommand]
    ) -> [ClawJSRuntimeLensSnapshot.RuntimeCommand] {
        var selected: [ClawJSRuntimeLensSnapshot.RuntimeCommand] = []
        var seen = Set<String>()

        func append(_ command: ClawJSRuntimeLensSnapshot.RuntimeCommand) {
            guard !seen.contains(command.command) else { return }
            selected.append(command)
            seen.insert(command.command)
        }

        allCommands
            .filter { $0.command.contains(" sessions ") && ($0.writesRuntime == true || $0.wouldWriteRuntime == true) }
            .forEach(append)
        allCommands
            .filter { $0.command.contains(" sessions ") && $0.command.contains("conflicts") }
            .forEach(append)
        allCommands
            .filter { $0.command.contains(" sessions ") }
            .forEach(append)
        allCommands
            .filter { $0.command.contains(" domains") || $0.command.contains(" resources ") || $0.command.contains(" status") }
            .forEach(append)
        allCommands.forEach(append)

        return Array(selected.prefix(12))
    }

    private static func writeDisposition(
        for command: ClawJSRuntimeLensSnapshot.RuntimeCommand
    ) -> String {
        if command.writesRuntime == true {
            return "writes runtime"
        }
        if command.wouldWriteRuntime == true {
            return "blocked write"
        }
        return "read/local"
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
