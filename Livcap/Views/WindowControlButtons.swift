//
//  WindowControlButtons.swift
//  Livcap
//
//  Custom window control buttons that mimic macOS traffic lights
//  Appears on mouse hover at top-left corner of borderless windows
//

import SwiftUI
import AppKit

struct WindowControlButtons: View {
    @Binding var isVisible: Bool
    
    @State private var closeHovered = false
    @State private var minimizeHovered = false
    @State private var maximizeHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Close button (red)
            Button(action: closeWindow) {
                ZStack {
                    Circle()
                        .fill(closeHovered ? Color.red.opacity(1.0) : Color.red.opacity(0.8))
                        .frame(width: 12, height: 12)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                closeHovered = hovering
            }
            .help("Close")
            
            // Minimize button (yellow)
            Button(action: minimizeWindow) {
                ZStack {
                    Circle()
                        .fill(minimizeHovered ? Color.yellow.opacity(1.0) : Color.yellow.opacity(0.8))
                        .frame(width: 12, height: 12)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                minimizeHovered = hovering
            }
            .help("Minimize")
            
            // Maximize/Restore button (green)
            Button(action: toggleMaximize) {
                ZStack {
                    Circle()
                        .fill(maximizeHovered ? Color.green.opacity(1.0) : Color.green.opacity(0.8))
                        .frame(width: 12, height: 12)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                maximizeHovered = hovering
            }
            .help(isWindowMaximized() ? "Restore" : "Maximize")
        }
        .padding(3)
        .opacity(isVisible ? 1.0 : 0.0)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
    
    // MARK: - Window Actions
    
    private func closeWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.close()
    }
    
    private func minimizeWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.miniaturize(nil)
    }
    
    private func toggleMaximize() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        if isWindowMaximized() {
            // Restore to previous size
            restoreWindow(window)
        } else {
            // Maximize window
            maximizeWindow(window)
        }
    }
    
    private func isWindowMaximized() -> Bool {
        guard let window = NSApplication.shared.windows.first,
              let screen = window.screen else { return false }
        
        let windowFrame = window.frame
        let screenFrame = screen.visibleFrame
        
        // Check if window frame is approximately equal to screen frame
        let tolerance: CGFloat = 10
        return abs(windowFrame.minX - screenFrame.minX) < tolerance &&
               abs(windowFrame.minY - screenFrame.minY) < tolerance &&
               abs(windowFrame.width - screenFrame.width) < tolerance &&
               abs(windowFrame.height - screenFrame.height) < tolerance
    }
    
    private func maximizeWindow(_ window: NSWindow) {
        guard let screen = window.screen else { return }
        
        // Store current frame for restoration
        let currentFrame = window.frame
        UserDefaults.standard.set(NSStringFromRect(currentFrame), forKey: "WindowRestoreFrame")
        
        // Animate to full screen
        let targetFrame = screen.visibleFrame
        
        withAnimation(.easeInOut(duration: 0.3)) {
            window.setFrame(targetFrame, display: true, animate: true)
        }
    }
    
    private func restoreWindow(_ window: NSWindow) {
        // Get stored frame or use default
        let storedFrameString = UserDefaults.standard.string(forKey: "WindowRestoreFrame")
        let restoreFrame: NSRect
        
        if let frameString = storedFrameString {
            restoreFrame = NSRectFromString(frameString)
        } else {
            // Default restore size
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect.zero
            restoreFrame = NSRect(
                x: screenFrame.midX - 300,
                y: screenFrame.midY - 150,
                width: 600,
                height: 300
            )
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            window.setFrame(restoreFrame, display: true, animate: true)
        }
    }
}

#Preview("Light") {
    WindowControlButtons(isVisible: .constant(true))
        .frame(width: 200, height: 100)

        .preferredColorScheme(.light)
    
}

#Preview("Dark") {
    WindowControlButtons(isVisible: .constant(true))
        .frame(width: 200, height: 100)

        .preferredColorScheme(.dark)
}
