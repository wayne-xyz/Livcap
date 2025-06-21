//
//  WordLevelDiffing.swift
//  Livcap
//
//  Created by Implementation Plan on 6/21/25.
//

import Foundation

/// Enhanced word-level diffing for overlapping transcription results
/// Implements sophisticated alignment and comparison algorithms
struct WordLevelDiffing {
    
    // MARK: - Configuration
    private let minConfidenceThreshold: Float = 0.7
    private let maxWordDistance: Int = 2
    private let similarityThreshold: Float = 0.8
    
    // MARK: - Word Structure
    struct Word: Hashable, Equatable {
        let text: String
        let confidence: Float
        let startTime: Double
        let endTime: Double
        let isStable: Bool
        
        init(text: String, confidence: Float = 1.0, startTime: Double = 0.0, endTime: Double = 0.0, isStable: Bool = false) {
            self.text = text
            self.confidence = confidence
            self.startTime = startTime
            self.endTime = endTime
            self.isStable = isStable
        }
        
        /// Calculates similarity with another word
        func similarity(to other: Word) -> Float {
            let textSimilarity = calculateTextSimilarity(text, other.text)
            let timeSimilarity = calculateTimeSimilarity(startTime, other.startTime)
            return (textSimilarity + timeSimilarity) / 2.0
        }
        
        private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Float {
            let normalized1 = text1.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let normalized2 = text2.lowercased().trimmingCharacters(in: .punctuationCharacters)
            
            if normalized1 == normalized2 {
                return 1.0
            }
            
            // Levenshtein distance for fuzzy matching
            let distance = levenshteinDistance(normalized1, normalized2)
            let maxLength = max(normalized1.count, normalized2.count)
            return maxLength > 0 ? Float(maxLength - distance) / Float(maxLength) : 0.0
        }
        
        private func calculateTimeSimilarity(_ time1: Double, _ time2: Double) -> Float {
            let timeDiff = abs(time1 - time2)
            return timeDiff < 0.5 ? 1.0 : max(0.0, 1.0 - Float(timeDiff))
        }
        
        private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
            let empty = Array(repeating: 0, count: s2.count + 1)
            var last = Array(0...s2.count)
            
