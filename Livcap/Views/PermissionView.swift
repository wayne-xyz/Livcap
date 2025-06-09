import SwiftUI
import AVFoundation

struct PermissionView: View {
    @ObservedObject var permissionManager=PermissionManager.shared
    

    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Status indicator
            HStack {
                Image(systemName: permissionManager.micPermissionGranted ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 30))
                    .foregroundColor( permissionManager.micPermissionGranted ? .green : .gray)
                
                Text(permissionManager.micPermissionGranted ?  "Microphone Access Granted" : "Microphone Access Required")
                    .font(.title)
            }
            .padding()
            
            // Status description
            Text(statusDescription)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button("Grant Required Permissions", action: {
                
            })

        }
        .padding()

    }
    
    private var statusDescription: String {
        if permissionManager.micPermissionGranted {
            return "Your microphone is ready to use. You can now start recording."
        } else {
            return "We need microphone access to enable voice recording features. Please grant permission in System Settings."
        }
    }
    

    
    private func requestPermission() {
        permissionManager.requestMicPermission()
    }
}

#Preview ("Light Mode") {
    PermissionView()
        .preferredColorScheme(.light)
}

#Preview ("Dark Mode") {
    PermissionView()
        .preferredColorScheme(.dark)
}
