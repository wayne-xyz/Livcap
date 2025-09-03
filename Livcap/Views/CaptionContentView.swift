//
//  CaptionContentView.swift
//  Livcap
//
//  Extracted shared caption content from CaptionView
//  Handles all caption display, scrolling, and animation logic
//

import SwiftUI

struct CaptionContentView: View {
    @ObservedObject var captionViewModel: CaptionViewModel
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