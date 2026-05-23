import Foundation

struct ClawJSSpawnedServiceProcess {
    var process: Process
    var logHandle: FileHandle
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
        if let bootstrapData = plan.bootstrapData {
            let pipe = Pipe()
            process.standardInput = pipe
            bootstrapPipe = pipe
            process.terminationHandler = terminationHandler
            try configureLogsAndRun(
                process: process,
                logURL: plan.logFileURL,
                bootstrapPipe: bootstrapPipe,
                bootstrapData: bootstrapData,
                fileManager: fileManager
            )
        } else {
            bootstrapPipe = nil
            process.terminationHandler = terminationHandler
            try configureLogsAndRun(
                process: process,
                logURL: plan.logFileURL,
                bootstrapPipe: bootstrapPipe,
                bootstrapData: nil,
                fileManager: fileManager
            )
        }

        guard let handle = process.standardOutput as? FileHandle else {
            throw NSError(domain: "ClawJSServiceSpawner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to attach service log handle."
            ])
        }
        return ClawJSSpawnedServiceProcess(process: process, logHandle: handle)
    }

    private static func configureLogsAndRun(
        process: Process,
        logURL: URL,
        bootstrapPipe: Pipe?,
        bootstrapData: Data?,
        fileManager: FileManager
    ) throws {
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        process.standardOutput = handle
        process.standardError = handle

        do {
            try process.run()
            if let bootstrapPipe, let bootstrapData {
                bootstrapPipe.fileHandleForWriting.write(bootstrapData)
                try? bootstrapPipe.fileHandleForWriting.close()
            }
        } catch {
            try? handle.close()
            throw error
        }
    }
}
