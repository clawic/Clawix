import Foundation

enum ClawJSServiceEnvironmentBuilder {
    static func cliEnvironment() -> [String: String] {
        environment(for: .database, adminToken: nil, signedHostToken: nil)
    }

    static func environment(
        for service: ClawJSService,
        adminToken: String?,
        signedHostToken: String?,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        for tokenEnvVar in ClawJSServiceSupervisorPolicy.adminTokenEnvVar.values {
            env.removeValue(forKey: tokenEnvVar)
        }
        env.removeValue(forKey: "CLAW_SECRETS_TOKEN")
        env.removeValue(forKey: "CLAW_SECRETS_KEK_BASE64")
        env.removeValue(forKey: "CLAW_SECRETS_HOST_ASSERTION_KEY_BASE64")

        env["HOME"] = ClawJSServiceSupervisorRoutes.homeURL(
            applicationSupportRoot: ClawJSServiceDirectoryResolver.applicationSupportRoot
        ).path
        env["CLAW_WORKSPACE"] = ClawJSServiceDirectoryResolver.workspaceURL.path
        env["CLAW_HOME"] = ClawJSServiceDirectoryResolver.frameworkGlobalRootURL.path
        env["CLAW_DATA_DIR"] = ClawJSServiceDirectoryResolver.mainDataDirectoryURL.path
        env["CLAW_DB_PATH"] = ClawJSServiceDirectoryResolver.mainDatabaseURL.path
        env["CLAW_FILES_DIR"] = ClawJSServiceDirectoryResolver.mainFilesDirectoryURL.path
        env["CLAW_SERVICE_PORT"] = String(service.port)
        env["CLAW_SERVICE_NAME"] = service.rawValue
        env["RUNTIME_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["RUNTIME_PORT"] = String(ClawJSService.runtime.port)
        env["RUNTIME_DATA_DIR"] = ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .runtime).path
        env["RUNTIME_DB_PATH"] = ClawJSServiceSupervisorRoutes.runtimeDatabaseURL(
            runtimeDataDirectoryURL: ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .runtime)
        ).path
        env["CLAW_RUNTIME_SESSIONS_URL"] = ClawJSServiceEndpointResolver.originString(for: .sessions)
        for (key, value) in ClawJSActorAssertion.environment() {
            env[key] = value
        }
        env["CLAW_SECRETS_PROXY_PATH"] = ClawJSServiceSupervisorRoutes.secretsProxyURL().path
        env["PORT"] = String(service.port)
        env["HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_DATABASE_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_DATABASE_PORT"] = String(ClawJSService.database.port)
        env["CLAW_DATABASE_DATA_DIR"] = ClawJSServiceDirectoryResolver.mainDataDirectoryURL.path
        env["CLAW_DATABASE_DB_PATH"] = ClawJSServiceDirectoryResolver.mainDatabaseURL.path
        env["CLAW_DATABASE_FILES_DIR"] = ClawJSServiceDirectoryResolver.mainFilesDirectoryURL.path
        env["CLAW_DRIVE_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_DRIVE_PORT"] = String(ClawJSService.drive.port)
        env["CLAW_DRIVE_DATA_DIR"] = ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .drive).path
        env["CLAW_SESSIONS_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_SESSIONS_PORT"] = String(ClawJSService.sessions.port)
        env["CLAW_SESSIONS_DATA_DIR"] = ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .sessions).path
        env["CLAW_SESSIONS_DB_PATH"] = ClawJSServiceSupervisorRoutes.sessionsDatabaseURL(
            dataDirectoryURL: ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .sessions)
        ).path
        env["CLAW_SECRETS_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["CLAW_SECRETS_PORT"] = String(ClawJSService.secrets.port)
        env["CLAW_SECRETS_DATA_DIR"] = ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .secrets).path
        env["CLAW_SECRETS_DB_PATH"] = ClawJSServiceSupervisorRoutes.secretsDatabaseURL(
            dataDirectoryURL: ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .secrets)
        ).path
        env["CLAW_SECRETS_BASE_URL"] = ClawJSServiceEndpointResolver.originString(for: .secrets)
        env["CLAW_SECRETS_TENANT_ID"] = ClawJSSecretsClient.defaultTenantId

        if service == .telegram {
            env["CLAW_TELEGRAM_PORT"] = String(service.port)
            env["CLAW_TELEGRAM_WORKSPACE"] = ClawJSServiceDirectoryResolver.workspaceURL.path
        }
        if service == .publishing {
            let publishingData = ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .publishing).path
            env["CLAW_PUBLISHING_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
            env["CLAW_PUBLISHING_PORT"] = String(service.port)
            env["CLAW_PUBLISHING_DATA_DIR"] = publishingData
            env["CLAW_PUBLISHING_STATUS_FILE"] = ClawJSServiceDirectoryResolver.statusFileURL(for: service).path
        }
        if adminToken != nil, ClawJSServiceSupervisorPolicy.requiresSessionAdminToken(service) {
            if service == .runtime {
                env["RUNTIME_SHARED_SECRET"] = adminToken
            } else if service == .secrets {
                env["CLAW_SECRETS_BOOTSTRAP_STDIN"] = "1"
            } else {
                env["CLAW_LOCAL_ADMIN_BOOTSTRAP_STDIN"] = "1"
            }
        }
        if service == .secrets, signedHostToken != nil {
            env["CLAW_SECRETS_BOOTSTRAP_STDIN"] = "1"
        }
        return env
    }

    static func iotEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["IOT_HOST"] = ClawJSServiceEndpointResolver.loopbackHost
        env["IOT_PORT"] = String(ClawJSService.iot.port)
        let dataDir = ClawJSServiceDirectoryResolver.dataDirectoryURL(for: .iot)
        env["IOT_DATA_DIR"] = dataDir.path
        env["IOT_DB_PATH"] = dataDir.appendingPathComponent(
            ClawixPersistentSurfacePaths.components.iotDatabase,
            isDirectory: false
        ).path
        return env
    }
}
