//
//  RealTimeCaptionView.swift
//  Livcap
//
//  Created by Implementation Plan on 6/21/25.
//

import SwiftUI

/// Enhanced UI for real-time captioning with word-by-word animations
/// Provides smooth, beautiful display of overlapping transcription results
struct RealTimeCaptionView: View {
    @StateObject private var viewModel = RealTimeCaptionViewModel()
    @State private var showDebugInfo = false
    @State private var showStabilityStats = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main caption area
            VStack(spacing: 16) {
                // Stable transcription (confirmed text)
                if !viewModel.stableTranscription.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stable Transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView {
                            Text(viewModel.stableTranscription)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                        .frame(maxHeight: 150)
                    }
                }
                
                // Current transcription (latest window)
                if !viewModel.currentTranscription.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Window")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView {
                            Text(viewModel.currentTranscription)
                                .font(.body)
                                .foregroundColor(.primary.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                        .frame(maxHeight: 100)
                    }
                }
                
                // New words animation area
                if !viewModel.wordAnimations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.wordAnimations) { animation in
                                    AnimatedWordView(word: animation)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 40)
                    }
                }
            }
            .padding()
            
            Spacer()
            
            // Status and controls
            VStack(spacing: 12) {
                // Status bar
                HStack {
                    // Recording indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                            .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: viewModel.isRecording)
                        
                        Text(viewModel.isRecording ? "Recording" : "Ready")
                            .font(.caption)
                            .foregroundColor(viewModel.isRecording ? .red : .secondary)
                    }
                    
                    Spacer()
                    
                    // Confidence indicator
                    HStack(spacing: 4) {
                        Text("Confidence:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(Int(viewModel.confidence * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(confidenceColor(viewModel.confidence))
                    }
                    
                    Spacer()
                    
                    // Stability indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.stabilityStats.isStable ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        
                        Text(viewModel.stabilityStats.isStable ? "Stable" : "Unstable")
                            .font(.caption)
                            .foregroundColor(viewModel.stabilityStats.isStable ? .green : .orange)
                    }
                }
                .padding(.horizontal)
                
                // Status text
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Control buttons
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
                        showStabilityStats.toggle()
                    }) {
                        HStack {
                            Image(systemName: "chart.bar")
                            Text("Stats")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.purple)
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
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showDebugInfo) {
            DebugInfoView(viewModel: viewModel)
        }
        .sheet(isPresented: $showStabilityStats) {
            StabilityStatsView(viewModel: viewModel)
        }
        .onAppear {
            print("RealTimeCaptionView: Appeared - ready for real-time captioning")
        }
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Animated Word View

struct AnimatedWordView: View {
    let word: RealTimeCaptionViewModel.WordAnimation
    @State private var opacity: Double = 0.0
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        Text(word.word)
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .opacity(opacity)
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 1.0
                    scale = 1.0
                }
                
                // Fade out after 2.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        opacity = 0.0
                        scale = 0.8
                    }
                }
            }
    }
}

// MARK: - Debug Info View

struct DebugInfoView: View {
    let viewModel: RealTimeCaptionViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Debug Information")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Real-Time Captioning Status:")
                    .font(.headline)
                
                Text(viewModel.debugInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Stability Information:")
                    .font(.headline)
                
                Text(viewModel.stabilityInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Features:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Word-level diffing with fuzzy matching")
                    Text("• LocalAgreement-2 stabilization")
                    Text("• Real-time word animations")
                    Text("• Confidence-based filtering")
                    Text("• Stability statistics tracking")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}

// MARK: - Stability Stats View

struct StabilityStatsView: View {
    let viewModel: RealTimeCaptionViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stability Statistics")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                StatRow(title: "Agreement Rate", value: "\(String(format: "%.1f", viewModel.stabilityStats.agreementRate * 100))%")
                StatRow(title: "Average Confidence", value: "\(String(format: "%.2f", viewModel.stabilityStats.averageConfidence))")
                StatRow(title: "Stability Duration", value: "\(String(format: "%.1f", viewModel.stabilityStats.stabilityDuration))s")
                StatRow(title: "Window Count", value: "\(viewModel.stabilityStats.windowCount)")
                StatRow(title: "Is Stable", value: viewModel.stabilityStats.isStable ? "Yes" : "No")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Status:")
                    .font(.headline)
                
                Text(viewModel.statusText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
        .padding(.horizontal)
    }
}

#Preview {
    RealTimeCaptionView()
} 