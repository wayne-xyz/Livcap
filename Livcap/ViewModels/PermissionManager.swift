//
//  PermissionState.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//

import AVFoundation
import Combine
import AppKit

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var micPermissionGranted: Bool = false
    @Published var micPermissionStatus:AVAuthorizationStatus = .notDetermined

    init() {
        checkMicPermission()
        print("micPermissionGranted: \(micPermissionGranted)")
        debugLog("micPermissionStatus:\(micPermissionStatus)")
    }

    func checkMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            micPermissionGranted = true
        } else {
            micPermissionGranted = false
        }
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
    
}
