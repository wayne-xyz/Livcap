//
//  CaptionView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//
import SwiftUI
import AppKit


struct CaptionView: View {
    
    @StateObject private var captionViewModel: CaptionViewModel
    @State private var isPinned = false
    @State private var isHovering = false
    @State private var showWindowControls = false
    
    // Animation state for first content appearance
    @State private var hasShownFirstContentAnimation = false
    @State private var firstContentAnimationOffset: CGFloat = 30
    @State private var firstContentAnimationOpacity: Double = 0
    
    private let opacityLevel: Double = 0.7
    
    private let engineExamples=CoreAudioTapEngineExamples()
    


    init() {
        _captionViewModel = StateObject(wrappedValue: CaptionViewModel())
    }
    
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

            // Test CoreAudioTapEngine when view appears
            if #available(macOS 14.4, *) {
//                engineExamples.startSystemAudioCapture()


            }
        }

        .onDisappear {
            // Stop all audio sources when window closes
            if captionViewModel.isMicrophoneEnabled {
                captionViewModel.toggleMicrophone()
            }
            if captionViewModel.isSystemAudioEnabled {
                captionViewModel.toggleSystemAudio()
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
            
            // Centered content area with auto-scroll
            CaptionContentView(
                captionViewModel: captionViewModel,
                hasShownFirstContentAnimation: $hasShownFirstContentAnimation,
                firstContentAnimationOffset: $firstContentAnimationOffset,
                firstContentAnimationOpacity: $firstContentAnimationOpacity
            )
            .padding(.horizontal, 20) // Equal margins on both sides
            
            // Right side buttons: system audio, mic and pin (removed recording button)
            controlButtons()
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
                
                // Right side buttons: system audio, mic and pin (removed recording button)
                controlButtons()
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .frame(height: 50)
            
            // Main content area with auto-scroll
            CaptionContentView(
                captionViewModel: captionViewModel,
                hasShownFirstContentAnimation: $hasShownFirstContentAnimation,
                firstContentAnimationOffset: $firstContentAnimationOffset,
                firstContentAnimationOpacity: $firstContentAnimationOpacity
            )
            .padding(.horizontal, 20) // Equal margins on both sides for centering
            .padding(.bottom, 20)
        }
    }


    
    // MARK: - Window Management Functions
    
    private func toggleWindowPinning() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        if isPinned {
            // Pin window: Set to floating level to keep it on top
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            // Unpin window: Set to normal level
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces]
        }
    }
    
    @ViewBuilder
    private func controlButtons() -> some View {
        HStack(spacing: 8) {
            CircularControlButton(
                image: .system(captionViewModel.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"),
                helpText: "Toggle Microphone",
                isActive: captionViewModel.isMicrophoneEnabled,
                action: { captionViewModel.toggleMicrophone() }
            )

            CircularControlButton(
                image: .custom(captionViewModel.isSystemAudioEnabled ? "Laptop.wave" : "Laptop.wave.slash"),
                helpText: "Toggle System Audio",
                isActive: captionViewModel.isSystemAudioEnabled,
                action: { captionViewModel.toggleSystemAudio() }
            )
            
            CircularControlButton(
                image: .system(isPinned ? "pin.fill" : "pin"),
                helpText: "Pin Window",
                isActive: isPinned,
                action: {
                    isPinned.toggle()
                    toggleWindowPinning()
                }
            )
        }
        .opacity(isHovering ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
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

