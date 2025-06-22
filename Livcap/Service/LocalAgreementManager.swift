//
//  LocalAgreementManager.swift
//  Livcap
//
//  WhisperLive-inspired text stabilization using LocalAgreement algorithm
//  - Simple prefix matching instead of complex word-level alignment
//  - Confidence-based text selection and stabilization
//  - Sentence-level coherence tracking
//

import Foundation
import SwiftUI

struct TranscriptionCandidate {
    let text: String
    let timestamp: Date
    let confidence: Float
    let bufferDuration: TimeInterval
    let id: UUID
    
    var words: [String] {
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
    
    var wordCount: Int {
        return words.count
    }
}

struct PrefixMatch {
    let matchLength: Int        // Number of matching words
    let confidence: Float       // Confidence of the match
    let stabilityScore: Float   // How stable this prefix is across candidates
    let matchedText: String     // The actual matching text
}

struct LocalAgreementResult {
    let stabilizedText: String
    let confidence: Float
    let matchQuality: Float
    let candidateCount: Int
    let longestPrefix: String
    let newWords: [String]      // Words added since last stabilization
    let stabilizationMethod: String // "prefix_match", "confidence_boost", "single_candidate"
}

class LocalAgreementManager: ObservableObject {
    
    // MARK: - Configuration
    
    private struct AgreementConfig {
        static let maxCandidates: Int = 5              // Keep last 5 transcription candidates
        static let minPrefixLength: Int = 2            // Minimum 2 words for prefix matching
        static let prefixConfidenceThreshold: Float = 0.6  // Minimum confidence for prefix
        static let stabilityThreshold: Float = 0.7    // How often prefix must appear to be stable
        static let confidenceBoostThreshold: Float = 0.8  // High confidence can override agreement
        static let maxCandidateAge: TimeInterval = 10.0   // Remove candidates older than 10s
        static let sentenceEndPatterns = [".", "!", "?", "。", "！", "？"]
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var currentStabilizedText: String = ""
    @Published private(set) var lastAgreementResult: LocalAgreementResult?
    @Published private(set) var processingTimeMs: Double = 0
    @Published private(set) var totalAgreements: Int = 0
    @Published private(set) var averageConfidence: Float = 0
    
    // MARK: - Private Properties
    
    private var candidates: [TranscriptionCandidate] = []
    private var agreementHistory: [LocalAgreementResult] = []
    private var lastStabilizedWords: [String] = []
    private var processingTimes: [Double] = []
    
    // MARK: - Initialization
    
    init() {
        print("LocalAgreementManager: Initialized with WhisperLive prefix matching strategy")
    }
    
    // MARK: - Public Interface
    
    /// Process new transcription candidate and return stabilized text
    func processTranscription(_ transcription: SimpleTranscriptionResult, 
                            bufferDuration: TimeInterval) -> LocalAgreementResult {
        let startTime = Date()
        
        // Create candidate from transcription
        let candidate = TranscriptionCandidate(
            text: transcription.text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(),
            confidence: transcription.overallConfidence,
            bufferDuration: bufferDuration,
            id: UUID()
        )
        
        // Add to candidates list
        addCandidate(candidate)
        
        // Perform local agreement analysis
        let result = performLocalAgreement()
        
        // Update state
        currentStabilizedText = result.stabilizedText
        lastAgreementResult = result
        totalAgreements += 1
        
        // Update processing metrics
        processingTimeMs = Date().timeIntervalSince(startTime) * 1000
        processingTimes.append(processingTimeMs)
        if processingTimes.count > 20 {
            processingTimes.removeFirst()
        }
        
        updateAverageConfidence()
        
        // Store in history
        agreementHistory.append(result)
        if agreementHistory.count > 10 {
            agreementHistory.removeFirst()
        }
        
        // Logging
        print("🔄 LocalAgreement: \"\(result.stabilizedText)\" (\\(result.stabilizationMethod), confidence: \\(String(format: \"%.2f\", result.confidence)))")
        if !result.newWords.isEmpty {
            print("   ➕ New words: \\(result.newWords.joined(separator: \" \"))")
        }
        
        return result
    }
    
    /// Get current stabilized text for display
    func getStabilizedText() -> String {
        return currentStabilizedText
    }
    
    /// Check if current text represents a complete sentence
    func hasCompleteSentence() -> Bool {
        for pattern in AgreementConfig.sentenceEndPatterns {
            if currentStabilizedText.hasSuffix(pattern) {
                return true
            }
        }
        return false
    }
    
    /// Reset the agreement manager
    func reset() {
        candidates.removeAll()
        agreementHistory.removeAll()
        lastStabilizedWords.removeAll()
        currentStabilizedText = ""
        lastAgreementResult = nil
        processingTimeMs = 0
        totalAgreements = 0
        averageConfidence = 0
        processingTimes.removeAll()
        
        print("LocalAgreementManager: Reset complete")
    }
    
    // MARK: - Private Methods
    
