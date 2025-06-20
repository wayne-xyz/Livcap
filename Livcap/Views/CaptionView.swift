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
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: caption.captionHistory.count) { oldValue, newValue in
                    // Auto-scroll to the latest caption
                    if let lastEntry = caption.captionHistory.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(.windowBackgroundColor))
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

#Preview {
    CaptionView()
}
