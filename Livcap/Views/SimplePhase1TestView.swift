//
//  SimplePhase1TestView.swift
//  Livcap
//
//  Simple Phase 1 Test View
//

import SwiftUI

struct SimplePhase1TestView: View {
    @StateObject private var viewModel = ContinuousViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Phase 1: Continuous Streaming Test")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.isRecording {
                VStack(spacing: 12) {
                    if let metrics = viewModel.streamingMetrics {
                        Text("Chunks: \(metrics.totalChunksProcessed) | Triggers: \(metrics.totalTranscriptionsTriggered)")
                        Text("Buffer: \(Int(metrics.bufferUtilization * 100))% | Avg: \(String(format: "%.1f", metrics.averageChunkProcessingTimeMs))ms")
                    }
                    
                    Text("Last Chunk: \(viewModel.lastChunkInfo)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription Results")
                        .font(.headline)
                    
                    if viewModel.captionText.isEmpty || viewModel.captionText == "..." {
                        Text("🔇 Speak continuously for 2+ seconds to trigger transcription")
                            .foregroundColor(.secondary)
                    } else {
                        Text(viewModel.captionText)
                            .padding()
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                    }
                    
                    Text("Total transcriptions: \(viewModel.captionHistory.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions:")
                        .font(.headline)
                    Text("• Click 'Start Streaming' to begin")
                    Text("• Speak continuously for 2+ seconds")
                    Text("• Watch for transcription triggers every 2 seconds")
                    Text("• Monitor chunk processing (~10 chunks/second)")
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            HStack(spacing: 16) {
                Button(viewModel.isRecording ? "Stop Streaming" : "Start Streaming") {
                    viewModel.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Clear") {
                    viewModel.clearCaptions()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRecording)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SimplePhase1TestView()
        .frame(width: 600, height: 400)
}