//
//  TranscriptionUpdate.swift
//  Livcap
//
//  Created by Implementation Plan on 6/20/25.
//

import Foundation

/// Represents a transcription update from an overlapping window
/// Contains both the full transcription and the new words to display
struct TranscriptionUpdate: Sendable {
    let id: UUID
    let windowID: UUID
    let fullTranscription: String
    let newWords: [String]
    let previousTranscription: String
    let isFinal: Bool
    let confidence: Float
    let timestamp: Date
    
    /// Status of the transcription update
    enum Status {
        case partial      // Partial result, may change
        case stable       // Stable result, confirmed by overlap
        case final        // Final result for this window
    }
    
    let status: Status
    
    init(
        windowID: UUID,
        fullTranscription: String,
        newWords: [String],
        previousTranscription: String,
        isFinal: Bool = false,
        confidence: Float = 1.0,
        status: Status = .partial
    ) {
        self.id = UUID()
        self.windowID = windowID
        self.fullTranscription = fullTranscription
        self.newWords = newWords
        self.previousTranscription = previousTranscription
        self.isFinal = isFinal
        self.confidence = confidence
        self.timestamp = Date()
        self.status = status
    }
    
    /// Creates a transcription update with only new words
    static func newWords(
        windowID: UUID,
        newWords: [String],
        fullTranscription: String,
        previousTranscription: String
    ) -> TranscriptionUpdate {
        return TranscriptionUpdate(
            windowID: windowID,
            fullTranscription: fullTranscription,
            newWords: newWords,
            previousTranscription: previousTranscription,
            status: .partial
        )
    }
    
    /// Creates a stable transcription update (confirmed by overlap)
    static func stable(
        windowID: UUID,
        stableWords: [String],
        fullTranscription: String,
        previousTranscription: String
    ) -> TranscriptionUpdate {
        return TranscriptionUpdate(
            windowID: windowID,
            fullTranscription: fullTranscription,
            newWords: stableWords,
            previousTranscription: previousTranscription,
            status: .stable
        )
    }
    
    /// Creates a final transcription update
    static func final(
        windowID: UUID,
        finalWords: [String],
        fullTranscription: String,
        previousTranscription: String
    ) -> TranscriptionUpdate {
        return TranscriptionUpdate(
            windowID: windowID,
            fullTranscription: fullTranscription,
            newWords: finalWords,
            previousTranscription: previousTranscription,
            isFinal: true,
            status: .final
        )
    }
    
    /// Checks if this update contains any new words
    var hasNewWords: Bool {
        return !newWords.isEmpty
    }
    
    /// Gets the number of new words
    var newWordCount: Int {
        return newWords.count
    }
    
    /// Gets the new words as a single string
    var newWordsString: String {
        return newWords.joined(separator: " ")
    }
    
    /// Calculates the word-level difference between current and previous transcription
    static func calculateWordDifference(
        current: String,
        previous: String
    ) -> [String] {
        let currentWords = current.components(separatedBy: " ").filter { !$0.isEmpty }
        let previousWords = previous.components(separatedBy: " ").filter { !$0.isEmpty }
        
        // Find the longest common prefix
        var commonPrefixLength = 0
        let minLength = min(currentWords.count, previousWords.count)
        
        for i in 0..<minLength {
            if currentWords[i] == previousWords[i] {
                commonPrefixLength += 1
            } else {
                break
            }
        }
        
        // Return words after the common prefix
        if commonPrefixLength < currentWords.count {
            return Array(currentWords.suffix(from: commonPrefixLength))
        } else {
            return []
        }
    }
    
    /// Merges two transcription updates
    func merged(with other: TranscriptionUpdate) -> TranscriptionUpdate {
        let combinedNewWords = self.newWords + other.newWords
        let combinedFullTranscription = other.fullTranscription
        let combinedIsFinal = self.isFinal && other.isFinal
        let combinedConfidence = (self.confidence + other.confidence) / 2.0
        let combinedStatus: Status = {
            if self.status == .final || other.status == .final {
                return .final
            } else if self.status == .stable || other.status == .stable {
                return .stable
            } else {
                return .partial
            }
        }()
        
        return TranscriptionUpdate(
            windowID: other.windowID,
            fullTranscription: combinedFullTranscription,
            newWords: combinedNewWords,
            previousTranscription: self.previousTranscription,
            isFinal: combinedIsFinal,
            confidence: combinedConfidence,
            status: combinedStatus
        )
    }
}

// MARK: - Equatable and Hashable
extension TranscriptionUpdate: Equatable {
    static func == (lhs: TranscriptionUpdate, rhs: TranscriptionUpdate) -> Bool {
        return lhs.id == rhs.id
    }
}

extension TranscriptionUpdate: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible
extension TranscriptionUpdate: CustomStringConvertible {
    var description: String {
        return "TranscriptionUpdate(id: \(id.uuidString.prefix(8)), newWords: \(newWords.count), status: \(status), isFinal: \(isFinal))"
    }
} 