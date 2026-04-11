import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Speech

enum PermissionError: LocalizedError {
    case accessibility
    case inputMonitoring
    case microphone
    case speech

    var errorDescription: String? {
        switch self {
        case .accessibility:
            return "需要开启辅助功能或输入监控权限。"
        case .inputMonitoring:
            return "需要开启输入监控权限。"
        case .microphone:
            return "需要开启麦克风权限。"
        case .speech:
            return "需要开启语音识别权限。"
        }
    }
}

@MainActor
final class PermissionCenter {
    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func promptForInputMonitoring() {
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
    }

    func hasInputMonitoringAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    func ensureInputMonitoringAccess() throws {
        if hasInputMonitoringAccess() {
            return
        }

        promptForInputMonitoring()
        throw PermissionError.inputMonitoring
    }

    func hasPostEventAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightPostEventAccess()
        }
        return true
    }

    func ensurePostEventAccess() throws {
        if hasPostEventAccess() {
            return
        }

        if #available(macOS 10.15, *) {
            _ = CGRequestPostEventAccess()
        }
        throw PermissionError.accessibility
    }

    func ensureReadyForCapture() async throws {
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            throw PermissionError.accessibility
        }

        guard await requestMicrophoneAccess() else {
            throw PermissionError.microphone
        }

        guard await requestSpeechAccess() else {
            throw PermissionError.speech
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func requestSpeechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}
