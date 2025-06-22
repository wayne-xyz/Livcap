//
//  WhisperLiveTestView.swift
//  Livcap
//
//  Phase 3: WhisperLive Implementation Test UI
//  - Test and monitor WhisperLive pipeline performance
//  - Compare with Phase 2 implementation side-by-side
//  - Detailed metrics and debugging interface
//

import SwiftUI

struct WhisperLiveTestView: View {
    @StateObject private var frameManager = WhisperLiveFrameManager()
    @StateObject private var audioManager = AudioManager()
    
    @State private var isRecording = false
    @State private var showDebugInfo = false
    @State private var audioProcessingTask: Task<Void, Error>?
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            statusSection
            
            transcriptionSection
            
            inferenceHistoryListSection
            
            if showDebugInfo {
                debugSection
            }
            
            controlsSection
        }
        .padding()
        .navigationTitle("WhisperLive Real-Time Monitor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(showDebugInfo ? "Hide Debug" : "Show Debug") {
                    showDebugInfo.toggle()
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    // MARK: - UI Sections
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("WhisperLive Real-Time Monitoring")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Frame-based VAD • Speech extraction • Real-time inference tracking")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            // Main status card
            HStack {
                Circle()
                    .fill(isRecording ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(isRecording ? "Recording" : "Stopped")
                    .font(.headline)
                
                Spacer()
                
                if isRecording {
                    let stats = frameManager.getBufferStats()
                    Text(stats.durationString)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stats.isAtMaxCapacity ? 
                                  Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Real-time monitoring sections
            if isRecording {
                monitoringSection
            }
        }
    }
    
    // MARK: - Real-time Monitoring Section
    
    private var monitoringSection: some View {
        VStack(spacing: 16) {
            // 1. Last 10 seconds per-second monitoring
            perSecondMonitoringView
            
            // 2. Current buffer frame-level analysis  
            bufferFrameAnalysisView
            
            // 3. Inference history
            inferenceHistoryView
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var perSecondMonitoringView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("📊 Last 10 Seconds (Per-Second Analysis)")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                let stats = frameManager.getBufferStats()
                Text("Silent: \(stats.consecutiveSilentSeconds)/3")
                    .font(.caption)
                    .foregroundColor(stats.consecutiveSilentSeconds >= 2 ? .red : .secondary)
            }
            
            // Second-by-second blocks with details
            let recentSeconds = frameManager.getRecentSeconds()
            HStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { index in
                    let hasData = index < recentSeconds.count
                    let summary = hasData ? recentSeconds[index] : nil
                    
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(hasData ? (summary!.hasVoice ? Color.green : Color.red) : Color.gray.opacity(0.3))
                            .frame(width: 25, height: 25)
                            .cornerRadius(4)
                        
                        if let summary = summary {
                            Text("\(summary.voiceFrameCount)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        } else {
                            Text("-")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            HStack {
                Text("🟢 Voice detected")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Text("🔴 Silence")
                    .font(.caption)
                    .foregroundColor(.red)
                
                Spacer()
                
                Text("Numbers = voice frames/10")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var bufferFrameAnalysisView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("🔍 Current Buffer Analysis")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                let stats = frameManager.getBufferStats()
                Text("\(stats.totalFrames) frames (\(stats.durationString))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            let stats = frameManager.getBufferStats()
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Buffer Status:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("Duration: \(stats.durationString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Voice: \(stats.voicePercentageString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Ready for Inference:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if stats.voicePercentage > 0 {
                        Text("🟢 Yes")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("🔴 No voice")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Text("\(Int(stats.voicePercentage * Float(stats.totalFrames))) voice frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var inferenceHistoryView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("📝 Last Inference")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(frameManager.inferenceHistory.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show most recent inference result
            if let lastResult = frameManager.lastInferenceResult {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Second \(lastResult.secondIndex)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Confidence: \(lastResult.confidenceString)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(lastResult.processingTimeString)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("processing time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("No inferences yet...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    // MARK: - Inference History List
    
    private var inferenceHistoryListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("📋 Inference History")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(frameManager.inferenceHistory.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if frameManager.inferenceHistory.isEmpty {
                VStack(spacing: 8) {
                    Text("No inferences yet")
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text("Start recording and speak to see inference results")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(frameManager.inferenceHistory.reversed()) { result in
                            inferenceResultCard(result)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
                .background(Color.gray.opacity(0.02))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func inferenceResultCard(_ result: InferenceResult) -> some View {
        VStack(spacing: 8) {
            // Header row
            HStack {
                Text("Second \(result.secondIndex)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
                
                Text(result.timestampString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Transcription text
            HStack {
                Text("\"\(result.transcriptionText)\"")
                    .font(.body)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                
                Spacer()
            }
            
            // Metrics row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Buffer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.bufferDurationString)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.speechDurationString)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(result.voiceFrameCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Processing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.processingTimeString)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confidence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.confidenceString)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(result.confidence >= 0.7 ? .green : result.confidence >= 0.4 ? .orange : .red)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.8))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Transcription")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if frameManager.getCurrentTranscription().isEmpty {
                        Text("Waiting for speech...")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        Text(frameManager.getCurrentTranscription())
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 80, maxHeight: 120)
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            if frameManager.processingError != nil {
                Text("Error: \\(frameManager.processingError!)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
    }
    
    
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug Information")
                .font(.headline)
            
            ScrollView {
                Text(frameManager.getDetailedStatus())
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    private var controlsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button(action: toggleRecording) {
                    HStack {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                        Text(isRecording ? "Stop Recording" : "Start Recording")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Button(action: clearTranscription) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            
            HStack(spacing: 16) {
                Button("Reset Pipeline") {
                    resetPipeline()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
                
                Button("Export History") {
                    exportInferenceHistory()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }
    
    
    // MARK: - Computed Properties
    
    private func getSecondsColor(_ summary: SecondSummary) -> Color {
        return summary.hasVoice ? .green : .red
    }
    
    // MARK: - Actions
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        
        Task {
            await audioManager.start()
            
            audioProcessingTask = Task {
                
                do {
                    let audioFrameStream = audioManager.audioFrames()
                    
                    print("🎯 WhisperLive Test: Starting audio processing")
                    
                    // Start the WhisperLive frame-based pipeline
                    frameManager.startProcessing(audioFrameStream)
                    
                    // Keep the task alive
                    try await Task.sleep(nanoseconds: UInt64.max)
                    
                } catch is CancellationError {
                    print("WhisperLive Test: Processing cancelled")
                } catch {
                    print("WhisperLive Test: Error: \\(error)")
                }
                
                audioProcessingTask = nil
            }
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        audioManager.stop()
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
        frameManager.stopProcessing()
        
        print("WhisperLive Test: Recording stopped")
    }
    
    private func clearTranscription() {
        // Don't reset the entire pipeline, just clear the display
        // The pipeline continues running to maintain context
        print("WhisperLive Test: Clearing transcription display")
    }
    
    private func resetPipeline() {
        stopRecording()
        frameManager.reset()
        print("WhisperLive Test: Pipeline reset")
    }
    
    private func exportInferenceHistory() {
        let history = frameManager.inferenceHistory
        
        print("📊 WhisperLive Inference History Export:")
        print("Total inferences: \\(history.count)")
        print("Session duration: \\(String(format: \"%.1f\", Date().timeIntervalSince(frameManager.sessionStartTime)))s")
        print("")
        print("Detailed Results:")
        print("================")
        
        for (index, result) in history.enumerated() {
            print("\\(index + 1). Second \\(result.secondIndex) - \\(result.timestampString)")
            print("   Text: \"\\(result.transcriptionText)\"")
            print("   Buffer: \\(result.bufferDurationString) | Speech: \\(result.speechDurationString) | Frames: \\(result.voiceFrameCount)")
            print("   Processing: \\(result.processingTimeString) | Confidence: \\(result.confidenceString)")
            print("")
        }
        
        // Calculate averages
        if !history.isEmpty {
            let avgProcessing = history.map { $0.processingTimeMs }.reduce(0, +) / Double(history.count)
            let avgConfidence = history.map { $0.confidence }.reduce(0, +) / Float(history.count)
            let avgSpeechDuration = history.map { $0.speechDuration }.reduce(0, +) / Double(history.count)
            
            print("Summary Statistics:")
            print("===================")
            print("Average processing time: \\(String(format: \"%.1f\", avgProcessing))ms")
            print("Average confidence: \\(String(format: \"%.2f\", avgConfidence))")
            print("Average speech duration: \\(String(format: \"%.1f\", avgSpeechDuration))s")
        }
        
        // TODO: In a real app, this would export to a file or share sheet
    }
}

// MARK: - Preview

struct WhisperLiveTestView_Previews: PreviewProvider {
    static var previews: some View {
        WhisperLiveTestView()
    }
}