import Foundation

struct ClawJSSpawnedServiceProcess {
    var process: Process
    var logSink: ClawixRedactedProcessLogSink
}

enum ClawJSServiceSpawner {
    static func spawn(
        _ plan: ClawJSServiceLaunchPlan,
        terminationHandler: @escaping (Process) -> Void,
        fileManager: FileManager = .default
    ) throws -> ClawJSSpawnedServiceProcess {
        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        process.currentDirectoryURL = plan.currentDirectoryURL
        process.environment = plan.environment

        let bootstrapPipe: Pipe?
        let logSink: ClawixRedactedProcessLogSink
        if let bootstrapData = plan.bootstrapData {
            let pipe = Pipe()
            process.standardInput = pipe
            bootstrapPipe = pipe
            process.terminationHandler = terminationHandler
            logSink = try configureLogsAndRun(
                process: process,
                logURL: plan.logFileURL,
                bootstrapPipe: bootstrapPipe,
                bootstrapData: bootstrapData,
                fileManager: fileManager
            )
        } else {
            bootstrapPipe = nil
            process.terminationHandler = terminationHandler
            logSink = try configureLogsAndRun(
                process: process,
                logURL: plan.logFileURL,
                bootstrapPipe: bootstrapPipe,
                bootstrapData: nil,
                fileManager: fileManager
            )
        }

        return ClawJSSpawnedServiceProcess(process: process, logSink: logSink)
    }

    private static func configureLogsAndRun(
        process: Process,
        logURL: URL,
        bootstrapPipe: Pipe?,
        bootstrapData: Data?,
        fileManager: FileManager
    ) throws -> ClawixRedactedProcessLogSink {
        let logSink = try ClawixRedactedProcessLogSink(logURL: logURL, fileManager: fileManager)
        process.standardOutput = logSink.stdoutPipe
        process.standardError = logSink.stderrPipe

        do {
            try process.run()
            if let bootstrapPipe, let bootstrapData {
                bootstrapPipe.fileHandleForWriting.write(bootstrapData)
                try? bootstrapPipe.fileHandleForWriting.close()
            }
            return logSink
        } catch {
            logSink.close()
            throw error
        }
    }
}
