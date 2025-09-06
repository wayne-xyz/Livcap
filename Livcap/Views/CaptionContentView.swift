//
//  CaptionContentView.swift
//  Livcap
//
//  Extracted shared caption content from CaptionView
//  Handles all caption display, scrolling, and animation logic
//

import SwiftUI

struct CaptionContentView<ViewModel: CaptionViewModelProtocol>: View {
    @ObservedObject var captionViewModel: ViewModel
    @Binding var hasShownFirstContentAnimation: Bool
    @Binding var firstContentAnimationOffset: CGFloat
    @Binding var firstContentAnimationOpacity: Double
    
    private let opacityLevel: Double = 0.7
    
    var body: some View {
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
                            .padding(.vertical, 1)
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
                            .padding(.vertical, 1)
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
    }
    
    private func triggerFirstContentAnimation() {
        guard !hasShownFirstContentAnimation else { return }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.1)) {
            firstContentAnimationOffset = 0
            firstContentAnimationOpacity = 1.0
        }
        
        hasShownFirstContentAnimation = true
    }
}

// MARK: - Preview Support

class MockCaptionViewModel: ObservableObject, CaptionViewModelProtocol {
    @Published var captionHistory: [CaptionEntry] = [
        CaptionEntry(text: "Welcome to Livcap, the real-time live captioning application for macOS.", confidence: 0.95),
        CaptionEntry(text: "This app captures audio from your microphone and system audio sources.", confidence: 0.92),
        CaptionEntry(text: "Speech recognition is powered by Apple's advanced Speech framework.", confidence: 0.88)
    ]
    
    @Published var currentTranscription: String = "This is a sample of real-time transcription text as it appears during live captioning"
}



#Preview("Light Mode") {
    CaptionContentView(
        captionViewModel: MockCaptionViewModel(),
        hasShownFirstContentAnimation: .constant(true),
        firstContentAnimationOffset: .constant(0),
        firstContentAnimationOpacity: .constant(1.0)
    )
    .frame(width: 600, height: 200)
    .background(Color.gray.opacity(0.1))
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    CaptionContentView(
        captionViewModel: MockCaptionViewModel(),
        hasShownFirstContentAnimation: .constant(true),
        firstContentAnimationOffset: .constant(0),
        firstContentAnimationOpacity: .constant(1.0)
    )
    .frame(width: 600, height: 400)
    .background(Color.gray.opacity(0.1))
    .preferredColorScheme(.dark)
}

