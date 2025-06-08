//
//  LivcapApp.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/2/25.
//

import SwiftUI
import SwiftData
import AVFoundation

@main
struct LivcapApp: App {
    @StateObject private var permissionState=PermissionState.shared
    
    init() {
        print("App is launching... initing")
        
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
                
                if permissionState.micPermissionGranted {
                    ContentView()
                } else {
                    PermissionView()
                }
            

        }
        .modelContainer(sharedModelContainer)
    }
    
    /// Returns `true` if microphone access is already authorized; otherwise `false`.
    func checkMicrophoneAccess() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
