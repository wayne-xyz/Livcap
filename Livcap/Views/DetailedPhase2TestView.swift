//
//  DetailedPhase2TestView.swift
//  Livcap
//
//  Comprehensive Phase 2 Verification View - Single Tab with All Details
//

import SwiftUI
import Foundation

struct DetailedPhase2TestView: View {
    @StateObject private var viewModel = Phase2ContinuousViewModel()
    @State private var transcriptionWindows: [TranscriptionWindow] = []
    @State private var vadDecisions: [VADDecision] = []
    @State private var overlapAnalyses: [DetailedOverlapAnalysis] = []
    @State private var recentSkippedResults: [SkippedResult] = []
    
    struct TranscriptionWindow: Identifiable {
        let id = UUID()
        let windowNumber: Int
        let timestamp: Date
        let text: String
        let confidence: Float
        let isSkipped: Bool
        let skipReason: String?
        let words: [String]
    }
    
    struct VADDecision: Identifiable {
        let id = UUID()
        let timestamp: Date
        let energyLevel: Float
        let finalDecision: Bool
        let confidence: Float
        let reason: String
    }
    
    struct DetailedOverlapAnalysis: Identifiable {
        let id = UUID()
        let windowPair: String
        let previousWords: [String]
        let currentWords: [String]
        let exactMatches: [(String, String)]
        let conflicts: [(String, String)]
        let newWords: [String]
        let overlapConfidence: Float
    }
    
    struct SkippedResult: Identifiable {
        let id = UUID()
        let timestamp: Date
        let text: String
        let confidence: Float
        let reason: String
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                controlsSection
                
