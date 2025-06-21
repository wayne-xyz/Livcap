//
//  OverlappingTestView.swift
//  Livcap
//
//  Created by Implementation Plan on 6/20/25.
//

import SwiftUI

/// Test view for the overlapping windows approach
/// This allows us to test the new pipeline in Xcode
struct OverlappingTestView: View {
    @StateObject private var viewModel = OverlappingCaptionViewModel()
    @State private var showDebugInfo = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack {
                Text("WhisperLive-Style Overlapping Windows Test")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Phase 1 Implementation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            // Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Status:")
                    .font(.headline)
                
                Text(viewModel.statusText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // Buffer Stats
            VStack(alignment: .leading, spacing: 8) {
                Text("Buffer Stats:")
                    .font(.headline)
                
                Text(viewModel.bufferStats)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // Current Transcription
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Transcription:")
                    .font(.headline)
                
                ScrollView {
                    Text(viewModel.currentTranscription.isEmpty ? "No transcription yet..." : viewModel.currentTranscription)
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 200)
            }
            .padding(.horizontal)
            
            // New Words (Animated)
            if !viewModel.newWords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Words:")
                        .font(.headline)
                    
                    HStack {
                        ForEach(viewModel.newWords, id: \.self) { word in
                            Text(word)
                                .font(.body)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .cornerRadius(6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.newWords)
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Control Buttons
            HStack(spacing: 20) {
                Button(action: {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "play.circle.fill")
                        Text(viewModel.isRecording ? "Stop" : "Start")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(viewModel.isRecording ? Color.red : Color.green)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    viewModel.clearTranscription()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    showDebugInfo.toggle()
                }) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Debug")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.purple)
                    .cornerRadius(10)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showDebugInfo) {
            DebugInfoView(viewModel: viewModel)
        }
        .onAppear {
            print("OverlappingTestView: Appeared - ready for testing")
        }
    }
}

// MARK: - Debug Info View

struct DebugInfoView: View {
    let viewModel: OverlappingCaptionViewModel
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Debug Information")
                    .font(.title)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("WhisperLive Configuration:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Window Size: 3 seconds (48,000 samples)")
                        Text("• Step Size: 1 second (16,000 samples)")
                        Text("• Overlap: 2 seconds (32,000 samples)")
                        Text("• Update Frequency: Every 1 second")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current State:")
                        .font(.headline)
                    
                    Text(viewModel.debugInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Instructions:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Click 'Start' to begin recording")
                        Text("2. Speak continuously for at least 3 seconds")
                        Text("3. Watch for new words appearing every ~1 second")
                        Text("4. Check console for detailed logs")
                        Text("5. Monitor buffer stats for window timing")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Dismiss sheet
                    }
                }
            }
        }
    }
}

#Preview {
    OverlappingTestView()
} 