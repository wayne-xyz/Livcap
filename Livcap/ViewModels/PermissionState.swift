//
//  PermissionState.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//

import AVFoundation
import Combine

class PermissionState: ObservableObject {
    static let shared = PermissionState()
    
    @Published var micPermissionGranted: Bool = false

    init() {
        checkMicPermission()
        print("micPermissionGranted: \(micPermissionGranted)")
    }

    func checkMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            micPermissionGranted = true
        } else {
            micPermissionGranted = false
        }
    }
}
