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

    @State private var showAboutWindow = false
    
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
            CommandGroup(replacing: .systemServices) { }
            
            // Custom About menu item
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
        }
        
        // About window
        Window("About Livcap", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 300, height: 400)

    }
    
    private func getGoldenRatioWidth() -> CGFloat {
        // Get screen width and calculate golden ratio (0.618)
        if let screen = NSScreen.main {
            return screen.frame.width * 0.618
        }
        return 800 // fallback
    }
    
}

struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button("About Livcap") {
            openWindow(id: "about")
        }
        .keyboardShortcut("a", modifiers: .command)
    }
}
