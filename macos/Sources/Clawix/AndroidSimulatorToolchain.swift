import Foundation

extension AndroidSimulatorFramebufferController {
    nonisolated static func locateADB() throws -> String {
        let env = ProcessInfo.processInfo.environment
        let home = ClawixAndroidSimulatorRoutes.userHomePath(environment: env)
        let sdkRoots = ClawixAndroidSimulatorRoutes.sdkRoots(home: home, environment: env)
        let candidates = ClawixAndroidSimulatorRoutes.adbCandidates(sdkRoots: sdkRoots)
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw AndroidSimulatorError.commandFailed("adb was not found. Install Android Platform Tools or set ANDROID_HOME.")
    }

    nonisolated static func locateToolchain() async throws -> AndroidToolchain {
        try await Task.detached(priority: .utility) {
            let adb = try locateADB()
            let emulator = locateEmulator()
            return AndroidToolchain(adbPath: adb, emulatorPath: emulator, avds: loadAVDs(emulatorPath: emulator))
        }.value
    }

    nonisolated static func locateEmulator() -> String? {
        let env = ProcessInfo.processInfo.environment
        let home = ClawixAndroidSimulatorRoutes.userHomePath(environment: env)
        let sdkRoots = ClawixAndroidSimulatorRoutes.sdkRoots(home: home, environment: env)
        let candidates = ClawixAndroidSimulatorRoutes.emulatorCandidates(sdkRoots: sdkRoots)
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    nonisolated static func loadAVDs(emulatorPath: String?) -> [AndroidAVDChoice] {
        if let emulatorPath,
           let result = try? runToolSync(emulatorPath, ["-list-avds"]),
           result.status == 0 {
            let names = result.stdout
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !names.isEmpty {
                return names.map { AndroidAVDChoice(name: $0, config: configForAVD(named: $0)) }
                    .sorted()
            }
        }

        let home = ClawixAndroidSimulatorRoutes.userHomePath()
        let avdRoot = ClawixAndroidSimulatorRoutes.avdRoot(home: home)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: avdRoot,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "avd" }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return AndroidAVDChoice(name: name, config: configForAVD(named: name))
            }
            .sorted()
    }

    nonisolated static func configForAVD(named name: String) -> AndroidAVDConfig {
        let home = ClawixAndroidSimulatorRoutes.userHomePath()
        let path = ClawixAndroidSimulatorRoutes.avdConfig(home: home, name: name)
        guard let raw = try? String(contentsOf: path) else {
            return AndroidAVDConfig(width: nil, height: nil, deviceName: nil)
        }
        var values: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        return AndroidAVDConfig(
            width: values["hw.lcd.width"].flatMap(Int.init),
            height: values["hw.lcd.height"].flatMap(Int.init),
            deviceName: values["hw.device.name"]
        )
    }

    nonisolated static func selectAVD(from avds: [AndroidAVDChoice], preferredName: String?) throws -> AndroidAVDChoice {
        if let preferredName, let preferred = avds.first(where: { $0.name == preferredName }) {
            return preferred
        }
        guard let avd = avds.first else {
            throw AndroidSimulatorError.noAVD
        }
        return avd
    }

    nonisolated static func selectConnectedDevice(
        from devices: [AndroidEmulatorDevice],
        preferredAVDName: String?
    ) -> AndroidEmulatorDevice? {
        if let preferredAVDName {
            return devices.first(where: { $0.avdName == preferredAVDName && $0.state == "device" })
        }
        return devices.first(where: { $0.state == "device" })
    }


}
