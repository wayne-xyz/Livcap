//
//  LocalAgreementPolicy.swift
//  Livcap
//
//  Created by Implementation Plan on 6/21/25.
//

import Foundation

/// Implements LocalAgreement-2 policy for stabilizing overlapping transcription results
/// Based on the Whisper-Streaming paper's stabilization approach
class LocalAgreementPolicy {
    
    // MARK: - Configuration
    private let agreementThreshold: Int = 2  // Number of windows that must agree
    private let maxHistorySize: Int = 5      // Maximum number of history windows to keep
    private let minStableLength: Int = 3     // Minimum length for stable prefix
    private let confidenceThreshold: Float = 0.8
    
    // MARK: - State
    private var transcriptionHistory: [TranscriptionWindow] = []
    private var stablePrefix: String = ""
    private var lastStableUpdate: Date = Date()
    
    // MARK: - Data Structures
    struct TranscriptionWindow {
        let id: UUID
        let transcription: String
        let confidence: Float
        let timestamp: Date
        let windowStartTime: Double
        let windowEndTime: Double
        
        init(transcription: String, confidence: Float = 1.0, windowStartTime: Double = 0.0, windowEndTime: Double = 0.0) {
            self.id = UUID()
            self.transcription = transcription
            self.confidence = confidence
            self.timestamp = Date()
            self.windowStartTime = windowStartTime
            self.windowEndTime = windowEndTime
        }
    }
    
    struct StabilizationResult {
        let stablePrefix: String
        let newWords: [String]
        let confidence: Float
        let isStable: Bool
        let agreementCount: Int
        let totalWindows: Int
        
        var hasNewContent: Bool {
            return !newWords.isEmpty
        }
        
        var stabilityPercentage: Float {
            return totalWindows > 0 ? Float(agreementCount) / Float(totalWindows) : 0.0
        }
    }
    
    // MARK: - Public Interface
    
    /// Processes a new transcription window and returns stabilization result
    func processWindow(
        transcription: String,
        confidence: Float = 1.0,
        windowStartTime: Double = 0.0,
        windowEndTime: Double = 0.0
    ) -> StabilizationResult {
        
        let window = TranscriptionWindow(
            transcription: transcription,
            confidence: confidence,
            windowStartTime: windowStartTime,
            windowEndTime: windowEndTime
        )
        
        // Add to history
        transcriptionHistory.append(window)
        
        // Maintain history size
        if transcriptionHistory.count > maxHistorySize {
            transcriptionHistory.removeFirst()
        }
        
        // Apply LocalAgreement-2 policy
        return applyLocalAgreementPolicy()
    }
    
    /// Gets the current stable transcription
    var currentStableTranscription: String {
        return stablePrefix
    }
    
    /// Gets the current history
    var history: [TranscriptionWindow] {
        return transcriptionHistory
    }
    
    /// Resets the policy state
    func reset() {
        transcriptionHistory.removeAll()
        stablePrefix = ""
        lastStableUpdate = Date()
    }
    
    /// Checks if the current state is stable
    var isStable: Bool {
        return transcriptionHistory.count >= agreementThreshold
    }
    
    // MARK: - Private Methods
    
    private func applyLocalAgreementPolicy() -> StabilizationResult {
        guard transcriptionHistory.count >= 2 else {
            // Not enough history for agreement
            return StabilizationResult(
                stablePrefix: transcriptionHistory.last?.transcription ?? "",
                newWords: transcriptionHistory.last?.transcription.components(separatedBy: " ").filter { !$0.isEmpty } ?? [],
                confidence: transcriptionHistory.last?.confidence ?? 0.0,
                isStable: false,
                agreementCount: 1,
                totalWindows: transcriptionHistory.count
            )
        }
        
        // Find the longest common prefix among recent windows
        let recentWindows = Array(transcriptionHistory.suffix(agreementThreshold))
        let commonPrefix = findLongestCommonPrefix(among: recentWindows)
        
        // Check if we have enough agreement
        let agreementCount = countAgreement(for: commonPrefix, in: recentWindows)
        let hasAgreement = agreementCount >= agreementThreshold
        
        // Determine new words
        let newWords = extractNewWords(commonPrefix: commonPrefix)
        
        // Update stable prefix if we have agreement
        if hasAgreement && commonPrefix.count >= minStableLength {
            stablePrefix = commonPrefix
            lastStableUpdate = Date()
        }
        
        return StabilizationResult(
            stablePrefix: stablePrefix,
            newWords: newWords,
            confidence: calculateOverallConfidence(windows: recentWindows),
            isStable: hasAgreement,
            agreementCount: agreementCount,
            totalWindows: recentWindows.count
        )
    }
    
