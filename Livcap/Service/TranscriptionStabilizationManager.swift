//
//  TranscriptionStabilizationManager.swift
//  Livcap
//
//  Overlapping Buffer Confirmation System for Phase 2
//

import Foundation
import Combine
import SwiftUI

struct OverlapConfig {
    let windowSizeMs: Int = 5000        // 5-second transcription window
    let strideMs: Int = 2000            // 2-second move stride
    let overlapMs: Int = 3000           // 3-second overlap (windowSize - stride)
    let sampleRate: Int = 16000         // 16kHz sampling rate
    let confidenceThreshold: Float = 0.6 // Minimum confidence for word confirmation
    let stabilizationRounds: Int = 3     // How many overlaps needed for full stabilization
    
    var overlapSamples: Int {
        return (sampleRate * overlapMs) / 1000
    }
}

struct TimestampedTranscription {
    let id: UUID
    let text: String
    let words: [WhisperWordData]
    let startTimeMs: Int
    let endTimeMs: Int
    let bufferStartTimeMs: Int      // When this buffer started
    let overallConfidence: Float
    let timestamp: Date
    
    var durationMs: Int {
        return endTimeMs - startTimeMs
    }
}

struct WhisperWordData {
    let text: String
    let confidence: Float
    let startTimeMs: Int
    let endTimeMs: Int
    let bufferOffset: Int           // Position within the transcription buffer
}

struct StabilizedWord {
    let text: String
    let confidence: Float
    let stabilizationCount: Int     // How many overlaps confirmed this word
    let firstSeenTime: Date
    let lastConfirmedTime: Date
    let startTimeMs: Int
    let endTimeMs: Int
    let isStabilized: Bool          // Has been confirmed across multiple overlaps
    
    var stabilizationStrength: Float {
        return Float(stabilizationCount) / Float(OverlapConfig().stabilizationRounds)
    }
}

struct OverlapAnalysis {
    let overlapRegionMs: ClosedRange<Int>
    let previousWords: [WhisperWordData]
    let currentWords: [WhisperWordData]
    let matchedPairs: [(previous: WhisperWordData, current: WhisperWordData)]
    let conflicts: [(previous: WhisperWordData, current: WhisperWordData)]
    let newWords: [WhisperWordData]
    let confidence: Float
}

class TranscriptionStabilizationManager: ObservableObject {
    private let config = OverlapConfig()
    
    // Transcription History
    private var transcriptionHistory: [TimestampedTranscription] = []
    private var stabilizedWords: [StabilizedWord] = []
    
    // Current State
    @Published private(set) var currentStabilizedText: String = ""
    @Published private(set) var recentTranscriptions: [TimestampedTranscription] = []
    @Published private(set) var overlapAnalyses: [OverlapAnalysis] = []
    
    // Metrics
    @Published var stabilizationMetrics: StabilizationMetrics?
    
    struct StabilizationMetrics {
        let totalTranscriptions: Int
        let totalOverlaps: Int
        let averageOverlapConfidence: Float
        let stabilizedWordCount: Int
        let conflictCount: Int
        let stabilizationRate: Float
    }
    
    init() {
        print("TranscriptionStabilizationManager: Initialized with \(config.overlapMs)ms overlap window")
    }
    
