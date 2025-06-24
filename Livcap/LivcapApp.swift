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
    @StateObject private var permissionState=PermissionManager.shared
    
    init() {
        print("App is launching... initing")
    }

    var body: some Scene {
        WindowGroup {
            AppRouterView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: getGoldenRatioWidth(), height: 100)
        .defaultPosition(.bottom)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            // Remove default menu items for cleaner experience
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) { }
            CommandGroup(replacing: .systemServices) { }
        }
    }
    
    private func getGoldenRatioWidth() -> CGFloat {
        // Get screen width and calculate golden ratio (0.618)
        if let screen = NSScreen.main {
            return screen.frame.width * 0.618
        }
        return 800 // fallback
    }
}