            for (i, char1) in s1.enumerated() {
                var current = [i + 1] + empty
                for (j, char2) in s2.enumerated() {
                    current[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], current[j]) + 1
                }
                last = current
            }
            return last[s2.count]
        }
    }
    
    // MARK: - Diff Result
    struct DiffResult {
        let newWords: [Word]
        let stableWords: [Word]
        let removedWords: [Word]
        let confidence: Float
        let isSignificant: Bool
        
        var hasChanges: Bool {
            return !newWords.isEmpty || !removedWords.isEmpty
        }
        
        var changeCount: Int {
            return newWords.count + removedWords.count
        }
    }
    
    // MARK: - Public Interface
    
    /// Performs word-level diffing between current and previous transcriptions
    func diffTranscriptions(
        current: String,
        previous: String,
        currentConfidence: Float = 1.0,
        previousConfidence: Float = 1.0
    ) -> DiffResult {
        
        let currentWords = parseWords(from: current, confidence: currentConfidence)
        let previousWords = parseWords(from: previous, confidence: previousConfidence)
        
        return performWordLevelDiff(currentWords: currentWords, previousWords: previousWords)
    }
    
    /// Performs advanced diffing with multiple history windows
    func diffWithHistory(
        current: String,
        history: [String],
        confidences: [Float]
    ) -> DiffResult {
        
        let currentWords = parseWords(from: current, confidence: confidences.first ?? 1.0)
        let historyWords = history.enumerated().map { index, text in
            parseWords(from: text, confidence: confidences.indices.contains(index) ? confidences[index] : 1.0)
        }
        
        return performAdvancedDiff(currentWords: currentWords, historyWords: historyWords)
    }
    
    /// Aligns words between overlapping windows
    func alignWords(
        window1: [Word],
        window2: [Word]
    ) -> (aligned1: [Word], aligned2: [Word], alignment: [Int]) {
        
        let alignment = performAlignment(window1: window1, window2: window2)
        let (aligned1, aligned2) = createAlignedSequences(window1: window1, window2: window2, alignment: alignment)
        
        return (aligned1, aligned2, alignment)
    }
    
    // MARK: - Private Methods
    
    private func parseWords(from text: String, confidence: Float) -> [Word] {
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        return words.enumerated().map { index, word in
            Word(
                text: word,
                confidence: confidence,
                startTime: Double(index) * 0.1, // Approximate timing
                endTime: Double(index + 1) * 0.1,
                isStable: false
            )
        }
    }
    
    private func performWordLevelDiff(currentWords: [Word], previousWords: [Word]) -> DiffResult {
        let alignment = performAlignment(window1: previousWords, window2: currentWords)
        
        var newWords: [Word] = []
        var stableWords: [Word] = []
        var removedWords: [Word] = []
        
        var currentIndex = 0
        var previousIndex = 0
        
        for alignmentType in alignment {
            switch alignmentType {
            case .match:
                if currentIndex < currentWords.count && previousIndex < previousWords.count {
                    let currentWord = currentWords[currentIndex]
                    let previousWord = previousWords[previousIndex]
                    
                    if currentWord.similarity(to: previousWord) >= similarityThreshold {
                        stableWords.append(currentWord)
                    } else {
                        newWords.append(currentWord)
                        removedWords.append(previousWord)
                    }
                }
                currentIndex += 1
                previousIndex += 1
                
            case .insert:
                if currentIndex < currentWords.count {
                    newWords.append(currentWords[currentIndex])
                }
                currentIndex += 1
                
            case .delete:
                if previousIndex < previousWords.count {
                    removedWords.append(previousWords[previousIndex])
                }
                previousIndex += 1
            }
        }
        
        // Add remaining words
        while currentIndex < currentWords.count {
            newWords.append(currentWords[currentIndex])
            currentIndex += 1
        }
        
        while previousIndex < previousWords.count {
            removedWords.append(previousWords[previousIndex])
            previousIndex += 1
        }
        
        let confidence = calculateOverallConfidence(newWords: newWords, stableWords: stableWords)
        let isSignificant = newWords.count > 0 || removedWords.count > 0
        
        return DiffResult(
            newWords: newWords,
            stableWords: stableWords,
            removedWords: removedWords,
            confidence: confidence,
            isSignificant: isSignificant
        )
    }
    
    private func performAdvancedDiff(currentWords: [Word], historyWords: [[Word]]) -> DiffResult {
        guard !historyWords.isEmpty else {
            return DiffResult(
                newWords: currentWords,
                stableWords: [],
                removedWords: [],
                confidence: 1.0,
                isSignificant: true
            )
        }
        
        // Use the most recent history for primary diffing
        let primaryDiff = performWordLevelDiff(currentWords: currentWords, previousWords: historyWords.last!)
        
        // Cross-reference with older history for stability
        var stableWords: [Word] = []
        var confirmedNewWords: [Word] = []
        
        for newWord in primaryDiff.newWords {
            var isConfirmedNew = true
            
            for history in historyWords {
                for historyWord in history {
                    if newWord.similarity(to: historyWord) >= similarityThreshold {
                        isConfirmedNew = false
                        stableWords.append(newWord)
                        break
                    }
                }
                if !isConfirmedNew { break }
            }
            
            if isConfirmedNew {
                confirmedNewWords.append(newWord)
            }
        }
        
        return DiffResult(
            newWords: confirmedNewWords,
            stableWords: stableWords,
            removedWords: primaryDiff.removedWords,
            confidence: primaryDiff.confidence,
            isSignificant: !confirmedNewWords.isEmpty || !primaryDiff.removedWords.isEmpty
        )
    }
    
    private func performAlignment(window1: [Word], window2: [Word]) -> [AlignmentType] {
        let m = window1.count
        let n = window2.count
        
        // Dynamic programming matrix for alignment
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        var traceback = Array(repeating: Array(repeating: AlignmentType.match, count: n + 1), count: m + 1)
        
        // Initialize first row and column
        for i in 0...m {
            dp[i][0] = i
            traceback[i][0] = .delete
        }
        for j in 0...n {
            dp[0][j] = j
            traceback[0][j] = .insert
        }
        
        // Fill the matrix
        for i in 1...m {
            for j in 1...n {
                let matchCost = window1[i-1].similarity(to: window2[j-1]) >= similarityThreshold ? 0 : 1
                let match = dp[i-1][j-1] + matchCost
                let insert = dp[i][j-1] + 1
                let delete = dp[i-1][j] + 1
                
                dp[i][j] = min(match, insert, delete)
                
                if dp[i][j] == match {
                    traceback[i][j] = matchCost == 0 ? .match : .delete
                } else if dp[i][j] == insert {
                    traceback[i][j] = .insert
                } else {
                    traceback[i][j] = .delete
                }
            }
        }
        
        // Traceback to get alignment
        var alignment: [AlignmentType] = []
        var i = m, j = n
        
        while i > 0 || j > 0 {
            alignment.append(traceback[i][j])
            
            switch traceback[i][j] {
            case .match:
                i -= 1
                j -= 1
            case .insert:
                j -= 1
            case .delete:
                i -= 1
            }
        }
        
        return alignment.reversed()
    }
    
    private func createAlignedSequences(window1: [Word], window2: [Word], alignment: [Int]) -> ([Word], [Word]) {
        var aligned1: [Word] = []
        var aligned2: [Word] = []
        
        var i = 0, j = 0
        
        for alignmentType in alignment {
            switch alignmentType {
            case .match:
                aligned1.append(i < window1.count ? window1[i] : Word(text: ""))
                aligned2.append(j < window2.count ? window2[j] : Word(text: ""))
                i += 1
                j += 1
            case .insert:
                aligned1.append(Word(text: ""))
                aligned2.append(j < window2.count ? window2[j] : Word(text: ""))
                j += 1
            case .delete:
                aligned1.append(i < window1.count ? window1[i] : Word(text: ""))
                aligned2.append(Word(text: ""))
                i += 1
            }
        }
        
        return (aligned1, aligned2)
    }
    
    private func calculateOverallConfidence(newWords: [Word], stableWords: [Word]) -> Float {
        let allWords = newWords + stableWords
        guard !allWords.isEmpty else { return 0.0 }
        
        let totalConfidence = allWords.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(allWords.count)
    }
}

// MARK: - Supporting Types

enum AlignmentType {
    case match
    case insert
    case delete
}

// MARK: - Extensions

extension WordLevelDiffing.Word: CustomStringConvertible {
    var description: String {
        return "Word('\(text)', conf: \(String(format: "%.2f", confidence)), stable: \(isStable))"
    }
}

extension WordLevelDiffing.DiffResult: CustomStringConvertible {
    var description: String {
        return "DiffResult(new: \(newWords.count), stable: \(stableWords.count), removed: \(removedWords.count), conf: \(String(format: "%.2f", confidence)))"
    }
} 