//
//  PermissionWarningBanner.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//

import SwiftUI

struct PermissionWarningBanner: View {
    @ObservedObject var permissionManager: PermissionManager
    @State private var isVisible = true
    
    var body: some View {
        if permissionManager.hasDeniedPermissions && isVisible {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                    
                    Text(permissionManager.deniedPermissionMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
       
                    
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Light") {
    VStack {
        PermissionWarningBanner(permissionManager: {
            let manager = PermissionManager()
            manager.hasDeniedPermissions = true
            manager.deniedPermissionMessage = "Microphone and Speech Recognition access denied. Please enable in System Settings > Privacy & Security to use this feature. And restart the Livcap"
            return manager
        }())
        
        Spacer()
    }
    .frame(width: 400, height: 200)
    .preferredColorScheme(.light)
}



#Preview("Dark") {
    VStack {
        PermissionWarningBanner(permissionManager: {
            let manager = PermissionManager()
            manager.hasDeniedPermissions = true
            manager.deniedPermissionMessage = "Microphone and Speech Recognition access denied. Please enable in System Settings > Privacy & Security to use this feature. And restart the Livcap"
            return manager
        }())
        
        Spacer()
    }
    .frame(width: 400, height: 200)
    .preferredColorScheme(.dark)
}
