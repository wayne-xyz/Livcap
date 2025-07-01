//
//  CaptionView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//
import SwiftUI


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
            // Reset animation state on view appear
            resetFirstContentAnimation()
            
            // Test CoreAudioTapEngine when view appears
            if #available(macOS 14.4, *) {
//                engineExamples.startSystemAudioCapture()


            }
        }
        .onChange(of: captionViewModel.captionHistory.isEmpty) { _, isEmpty in
            // Reset animation when captions are cleared
            if isEmpty && captionViewModel.currentTranscription.isEmpty {
                resetFirstContentAnimation()
            }
        }
        .onDisappear {
            // Stop audio sources when window closes
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Caption history (older sentences at top)
                        ForEach(captionViewModel.captionHistory.indices, id: \.self) { index in
                            let entry = captionViewModel.captionHistory[index]
                            let isFirstContent = index == 0 && captionViewModel.currentTranscription.isEmpty
                            
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
                                .offset(y: isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOffset : 0)
                                .opacity(isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOpacity : 1.0)
                        }
                        
                        // Current transcription (real-time at bottom)
                        if !captionViewModel.currentTranscription.isEmpty {
                            let isFirstContent = captionViewModel.captionHistory.isEmpty
                            
                            Text(captionViewModel.currentTranscription+"...")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                                .lineSpacing(7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("currentTranscription")
                                .offset(y: isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOffset : 0)
                                .opacity(isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOpacity : 1.0)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: captionViewModel.currentTranscription) {
                    // Trigger first content animation for currentTranscription
                    if !captionViewModel.currentTranscription.isEmpty && !hasShownFirstContentAnimation && captionViewModel.captionHistory.isEmpty {
                        triggerFirstContentAnimation()
                    }
                    
                    if !captionViewModel.currentTranscription.isEmpty {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("currentTranscription", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: captionViewModel.captionHistory.count) {
                    // Trigger first content animation for first caption history entry
                    if !captionViewModel.captionHistory.isEmpty && !hasShownFirstContentAnimation {
                        triggerFirstContentAnimation()
                    }
                    
                    // Auto-scroll when new caption is added
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastEntry = captionViewModel.captionHistory.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Caption history (older sentences at top)
                        ForEach(captionViewModel.captionHistory.indices, id: \.self) { index in
                            let entry = captionViewModel.captionHistory[index]
                            let isFirstContent = index == 0 && captionViewModel.currentTranscription.isEmpty
                            
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
                                .offset(y: isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOffset : 0)
                                .opacity(isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOpacity : 1.0)
                        }
                        
                        // Current transcription (real-time at bottom)
                        if !captionViewModel.currentTranscription.isEmpty {
                            let isFirstContent = captionViewModel.captionHistory.isEmpty
                            
                            Text(captionViewModel.currentTranscription+"...")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                                .lineSpacing(7)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("currentTranscription")
                                .offset(y: isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOffset : 0)
                                .opacity(isFirstContent && !hasShownFirstContentAnimation ? firstContentAnimationOpacity : 1.0)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: captionViewModel.currentTranscription) {
                    // Trigger first content animation for currentTranscription
                    if !captionViewModel.currentTranscription.isEmpty && !hasShownFirstContentAnimation && captionViewModel.captionHistory.isEmpty {
                        triggerFirstContentAnimation()
                    }
                    
                    if !captionViewModel.currentTranscription.isEmpty {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("currentTranscription", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: captionViewModel.captionHistory.count) {
                    // Trigger first content animation for first caption history entry
                    if !captionViewModel.captionHistory.isEmpty && !hasShownFirstContentAnimation {
                        triggerFirstContentAnimation()
                    }
                    
                    // Auto-scroll when new caption is added
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastEntry = captionViewModel.captionHistory.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20) // Equal margins on both sides for centering
            .padding(.bottom, 20)

        }
    }
    
    // MARK: - Animation Functions
    
    private func triggerFirstContentAnimation() {
        guard !hasShownFirstContentAnimation else { return }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.1)) {
            firstContentAnimationOffset = 0
            firstContentAnimationOpacity = 1.0
        }
        
        hasShownFirstContentAnimation = true
    }
    
    private func resetFirstContentAnimation() {
        hasShownFirstContentAnimation = false
        firstContentAnimationOffset = 30
        firstContentAnimationOpacity = 0
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
                    // Add window pinning logic here
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

