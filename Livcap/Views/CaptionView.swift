//
//  CaptionView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//
import SwiftUI

struct CaptionView: View {
    
    @StateObject private var caption = CaptionViewModel()
    @State private var isPinned = false
    @State private var isHovering = false
    
    private let opacityLevel: Double=0.75
    
    var body: some View {
        ZStack {
            // Transparent background with blur
            Rectangle()
                .fill(Color.backgroundColor)
                .background(.ultraThinMaterial, in: Rectangle())
                .opacity(opacityLevel)
            
            VStack(spacing: 0) {
                // Pin button - only visible when hovering
                HStack {
                    Spacer()
                    
                    Button(action: {
                        togglePin()
                    }) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isPinned ? .blue : .secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.5)
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(isPinned ? "Unpin from top" : "Pin to top ")
                    .opacity(isHovering ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                
                // Simple scrollable caption display
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(caption.captionHistory) { entry in
                                Text(entry.text)
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.clear)
                                            .opacity(opacityLevel)
                                    )
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        
                    
                        
                        
                    }
                    .onChange(of: caption.captionHistory.count) { _, _ in
                        if let lastEntry = caption.captionHistory.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                    

                    
                }
            }
        }
        .frame(minWidth: 400, minHeight: 100)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            // Start recording automatically
            if !caption.isRecording {
                caption.toggleRecording()
            }
        }
        .onDisappear {
            // Stop recording when window closes
            if caption.isRecording {
                caption.toggleRecording()
            }
        }
    }
    
    private func togglePin() {
        isPinned.toggle()
        
        guard let window = NSApplication.shared.windows.first else { return }
        
        if isPinned {
            // Set window to always on top
            window.level = .floating
        } else {
            // Set window to normal level
            window.level = .normal
        }
    }
}

#Preview("Light Mode") {
    CaptionView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    CaptionView()
        .preferredColorScheme(.dark)
}
