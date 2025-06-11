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

    }
    
}
