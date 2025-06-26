//
//  TranscriptionDisplayManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/20/25.
//

import Foundation
import Combine

/// Manages the display and processing of transcription results
/// Handles caption history, overlapping inference, and display formatting
final class TranscriptionDisplayManager: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var currentCaption: String = "..."
    @Published private(set) var captionHistory: [CaptionEntry] = []
    @Published private(set) var displayStatus: DisplayStatus = .ready
    
    // MARK: - Configuration
    
    private let maxHistoryEntries: Int = 100 // Increased for longer sessions
    private let minConfidenceThreshold: Float = 0.1 // For future confidence filtering
    
    // MARK: - Internal State
    
    private var pendingTranscriptions: [SimpleTranscriptionResult] = []
    private var lastProcessedTime: Date = Date()
    private var isProcessingOverlap: Bool = false
    
    // MARK: - Overlapping Inference Support (Future)
    
    private var overlappingSegments: [UUID: TranscriptionSegment] = [:]
    private var segmentConfidence: [UUID: Float] = [:]
    
    // MARK: - Initialization
    
    init() {
        reset()
    }
    
    // MARK: - Public Interface
    
    /// Processes a new transcription result
    func processTranscription(_ result: SimpleTranscriptionResult) {
        // Filter out empty or low-quality transcriptions
        guard isValidTranscription(result) else { return }
        
        // Add to pending queue for potential overlapping processing
        pendingTranscriptions.append(result)
        
        // Process immediately for now (can be enhanced with overlapping logic)
        processPendingTranscriptions()
    }
    
    /// Clears all caption history and resets the display
    func clearAll() {
        reset()
    }
    
    /// Updates the display status
    func updateStatus(_ status: DisplayStatus) {
        displayStatus = status
    }
    
    /// Gets the current caption text for display
    var displayCaption: String {
        return currentCaption.isEmpty ? "..." : currentCaption
    }
    
    /// Gets the number of entries in history
    var historyCount: Int {
        return captionHistory.count
    }
    
    /// Gets high confidence captions only
    func getHighConfidenceCaptions(minConfidence: Float = 0.7) -> [CaptionEntry] {
        return captionHistory.filter { entry in
            guard let confidence = entry.confidence else { return true }
            return confidence >= minConfidence
        }
    }
    
    /// Gets the average confidence of recent captions
    func getRecentConfidenceScore(lastN: Int = 5) -> Float {
        let recentEntries = Array(captionHistory.suffix(lastN))
        let confidences = recentEntries.compactMap(\.confidence)
        
        guard !confidences.isEmpty else { return 1.0 }
        return confidences.reduce(0, +) / Float(confidences.count)
    }
    
    // MARK: - Private Methods
    
    private func reset() {
        currentCaption = "..."
        captionHistory.removeAll()
        displayStatus = .ready
        pendingTranscriptions.removeAll()
        overlappingSegments.removeAll()
        segmentConfidence.removeAll()
        lastProcessedTime = Date()
        isProcessingOverlap = false
    }
    
    private func isValidTranscription(_ result: SimpleTranscriptionResult) -> Bool {
        let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidText = !trimmedText.isEmpty && trimmedText.count > 1
        let hasMinimumConfidence = result.overallConfidence >= minConfidenceThreshold
        
        return hasValidText && hasMinimumConfidence
    }
    
    private func processPendingTranscriptions() {
        guard !pendingTranscriptions.isEmpty else { return }
        
        // For now, process each transcription individually
        // This can be enhanced with overlapping logic later
        for result in pendingTranscriptions {
            processIndividualTranscription(result)
        }
        
        pendingTranscriptions.removeAll()
    }
    
    private func processIndividualTranscription(_ result: SimpleTranscriptionResult) {
        let entry = CaptionEntry(
            id: result.segmentID,
            text: result.text,
            confidence: result.overallConfidence
        )
        
        // Update current caption with confidence indicator
        if result.overallConfidence < 0.5 {
            currentCaption = "\(result.text) (?)"  // Low confidence indicator
        } else {
            currentCaption = result.text
        }
        
        // Add to history
        captionHistory.append(entry)
        
        // Maintain history size limit
        if captionHistory.count > maxHistoryEntries {
            captionHistory.removeFirst()
        }
        
        // Update status
        displayStatus = .liveCaptioning
        
        print("TranscriptionDisplayManager: Added caption: \(result.text) (confidence: \(String(format: "%.3f", result.overallConfidence)))")
    }
    
    // MARK: - Future Overlapping Inference Methods
    
    /// Future: Process overlapping segments for better accuracy
    private func processOverlappingSegments() {
        // TODO: Implement overlapping segment processing
        // This will combine multiple overlapping transcriptions
        // and select the best result based on confidence
    }
    
    /// Future: Calculate confidence score for transcription
    private func calculateConfidence(for result: SimpleTranscriptionResult) -> Float {
        // TODO: Implement confidence calculation
        // This could be based on Whisper's internal confidence scores
        return 1.0 // Placeholder
    }
    
    /// Future: Merge overlapping transcriptions
    private func mergeOverlappingTranscriptions(_ segments: [SimpleTranscriptionResult]) -> String {
        // TODO: Implement intelligent merging of overlapping segments
        // This could use techniques like:
        // - Word-level alignment
        // - Confidence-weighted selection
        // - Temporal overlap analysis
        return segments.last?.text ?? ""
    }
}

// MARK: - Supporting Types

/// Represents a transcription segment with timing information
struct TranscriptionSegment {
    let id: UUID
    let text: String
    let startTime: Date
    let endTime: Date
    let confidence: Float
}

/// Display status for the transcription manager
enum DisplayStatus {
    case ready
    case liveCaptioning
    case processing
    case error(String)
    
    var description: String {
        switch self {
        case .ready:
            return "Ready to record"
        case .liveCaptioning:
            return "Live captioning..."
        case .processing:
            return "Processing transcription..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