    func processNewTranscription(_ result: SimpleTranscriptionResult, bufferStartTimeMs: Int) {
        let timestamp = Date()
        
        // Quality filter - skip obviously bad transcriptions
        let cleanText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.isEmpty || 
           result.overallConfidence < 0.3 || 
           cleanText.contains("[ Silence ]") ||
           cleanText.count < 3 {
            
            let skipReason = cleanText.isEmpty ? "Empty text" :
                           result.overallConfidence < 0.3 ? "Low confidence (<0.3)" :
                           cleanText.contains("[ Silence ]") ? "Silence marker detected" : "Text too short"
            
            print("🔍 Skipping low-quality transcription: '\(cleanText)' (confidence: \(result.overallConfidence))")
            
            // Post skipped result notification
            NotificationCenter.default.post(
                name: Notification.Name("SkippedResult"),
                object: [
                    "timestamp": timestamp,
                    "text": cleanText,
                    "confidence": result.overallConfidence,
                    "reason": skipReason
                ]
            )
            
            return
        }
        
        // Convert to timestamped transcription with word-level data
        let timestampedTranscription = createTimestampedTranscription(
            result: result,
            bufferStartTimeMs: bufferStartTimeMs,
            timestamp: timestamp
        )
        
        // Post successful transcription window notification
        NotificationCenter.default.post(
            name: Notification.Name("TranscriptionWindow"),
            object: [
                "timestamp": timestamp,
                "text": timestampedTranscription.text,
                "confidence": timestampedTranscription.overallConfidence,
                "isSkipped": false,
                "words": timestampedTranscription.words.map { $0.text }
            ]
        )
        
        // Add to history
        transcriptionHistory.append(timestampedTranscription)
        
        // Analyze overlap with previous transcription
        if transcriptionHistory.count > 1 {
            let previousTranscription = transcriptionHistory[transcriptionHistory.count - 2]
            let overlapAnalysis = analyzeOverlap(
                previous: previousTranscription,
                current: timestampedTranscription
            )
            
            overlapAnalyses.append(overlapAnalysis)
            
            // Post overlap analysis notification
            NotificationCenter.default.post(
                name: Notification.Name("OverlapAnalysis"),
                object: [
                    "windowPair": "Window \(transcriptionHistory.count-1) → \(transcriptionHistory.count)",
                    "previousWords": overlapAnalysis.previousWords.map { $0.text },
                    "currentWords": overlapAnalysis.currentWords.map { $0.text },
                    "exactMatches": overlapAnalysis.matchedPairs.map { ($0.previous.text, $0.current.text) },
                    "conflicts": overlapAnalysis.conflicts.map { ($0.previous.text, $0.current.text) },
                    "newWords": overlapAnalysis.newWords.map { $0.text },
                    "overlapConfidence": overlapAnalysis.confidence
                ]
            )
            
            // Apply stabilization based on overlap analysis
            applyStabilization(overlapAnalysis)
            
            print("🔍 Overlap Analysis: \(overlapAnalysis.matchedPairs.count) matches, \(overlapAnalysis.conflicts.count) conflicts")
        } else {
            // First transcription - initialize stabilized words
            initializeStabilizedWords(from: timestampedTranscription)
        }
        
        // Update current stabilized text
        updateStabilizedText()
        
        // Update metrics
        updateMetrics()
        
        // Cleanup old data
        cleanupHistory()
        
        // Update published arrays
        recentTranscriptions = Array(transcriptionHistory.suffix(5))
        
        print("📝 Stabilization: \(stabilizedWords.filter { $0.isStabilized }.count)/\(stabilizedWords.count) words stabilized")
    }
    
    private func createTimestampedTranscription(result: SimpleTranscriptionResult, bufferStartTimeMs: Int, timestamp: Date) -> TimestampedTranscription {
        // Convert result to word-level data
        // For now, we'll estimate word boundaries - in a full implementation, 
        // we'd extract this from Whisper's detailed output
        let words = estimateWordBoundaries(
            text: result.text,
            confidence: result.overallConfidence,
            bufferStartTimeMs: bufferStartTimeMs
        )
        
        let estimatedDuration = max(1000, Int(Float(result.text.count) * 100)) // Rough estimate
        
        return TimestampedTranscription(
            id: UUID(),
            text: result.text,
            words: words,
            startTimeMs: bufferStartTimeMs,
            endTimeMs: bufferStartTimeMs + estimatedDuration,
            bufferStartTimeMs: bufferStartTimeMs,
            overallConfidence: result.overallConfidence,
            timestamp: timestamp
        )
    }
    
    private func estimateWordBoundaries(text: String, confidence: Float, bufferStartTimeMs: Int) -> [WhisperWordData] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        
        let avgWordDurationMs = config.windowSizeMs / max(1, words.count)
        
