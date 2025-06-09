//
//  AppRouterView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//

import SwiftUI
import AVFoundation


// 3. The Router View (Handles Conditional Display)
struct AppRouterView: View {
    @StateObject private var permissionState=PermissionManager.shared


    var body: some View {
        Group { // Or any container like VStack, ZStack
            if permissionState.micPermissionGranted {
                let _ = print("Mic Permission Granted")
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
        }
    }
}
