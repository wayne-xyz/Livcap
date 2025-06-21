//
//  StreamingWhisperTranscriber.swift
//  Livcap
//
//  Created by Implementation Plan on 6/20/25.
//

import Foundation
import Combine

/// Handles streaming transcription of overlapping audio windows
/// Implements word-level diffing and LocalAgreement-2 stabilization
actor StreamingWhisperTranscriber {
    
    // MARK: - Properties
    private var whisperCppContext: WhisperCpp?
    private let modelName: String
    private var canTranscribe: Bool = false
    
    // MARK: - State Management
    private var previousTranscription: String = ""
    private var transcriptionHistory: [TranscriptionUpdate] = []
    private var isProcessing: Bool = false
    
    // MARK: - Publishers
    nonisolated let transcriptionPublisher = PassthroughSubject<TranscriptionUpdate, Error>()
    
    // MARK: - Configuration
    private let maxHistoryEntries: Int = 50
    private let minConfidenceThreshold: Float = 0.1
    
    // MARK: - Initialization
    init(modelName: String = WhisperModelName().baseEn) {
        self.modelName = modelName
        Task {
            await loadModel()
        }
    }
    
    // MARK: - Public Interface
    
    /// Transcribes an audio window and returns a transcription update
    func transcribeWindow(_ window: AudioWindow) async -> TranscriptionUpdate {
        guard canTranscribe, let whisperCppContext = whisperCppContext else {
            print("StreamingWhisperTranscriber: Model not loaded or not ready for transcription.")
            return TranscriptionUpdate(
                windowID: window.id,
                fullTranscription: "",
                newWords: [],
                previousTranscription: previousTranscription
            )
        }
        
        guard !isProcessing else {
            print("StreamingWhisperTranscriber: Already processing a window, skipping \(window.id)")
            return TranscriptionUpdate(
                windowID: window.id,
                fullTranscription: previousTranscription,
                newWords: [],
                previousTranscription: previousTranscription
            )
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        print("StreamingWhisperTranscriber: Starting transcription for window \(window.id.uuidString.prefix(8)) at \(window.startTimeMS)ms")
        
        // Transcribe the window
        await whisperCppContext.fullTranscribe(samples: window.audio)
        let currentTranscription = await whisperCppContext.getTranscription()
        
        // Calculate word-level difference
        let newWords = TranscriptionUpdate.calculateWordDifference(
            current: currentTranscription,
            previous: previousTranscription
        )
        
        // Create transcription update
        let update = TranscriptionUpdate(
            windowID: window.id,
            fullTranscription: currentTranscription,
            newWords: newWords,
            previousTranscription: previousTranscription,
            status: newWords.isEmpty ? .stable : .partial
        )
        
        // Update state
        previousTranscription = currentTranscription
        transcriptionHistory.append(update)
        
        // Maintain history size
        if transcriptionHistory.count > maxHistoryEntries {
            transcriptionHistory.removeFirst()
        }
        
        // Emit the update
        transcriptionPublisher.send(update)
        
        print("StreamingWhisperTranscriber: Completed transcription for window \(window.id.uuidString.prefix(8)), new words: \(newWords.count)")
        
        return update
    }
    
    /// Processes a stream of audio windows
    func processWindowStream<S: AsyncSequence>(_ windowStream: S) -> AsyncStream<TranscriptionUpdate> where S.Element == AudioWindow {
        return AsyncStream { continuation in
            Task {
                do {
                    for try await window in windowStream {
                        let update = await self.transcribeWindow(window)
                        continuation.yield(update)
                        
                        try Task.checkCancellation()
                    }
                } catch {
                    print("StreamingWhisperTranscriber: Error processing window stream: \(error)")
                }
                
                continuation.finish()
            }
        }
    }
    
    /// Applies LocalAgreement-2 policy to stabilize transcription
    func applyLocalAgreementPolicy(_ currentUpdate: TranscriptionUpdate) -> TranscriptionUpdate {
        // LocalAgreement-2: Find the longest common prefix between current and previous
        // For now, we'll use a simple approach - in a full implementation, you'd compare
        // with the previous 2 windows to ensure stability
        
        guard let lastUpdate = transcriptionHistory.last else {
            return currentUpdate
        }
        
        // Find longest common prefix
        let currentWords = currentUpdate.fullTranscription.components(separatedBy: " ").filter { !$0.isEmpty }
        let previousWords = lastUpdate.fullTranscription.components(separatedBy: " ").filter { !$0.isEmpty }
        
        var commonPrefixLength = 0
        let minLength = min(currentWords.count, previousWords.count)
        
        for i in 0..<minLength {
            if currentWords[i] == previousWords[i] {
                commonPrefixLength += 1
            } else {
                break
            }
        }
        
        // If we have a significant common prefix, mark as stable
        if commonPrefixLength > 0 && commonPrefixLength >= min(3, currentWords.count / 2) {
            let stableWords = Array(currentWords.prefix(commonPrefixLength))
            let newWords = Array(currentWords.suffix(from: commonPrefixLength))
            
            return TranscriptionUpdate.stable(
                windowID: currentUpdate.windowID,
                stableWords: stableWords,
                fullTranscription: currentUpdate.fullTranscription,
                previousTranscription: currentUpdate.previousTranscription
            )
        }
        
        return currentUpdate
    }
    
    /// Gets the current transcription state
    var currentTranscription: String {
        return previousTranscription
    }
    
    /// Gets transcription history
    var history: [TranscriptionUpdate] {
        return transcriptionHistory
    }
    
    /// Resets the transcriber state
    func reset() {
        previousTranscription = ""
        transcriptionHistory.removeAll()
        isProcessing = false
        print("StreamingWhisperTranscriber: Reset")
    }
    
    // MARK: - Private Methods
    
    private func loadModel() async {
        guard let modelPath = Bundle.main.path(forResource: self.modelName, ofType: "bin") else {
            print("StreamingWhisperTranscriber: Model file not found.")
            return
        }
        
        do {
            self.whisperCppContext = try WhisperCpp.createContext(path: modelPath)
            canTranscribe = true
            print("StreamingWhisperTranscriber: Whisper model initialized with path: \(modelName)")
        } catch {
            print("StreamingWhisperTranscriber: Error loading model: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Extensions

extension StreamingWhisperTranscriber {
    
    /// Calculates confidence score for a transcription (placeholder implementation)
    private func calculateConfidence(for transcription: String) -> Float {
        // In a real implementation, this would use Whisper's internal confidence scores
        // For now, we'll use a simple heuristic based on transcription length and content
        
        let words = transcription.components(separatedBy: " ").filter { !$0.isEmpty }
        let wordCount = words.count
        
        // Simple confidence heuristic
        if wordCount == 0 {
            return 0.0
        } else if wordCount < 3 {
            return 0.5
        } else if wordCount < 10 {
            return 0.8
        } else {
            return 0.9
        }
    }
    
    /// Validates transcription quality
    private func isValidTranscription(_ transcription: String) -> Bool {
        let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count > 1
    }
} 