    private func addCandidate(_ candidate: TranscriptionCandidate) {
        // Add new candidate
        candidates.append(candidate)
        
        // Remove old candidates
        let cutoffTime = Date().addingTimeInterval(-AgreementConfig.maxCandidateAge)
        candidates = candidates.filter { $0.timestamp >= cutoffTime }
        
        // Limit number of candidates
        if candidates.count > AgreementConfig.maxCandidates {
            candidates.removeFirst(candidates.count - AgreementConfig.maxCandidates)
        }
        
        print("📝 Added candidate: \"\(candidate.text)\" (confidence: \\(String(format: \"%.2f\", candidate.confidence)), total: \\(candidates.count))")
    }
    
    private func performLocalAgreement() -> LocalAgreementResult {
        guard !candidates.isEmpty else {
            return createEmptyResult()
        }
        
        // Single candidate - use directly if confidence is reasonable
        if candidates.count == 1 {
            let candidate = candidates[0]
            let newWords = getNewWords(candidate.words)
            lastStabilizedWords = candidate.words
            
            return LocalAgreementResult(
                stabilizedText: candidate.text,
                confidence: candidate.confidence,
                matchQuality: candidate.confidence,
                candidateCount: 1,
                longestPrefix: candidate.text,
                newWords: newWords,
                stabilizationMethod: "single_candidate"
            )
        }
        
        // Multiple candidates - perform prefix matching
        return performPrefixMatching()
    }
    
    private func performPrefixMatching() -> LocalAgreementResult {
        // Find the longest common prefix across candidates
        let longestPrefix = findLongestCommonPrefix()
        
        // Check if any candidate has very high confidence (can override agreement)
        if let highConfidenceCandidate = candidates.first(where: { $0.confidence >= AgreementConfig.confidenceBoostThreshold }) {
            let newWords = getNewWords(highConfidenceCandidate.words)
            lastStabilizedWords = highConfidenceCandidate.words
            
            return LocalAgreementResult(
                stabilizedText: highConfidenceCandidate.text,
                confidence: highConfidenceCandidate.confidence,
                matchQuality: highConfidenceCandidate.confidence,
                candidateCount: candidates.count,
                longestPrefix: longestPrefix.matchedText,
                newWords: newWords,
                stabilizationMethod: "confidence_boost"
            )
        }
        
        // Use prefix matching if we have a good match
        if longestPrefix.matchLength >= AgreementConfig.minPrefixLength &&
           longestPrefix.stabilityScore >= AgreementConfig.stabilityThreshold {
            
            // Find the best candidate that matches this prefix
            let bestCandidate = findBestCandidateForPrefix(longestPrefix)
            let newWords = getNewWords(bestCandidate.words)
            lastStabilizedWords = bestCandidate.words
            
            return LocalAgreementResult(
                stabilizedText: bestCandidate.text,
                confidence: bestCandidate.confidence,
                matchQuality: longestPrefix.stabilityScore,
                candidateCount: candidates.count,
                longestPrefix: longestPrefix.matchedText,
                newWords: newWords,
                stabilizationMethod: "prefix_match"
            )
        }
        
        // Fallback: use highest confidence candidate
        let bestCandidate = candidates.max { $0.confidence < $1.confidence } ?? candidates.last!
        let newWords = getNewWords(bestCandidate.words)
        lastStabilizedWords = bestCandidate.words
        
        return LocalAgreementResult(
            stabilizedText: bestCandidate.text,
            confidence: bestCandidate.confidence,
            matchQuality: bestCandidate.confidence * 0.7, // Reduced since no agreement
            candidateCount: candidates.count,
            longestPrefix: longestPrefix.matchedText,
            newWords: newWords,
            stabilizationMethod: "fallback_best_confidence"
        )
    }
    
    private func findLongestCommonPrefix() -> PrefixMatch {
        guard candidates.count >= 2 else {
            if let candidate = candidates.first {
                return PrefixMatch(
                    matchLength: candidate.wordCount,
                    confidence: candidate.confidence,
                    stabilityScore: 1.0,
                    matchedText: candidate.text
                )
            }
            return PrefixMatch(matchLength: 0, confidence: 0, stabilityScore: 0, matchedText: "")
        }
        
        // Get all word arrays
        let wordArrays = candidates.map { $0.words }
        
        // Find longest common prefix across all candidates
        var prefixLength = 0
        let minLength = wordArrays.map { $0.count }.min() ?? 0
        
        for i in 0..<minLength {
            let word = wordArrays[0][i].lowercased()
            let allMatch = wordArrays.allSatisfy { $0[i].lowercased() == word }
            
            if allMatch {
                prefixLength = i + 1
            } else {
                break
            }
        }
        
        // Calculate stability score (how often this prefix appears)
        let stabilityScore: Float
        if prefixLength > 0 {
            let prefixWords = Array(wordArrays[0][0..<prefixLength])
            let matchingCandidates = wordArrays.filter { words in
                guard words.count >= prefixLength else { return false }
                let candidatePrefix = Array(words[0..<prefixLength])
                return candidatePrefix.map { $0.lowercased() } == prefixWords.map { $0.lowercased() }
            }
            stabilityScore = Float(matchingCandidates.count) / Float(wordArrays.count)
        } else {
            stabilityScore = 0.0
        }
        
        // Calculate average confidence for matching prefix
        let avgConfidence = candidates.map { $0.confidence }.reduce(0, +) / Float(candidates.count)
        
        // Create matched text
        let matchedText = prefixLength > 0 ? 
            Array(wordArrays[0][0..<prefixLength]).joined(separator: " ") : ""
        
        return PrefixMatch(
            matchLength: prefixLength,
            confidence: avgConfidence,
            stabilityScore: stabilityScore,
            matchedText: matchedText
        )
    }
    
