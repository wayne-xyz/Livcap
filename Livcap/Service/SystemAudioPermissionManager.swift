//
//  SystemAudioPermissionManager.swift
//  Livcap
//
//  System audio capture permission management for macOS 14.4+
//  Includes TCC framework integration with fallback support
//

import Foundation
import OSLog
import AppKit

class SystemAudioPermissionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var permissionStatus: PermissionStatus = .unknown
    @Published private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livcap.permissions", category: "SystemAudioPermissionManager")
    
    // MARK: - Configuration
    
    /// Enable TCC framework integration (can be disabled at build time)
    private let enableTCCFramework: Bool = {
        #if DEBUG
        return true  // Enable in debug builds
        #else
        return false // Disable in release builds for App Store compatibility
        #endif
    }()
    
    // MARK: - Initialization
    
    init() {
        logger.info("SystemAudioPermissionManager initialized")
        checkCurrentPermissionStatus()
    }
    
    // MARK: - Public Interface
    
    /// Check and return current permission status
    func checkPermissionStatus() -> PermissionStatus {
        checkCurrentPermissionStatus()
        return permissionStatus
    }
    
    /// Request system audio capture permission
    func requestPermission() async -> Bool {
        logger.info("Requesting system audio permission")
        
        if enableTCCFramework {
            return await requestPermissionViaTCC()
        } else {
            return await requestPermissionViaRuntime()
        }
    }
    
    /// Open System Settings to the appropriate privacy panel
    func openSystemSettings() {
        logger.info("Opening System Settings for privacy permissions")
        
        // Try to open specific audio capture privacy settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback to general privacy settings
            if let generalURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(generalURL)
            } else {
                logger.error("Failed to open System Settings")
                updateErrorMessage("Unable to open System Settings")
            }
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
    
    // MARK: - Permission Status Checking
    
    private func checkCurrentPermissionStatus() {
        guard isSystemAudioCaptureSupported() else {
            updatePermissionStatus(.unsupported)
            return
        }
        
        if enableTCCFramework {
            checkPermissionStatusViaTCC()
        } else {
            // Without TCC framework, we can't check until we try to capture
            updatePermissionStatus(.unknown)
        }
    }
    
    // MARK: - TCC Framework Integration
    
    private func checkPermissionStatusViaTCC() {
        guard let preflight = TCCFramework.preflightFunction else {
            logger.warning("TCC preflight function not available")
            updatePermissionStatus(.unknown)
            return
        }
        
        let result = preflight("kTCCServiceAudioCapture" as CFString, nil)
        
        switch result {
        case 0:
            updatePermissionStatus(.authorized)
        case 1:
            updatePermissionStatus(.denied)
        default:
            updatePermissionStatus(.unknown)
        }
        
        logger.info("TCC permission status: \(result)")
    }
    
    private func requestPermissionViaTCC() async -> Bool {
        guard let request = TCCFramework.requestFunction else {
            logger.error("TCC request function not available")
            updateErrorMessage("Permission request system unavailable")
            return false
        }
        
        return await withCheckedContinuation { continuation in
            request("kTCCServiceAudioCapture" as CFString, nil) { [weak self] granted in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                self.logger.info("TCC permission request result: \(granted)")
                
                DispatchQueue.main.async {
                    if granted {
                        self.updatePermissionStatus(.authorized)
                    } else {
                        self.updatePermissionStatus(.denied)
                    }
                }
                
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - Runtime Permission Checking
    
    private func requestPermissionViaRuntime() async -> Bool {
        logger.info("Attempting runtime permission check via system audio capture")
        
        // Try to create a system audio manager to trigger permission prompt
        if #available(macOS 14.4, *) {
            do {
                let systemAudioManager = SystemAudioManager()
                try await systemAudioManager.startCapture()
                
                // If we get here, permission was granted
                systemAudioManager.stopCapture()
                updatePermissionStatus(.authorized)
                return true
                
            } catch {
                logger.error("Runtime permission check failed: \(error.localizedDescription)")
                
                // Check if this is a permission error
                if error.localizedDescription.contains("permission") || 
                   error.localizedDescription.contains("authorization") {
                    updatePermissionStatus(.denied)
                } else {
                    updatePermissionStatus(.unknown)
                    updateErrorMessage(error.localizedDescription)
                }
                
                return false
            }
        } else {
            updatePermissionStatus(.unsupported)
            return false
        }
    }
    
    // MARK: - State Updates
    
    private func updatePermissionStatus(_ status: PermissionStatus) {
        Task { @MainActor in
            self.permissionStatus = status
            self.errorMessage = nil
        }
    }
    
    private func updateErrorMessage(_ message: String) {
        Task { @MainActor in
            self.errorMessage = message
        }
    }
    
    // MARK: - Utility Methods
    
    func getPermissionStatusDescription() -> String {
        switch permissionStatus {
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
    
    func shouldShowPermissionUI() -> Bool {
        return permissionStatus == .denied || permissionStatus == .unsupported
    }
}

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

// MARK: - TCC Framework Integration

private struct TCCFramework {
    
    typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void
    
    /// `dlopen` handle to the TCC framework
    private static let frameworkHandle: UnsafeMutableRawPointer? = {
        let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"
        return dlopen(tccPath, RTLD_NOW)
    }()
    
    /// `dlsym` function handle for `TCCAccessPreflight`
    static let preflightFunction: PreflightFunction? = {
        guard let handle = frameworkHandle else { return nil }
        
        guard let symbol = dlsym(handle, "TCCAccessPreflight") else {
            return nil
        }
        
        return unsafeBitCast(symbol, to: PreflightFunction.self)
    }()
    
    /// `dlsym` function handle for `TCCAccessRequest`
    static let requestFunction: RequestFunction? = {
        guard let handle = frameworkHandle else { return nil }
        
        guard let symbol = dlsym(handle, "TCCAccessRequest") else {
            return nil
        }
        
        return unsafeBitCast(symbol, to: RequestFunction.self)
    }()
} 