//
//  CaptionView.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/8/25.
//
import SwiftUI

struct CaptionView: View {
    
    @StateObject private var caption = CaptionViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Simple scrollable caption display
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(caption.captionHistory) { entry in
                            Text(entry.text)
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary.opacity(0.3))
                                        .opacity(0.6)
                                )
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: caption.captionHistory.count) { oldValue, newValue in
                    // Auto-scroll to the latest caption
                    if let lastEntry = caption.captionHistory.last {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 100) // Allow resizing with minimum height
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.quaternary, lineWidth: 0.8)
                )
        )
        .onAppear {
            // Automatically start recording when the view appears
            if !caption.isRecording {
                caption.toggleRecording()
            }
        }
        .onDisappear {
            // Automatically stop recording when the view disappears
            if caption.isRecording {
                caption.toggleRecording()
            }
        }
    }
}

#Preview("Light Mode") {
    CaptionView()
        .preferredColorScheme(.light)
        .frame(width: 400, height: 150)
        .background(Color.gray.opacity(0.1))
}

#Preview("Dark Mode") {
    CaptionView()
        .preferredColorScheme(.dark)
        .frame(width: 400, height: 150)
        .background(Color.black.opacity(0.8))
}