                if viewModel.isRecording {
                    realTimeStatusSection
                    vadAnalysisSection
                    transcriptionWindowsSection
                    overlapAnalysisSection
                    skippedResultsSection
                    finalStabilizedWordsSection
                } else {
                    instructionsSection
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .init("VADDecision"))) { notification in
            if let vadInfo = notification.object as? [String: Any] {
                addVADDecision(from: vadInfo)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("TranscriptionWindow"))) { notification in
            if let windowInfo = notification.object as? [String: Any] {
                addTranscriptionWindow(from: windowInfo)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OverlapAnalysis"))) { notification in
            if let overlapInfo = notification.object as? [String: Any] {
                addOverlapAnalysis(from: overlapInfo)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("SkippedResult"))) { notification in
            if let skippedInfo = notification.object as? [String: Any] {
                addSkippedResult(from: skippedInfo)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Phase 2: Detailed Verification View")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Real-time monitoring of VAD decisions, transcription windows, overlap analysis")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var controlsSection: some View {
        HStack(spacing: 16) {
            Button(viewModel.isRecording ? "Stop Enhanced Streaming" : "Start Enhanced Streaming") {
                viewModel.toggleRecording()
                if !viewModel.isRecording {
                    clearAllData()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("Clear Data") {
                clearAllData()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRecording)
        }
    }
    
    private var realTimeStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Real-time Status")
                .font(.headline)
            
            HStack(spacing: 20) {
                statusItem("Windows", value: "\(transcriptionWindows.count)")
                statusItem("VAD Decisions", value: "\(vadDecisions.count)")
                statusItem("Overlaps", value: "\(overlapAnalyses.count)")
                statusItem("Skipped", value: "\(recentSkippedResults.count)")
            }
            
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var vadAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VAD Analysis (Last 10 Decisions)")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vadDecisions.suffix(10)) { decision in
                        vadDecisionView(decision)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var transcriptionWindowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Windows (Last 5)")
                .font(.headline)
            
            ForEach(transcriptionWindows.suffix(5)) { window in
                transcriptionWindowView(window)
            }
            
            if transcriptionWindows.isEmpty {
                Text("No transcription windows yet - speak to trigger")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var overlapAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlap Analysis (Last 3)")
                .font(.headline)
            
            ForEach(overlapAnalyses.suffix(3)) { analysis in
                overlapAnalysisView(analysis)
            }
            
            if overlapAnalyses.isEmpty {
                Text("No overlap analysis yet - need at least 2 windows")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var skippedResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skipped Results (Quality Filter)")
                .font(.headline)
            
            ForEach(recentSkippedResults.suffix(3)) { skipped in
                skippedResultView(skipped)
            }
            
            if recentSkippedResults.isEmpty {
                Text("No results skipped yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var finalStabilizedWordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final Stabilized Text")
                .font(.headline)
            
            if !viewModel.captionText.isEmpty && viewModel.captionText != "..." {
                Text(viewModel.captionText)
                    .padding()
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                    .font(.body)
            } else {
                Text("No stabilized text yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            
            // Show word-level details
            let words = viewModel.stabilizationManager.getStabilizedWords()
            if !words.isEmpty {
                Text("Word Details (\(words.count) words)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(words.suffix(10), id: \.text) { word in
                            wordDetailView(word)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verification Instructions:")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Click 'Start Enhanced Streaming'")
                Text("2. Watch VAD decisions in real-time (green = speech, red = silence)")
                Text("3. Speak clearly and observe transcription windows appear")
                Text("4. Check overlap analysis for matches/conflicts between windows")
                Text("5. Monitor skipped results to see quality filtering in action")
                Text("6. Observe final stabilized text evolution")
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Helper Views
    
    private func statusItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func vadDecisionView(_ decision: VADDecision) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(decision.finalDecision ? Color.green : Color.red)
                .frame(width: 20, height: 20)
            
            Text(String(format: "%.2f", decision.confidence))
                .font(.caption2)
                .fontWeight(.medium)
            
            Text(decision.finalDecision ? "Speech" : "Silence")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(decision.reason)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(.textBackgroundColor))
        .cornerRadius(6)
        .frame(width: 80)
    }
    
    private func transcriptionWindowView(_ window: TranscriptionWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Window #\(window.windowNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if window.isSkipped {
                    Text("SKIPPED")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Text("Confidence: \(String(format: "%.2f", window.confidence))")
                        .font(.caption)
                        .foregroundColor(window.confidence > 0.6 ? .green : .orange)
                }
            }
            
            if window.isSkipped {
                Text("Skipped: \(window.skipReason ?? "Unknown")")
                    .font(.caption)
                    .foregroundColor(.red)
                Text("Text: '\(window.text)'")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Text: '\(window.text)'")
                    .font(.body)
                
                Text("Words: \(window.words.joined(separator: " • "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(window.isSkipped ? Color.red.opacity(0.05) : Color(.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(window.isSkipped ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private func overlapAnalysisView(_ analysis: DetailedOverlapAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(analysis.windowPair)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous Words:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(analysis.previousWords.joined(separator: " • "))
                        .font(.caption)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Words:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(analysis.currentWords.joined(separator: " • "))
                        .font(.caption)
                }
            }
            
            HStack(spacing: 20) {
                if !analysis.exactMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("✅ Matches (\(analysis.exactMatches.count))")
                            .font(.caption)
                            .foregroundColor(.green)
                        ForEach(analysis.exactMatches.indices, id: \.self) { index in
                            Text("'\(analysis.exactMatches[index].0)' = '\(analysis.exactMatches[index].1)'")
                                .font(.caption2)
                        }
                    }
                }
                
                if !analysis.conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("⚠️ Conflicts (\(analysis.conflicts.count))")
                            .font(.caption)
                            .foregroundColor(.orange)
                        ForEach(analysis.conflicts.indices, id: \.self) { index in
                            Text("'\(analysis.conflicts[index].0)' ≠ '\(analysis.conflicts[index].1)'")
                                .font(.caption2)
                        }
                    }
                }
                
                if !analysis.newWords.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🆕 New (\(analysis.newWords.count))")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(analysis.newWords.joined(separator: " • "))
                            .font(.caption2)
                    }
                }
            }
            
            Text("Overlap Confidence: \(String(format: "%.2f", analysis.overlapConfidence))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.textBackgroundColor))
        .cornerRadius(8)
    }
    
    private func skippedResultView(_ skipped: SkippedResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SKIPPED")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
                
                Spacer()
                
                Text("Confidence: \(String(format: "%.2f", skipped.confidence))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Reason: \(skipped.reason)")
                .font(.caption)
                .foregroundColor(.red)
            
            Text("Text: '\(skipped.text)'")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func wordDetailView(_ word: StabilizedWord) -> some View {
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
    
    // MARK: - Data Management
    
    private func clearAllData() {
        transcriptionWindows.removeAll()
        vadDecisions.removeAll()
        overlapAnalyses.removeAll()
        recentSkippedResults.removeAll()
    }
    
    private func addVADDecision(from info: [String: Any]) {
        let decision = VADDecision(
            timestamp: info["timestamp"] as? Date ?? Date(),
            energyLevel: info["energyLevel"] as? Float ?? 0.0,
            finalDecision: info["finalDecision"] as? Bool ?? false,
            confidence: info["confidence"] as? Float ?? 0.0,
            reason: info["reason"] as? String ?? ""
        )
        
        vadDecisions.append(decision)
        if vadDecisions.count > 50 {
            vadDecisions.removeFirst()
        }
    }
    
    private func addTranscriptionWindow(from info: [String: Any]) {
        let window = TranscriptionWindow(
            windowNumber: transcriptionWindows.count + 1,
            timestamp: info["timestamp"] as? Date ?? Date(),
            text: info["text"] as? String ?? "",
            confidence: info["confidence"] as? Float ?? 0.0,
            isSkipped: info["isSkipped"] as? Bool ?? false,
            skipReason: info["skipReason"] as? String,
            words: info["words"] as? [String] ?? []
        )
        
        transcriptionWindows.append(window)
        if transcriptionWindows.count > 20 {
            transcriptionWindows.removeFirst()
        }
    }
    
    private func addOverlapAnalysis(from info: [String: Any]) {
        let analysis = DetailedOverlapAnalysis(
            windowPair: info["windowPair"] as? String ?? "",
            previousWords: info["previousWords"] as? [String] ?? [],
            currentWords: info["currentWords"] as? [String] ?? [],
            exactMatches: info["exactMatches"] as? [(String, String)] ?? [],
            conflicts: info["conflicts"] as? [(String, String)] ?? [],
            newWords: info["newWords"] as? [String] ?? [],
            overlapConfidence: info["overlapConfidence"] as? Float ?? 0.0
        )
        
        overlapAnalyses.append(analysis)
        if overlapAnalyses.count > 10 {
            overlapAnalyses.removeFirst()
        }
    }
    
    private func addSkippedResult(from info: [String: Any]) {
        let skipped = SkippedResult(
            timestamp: info["timestamp"] as? Date ?? Date(),
            text: info["text"] as? String ?? "",
            confidence: info["confidence"] as? Float ?? 0.0,
            reason: info["reason"] as? String ?? ""
        )
        
        recentSkippedResults.append(skipped)
        if recentSkippedResults.count > 10 {
            recentSkippedResults.removeFirst()
        }
    }
}

#Preview {
    DetailedPhase2TestView()
        .frame(width: 1000, height: 800)
}