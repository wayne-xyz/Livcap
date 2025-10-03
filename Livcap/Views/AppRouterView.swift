//
//  AppRouterView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//

import SwiftUI
import AVFoundation

struct AppRouterView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var hasInitialized = false

    var body: some View {
        VStack(spacing: 0) {
            // Warning banner for denied permissions (appears at top if needed)
            PermissionWarningBanner(permissionManager: permissionManager)
            
            // Always show CaptionView (no more permission blocking)
            CaptionView()
                .onAppear {
                    if !hasInitialized {
                        configureInitialCaptionWindow()
                    }
                }
        }
        .onAppear {
            initializeApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // App regained focus - recheck for permission changes
            debugLog("App became active - rechecking denied permissions")
            permissionManager.checkDeniedPermissionsOnLoad()
        }
    }
    
    private func initializeApp() {
        guard !hasInitialized else { return }
        hasInitialized = true
        
        debugLog("AppRouter Initializing - new simple flow")
        
        // Check for denied permissions (for warning banner)
        permissionManager.checkDeniedPermissionsOnLoad()
        
        // Configure window appearance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            configureWindowAppearance()
        }
    }
    
    // MARK: - Window Configuration Methods
    
    private func configureInitialCaptionWindow() {
        debugLog("Configuring initial caption window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApplication.shared.windows.first else { return }
            
            // Set initial compact size
            let newSize = NSSize(width: 400, height: 45)
            
            // Position at bottom center
            let screen = self.getFocusedScreen()
            let x = screen.frame.minX + (screen.frame.width - newSize.width) / 2
            let y = self.calculateYPositionAboveDock(screen: screen, windowHeight: newSize.height)
            
            let newFrame = NSRect(origin: NSPoint(x: x, y: y), size: newSize)
            window.setFrame(newFrame, display: true, animate: false)
            
            // Set resizable constraints for caption window
            window.minSize = NSSize(width: 400, height: 45)
            window.maxSize = NSSize(width: 2000, height: 800)
        }
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
        window.styleMask = [.borderless, .resizable,.miniaturizable]
        
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
            contentView.layer?.cornerRadius = 26
            contentView.layer?.masksToBounds = true
        }
    }
}

// MARK: - Debug Helper

private func debugLog(_ message: String) {
    print("🟡 [AppRouter] \(message)")
}

#Preview {
    AppRouterView()
}
