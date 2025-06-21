//
//  Phase2TestView.swift
//  Livcap
//
//  Phase 2 Test View: Enhanced VAD + Overlapping Confirmation
//

import SwiftUI

struct Phase2TestView: View {
    @StateObject private var viewModel = Phase2ContinuousViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 16) {
            headerSection
            
            TabView(selection: $selectedTab) {
                // Main Monitoring Tab
                mainMonitoringView
                    .tabItem {
                        Image(systemName: "waveform.circle.fill")
                        Text("Streaming")
                    }
                    .tag(0)
                
                // VAD Analysis Tab
                vadAnalysisView
                    .tabItem {
                        Image(systemName: "mic.circle.fill")
                        Text("VAD")
                    }
                    .tag(1)
                
                // Stabilization Tab
                stabilizationView
                    .tabItem {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        Text("Stabilization")
                    }
                    .tag(2)
                
                // Detailed Metrics Tab
                detailedMetricsView
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("Metrics")
                    }
                    .tag(3)
            }
            .frame(height: 400)
            
            controlsSection
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Phase 2: Enhanced VAD + Overlapping Confirmation")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var mainMonitoringView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isRecording {
                    // Real-time streaming metrics
                    streamingMetricsCard
                    
                    // Transcription results with stabilization
                    transcriptionResultsCard
                    
                    // Quick VAD status
                    quickVADStatusCard
                } else {
                    instructionsCard
                }
            }
            .padding()
        }
    }
    
    private var vadAnalysisView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isRecording {
                    // VAD Status Card
                    vadStatusCard
                    
                    // Speech Segments
                    speechSegmentsCard
                    
                    // VAD Confidence History
                    vadConfidenceCard
                } else {
                    Text("Start recording to see VAD analysis")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding()
        }
    }
    
    private var stabilizationView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isRecording {
                    // Stabilization Metrics
                    stabilizationMetricsCard
                    
                    // Word-level Stabilization
                    wordStabilizationCard
                    
                    // Overlap Analysis
                    overlapAnalysisCard
                } else {
                    Text("Start recording to see stabilization analysis")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding()
        }
    }
    
    private var detailedMetricsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Detailed System Report")
                    .font(.headline)
                
                Text(viewModel.getDetailedStatusReport())
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                
                Text("Recent Overlap Analysis")
                    .font(.headline)
                
                if let analysis = viewModel.stabilizationManager.getRecentOverlapAnalysis() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Overlap Region: \\(analysis.overlapRegionMs.lowerBound)-\\(analysis.overlapRegionMs.upperBound)ms")
                        Text("Matched Words: \\(analysis.matchedPairs.count)")
                        Text("Conflicts: \\(analysis.conflicts.count)")
                        Text("New Words: \\(analysis.newWords.count)")
                        Text("Confidence: \\(String(format: \"%.3f\", analysis.confidence))")
                    }
                    .font(.caption)
                    .padding()
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                } else {
                    Text("No overlap analysis available yet")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
    
    private var streamingMetricsCard: some View {
        VStack(spacing: 12) {
            Text("Streaming Metrics")
                .font(.headline)
            
            if let metrics = viewModel.streamingMetrics {
                HStack(spacing: 20) {
                    metricItem("Chunks", value: "\\(metrics.totalChunksProcessed)")
                    metricItem("Triggers", value: "\\(metrics.totalTranscriptionsTriggered)")
                    metricItem("Buffer", value: "\\(Int(metrics.bufferUtilization * 100))%")
                    metricItem("Avg Time", value: "\\(String(format: \"%.1f\", metrics.averageChunkProcessingTimeMs))ms")
                }
            }
            
            Text("Last Chunk: \\(viewModel.lastChunkInfo)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var transcriptionResultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Results")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.stabilizedText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("✅ Stabilized Text:")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text(viewModel.stabilizedText)
                            .fontWeight(.semibold)
                    }
                }
                
                if !viewModel.captionText.isEmpty && viewModel.captionText != viewModel.stabilizedText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🔄 Current Text:")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(viewModel.captionText)
                    }
                }
                
                if viewModel.captionText.isEmpty || viewModel.captionText == "..." {
                    Text("🔇 Speak continuously for 2+ seconds to trigger transcription")
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Total transcriptions: \\(viewModel.captionHistory.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var quickVADStatusCard: some View {
        VStack(spacing: 8) {
            Text("VAD Status")
                .font(.headline)
            
            if let vadInfo = viewModel.vadMetrics {
                HStack(spacing: 20) {
                    vadStatusItem("Speech", value: "\\(Int(vadInfo.speechPercentage * 100))%", 
                                 isGood: vadInfo.speechPercentage > 0.3)
                    vadStatusItem("Confidence", value: String(format: "%.3f", vadInfo.averageConfidence),
                                 isGood: vadInfo.averageConfidence > 0.5)
                    vadStatusItem("Segments", value: "\\(vadInfo.segmentCount)",
                                 isGood: vadInfo.segmentCount > 0)
                }
            }
            
            HStack {
                Circle()
                    .fill(viewModel.enhancedVAD.currentVADState ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(viewModel.enhancedVAD.currentVADState ? "Speaking" : "Silent")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var vadStatusCard: some View {
        VStack(spacing: 12) {
            Text("Enhanced VAD Analysis")
                .font(.headline)
            
            HStack(spacing: 20) {
                vadDetailItem("Energy Level", value: String(format: "%.4f", viewModel.enhancedVAD.currentEnergyLevel))
                vadDetailItem("Spectral Activity", value: String(format: "%.3f", viewModel.enhancedVAD.currentSpectralActivity))
                vadDetailItem("Confidence", value: String(format: "%.3f", viewModel.enhancedVAD.currentConfidence))
            }
            
            if let vadInfo = viewModel.vadMetrics {
                HStack(spacing: 20) {
                    vadDetailItem("Speech %", value: "\\(Int(vadInfo.speechPercentage * 100))%")
                    vadDetailItem("Avg Confidence", value: String(format: "%.3f", vadInfo.averageConfidence))
                    vadDetailItem("Segments", value: "\\(vadInfo.segmentCount)")
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var speechSegmentsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Speech Segments")
                .font(.headline)
            
            if !viewModel.enhancedVAD.activeSpeechSegments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.enhancedVAD.activeSpeechSegments.suffix(5), id: \.id) { segment in
                            speechSegmentView(segment)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                Text("No speech segments detected yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var vadConfidenceCard: some View {
        VStack(spacing: 8) {
            Text("Current VAD State")
                .font(.headline)
            
            HStack {
                Image(systemName: viewModel.enhancedVAD.currentVADState ? "mic.fill" : "mic.slash.fill")
                    .foregroundColor(viewModel.enhancedVAD.currentVADState ? .green : .red)
                
                Text(viewModel.enhancedVAD.currentVADState ? "SPEAKING" : "SILENT")
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.enhancedVAD.currentVADState ? .green : .secondary)
            }
            .font(.title3)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var stabilizationMetricsCard: some View {
        VStack(spacing: 12) {
            Text("Stabilization Metrics")
                .font(.headline)
            
            if let metrics = viewModel.stabilizationMetrics {
                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        metricItem("Stabilized", value: "\\(metrics.stabilizedWordCount)")
                        metricItem("Rate", value: "\\(Int(metrics.stabilizationRate * 100))%")
                        metricItem("Overlaps", value: "\\(metrics.totalOverlaps)")
                        metricItem("Conflicts", value: "\\(metrics.conflictCount)")
                    }
                    
                    HStack(spacing: 20) {
                        metricItem("Transcriptions", value: "\\(metrics.totalTranscriptions)")
                        metricItem("Avg Overlap Conf.", value: String(format: "%.3f", metrics.averageOverlapConfidence))
                    }
                }
            } else {
                Text("No stabilization data available yet")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var wordStabilizationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Word-Level Stabilization")
                .font(.headline)
            
            let stabilizedWords = viewModel.stabilizedWords
            
            if !stabilizedWords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stabilizedWords.suffix(10), id: \.text) { word in
                            wordStabilizationView(word)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                Text("No words available for stabilization analysis")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var overlapAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overlap Analysis")
                .font(.headline)
            
            if let analysis = viewModel.stabilizationManager.getRecentOverlapAnalysis() {
                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        metricItem("Matches", value: "\\(analysis.matchedPairs.count)")
                        metricItem("Conflicts", value: "\\(analysis.conflicts.count)")
                        metricItem("New Words", value: "\\(analysis.newWords.count)")
                        metricItem("Confidence", value: String(format: "%.3f", analysis.confidence))
                    }
                    
                    Text("Overlap: \\(analysis.overlapRegionMs.lowerBound)-\\(analysis.overlapRegionMs.upperBound)ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No overlap analysis available yet - need at least 2 transcriptions")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phase 2 Features:")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("🎤 Enhanced VAD - Sophisticated speech detection using energy + spectral analysis")
                Text("🔄 Overlapping Confirmation - Cross-validate transcriptions across 3-second overlaps")
                Text("📊 Word Stabilization - Track confidence and stabilization across multiple windows")
                Text("⚡ Progressive Updates - Real-time stabilization and conflict resolution")
            }
            .font(.subheadline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions:")
                    .font(.headline)
                Text("• Click 'Start Enhanced Streaming' to begin")
                Text("• Speak continuously for 2+ seconds")
                Text("• Watch overlapping confirmation in action")
                Text("• Monitor VAD and stabilization tabs")
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var controlsSection: some View {
        HStack(spacing: 16) {
            Button(viewModel.isRecording ? "Stop Enhanced Streaming" : "Start Enhanced Streaming") {
                viewModel.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Clear All") {
                viewModel.clearCaptions()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRecording)
        }
    }
    
    // MARK: - Helper Views
    
    private func metricItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func vadStatusItem(_ label: String, value: String, isGood: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(isGood ? .green : .orange)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func vadDetailItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func speechSegmentView(_ segment: SpeechSegment) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1fs", segment.duration))
                .font(.caption)
                .fontWeight(.medium)
            Text(String(format: "%.3f", segment.averageConfidence))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.textBackgroundColor))
        .cornerRadius(6)
    }
    
    private func wordStabilizationView(_ word: StabilizedWord) -> some View {
        VStack(spacing: 2) {
            Text(word.text)
                .font(.caption)
                .fontWeight(word.isStabilized ? .bold : .regular)
                .foregroundColor(word.isStabilized ? .primary : .secondary)
            
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < word.stabilizationCount ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
            
            Text(String(format: "%.2f", word.confidence))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(word.isStabilized ? Color.green.opacity(0.1) : Color(.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(word.isStabilized ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    Phase2TestView()
        .frame(width: 800, height: 600)
}