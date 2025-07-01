//
//  SpeechRecognitionManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/24/25.
//

import Foundation
import Speech
import AVFoundation
import Combine
import os.log

// MARK: - Speech Events

enum SpeechEvent: Sendable {
    case transcriptionUpdate(String)
    case sentenceFinalized(String)
    case statusChanged(String)
    case error(Error)
}

// MARK: - SpeechRecognitionManager

final class SpeechRecognitionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isRecording = false
    @Published var currentTranscription: String = ""
    @Published var captionHistory: [CaptionEntry] = []
    @Published var statusText: String = "Ready to record"
    
    // MARK: - Private Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    // Text processing state
    private var processedTextLength: Int = 0
    private var fullTranscriptionText: String = ""
    
    // Frame-based silence detection
    private var consecutiveSilenceFrames: Int = 0
    private let silenceFrameThreshold: Int = 10  // ~2 seconds (20 frames × 100ms)
    private var currentSpeechState: Bool = false
    
    // AsyncStream for events
    private var speechEventsContinuation: AsyncStream<SpeechEvent>.Continuation?
    private var speechEventsStream: AsyncStream<SpeechEvent>?
    
    // Logging
    private let logger = Logger(subsystem: "com.livcap.speech", category: "SpeechRecognitionManager")
    
    // MARK: - Initialization
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        setupSpeechRecognition()
    }
    
    deinit {
        stopRecording()
        speechEventsContinuation?.finish()
    }
    
    // MARK: - AsyncStream Interface
    
    func speechEvents() -> AsyncStream<SpeechEvent> {
        if let stream = speechEventsStream {
            return stream
        }
        
        speechEventsStream = AsyncStream { continuation in
            self.speechEventsContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.logger.info("🛑 Speech events stream terminated")
            }
        }
        
        return speechEventsStream!
    }
    
    // MARK: - Setup
    
    private func setupSpeechRecognition() {
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            guard let self = self else { return }
            
            Task { @MainActor in
                let status: String
                switch authStatus {
                case .authorized:
                    status = "Ready to record"
                case .denied:
                    status = "Speech recognition permission denied"
                case .restricted:
                    status = "Speech recognition restricted"
                case .notDetermined:
                    status = "Speech recognition not determined"
                @unknown default:
                    status = "Speech recognition authorization unknown"
                }
                
                self.statusText = status
                self.speechEventsContinuation?.yield(.statusChanged(status))
            }
        }
    }
    
    // MARK: - Public Interface
    
    func startRecording() async throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            let error = SpeechRecognitionError.recognizerNotAvailable
            await updateStatus("Speech recognizer not available")
            speechEventsContinuation?.yield(.error(error))
            throw error
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            let error = SpeechRecognitionError.notAuthorized
            await updateStatus("Speech recognition not authorized")
            speechEventsContinuation?.yield(.error(error))
            throw error
        }
        
        logger.info("🔴 STARTING SPEECH RECOGNITION ENGINE")
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            let error = SpeechRecognitionError.requestCreationFailed
            await updateStatus("Failed to create recognition request")
            speechEventsContinuation?.yield(.error(error))
            throw error
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            Task {
                if let error = error {
                    await self.updateStatus("Recognition error: \(error.localizedDescription)")
                    self.speechEventsContinuation?.yield(.error(error))
                    return
                }
                
                if let result = result {
                    let transcription = result.bestTranscription.formattedString
                    await self.processTranscriptionResult(transcription)
                }
            }
        }
        
        await MainActor.run {
            self.isRecording = true
            self.currentTranscription = ""
        }
        
        // Reset state
        processedTextLength = 0
        fullTranscriptionText = ""
        currentSpeechState = false
        consecutiveSilenceFrames = 0
        
        logger.info("✅ SPEECH RECOGNITION ENGINE STARTED")
    }
    
    func stopRecording() {
        logger.info("⏹️ STOPPING SPEECH RECOGNITION ENGINE")
        
        guard isRecording else { return }
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        Task { @MainActor in
            self.isRecording = false
            
            // Add final transcription to history if not empty
            if !self.currentTranscription.isEmpty {
                self.addToHistory(self.currentTranscription)
                self.speechEventsContinuation?.yield(.sentenceFinalized(self.currentTranscription))
                self.currentTranscription = ""
            }
        }
        
        // Reset state
        processedTextLength = 0
        fullTranscriptionText = ""
        consecutiveSilenceFrames = 0
        
        logger.info("✅ SPEECH RECOGNITION ENGINE STOPPED")
    }
    
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.append(buffer)
    }
    
    func appendAudioBufferWithVAD(_ audioFrame: AudioFrameWithVAD) {
        guard isRecording, let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.append(audioFrame.buffer)
        
        // Frame-based silence detection
        if audioFrame.isSpeech {
            consecutiveSilenceFrames = 0
            onSpeechStart()
        } else {
            consecutiveSilenceFrames += 1
            
            if consecutiveSilenceFrames == 1 {
                onSpeechEnd()
            } else if consecutiveSilenceFrames == silenceFrameThreshold {
                // 2 seconds of silence - create new line!
                logger.info("⏰ 2s SILENCE DETECTED - Creating new caption line")
                Task {
                    await finalizeSentence()
                }
                consecutiveSilenceFrames = 0  // Reset counter
            }
        }
    }
    
    func onSpeechStart() {
        currentSpeechState = true
    }
    
    func onSpeechEnd() {
        currentSpeechState = false
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func updateStatus(_ status: String) {
        statusText = status
        speechEventsContinuation?.yield(.statusChanged(status))
    }
    
    @MainActor
    private func processTranscriptionResult(_ transcription: String) {
        // Store the full transcription from SFSpeechRecognizer
        let previousFullLength = fullTranscriptionText.count
        fullTranscriptionText = transcription
        
        // Extract only the NEW part that hasn't been processed yet
        let newPart = extractNewTranscriptionPart(from: transcription)
        currentTranscription = newPart
        
        // Notify via AsyncStream
        speechEventsContinuation?.yield(.transcriptionUpdate(newPart))
        
        // Reset silence counter if new text was added during silence
        if transcription.count > previousFullLength && !currentSpeechState {
            consecutiveSilenceFrames = 0
        }
    }
    
    private func extractNewTranscriptionPart(from fullText: String) -> String {
        // Extract only the part that hasn't been processed yet
        if fullText.count > processedTextLength {
            let startIndex = fullText.index(fullText.startIndex, offsetBy: processedTextLength)
            let newPart = String(fullText[startIndex...])
            return newPart.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
    
    @MainActor
    private func finalizeSentence() {
        if !currentTranscription.isEmpty {
            logger.info("📝 FINALIZING SENTENCE: \(self.currentTranscription)")
            
            // Add the current sentence part to history
            addToHistory(currentTranscription)
            
            // Notify via AsyncStream - this triggers UI to create new line!
            speechEventsContinuation?.yield(.sentenceFinalized(currentTranscription))
            
            // Update processed length to include what we just added
            processedTextLength = fullTranscriptionText.count
            
            // Clear current transcription for next sentence
            currentTranscription = ""
        }
    }
    
    @MainActor
    private func addToHistory(_ text: String) {
        let entry = CaptionEntry(
            id: UUID(),
            text: text,
            confidence: 1.0 // SFSpeechRecognizer doesn't provide confidence scores
        )
        captionHistory.append(entry)
        
        // Keep only last 50 entries to prevent memory issues
        if captionHistory.count > 50 {
            captionHistory.removeFirst()
        }
        
        logger.info("📝 Added to history: \(text)")
    }
    
    // MARK: - Public Utility Methods
    
    func clearCaptions() {
        Task { @MainActor in
            self.captionHistory.removeAll()
            self.currentTranscription = ""
            self.consecutiveSilenceFrames = 0
            self.logger.info("🗑️ CLEARED ALL CAPTIONS")
        }
    }
}

// MARK: - Error Types

enum SpeechRecognitionError: Error, LocalizedError {
    case recognizerNotAvailable
    case notAuthorized
    case requestCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .notAuthorized:
            return "Speech recognition is not authorized"
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        }
    }
}
