//
//  PermissionManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//  Simplified to only handle denied permissions - system handles requests automatically
//

import AVFoundation
import Combine
import AppKit
import AudioToolbox
import OSLog
import Speech

// MARK: - Permission Status Enum

enum PermissionStatus: String, CaseIterable {
    case unknown = "unknown"
    case authorized = "authorized" 
    case denied = "denied"
    case unsupported = "unsupported"
    
    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .unsupported:
            return "Unsupported"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .unknown:
            return "questionmark.circle"
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .unsupported:
            return "exclamationmark.triangle.fill"
        }
    }
}

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    // MARK: - Permission Status Properties
    @Published var micPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var speechPermissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var systemAudioPermissionStatus: PermissionStatus = .unknown
    
    // MARK: - Denial Check Properties (for warning messages)
    @Published var hasDeniedPermissions: Bool = false
    @Published var deniedPermissionMessage: String = ""
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.livcap.permissions", category: "PermissionManager")

    init() {
        checkDeniedPermissionsOnLoad()
        logger.info("PermissionManager initialized - simplified approach")
    }

    // MARK: - Simple Permission Checks
    
    /// Check if any permissions are explicitly denied (for warning message on app load)
    func checkDeniedPermissionsOnLoad() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        
        self.micPermissionStatus = micStatus
        self.speechPermissionStatus = speechStatus
        
        var deniedPermissions: [String] = []
        
        // Check microphone
        if micStatus == .denied || micStatus == .restricted {
            deniedPermissions.append("Microphone")
        }
        
        // Check speech recognition  
        if speechStatus == .denied || speechStatus == .restricted {
            deniedPermissions.append("Speech Recognition")
        }
        
        // Update denial state
        if deniedPermissions.isEmpty {
            hasDeniedPermissions = false
            deniedPermissionMessage = ""
        } else {
            hasDeniedPermissions = true
            deniedPermissionMessage = createDenialMessage(deniedPermissions)
        }
        
        logger.info("Denied permissions check: \(deniedPermissions)")
    }
    
    private func createDenialMessage(_ deniedPermissions: [String]) -> String {
        let permissionList = deniedPermissions.joined(separator: " and ")
        return "\(permissionList) access denied. Please enable in System Settings > Privacy & Security to use this feature. And restart the Livcap"
    }

    // MARK: - Simple Permission Status Checks
    
    /// Check if microphone is explicitly denied (user needs to go to System Settings)
    func isMicrophoneDenied() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .denied || status == .restricted
    }
    
    /// Check if speech recognition is explicitly denied (user needs to go to System Settings)
    func isSpeechRecognitionDenied() -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        return status == .denied || status == .restricted
    }
    
    /// Check if either microphone or speech recognition is denied
    func hasEssentialPermissionsDenied() -> Bool {
        return isMicrophoneDenied() || isSpeechRecognitionDenied()
    }

    // MARK: - System Settings Helpers
    
    func openSystemSettingsForMicPermission() {
        logger.info("Opening System Settings for microphone permission")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        } else {
            openGeneralPrivacySettings()
        }
    }
    
    func openSystemSettingsForSpeechPermission() {
        logger.info("Opening System Settings for speech recognition permission")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        } else {
            openGeneralPrivacySettings()
        }
    }
    
    private func openGeneralPrivacySettings() {
        if let generalURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(generalURL)
        } else {
            logger.error("Failed to open System Settings")
        }
    }

    // MARK: - System Audio Methods (unchanged for now)
    
    @available(macOS 14.4, *)
    func checkSystemAudioPermission() {
        self.systemAudioPermissionStatus = .unknown
        logger.info("System audio permission status set to unknown (will be checked when user enables feature)")
    }
    
    func isSystemAudioCaptureSupported() -> Bool {
        if #available(macOS 14.4, *) {
            return true
        } else {
            return false
        }
    }

    // MARK: - Legacy Methods (simplified for compatibility)
    
    /// Legacy method - now just updates current status without blocking flow
    func checkAllPermissions() {
        checkDeniedPermissionsOnLoad()
    }
    
    /// Legacy method - simplified to check basic authorization
    func hasAllRequiredPermissions() -> Bool {
        return micPermissionStatus == .authorized && speechPermissionStatus == .authorized
    }
    
    func hasAllPermissionsIncludingSystemAudio() -> Bool {
        return micPermissionStatus == .authorized && 
               speechPermissionStatus == .authorized && 
               systemAudioPermissionStatus == .authorized
    }
    
    // Legacy individual permission methods (simplified)
    func checkMicPermission() {
        micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func checkSpeechPermission() {
        speechPermissionStatus = SFSpeechRecognizer.authorizationStatus()
    }
    
    // Legacy request methods - now just open system settings if denied
    func requestMicPermission() {
        if isMicrophoneDenied() {
            openSystemSettingsForMicPermission()
        }
    }
    
    func requestSpeechPermission() {
        if isSpeechRecognitionDenied() {
            openSystemSettingsForSpeechPermission()
        }
    }
}