    private func findBestCandidateForPrefix(_ prefix: PrefixMatch) -> TranscriptionCandidate {
        // Find candidates that match the prefix
        let matchingCandidates = candidates.filter { candidate in
            guard candidate.wordCount >= prefix.matchLength else { return false }
            let candidatePrefix = Array(candidate.words[0..<prefix.matchLength])
            let targetPrefix = prefix.matchedText.components(separatedBy: " ")
            return candidatePrefix.map { $0.lowercased() } == targetPrefix.map { $0.lowercased() }
        }
        
        // Return the one with highest confidence, or fallback to last candidate
        return matchingCandidates.max { $0.confidence < $1.confidence } ?? candidates.last!
    }
    
    private func getNewWords(_ currentWords: [String]) -> [String] {
        // Find words that weren't in the last stabilized text
        let newWords = Array(currentWords.dropFirst(lastStabilizedWords.count))
        return newWords
    }
    
    private func updateAverageConfidence() {
        guard !agreementHistory.isEmpty else { return }
        
        let totalConfidence = agreementHistory.map { $0.confidence }.reduce(0, +)
        averageConfidence = totalConfidence / Float(agreementHistory.count)
    }
    
    private func createEmptyResult() -> LocalAgreementResult {
        return LocalAgreementResult(
            stabilizedText: "",
            confidence: 0,
            matchQuality: 0,
            candidateCount: 0,
            longestPrefix: "",
            newWords: [],
            stabilizationMethod: "empty"
        )
    }
    
    // MARK: - Public Utility Methods
    
    /// Get agreement statistics for monitoring
    func getAgreementStats() -> AgreementStats {
        let recentResults = agreementHistory.suffix(10)
        let avgMatchQuality = recentResults.isEmpty ? 0 : 
            recentResults.map { $0.matchQuality }.reduce(0, +) / Float(recentResults.count)
        
        let avgProcessingTime = processingTimes.isEmpty ? 0 :
            processingTimes.reduce(0, +) / Double(processingTimes.count)
        
        let methodCounts = agreementHistory.reduce(into: [String: Int]()) { counts, result in
            counts[result.stabilizationMethod, default: 0] += 1
        }
        
        return AgreementStats(
            totalAgreements: totalAgreements,
            averageConfidence: averageConfidence,
            averageMatchQuality: avgMatchQuality,
            lastProcessingTimeMs: processingTimeMs,
            averageProcessingTimeMs: avgProcessingTime,
            activeCandidates: candidates.count,
            methodDistribution: methodCounts,
            hasCompleteSentence: hasCompleteSentence()
        )
    }
    
    /// Get detailed debug information
    func getDebugInfo() -> String {
        var info = "📊 LocalAgreement Debug:\n"
        info += "- Active candidates: \(candidates.count)\n"
        info += "- Current text: \"\(currentStabilizedText)\"\n"
        info += "- Last method: \(lastAgreementResult?.stabilizationMethod ?? "none")\n"
        info += "- Average confidence: \(String(format: "%.2f", averageConfidence))\n"
        
        if let lastResult = lastAgreementResult {
            info += "- Last quality: \(String(format: "%.2f", lastResult.matchQuality))\n"
            info += "- New words: \(lastResult.newWords.joined(separator: " "))\n"
        }
        
        info += "\nCandidates:\n"
        for (i, candidate) in candidates.enumerated() {
            info += "  \(i+1). \"\(candidate.text)\" (conf: \(String(format: "%.2f", candidate.confidence)))\n"
        }
        
        return info
    }
}

// MARK: - Supporting Types

struct AgreementStats {
    let totalAgreements: Int
    let averageConfidence: Float
    let averageMatchQuality: Float
    let lastProcessingTimeMs: Double
    let averageProcessingTimeMs: Double
    let activeCandidates: Int
    let methodDistribution: [String: Int]
    let hasCompleteSentence: Bool
    
    var confidenceString: String {
        return String(format: "%.2f", averageConfidence)
    }
    
    var qualityString: String {
        return String(format: "%.2f", averageMatchQuality)
    }
    
    var processingString: String {
        return String(format: "%.1fms", averageProcessingTimeMs)
    }
}