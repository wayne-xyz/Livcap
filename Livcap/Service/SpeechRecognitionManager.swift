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

// MARK: - Protocol

protocol SpeechRecognitionManagerDelegate: AnyObject {
    func speechRecognitionDidUpdateTranscription(_ manager: SpeechRecognitionManager, newText: String)
    func speechRecognitionDidFinalizeSentence(_ manager: SpeechRecognitionManager, sentence: String)
    func speechRecognitionDidEncounterError(_ manager: SpeechRecognitionManager, error: Error)
    func speechRecognitionStatusDidChange(_ manager: SpeechRecognitionManager, status: String)
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
    
    // Sentence timing
    private var silenceStartTime: Date = Date()
    private let sentenceTimeoutDuration: TimeInterval = 2.0 // 2 seconds of silence to end sentence
    private var currentSpeechState: Bool = false
    
    // Logging
    private let logger = Logger(subsystem: "com.livcap.speech", category: "SpeechRecognitionManager")
    
    // Delegate
    weak var delegate: SpeechRecognitionManagerDelegate?
    
    // MARK: - Initialization
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        setupSpeechRecognition()
    }
    
    deinit {
        stopRecording()
    }
    
    // MARK: - Setup
    
    private func setupSpeechRecognition() {
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.statusText = "Ready to record"
                case .denied:
                    self?.statusText = "Speech recognition permission denied"
                case .restricted:
                    self?.statusText = "Speech recognition restricted"
                case .notDetermined:
                    self?.statusText = "Speech recognition not determined"
                @unknown default:
                    self?.statusText = "Speech recognition authorization unknown"
                }
                
                if let self = self {
                    self.delegate?.speechRecognitionStatusDidChange(self, status: self.statusText)
                }
            }
        }
    }
    
    // MARK: - Public Interface
    
    func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            statusText = "Speech recognizer not available"
            delegate?.speechRecognitionStatusDidChange(self, status: statusText)
            return
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusText = "Speech recognition not authorized"
            delegate?.speechRecognitionStatusDidChange(self, status: statusText)
            return
        }
        
        logger.info("🔴 STARTING SPEECH RECOGNITION ENGINE")
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            statusText = "Failed to create recognition request"
            delegate?.speechRecognitionStatusDidChange(self, status: statusText)
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.statusText = "Recognition error: \(error.localizedDescription)"
                    self.delegate?.speechRecognitionDidEncounterError(self, error: error)
                    self.delegate?.speechRecognitionStatusDidChange(self, status: self.statusText)
                }
                return
            }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                
                DispatchQueue.main.async {
                    self.processTranscriptionResult(transcription)
                }
            }
        }
        
        isRecording = true
        currentTranscription = ""
        
        // Reset state
        processedTextLength = 0
        fullTranscriptionText = ""
        silenceStartTime = Date()
        currentSpeechState = false
        
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
        
        isRecording = false
        
        // Add final transcription to history if not empty
        if !currentTranscription.isEmpty {
            addToHistory(currentTranscription)
            delegate?.speechRecognitionDidFinalizeSentence(self, sentence: currentTranscription)
            currentTranscription = ""
        }
        
        // Reset text tracking
        processedTextLength = 0
        fullTranscriptionText = ""
        
        logger.info("✅ SPEECH RECOGNITION ENGINE STOPPED")
    }
    
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.append(buffer)
    }
    
    func appendAudioBufferWithVAD(_ audioFrame: AudioFrameWithVAD) {
        guard isRecording, let recognitionRequest = recognitionRequest else { return }
        
        // Direct buffer append - no conversion needed! 🎉
        recognitionRequest.append(audioFrame.buffer)
        
        // Use VAD result for speech state management
        if audioFrame.isSpeech {
            onSpeechStart()
        } else {
            onSpeechEnd()
            checkSentenceTimeout()
        }
    }
    
    func onSpeechStart() {
        currentSpeechState = true
    }
    
    func onSpeechEnd() {
        currentSpeechState = false
        silenceStartTime = Date()
    }
    
    func checkSentenceTimeout() {
        if !currentSpeechState && !currentTranscription.isEmpty {
            let silenceDuration = Date().timeIntervalSince(silenceStartTime)
            if silenceDuration >= sentenceTimeoutDuration {
                logger.info("⏰ SENTENCE TIMEOUT after \(String(format: "%.1f", silenceDuration))s silence")
                finalizeSentence()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func processTranscriptionResult(_ transcription: String) {
        // Store the full transcription from SFSpeechRecognizer
        let previousFullLength = fullTranscriptionText.count
        fullTranscriptionText = transcription
        
        // Extract only the NEW part that hasn't been processed yet
        let newPart = extractNewTranscriptionPart(from: transcription)
        currentTranscription = newPart
        
        // Notify delegate of transcription update
        delegate?.speechRecognitionDidUpdateTranscription(self, newText: newPart)
        
        // If new text was added, reset silence timer if we're currently in silence
        if transcription.count > previousFullLength {
            if !currentSpeechState {
                silenceStartTime = Date()
            }
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
    
    private func finalizeSentence() {
        if !currentTranscription.isEmpty {
            logger.info("📝 FINALIZING SENTENCE: \(self.currentTranscription)")
            
            // Add the current sentence part to history
            addToHistory(currentTranscription)
            
            // Notify delegate
            delegate?.speechRecognitionDidFinalizeSentence(self, sentence: currentTranscription)
            
            // Update processed length to include what we just added
            processedTextLength = fullTranscriptionText.count
            
            // Clear current transcription for next sentence
            currentTranscription = ""
            
            // Reset silence timer
            silenceStartTime = Date()
        }
    }
    
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
        captionHistory.removeAll()
        currentTranscription = ""
        logger.info("🗑️ CLEARED ALL CAPTIONS")
    }
} 