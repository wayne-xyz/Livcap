import SwiftUI
import AVFoundation
import Speech

struct PermissionView: View {
    @ObservedObject var permissionManager = PermissionManager.shared
    @State private var isRequesting = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent background with blur (same as CaptionView)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.backgroundColor)
                    .background(.ultraThinMaterial, in: Rectangle())
                    .opacity(0.7)
                
                // Content layout
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Text("Permissions Required")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Grant permissions to start live captions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    
                    // Permission Buttons (Horizontal Layout)
                    HStack(spacing: 24) {
                        // Microphone Permission
                        PermissionButton(
                            title: "Microphone",
                            description: "",
                            image: .system(permissionManager.micPermissionGranted ? "mic.fill" : "mic.slash.fill"),
                            isGranted: permissionManager.micPermissionGranted,
                            onRequestPermission: {
                                permissionManager.requestMicPermission()
                            }
                        )
                        
                        // Speech Recognition Permission
                        PermissionButton(
                            title: "Speech",
                            description: "",
                            image: .system(permissionManager.speechPermissionGranted ? "text.bubble.fill" : "text.bubble"),
                            isGranted: permissionManager.speechPermissionGranted,
                            onRequestPermission: {
                                permissionManager.requestSpeechPermission()
                            }
                        )
                        
                        // System Audio Permission
                        PermissionButton(
                            title: "System Audio",
                            description: "",
                            image: .custom(permissionManager.systemAudioPermissionStatus == .authorized ? "Laptop.wave" : "Laptop.wave.slash"),
                            isGranted: permissionManager.systemAudioPermissionStatus == .authorized,
                            onRequestPermission: {
                                if #available(macOS 14.4, *) {
                                    Task {
                                        await permissionManager.requestSystemAudioPermission()
                                    }
                                } else {
                                    permissionManager.openSystemAudioSettings()
                                }
                            }
                        )
                    }
                    
                    // Continue Button
                    Button("Continue") {
                        // This will trigger the AppRouterView to switch to CaptionView
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!permissionManager.hasAllRequiredPermissions())
                    
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(minWidth: 400, minHeight: 45)
    }
}

struct PermissionButton: View {
    let title: String
    let description: String
    let image: ButtonImage
    let isGranted: Bool
    let onRequestPermission: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon Button (same style as CaptionView CircularControlButton)
            Button(action: {
                if !isGranted {
                    onRequestPermission()
                }
            }) {
                Group {
                    switch image {
                    case .custom(let name):
                        Image(name)
                    case .system(let name):
                        Image(systemName: name)
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isGranted ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(isHovering ? 1 : 0.5)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    Circle()
                        .stroke(isGranted ? Color.green.opacity(0.6) : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
            .disabled(isGranted)
            
            // Compact text
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                // Status indicator
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isGranted ? .green : .orange)
            }
        }
        .frame(width: 80)
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
