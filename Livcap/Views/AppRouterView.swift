//
//  AppRouterView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//

import SwiftUI
import AVFoundation

struct AppRouterView: View {
    @StateObject private var permissionState = PermissionManager.shared

    var body: some View {
        Group {
            if permissionState.micPermissionGranted {
                CaptionView()
            } else {
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
            
            // Configure window appearance to match content
            configureWindowAppearance()
        }
    }
    
    private func positionWindowAtBottomCenter() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        // Get the focused screen (where mouse cursor is)
        let focusedScreen = getFocusedScreen()
        
        // Calculate window position
        let windowWidth = window.frame.width
        let windowHeight = window.frame.height
        
        // Center horizontally on the focused screen
        let x = focusedScreen.frame.minX + (focusedScreen.frame.width - windowWidth) / 2
        
        // Position at bottom, just above Dock
        let y = calculateYPositionAboveDock(screen: focusedScreen, windowHeight: windowHeight)
        
        // Set window position
        let newFrame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        window.setFrame(newFrame, display: true, animate: true)
        
        // Set window level to floating for better visibility
        window.level = .floating
        
        // Make window resizable
        window.styleMask.insert(.resizable)
        
        // Set minimum size
        window.minSize = NSSize(width: 400, height: 100)
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
    
    private func calculateYPositionAboveDock(screen: NSScreen, windowHeight: CGFloat) -> CGFloat {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        // Check if Dock is visible on this screen
        let dockHeight = fullFrame.height - visibleFrame.height
        
        if dockHeight > 0 {
            // Dock is visible, position above it
            return visibleFrame.minY + 10
        } else {
            // No Dock visible, use bottom margin
            return fullFrame.minY + 20
        }
    }
    
    private func configureWindowAppearance() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        // Hide the titlebar completely
        window.styleMask = [.borderless, .resizable]
        
        // Make title bar transparent and match content background
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        
        // Set window background to match content
        window.backgroundColor = NSColor(Color.backgroundColor).withAlphaComponent(0.75)
        
        // Make the window movable by dragging anywhere on it
        window.isMovableByWindowBackground = true
        
        // Add rounded corners to the window using layer
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = NSColor.clear
        
        // Set the window's content view to have rounded corners
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 8
            contentView.layer?.masksToBounds = true
        }
    }
}

#Preview {
    AppRouterView()
}
