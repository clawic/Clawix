import Foundation

struct ClawJSServiceLaunchPlan {
    var service: ClawJSService
    var executableURL: URL
    var arguments: [String]
    var currentDirectoryURL: URL
    var environment: [String: String]
    var bootstrapData: Data?
    var logFileURL: URL
}

enum ClawJSServiceLaunchAdapter {
    static func commandLine(for service: ClawJSService, fileManager: FileManager = .default) -> [String]? {
        if service == .iot { return nil }
        if service == .publishing {
            let serverJs = ClawJSRuntime.bundleRootURL
                .appendingPathComponent("node_modules/publishing/dist/server.js", isDirectory: false)
            guard fileManager.fileExists(atPath: serverJs.path) else { return nil }
            return [serverJs.path]
        }
        if service == .runtime {
            let packageURL = ClawJSRuntime.bundleRootURL
                .appendingPathComponent("node_modules/@clawjs/runtime/package.json", isDirectory: false)
            guard fileManager.fileExists(atPath: packageURL.path) else { return nil }
            return [
                "--input-type=module",
                "--eval",
                """
                import { buildRuntimeApp } from '@clawjs/runtime';
                const app = buildRuntimeApp();
                const host = process.env.RUNTIME_HOST || process.env.HOST || '127.0.0.1';
                const port = Number(process.env.RUNTIME_PORT || process.env.PORT || '24100');
                await app.listen({ host, port });
                """
            ]
        }

        guard bundledLauncherScript(for: service, fileManager: fileManager) != nil else { return nil }

        var arguments = [
            ClawJSRuntime.cliScriptURL.path,
            "open", service.rawValue,
            "--host", "127.0.0.1",
            "--port", String(service.port),
            "--workspace", ClawJSServiceDirectoryResolver.workspaceURL.path,
            "--status-file", ClawJSServiceDirectoryResolver.statusFileURL(for: service).path,
        ]

        switch service {
        case .runtime:
            return arguments
        case .database:
            arguments += [
                "--data-dir", ClawJSServiceDirectoryResolver.mainDataDirectoryURL.path,
                "--db-path", ClawJSServiceDirectoryResolver.mainDatabaseURL.path,
                "--files-dir", ClawJSServiceDirectoryResolver.mainFilesDirectoryURL.path,
            ]
            return arguments
        case .secrets:
            return arguments
        case .telegram:
            return arguments
        case .memory, .drive, .sessions:
            arguments += ["--data-dir", ClawJSServiceDirectoryResolver.dataDirectoryURL(for: service).path]
            if service == .sessions {
                arguments += [
                    "--db-path", ClawJSServiceSupervisorRoutes.sessionsDatabaseURL(
                        dataDirectoryURL: ClawJSServiceDirectoryResolver.dataDirectoryURL(for: service)
                    ).path,
                ]
            }
            return arguments
        case .audio:
            arguments += [
                "--data-dir", ClawJSServiceDirectoryResolver.dataDirectoryURL(for: service).path,
                "--blobs-dir", ClawJSServiceDirectoryResolver.dataDirectoryURL(for: service)
                    .appendingPathComponent(ClawixPersistentSurfacePaths.components.blobs, isDirectory: true).path,
            ]
            return arguments
        case .index:
            arguments += [
                "--data-dir", ClawJSServiceDirectoryResolver.dataDirectoryURL(for: service).path,
                "--db-path", ClawJSServiceDirectoryResolver.dataDirectoryURL(for: service)
                    .appendingPathComponent(ClawixPersistentSurfacePaths.components.indexDatabase, isDirectory: false).path,
            ]
            return arguments
        case .iot, .publishing:
            return nil
        }
    }

    static func plan(
        for service: ClawJSService,
        tokenVault: inout ClawJSServiceTokenVault
    ) throws -> ClawJSServiceLaunchPlan? {
        guard let arguments = commandLine(for: service) else { return nil }
        let adminToken = tokenVault.ensureAdminToken(for: service)
        let signedHostToken = tokenVault.ensureSignedHostToken(for: service)
        let hostAssertionKey = tokenVault.ensureHostAssertionKey(for: service)
        let bootstrapData: Data?
        if service == .secrets {
            bootstrapData = try ClawJSServiceTokenVault.secretsBootstrapPayload(
                adminToken: adminToken,
                signedHostToken: signedHostToken,
                hostAssertionKeyBase64: hostAssertionKey,
                platformKey: try SecretsPlatformKey.loadOrCreate()
            )
        } else if let adminToken {
            bootstrapData = try ClawJSServiceTokenVault.localAdminBootstrapPayload(adminToken: adminToken)
        } else {
            bootstrapData = nil
        }
        return ClawJSServiceLaunchPlan(
            service: service,
            executableURL: ClawJSRuntime.nodeBinaryURL,
            arguments: arguments,
            currentDirectoryURL: ClawJSServiceDirectoryResolver.workingDirectoryURL(for: service),
            environment: ClawJSServiceEnvironmentBuilder.environment(
                for: service,
                adminToken: adminToken,
                signedHostToken: signedHostToken
            ),
            bootstrapData: bootstrapData,
            logFileURL: ClawJSServiceDirectoryResolver.logFileURL(for: service)
        )
    }

    static func iotPlan(projectDir: URL) -> ClawJSServiceLaunchPlan {
        let serverJs = projectDir.appendingPathComponent("dist/server.js", isDirectory: false)
        return ClawJSServiceLaunchPlan(
            service: .iot,
            executableURL: ClawJSServiceSupervisorRoutes.envURL,
            arguments: ["node", serverJs.path],
            currentDirectoryURL: projectDir,
            environment: ClawJSServiceEnvironmentBuilder.iotEnvironment(),
            bootstrapData: nil,
            logFileURL: ClawJSServiceDirectoryResolver.logFileURL(for: .iot)
        )
    }

    static func iotProjectDirectory(
        applicationSupportRoot: URL = ClawJSServiceDirectoryResolver.applicationSupportRoot,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> URL? {
        let pointerURL = ClawJSServiceSupervisorRoutes.iotPointerURL(applicationSupportRoot: applicationSupportRoot)
        if let raw = try? String(contentsOf: pointerURL, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let candidate = URL(fileURLWithPath: trimmed, isDirectory: true)
                if fileManager.fileExists(atPath: candidate.appendingPathComponent("dist/server.js").path) {
                    return candidate
                }
            }
        }
        let bundled = bundleURL.appendingPathComponent("Contents/Resources/clawjs-iot", isDirectory: true)
        if fileManager.fileExists(atPath: bundled.appendingPathComponent("dist/server.js").path) {
            return bundled
        }
        return nil
    }

    private static func bundledLauncherScript(for service: ClawJSService, fileManager: FileManager) -> URL? {
        let url = ClawJSRuntime.bundleRootURL.appendingPathComponent(
            "node_modules/@clawjs/cli/bin/\(service.rawValue)-server-launcher.mjs",
            isDirectory: false
        )
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
