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
        .commands {
            // Remove default menu items for cleaner experience
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) { }
            CommandGroup(replacing: .systemServices) { }
        }
    }
    
    private func getGoldenRatioWidth() -> CGFloat {
        // Get the focused screen width and calculate golden ratio (0.618)
        let focusedScreen = getFocusedScreen()
        return focusedScreen.frame.width * 0.618
    }
    
    private func getFocusedScreen() -> NSScreen {
        // Get the screen where the mouse cursor is currently located
        let mouseLocation = NSEvent.mouseLocation
        
        // Find the screen that contains the mouse cursor
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        
        // Fallback to main screen if mouse is not on any screen
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen.main!
    }
}
