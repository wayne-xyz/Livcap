//
//  PermissionManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//  Enhanced to handle both microphone and system audio permissions
//

import AVFoundation
import Combine
import AppKit
import AudioToolbox
import OSLog

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
    
    // MARK: - Microphone Permissions
    @Published var micPermissionGranted: Bool = false
    @Published var micPermissionStatus: AVAuthorizationStatus = .notDetermined
    
    // MARK: - System Audio Permissions
    @Published var systemAudioPermissionStatus: PermissionStatus = .unknown
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.livcap.permissions", category: "PermissionManager")

    init() {
        checkAllPermissions()
        logger.info("PermissionManager initialized")
    }

    // MARK: - Public Interface
    
    /// Check all permission statuses
    func checkAllPermissions() {
        checkMicPermission()
        if #available(macOS 14.4, *) {
            checkSystemAudioPermission()
        } else {
            DispatchQueue.main.async {
                self.systemAudioPermissionStatus = .unsupported
            }
        }
    }
    
    /// Check if all required permissions are granted
    func hasAllRequiredPermissions() -> Bool {
        return micPermissionGranted && systemAudioPermissionStatus == .authorized
    }
    
    // MARK: - Microphone Permission Methods
    
    func checkMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        DispatchQueue.main.async {
            self.micPermissionStatus = status
            self.micPermissionGranted = (status == .authorized)
        }
        logger.info("Microphone permission status: \(status.rawValue)")
    }
    
    // Function to request permission.
    // This handles both initial requests and guiding the user after denial.
    func requestMicPermission() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch currentStatus {
        case .notDetermined:
            // This is the initial request, where the system prompt will appear.
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async { // Ensure UI updates on main thread
                    self?.micPermissionGranted = granted
                    self?.micPermissionStatus = granted ? .authorized : .denied
                    print("Prompt result - micPermissionGranted: \(self?.micPermissionGranted ?? false)")
                }
            }
        case .denied, .restricted:
            // User has previously denied or system restricts access.
            // We cannot programmatically show the prompt again.
            // Guide the user to System Settings.
            print("Microphone permission denied or restricted. Guiding user to System Settings.")
            openSystemSettingsForMicPermission()
            // Update status immediately as it's already denied/restricted
            DispatchQueue.main.async {
                self.micPermissionGranted = false
                self.micPermissionStatus = currentStatus
            }
        case .authorized:
            // Permission already granted. No action needed, just confirm state.
            print("Microphone permission already authorized.")
            DispatchQueue.main.async {
                self.micPermissionGranted = true
                self.micPermissionStatus = .authorized
            }
        @unknown default:
            // Handle future unknown cases gracefully
            print("Unknown microphone authorization status.")
            DispatchQueue.main.async {
                self.micPermissionGranted = false
                self.micPermissionStatus = .notDetermined // Or a more appropriate default
            }
        }
    }
    
    // Helper to open System Settings directly to the Microphone Privacy pane
    private func openSystemSettingsForMicPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback if the URL scheme changes or is not supported
            print("Could not open specific microphone privacy settings. Opening general privacy settings.")
            if let generalPrivacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(generalPrivacyURL)
            }
        }
    }
    
    // MARK: - System Audio Permission Methods
    
    @available(macOS 14.4, *)
    func checkSystemAudioPermission() {
        // System audio permission can't be easily checked without trying to capture
        // Set to unknown initially, will be updated when attempting capture
        DispatchQueue.main.async {
            self.systemAudioPermissionStatus = .unknown
        }
        logger.info("System audio permission status set to unknown (requires runtime check)")
    }
    
    @available(macOS 14.4, *)
    func requestSystemAudioPermission() async -> Bool {
        logger.info("Requesting system audio permission")
        
        do {
            // Try to access Core Audio system processes to test permission
            let processObjectIDs = try AudioObjectID.system.readProcessList()
            
            if !processObjectIDs.isEmpty {
                // If we can read the process list, we likely have permission
                DispatchQueue.main.async {
                    self.systemAudioPermissionStatus = .authorized
                }
                logger.info("System audio permission granted")
                return true
            } else {
                DispatchQueue.main.async {
                    self.systemAudioPermissionStatus = .denied
                }
                logger.warning("System audio permission denied - empty process list")
                return false
            }
            
        } catch {
            logger.error("System audio permission check failed: \(error.localizedDescription)")
            
            // Check if this is a permission error
            if error.localizedDescription.contains("permission") || 
               error.localizedDescription.contains("authorization") ||
               error.localizedDescription.contains("denied") {
                DispatchQueue.main.async {
                    self.systemAudioPermissionStatus = .denied
                }
            } else {
                DispatchQueue.main.async {
                    self.systemAudioPermissionStatus = .unknown
                }
            }
            
            return false
        }
    }
    
    /// Open System Settings to audio capture privacy panel
    func openSystemAudioSettings() {
        logger.info("Opening System Settings for audio capture permissions")
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        } else {
            openGeneralPrivacySettings()
        }
    }
    
    /// Check if system audio capture is supported on this macOS version
    func isSystemAudioCaptureSupported() -> Bool {
        if #available(macOS 14.4, *) {
            return true
        } else {
            return false
        }
    }
    
    /// Get user-friendly system audio permission status description
    func getSystemAudioPermissionDescription() -> String {
        switch systemAudioPermissionStatus {
        case .unknown:
            return "Permission status unknown. System audio capture may require user authorization."
        case .authorized:
            return "System audio capture is authorized and ready to use."
        case .denied:
            return "System audio capture permission has been denied. Please enable it in System Settings."
        case .unsupported:
            return "System audio capture requires macOS 14.4 or later."
        }
    }
    
    /// Get user-friendly microphone permission status description
    func getMicrophonePermissionDescription() -> String {
        switch micPermissionStatus {
        case .notDetermined:
            return "Microphone permission has not been requested yet."
        case .authorized:
            return "Microphone access is authorized and ready to use."
        case .denied, .restricted:
            return "Microphone access has been denied. Please enable it in System Settings."
        @unknown default:
            return "Microphone permission status is unknown."
        }
    }
    
    /// Check if system audio permission UI should be shown
    func shouldShowSystemAudioPermissionUI() -> Bool {
        return systemAudioPermissionStatus == .denied || systemAudioPermissionStatus == .unsupported
    }
    
    /// Check if microphone permission UI should be shown
    func shouldShowMicrophonePermissionUI() -> Bool {
        return micPermissionStatus == .denied || micPermissionStatus == .restricted
    }
    
    // MARK: - Helper Methods
    
    private func openGeneralPrivacySettings() {
        logger.info("Opening general privacy settings as fallback")
        
        if let generalURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(generalURL)
        } else {
            logger.error("Failed to open System Settings")
        }
    }
}
