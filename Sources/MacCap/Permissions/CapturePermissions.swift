import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct CapturePermissionSnapshot: Equatable, Sendable {
    public let screenRecording: Bool
    public let accessibility: Bool

    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }

    public var allGranted: Bool {
        screenRecording && accessibility
    }
}

public enum CapturePermissions {
    public static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    public static var current: CapturePermissionSnapshot {
        CapturePermissionSnapshot(
            screenRecording: hasScreenRecordingAccess,
            accessibility: hasAccessibilityAccess
        )
    }

    /// Requests screen-recording access. macOS may require the application to be
    /// relaunched after the user grants this permission.
    @discardableResult
    public static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Prompts for Accessibility access and returns the current trust state.
    @discardableResult
    public static func requestAccessibilityAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public static func requestRequiredAccess() -> CapturePermissionSnapshot {
        if !hasScreenRecordingAccess {
            _ = requestScreenRecordingAccess()
        }
        if !hasAccessibilityAccess {
            _ = requestAccessibilityAccess()
        }
        return current
    }

    @MainActor
    public static func openScreenRecordingSettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    @MainActor
    public static func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    @MainActor
    private static func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
