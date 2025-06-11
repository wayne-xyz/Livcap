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
//                ASRSimple()
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
        }
    }
}

#Preview {
    AppRouterView()
}
