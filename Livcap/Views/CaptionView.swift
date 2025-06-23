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
    @State private var showWindowControls = false
    
    private let opacityLevel: Double = 0.7
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent background with blur
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.backgroundColor)
                    .background(.ultraThinMaterial, in: Rectangle())
                    .opacity(opacityLevel)
                
                // Adaptive layout based on window height
                if geometry.size.height <= 100 {
                    // Small height: Single row layout
                    compactLayout(geometry: geometry)
                } else {
                    // Larger height: Traditional layout with controls at top, content below
                    expandedLayout(geometry: geometry)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 45)
        .onHover { hovering in
            isHovering = hovering
            showWindowControls = hovering
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
    
    // MARK: - Layout Functions
    
    @ViewBuilder
    private func compactLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Window control buttons (left side)
            WindowControlButtons(isVisible: $showWindowControls)
                .frame(width: 80) // Fixed width for buttons
            
            // Centered content area - same scrollable structure as expanded layout
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Current transcription (real-time)
                        if !caption.currentTranscription.isEmpty {
                            Text(caption.currentTranscription)
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                                .lineSpacing(7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.clear)
                                        .opacity(opacityLevel)
                                )
                                .id("current")
                        }
                        
                        // Caption history
                        ForEach(caption.captionHistory) { entry in
                            Text(entry.text)
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .lineSpacing(7)
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
                    .padding(.vertical, 16)
                }
                .onChange(of: caption.captionHistory.count) { _, _ in
                    if let lastEntry = caption.captionHistory.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: caption.currentTranscription) { _, _ in
                    if !caption.currentTranscription.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("current", anchor: .bottom)
                        }
                    }
                }
            }
            .padding(.horizontal, 20) // Equal margins on both sides

            
            // Pin button (right side)
            pinButton()
                .frame(width: 80) // Fixed width for pin button (same as control buttons)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func expandedLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top section with window controls and pin button
            HStack {
                // Window control buttons (left side)
                WindowControlButtons(isVisible: $showWindowControls)
                
                Spacer()
                
                // Pin button (right side)
                pinButton()
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .frame(height: 50)
            
            // Main content area - ScrollView with speech recognition content (centered)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Current transcription (real-time)
                        if !caption.currentTranscription.isEmpty {
                            Text(caption.currentTranscription)
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                                .lineSpacing(7)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.clear)
                                        .opacity(opacityLevel)
                                )
                                .id("current")
                        }
                        
                        // Caption history
                        ForEach(caption.captionHistory) { entry in
                            Text(entry.text)
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                                .lineSpacing(7)
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
                    .padding(.vertical, 16)
                }
                .onChange(of: caption.captionHistory.count) { _, _ in
                    if let lastEntry = caption.captionHistory.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: caption.currentTranscription) { _, _ in
                    if !caption.currentTranscription.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("current", anchor: .bottom)
                        }
                    }
                }
            }
            .padding(.horizontal, 20) // Equal margins on both sides for centering
            .padding(.bottom, 20)

        }
    }
    
    @ViewBuilder
    private func pinButton() -> some View {
        Button(action: {
            togglePin()
        }) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isPinned ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(isPinned ? "Unpin from top" : "Pin to top")
        .opacity(isHovering ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
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

#Preview("Light Mode - Hover State") {
    CaptionViewPreview(isHovering: true)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode - Hover State") {
    CaptionViewPreview(isHovering: true)
        .preferredColorScheme(.dark)
}

#Preview("Light Mode - Compact Layout") {
    CaptionViewPreview(isHovering: true)
        .frame(height: 80)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode - Compact Layout") {
    CaptionViewPreview(isHovering: true)
        .frame(height: 80)
        .preferredColorScheme(.dark)
}

// MARK: - Preview Helper

struct CaptionViewPreview: View {
    let isHovering: Bool
    
    @StateObject private var caption = CaptionViewModel()
    @State private var isPinned = false
    
    private let opacityLevel: Double = 0.7
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent background with blur
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.backgroundColor)
                    .background(.ultraThinMaterial, in: Rectangle())
                    .opacity(opacityLevel)
                
                // Adaptive layout based on window height
                if geometry.size.height <= 100 {
                    // Small height: Single row layout
                    compactPreviewLayout(geometry: geometry)
                } else {
                    // Larger height: Traditional layout
                    expandedPreviewLayout(geometry: geometry)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }
    
    @ViewBuilder
    private func compactPreviewLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Window control buttons (left side)
            WindowControlButtons(isVisible: .constant(isHovering))
                .frame(width: 80) // Fixed width for buttons
            
            // Centered content area - same scrollable structure as expanded layout
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Sample current transcription
                    Text("This is a live transcription example...")
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
                    
                    // Sample caption history
                    ForEach(0..<3, id: \.self) { index in
                        Text("This is caption history item \(index + 1). It shows how the transcribed text appears in the interface.")
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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .padding(.horizontal, 20) // Equal margins on both sides
            
            // Pin button (right side)
            previewPinButton()
                .frame(width: 80) // Fixed width for pin button (same as control buttons)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func expandedPreviewLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top section with window controls and pin button
            HStack {
                // Window control buttons (left side)
                WindowControlButtons(isVisible: .constant(isHovering))
                
                Spacer()
                
                // Pin button (right side)
                previewPinButton()
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .frame(height: 50)
            
            // Main content area (centered)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Sample current transcription
                    Text("This is a live transcription example...")
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
                    
                    // Sample caption history
                    ForEach(0..<3, id: \.self) { index in
                        Text("This is caption history item \(index + 1). It shows how the transcribed text appears in the interface.")
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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .padding(.horizontal, 20) // Equal margins on both sides for centering
            .padding(.bottom, 20)

        }
    }
    
    @ViewBuilder
    private func previewPinButton() -> some View {
        Button(action: {
            isPinned.toggle()
        }) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isPinned ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(isPinned ? "Unpin from top" : "Pin to top")
        .opacity(isHovering ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
}
