import SwiftUI
import AVFoundation

struct PermissionView: View {
    @ObservedObject var permissionState=PermissionState.shared
    

    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Status indicator
            HStack {
                Image(systemName: permissionState.micPermissionGranted ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 40))
                    .foregroundColor( permissionState.micPermissionGranted ? .green : .red)
                
                Text(permissionState.micPermissionGranted ?  "Microphone Access Granted" : "Microphone Access Required")
                    .font(.headline)
            }
            .padding()
            
            // Status description
            Text(statusDescription)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            

        }
        .padding()

    }
    
    private var statusDescription: String {
        if permissionState.micPermissionGranted {
            return "Your microphone is ready to use. You can now start recording."
        } else {
            return "We need microphone access to enable voice recording features. Please grant permission in System Settings."
        }
    }
    

    
    private func requestPermission() {
        isRequesting = true
        
        // On macOS, we need to direct users to System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        
        // Check permission status after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRequesting = false
        }
    }
}

#Preview {
    PermissionView()
} 