    private func findLongestCommonPrefix(among windows: [TranscriptionWindow]) -> String {
        guard !windows.isEmpty else { return "" }
        
        let transcriptions = windows.map { $0.transcription }
        let words = transcriptions.map { $0.components(separatedBy: " ").filter { !$0.isEmpty } }
        
        guard !words.isEmpty else { return "" }
        
        let minLength = words.map { $0.count }.min() ?? 0
        var commonPrefix: [String] = []
        
        for i in 0..<minLength {
            let currentWord = words[0][i]
            let allMatch = words.allSatisfy { $0[i] == currentWord }
            
            if allMatch {
                commonPrefix.append(currentWord)
            } else {
                break
            }
        }
        
        return commonPrefix.joined(separator: " ")
    }
    
    private func countAgreement(for prefix: String, in windows: [TranscriptionWindow]) -> Int {
        return windows.filter { window in
            window.transcription.hasPrefix(prefix) || 
            window.transcription == prefix ||
            calculateSimilarity(window.transcription, prefix) >= confidenceThreshold
        }.count
    }
    
    private func extractNewWords(commonPrefix: String) -> [String] {
        guard !commonPrefix.isEmpty else { return [] }
        
        let currentWords = commonPrefix.components(separatedBy: " ").filter { !$0.isEmpty }
        let stableWords = stablePrefix.components(separatedBy: " ").filter { !$0.isEmpty }
        
        // Find words that are new compared to stable prefix
        if currentWords.count > stableWords.count {
            return Array(currentWords.suffix(from: stableWords.count))
        }
        
        return []
    }
    
    private func calculateSimilarity(_ text1: String, _ text2: String) -> Float {
        let words1 = text1.components(separatedBy: " ").filter { !$0.isEmpty }
        let words2 = text2.components(separatedBy: " ").filter { !$0.isEmpty }
        
        let minLength = min(words1.count, words2.count)
        guard minLength > 0 else { return 0.0 }
        
        var matches = 0
        for i in 0..<minLength {
            if words1[i] == words2[i] {
                matches += 1
            }
        }
        
        return Float(matches) / Float(minLength)
    }
    
    private func calculateOverallConfidence(windows: [TranscriptionWindow]) -> Float {
        guard !windows.isEmpty else { return 0.0 }
        
        let totalConfidence = windows.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(windows.count)
    }
}

// MARK: - Extensions

extension LocalAgreementPolicy.TranscriptionWindow: CustomStringConvertible {
    var description: String {
        return "Window(id: \(id.uuidString.prefix(8)), text: '\(transcription)', conf: \(String(format: "%.2f", confidence)))"
    }
}

extension LocalAgreementPolicy.StabilizationResult: CustomStringConvertible {
    var description: String {
        return "StabilizationResult(stable: '\(stablePrefix)', new: \(newWords.count), isStable: \(isStable), agreement: \(agreementCount)/\(totalWindows))"
    }
}

// MARK: - Advanced Features

extension LocalAgreementPolicy {
    
    /// Performs advanced stabilization with confidence weighting
    func processWindowWithConfidence(
        transcription: String,
        confidence: Float,
        windowStartTime: Double,
        windowEndTime: Double
    ) -> StabilizationResult {
        
        // Apply confidence-based filtering
        let filteredTranscription = confidence >= confidenceThreshold ? transcription : stablePrefix
        
        return processWindow(
            transcription: filteredTranscription,
            confidence: confidence,
            windowStartTime: windowStartTime,
            windowEndTime: windowEndTime
        )
    }
    
    /// Gets stability statistics
    func getStabilityStats() -> (averageConfidence: Float, agreementRate: Float, stabilityDuration: TimeInterval) {
        let avgConfidence = transcriptionHistory.isEmpty ? 0.0 : 
            transcriptionHistory.reduce(0.0) { $0 + $1.confidence } / Float(transcriptionHistory.count)
        
        let agreementRate = transcriptionHistory.count >= 2 ? 
            Float(transcriptionHistory.count - 1) / Float(transcriptionHistory.count) : 0.0
        
        let stabilityDuration = Date().timeIntervalSince(lastStableUpdate)
        
        return (avgConfidence, agreementRate, stabilityDuration)
    }
    
    /// Checks if the current state needs stabilization
    var needsStabilization: Bool {
        return transcriptionHistory.count >= agreementThreshold && 
               Date().timeIntervalSince(lastStableUpdate) > 2.0 // 2 seconds without stable update
    }
} 