//
//  AppRouterView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//

import SwiftUI
import AVFoundation

struct AppRouterView: View {
    @StateObject private var permissionState=PermissionManager.shared

    var body: some View {
        Group {
            if permissionState.micPermissionGranted {
               CaptionView()
            }else{
                PermissionView()
            }
        }
        // This onAppear is crucial if the app was closed and reopened,
        // to re-check permission status.
        .onAppear {
            //update the permission state
            permissionState.checkMicPermission()
            debugLog("AppRouter Appear")
            
            // Position window at bottom center, just above Dock
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                positionWindowAtBottomCenter()
            }
        }
    }
    
    private func positionWindowAtBottomCenter() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        // Get the currently focused screen (where the user is working)
        let focusedScreen = getFocusedScreen()
        
        // Calculate window dimensions
        let windowWidth = focusedScreen.frame.width * 0.618 // Golden ratio
        let windowHeight: CGFloat = 100 // Default height, but can be resized
        
        // Calculate position on the focused screen
        let x = focusedScreen.frame.minX + (focusedScreen.frame.width - windowWidth) / 2 // Center horizontally
        
        // Calculate Y position to avoid Dock overlap
        let y = calculateYPositionAboveDock(screen: focusedScreen, windowHeight: windowHeight)
        
        // Set window frame
        let newFrame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        window.setFrame(newFrame, display: true, animate: true)
        
        // Make sure window is on top and has proper level
        window.level = .floating
        window.orderFront(nil)
        
        // Ensure window appears on the correct space/desktop
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Set minimum size constraints for resizable window
        window.minSize = NSSize(width: 300, height: 100)
        
        // Enable resizing by setting the style mask
        window.styleMask.insert(.resizable)
    }
    
    private func calculateYPositionAboveDock(screen: NSScreen, windowHeight: CGFloat) -> CGFloat {
        // Get the visible frame (screen area excluding Dock and menu bar)
        let visibleFrame = screen.visibleFrame
        
        // Get the full screen frame
        let fullFrame = screen.frame
        
        // Calculate Dock height by comparing full frame to visible frame
        let dockHeight = fullFrame.height - visibleFrame.height
        
        // If Dock is visible on this screen (dockHeight > 0), position above it
        if dockHeight > 0 {
            // Position window above the Dock with a small gap
            return visibleFrame.minY + 50 // 10px gap above Dock
        } else {
            // No Dock on this screen, position at bottom with small margin
            return fullFrame.minY + 20
        }
    }
    
    private func getFocusedScreen() -> NSScreen {
        // Get the screen where the mouse cursor is currently located
        // This is a good approximation for the "focused" screen
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

#Preview {
    AppRouterView()
}
