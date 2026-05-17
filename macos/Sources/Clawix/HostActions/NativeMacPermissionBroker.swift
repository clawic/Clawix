import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import IOKit.hid
import Speech

@MainActor
enum NativeMacPermissionBroker {
    enum PermissionID: String, CaseIterable, Codable {
        case microphone = "mac.permission.microphone"
        case speechRecognition = "mac.permission.speech_recognition"
        case camera = "mac.permission.camera"
        case accessibility = "mac.permission.accessibility"
        case inputMonitoring = "mac.permission.input_monitoring"
        case automationAppleEvents = "mac.permission.automation_apple_events"
    }

    enum Status {
        case granted
        case denied
        case notDetermined
    }

    nonisolated static let accessibilityRequestedKey = "dictation.accessibility.hasRequested"

    static func status(for permission: PermissionID) -> Status {
        switch permission {
        case .microphone:
            return microphoneStatus()
        case .speechRecognition:
            return speechRecognitionStatus()
        case .camera:
            return cameraStatus()
        case .accessibility:
            return accessibilityStatus()
        case .inputMonitoring:
            return inputMonitoringStatus()
        case .automationAppleEvents:
            return .notDetermined
        }
    }

    static func request(_ permission: PermissionID) async -> Bool {
        switch permission {
        case .microphone:
            return await requestMicrophone()
        case .speechRecognition:
            return await requestSpeechRecognition()
        case .camera:
            return await requestCamera()
        case .accessibility:
            return requestAccessibility()
        case .inputMonitoring:
            return requestInputMonitoring()
        case .automationAppleEvents:
            return false
        }
    }

    static func openSettings(for permission: PermissionID) {
        switch permission {
        case .microphone:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .camera:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        case .accessibility:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .automationAppleEvents:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }

    static func speechRecognitionAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    private static func microphoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func speechRecognitionStatus() -> Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private static func requestSpeechRecognition() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func cameraStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private static func requestCamera() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func accessibilityStatus() -> Status {
        if AXIsProcessTrusted() { return .granted }
        if UserDefaults.standard.bool(forKey: accessibilityRequestedKey) { return .denied }
        return .notDetermined
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        UserDefaults.standard.set(true, forKey: accessibilityRequestedKey)
        return trusted
    }

    private static func inputMonitoringStatus() -> Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .notDetermined
        }
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    private static func open(_ url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }
}