        return words.enumerated().map { index, word in
            let startTime = bufferStartTimeMs + (index * avgWordDurationMs)
            let endTime = startTime + avgWordDurationMs
            
            return WhisperWordData(
                text: word,
                confidence: confidence + Float.random(in: -0.1...0.1), // Add some variance
                startTimeMs: startTime,
                endTimeMs: endTime,
                bufferOffset: index * avgWordDurationMs
            )
        }
    }
    
    private func analyzeOverlap(previous: TimestampedTranscription, current: TimestampedTranscription) -> OverlapAnalysis {
        print("🔍 Analyzing overlap: Previous '\(previous.text)' vs Current '\(current.text)'")
        
        // Skip analysis for low-confidence or silence/empty results
        if previous.overallConfidence < 0.5 || current.overallConfidence < 0.5 ||
           previous.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           previous.text.contains("Silence") || current.text.contains("Silence") {
            print("🔍 Skipping overlap analysis - low confidence or silence detected")
            return OverlapAnalysis(
                overlapRegionMs: 0...0,
                previousWords: [],
                currentWords: [],
                matchedPairs: [],
                conflicts: [],
                newWords: current.words.filter { $0.confidence > 0.6 }, // Only high confidence words
                confidence: 0.0
            )
        }
        
        // Simple word-based overlap detection
        let previousWords = Array(previous.words.suffix(3)) // Last 3 words from previous
        let currentWords = Array(current.words.prefix(3))   // First 3 words from current
        
        print("🔍 Previous words: \(previousWords.map { $0.text })")
        print("🔍 Current words: \(currentWords.map { $0.text })")
        
        // Find matches and conflicts
        let (matches, conflicts) = matchWordsInOverlap(
            previousWords: previousWords,
            currentWords: currentWords
        )
        
        // Only include new words that are high confidence and not duplicates
        let newWords = current.words.filter { word in
            word.confidence > 0.6 && !isWordDuplicate(word.text, in: previousWords)
        }
        
        let overlapConfidence = calculateOverlapConfidence(matches: matches, conflicts: conflicts)
        
        print("🔍 Found \(matches.count) matches, \(conflicts.count) conflicts, \(newWords.count) new words")
        
        return OverlapAnalysis(
            overlapRegionMs: 0...1000, // Simplified
            previousWords: previousWords,
            currentWords: currentWords,
            matchedPairs: matches,
            conflicts: conflicts,
            newWords: newWords,
            confidence: overlapConfidence
        )
    }
    
    private func isWordDuplicate(_ word: String, in words: [WhisperWordData]) -> Bool {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return words.contains { existingWord in
            let cleanExisting = existingWord.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return cleanWord == cleanExisting
        }
    }
    
    private func matchWordsInOverlap(previousWords: [WhisperWordData], currentWords: [WhisperWordData]) -> (matches: [(previous: WhisperWordData, current: WhisperWordData)], conflicts: [(previous: WhisperWordData, current: WhisperWordData)]) {
        
        var matches: [(previous: WhisperWordData, current: WhisperWordData)] = []
        var conflicts: [(previous: WhisperWordData, current: WhisperWordData)] = []
        var usedCurrentIndices: Set<Int> = []
        
        // Improved matching with multiple strategies
        for prevWord in previousWords {
            let cleanPrevWord = cleanWord(prevWord.text)
            
            // Strategy 1: Exact match (case-insensitive)
            for (index, currentWord) in currentWords.enumerated() {
                if !usedCurrentIndices.contains(index) && cleanWord(currentWord.text) == cleanPrevWord {
                    matches.append((previous: prevWord, current: currentWord))
                    usedCurrentIndices.insert(index)
                    print("🔍 Exact match: '\(prevWord.text)' = '\(currentWord.text)'")
                    break
                }
            }
            
            // Skip if already matched
            if matches.contains(where: { $0.previous.text == prevWord.text }) { continue }
            
            // Strategy 2: Partial match (for compound words or slight variations)
            for (index, currentWord) in currentWords.enumerated() {
                if !usedCurrentIndices.contains(index) {
                    let cleanCurrentWord = cleanWord(currentWord.text)
                    if (cleanPrevWord.contains(cleanCurrentWord) || cleanCurrentWord.contains(cleanPrevWord)) &&
                       min(cleanPrevWord.count, cleanCurrentWord.count) >= 3 {
                        let similarity = calculateWordSimilarity(prevWord.text, currentWord.text)
                        if similarity > 0.6 {
                            matches.append((previous: prevWord, current: currentWord))
                            usedCurrentIndices.insert(index)
                            print("🔍 Partial match: '\(prevWord.text)' ~ '\(currentWord.text)' (similarity: \(String(format: "%.2f", similarity)))")
                            break
                        }
                    }
                }
            }
            
            // Skip if already matched
            if matches.contains(where: { $0.previous.text == prevWord.text }) { continue }
            
            // Strategy 3: Sound-alike words (simple phonetic matching)
            for (index, currentWord) in currentWords.enumerated() {
                if !usedCurrentIndices.contains(index) && areSoundAlike(prevWord.text, currentWord.text) {
                    conflicts.append((previous: prevWord, current: currentWord))
                    usedCurrentIndices.insert(index)
                    print("🔍 Sound-alike conflict: '\(prevWord.text)' ≈ '\(currentWord.text)'")
                    break
                }
            }
        }
        
        return (matches, conflicts)
    }
    
    private func cleanWord(_ word: String) -> String {
        return word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
    }
    
    private func areSoundAlike(_ word1: String, _ word2: String) -> Bool {
        let clean1 = cleanWord(word1)
        let clean2 = cleanWord(word2)
        
        // Simple sound-alike detection
        if clean1.count >= 3 && clean2.count >= 3 {
            let similarity = calculateWordSimilarity(word1, word2)
            return similarity > 0.7 && abs(clean1.count - clean2.count) <= 2
        }
        
        return false
    }
    
    private func calculateWordSimilarity(_ word1: String, _ word2: String) -> Float {
        let str1 = word1.lowercased()
        let str2 = word2.lowercased()
        
        if str1 == str2 { return 1.0 }
        
        // Simple Levenshtein-based similarity
        let maxLength = max(str1.count, str2.count)
        guard maxLength > 0 else { return 0.0 }
        
        let distance = levenshteinDistance(str1, str2)
        return 1.0 - (Float(distance) / Float(maxLength))
    }
    
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let a = Array(str1)
        let b = Array(str2)
        let m = a.count
        let n = b.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    private func calculateOverlapConfidence(matches: [(previous: WhisperWordData, current: WhisperWordData)], conflicts: [(previous: WhisperWordData, current: WhisperWordData)]) -> Float {
        let totalPairs = matches.count + conflicts.count
        guard totalPairs > 0 else { return 0.0 }
        
        let matchRate = Float(matches.count) / Float(totalPairs)
        let avgMatchConfidence = matches.isEmpty ? 0.0 : matches.map { 
            ($0.previous.confidence + $0.current.confidence) / 2.0 
        }.reduce(0, +) / Float(matches.count)
        
        return matchRate * avgMatchConfidence
    }
    
    private func applyStabilization(_ overlapAnalysis: OverlapAnalysis) {
        // Apply matched pairs to strengthen stabilized words
        for match in overlapAnalysis.matchedPairs {
            strengthenStabilizedWord(
                text: match.current.text,
                newConfidence: match.current.confidence,
                timestamp: Date()
            )
        }
        
        // Handle conflicts - choose higher confidence word
        for conflict in overlapAnalysis.conflicts {
            resolveWordConflict(
                previousWord: conflict.previous,
                currentWord: conflict.current
            )
        }
        
        // Add new words to stabilized collection
        for newWord in overlapAnalysis.newWords {
            addNewStabilizedWord(from: newWord)
        }
    }
    
    private func initializeStabilizedWords(from transcription: TimestampedTranscription) {
        stabilizedWords = transcription.words.map { word in
            StabilizedWord(
                text: word.text,
                confidence: word.confidence,
                stabilizationCount: 1,
                firstSeenTime: Date(),
                lastConfirmedTime: Date(),
                startTimeMs: word.startTimeMs,
                endTimeMs: word.endTimeMs,
                isStabilized: false
            )
        }
    }
    
    private func strengthenStabilizedWord(text: String, newConfidence: Float, timestamp: Date) {
        if let index = stabilizedWords.firstIndex(where: { $0.text.lowercased() == text.lowercased() }) {
            let word = stabilizedWords[index]
            let updatedConfidence = (word.confidence + newConfidence) / 2.0 // Average
            let newCount = word.stabilizationCount + 1
            
            stabilizedWords[index] = StabilizedWord(
                text: word.text,
                confidence: updatedConfidence,
                stabilizationCount: newCount,
                firstSeenTime: word.firstSeenTime,
                lastConfirmedTime: timestamp,
                startTimeMs: word.startTimeMs,
                endTimeMs: word.endTimeMs,
                isStabilized: newCount >= config.stabilizationRounds
            )
        }
    }
    
    private func resolveWordConflict(previousWord: WhisperWordData, currentWord: WhisperWordData) {
        // Choose the word with higher confidence
        let winningWord = currentWord.confidence > previousWord.confidence ? currentWord : previousWord
        strengthenStabilizedWord(
            text: winningWord.text,
            newConfidence: winningWord.confidence,
            timestamp: Date()
        )
    }
    
    private func addNewStabilizedWord(from word: WhisperWordData) {
        let cleanNewWord = cleanWord(word.text)
        
        // Check if this word already exists in recent stabilized words
        let recentWords = stabilizedWords.suffix(10) // Check last 10 words
        
        if recentWords.contains(where: { cleanWord($0.text) == cleanNewWord }) {
            print("🔍 Skipping duplicate word: '\(word.text)'")
            return
        }
        
        // Only add words with reasonable confidence
        guard word.confidence > 0.5 && !cleanNewWord.isEmpty && cleanNewWord.count > 1 else {
            print("🔍 Skipping low confidence word: '\(word.text)' (confidence: \(word.confidence))")
            return
        }
        
        let newStabilizedWord = StabilizedWord(
            text: word.text,
            confidence: word.confidence,
            stabilizationCount: 1,
            firstSeenTime: Date(),
            lastConfirmedTime: Date(),
            startTimeMs: word.startTimeMs,
            endTimeMs: word.endTimeMs,
            isStabilized: false
        )
        
        stabilizedWords.append(newStabilizedWord)
        print("🔍 Added new stabilized word: '\(word.text)' (confidence: \(word.confidence))")
    }
    
    private func updateStabilizedText() {
        // Keep only the last 30 words to prevent infinite accumulation
        let maxWords = 30
        
        // Sort by timestamp and take the most recent words
        let sortedWords = stabilizedWords
            .sorted { $0.startTimeMs < $1.startTimeMs }
            .suffix(maxWords)
        
        // Only show stabilized words or very high confidence words
        let displayWords = sortedWords.filter { word in
            word.isStabilized || word.confidence > 0.8
        }
        
        currentStabilizedText = displayWords.map { word in
            return word.text
        }.joined(separator: " ")
        
        // Clean up very old words
        let cutoffTime = Date().addingTimeInterval(-60) // Remove words older than 60 seconds
        stabilizedWords.removeAll { $0.lastConfirmedTime < cutoffTime }
        
        print("📝 Updated stabilized text: '\(currentStabilizedText)' (\(displayWords.count)/\(stabilizedWords.count) words)")
    }
    
    private func updateMetrics() {
        let totalTranscriptions = transcriptionHistory.count
        let totalOverlaps = overlapAnalyses.count
        let avgOverlapConfidence = overlapAnalyses.isEmpty ? 0.0 : 
            overlapAnalyses.map { $0.confidence }.reduce(0, +) / Float(overlapAnalyses.count)
        let stabilizedCount = stabilizedWords.filter { $0.isStabilized }.count
        let conflictCount = overlapAnalyses.map { $0.conflicts.count }.reduce(0, +)
        let stabilizationRate = stabilizedWords.isEmpty ? 0.0 : 
            Float(stabilizedCount) / Float(stabilizedWords.count)
        
        stabilizationMetrics = StabilizationMetrics(
            totalTranscriptions: totalTranscriptions,
            totalOverlaps: totalOverlaps,
            averageOverlapConfidence: avgOverlapConfidence,
            stabilizedWordCount: stabilizedCount,
            conflictCount: conflictCount,
            stabilizationRate: stabilizationRate
        )
    }
    
    private func cleanupHistory() {
        // Keep only recent transcriptions and analyses
        let maxHistory = 10
        
        if transcriptionHistory.count > maxHistory {
            transcriptionHistory.removeFirst(transcriptionHistory.count - maxHistory)
        }
        
        if overlapAnalyses.count > maxHistory {
            overlapAnalyses.removeFirst(overlapAnalyses.count - maxHistory)
        }
        
        // Remove very old stabilized words
        let cutoffTime = Date().addingTimeInterval(-30) // 30 seconds
        stabilizedWords.removeAll { $0.lastConfirmedTime < cutoffTime }
    }
    
    // MARK: - Public Interface
    
    func getStabilizedText() -> String {
        return currentStabilizedText
    }
    
    func getStabilizedWords() -> [StabilizedWord] {
        return stabilizedWords
    }
    
    func getRecentOverlapAnalysis() -> OverlapAnalysis? {
        return overlapAnalyses.last
    }
    
    func reset() {
        transcriptionHistory.removeAll()
        stabilizedWords.removeAll()
        overlapAnalyses.removeAll()
        currentStabilizedText = ""
        stabilizationMetrics = nil
        
        print("TranscriptionStabilizationManager: Reset complete")
    }
}