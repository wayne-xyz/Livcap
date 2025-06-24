//
//  CaptionViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import Foundation
import Combine
import Speech
import AVFoundation
import Accelerate


/// CaptionViewModel for real-time speech recognition using SFSpeechRecognizer
final class CaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published private(set) var isSystemAudioEnabled = false
    @Published var statusText: String = "Ready to record"
    @Published var captionHistory: [CaptionEntry] = []
    @Published var currentTranscription: String = ""
    
    // MARK: - Private Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    // System audio components (available on macOS 14.4+)
    private var systemAudioManager: SystemAudioProtocol?
    private var audioMixingService: AudioMixingService?
    private var systemAudioPermissionManager: SystemAudioPermissionManager
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - VAD and Sentence Segmentation Properties
    
    private let vadProcessor = VADProcessor()
    private var currentSpeechState: Bool = false
    private var silenceStartTime: Date = Date()
    private let sentenceTimeoutDuration: TimeInterval = 2.0 // 2 seconds of silence to end sentence
    
    // Track processed text to avoid duplication
    private var processedTextLength: Int = 0
    private var fullTranscriptionText: String = ""
    
    // MARK: - Initialization
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        self.systemAudioPermissionManager = SystemAudioPermissionManager()
        setupSpeechRecognition()
        setupSystemAudioComponents()
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
            }
        }
    }
    
    // MARK: - Main control functions
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func toggleSystemAudio() {
        if isSystemAudioEnabled {
            stopSystemAudio()
        } else {
            startSystemAudio()
        }
    }
    
    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            statusText = "Speech recognizer not available"
            return
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusText = "Speech recognition not authorized"
            return
        }
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            statusText = "Failed to create audio engine"
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            statusText = "Failed to create recognition request"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // Always process audio through VAD for sentence segmentation
            self?.processAudioBufferForVAD(buffer)
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.statusText = "Recognition error: \(error.localizedDescription)"
                }
                return
            }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                print("transcription result: \(transcription)")
                
                DispatchQueue.main.async {
                    // Store the full transcription from SFSpeechRecognizer
                    let previousFullLength = self.fullTranscriptionText.count
                    self.fullTranscriptionText = transcription
                    
                    // Extract only the NEW part that hasn't been processed yet
                    let newPart = self.extractNewTranscriptionPart(from: transcription)
                    self.currentTranscription = newPart
                    
                    // If new text was added, reset silence timer if we're currently in silence
                    if transcription.count > previousFullLength {
                        if !self.currentSpeechState {
                            self.silenceStartTime = Date()
                        }
                    }
                }
            }
        }
        
        // Prepare and start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            statusText = "Recording..."
            currentTranscription = ""
            
        } catch {
            statusText = "Failed to start audio engine: \(error.localizedDescription)"
            print("Audio engine start error: \(error)")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        isRecording = false
        statusText = "Recording stopped"
        
        // Add final transcription to history if not empty
        if !currentTranscription.isEmpty {
            addToHistory(currentTranscription)
            currentTranscription = ""
        }
        
        // Reset VAD state and text tracking
        vadProcessor.reset()
        currentSpeechState = false
        processedTextLength = 0
        fullTranscriptionText = ""
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
    }
    
    func clearCaptions() {
        captionHistory.removeAll()
        currentTranscription = ""
    }
    
    // MARK: - VAD Processing for Sentence Segmentation
    
    private func processAudioBufferForVAD(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        
        let isSpeech = vadProcessor.processAudioChunk(samples)
        
        // Detect speech state transitions
        if isSpeech != currentSpeechState {
            if isSpeech {
                // Silence to speech transition
                onSpeechStart()
            } else {
                // Speech to silence transition
                onSpeechEnd()
            }
            currentSpeechState = isSpeech
        }
        
        // Check for sentence timeout during silence
        if !isSpeech && !currentTranscription.isEmpty {
            let silenceDuration = Date().timeIntervalSince(silenceStartTime)
            if silenceDuration >= sentenceTimeoutDuration {
                finalizeSentence()
            }
        }
    }
    
    private func onSpeechStart() {
        debugLog("Speech detected - continuing sentence")
        // Speech started, no immediate action needed
        // Just continue building the current transcription
    }
    
    private func onSpeechEnd() {
        // Speech ended, start silence timer
        silenceStartTime = Date()
        debugLog("Silence detected - starting sentence timeout")
    }
    
    // MARK: - System Audio Management
    
    private func setupSystemAudioComponents() {
        // Initialize system audio components only if supported
        if #available(macOS 14.4, *) {
            if systemAudioPermissionManager.isSystemAudioCaptureSupported() {
                systemAudioManager = SystemAudioManager()
                audioMixingService = AudioMixingService()
            }
        }
    }
    
    private func startSystemAudio() {
        guard !isSystemAudioEnabled else {
            debugLog("System audio already enabled")
            return
        }
        
        guard #available(macOS 14.4, *) else {
            statusText = "System audio requires macOS 14.4+"
            return
        }
        
        guard let systemAudioManager = systemAudioManager else {
            statusText = "System audio not available"
            return
        }
        
        Task {
            do {
                // Check/request permission first
                let hasPermission = await systemAudioPermissionManager.requestPermission()
                guard hasPermission else {
                    await MainActor.run {
                        self.statusText = "System audio permission denied"
                    }
                    return
                }
                
                // Start system audio capture
                try await systemAudioManager.startCapture()
                
                await MainActor.run {
                    self.isSystemAudioEnabled = true
                    self.statusText = isRecording ? "Recording with system audio" : "System audio enabled"
                }
                
                // If microphone is already recording, restart with mixed audio
                if isRecording {
                    restartRecordingWithMixedAudio()
                }
                
            } catch {
                await MainActor.run {
                    self.statusText = "Failed to start system audio: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func stopSystemAudio() {
        guard isSystemAudioEnabled else { return }
        
        systemAudioManager?.stopCapture()
        audioMixingService?.stopMixing()
        
        isSystemAudioEnabled = false
        statusText = isRecording ? "Recording (microphone only)" : "System audio disabled"
        
        // If microphone is recording, restart with microphone-only audio
        if isRecording {
            restartRecordingWithMicrophoneOnly()
        }
    }
    
    private func restartRecordingWithMixedAudio() {
        guard isRecording, isSystemAudioEnabled else { return }
        guard let audioMixingService = audioMixingService else { return }
        guard let systemAudioManager = systemAudioManager else { return }
        
        // Get audio streams
        let microphoneStream = getMicrophoneAudioStream()
        
        // Get system audio stream
        let systemAudioStream = systemAudioManager.systemAudioStream()
        
        // Start mixing
        audioMixingService.startMixing(
            microphoneStream: microphoneStream,
            systemAudioStream: systemAudioStream
        )
        
        // Restart speech recognition with mixed audio
        restartSpeechRecognitionWithMixedAudio(audioMixingService.mixedAudioStream())
        
        debugLog("Restarted recording with mixed audio")
    }
    
    private func restartRecordingWithMicrophoneOnly() {
        guard isRecording else { return }
        
        // Stop audio mixing
        audioMixingService?.stopMixing()
        
        // Restart speech recognition with microphone-only audio
        restartSpeechRecognitionWithMicrophoneOnly()
        
        debugLog("Restarted recording with microphone only")
    }
    
    private func restartSpeechRecognitionWithMixedAudio(_ mixedStream: AsyncStream<[Float]>) {
        // Stop current recognition
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        
        // Create new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // Start new recognition task with mixed audio
        startSpeechRecognitionTask(with: recognitionRequest)
        
        // Process mixed audio stream
        Task {
            for try await audioSamples in mixedStream {
                // Convert to AVAudioPCMBuffer and send to recognizer
                if let buffer = createAudioBuffer(from: audioSamples) {
                    recognitionRequest.append(buffer)
                    processAudioBufferForVAD(buffer)
                }
            }
        }
    }
    
    private func restartSpeechRecognitionWithMicrophoneOnly() {
        // This will restart the original microphone-based recording
        let wasRecording = isRecording
        stopRecording()
        if wasRecording {
            startRecording()
        }
    }
    
    private func getMicrophoneAudioStream() -> AsyncStream<[Float]> {
        // Create a stream from the current microphone audio engine
        return AsyncStream { continuation in
            // This is a simplified implementation
            // In practice, you'd need to modify the existing audio engine setup
            // to provide this stream alongside the SFSpeechRecognizer input
            continuation.finish()
        }
    }
    
    private func startSpeechRecognitionTask(with request: SFSpeechAudioBufferRecognitionRequest) {
        guard let speechRecognizer = speechRecognizer else { return }
        
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.statusText = "Recognition error: \(error.localizedDescription)"
                }
                return
            }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                print("transcription result: \(transcription)")
                
                DispatchQueue.main.async {
                    let previousFullLength = self.fullTranscriptionText.count
                    self.fullTranscriptionText = transcription
                    
                    let newPart = self.extractNewTranscriptionPart(from: transcription)
                    self.currentTranscription = newPart
                    
                    if transcription.count > previousFullLength {
                        if !self.currentSpeechState {
                            self.silenceStartTime = Date()
                        }
                    }
                }
            }
        }
    }
    
    private func createAudioBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        // Create audio format
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { return nil }
        
        // Create buffer
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }
        
        // Copy samples
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
        }
        
        return buffer
    }
    
    private func finalizeSentence() {
        DispatchQueue.main.async {
            if !self.currentTranscription.isEmpty {
                debugLog("Sentence timeout reached - finalizing: \(self.currentTranscription)")
                
                // Add the current sentence part to history
                self.addToHistory(self.currentTranscription)
                
                // Update processed length to include what we just added
                self.processedTextLength = self.fullTranscriptionText.count
                
                // Clear current transcription for next sentence
                self.currentTranscription = ""
                
                // Reset silence timer
                self.silenceStartTime = Date()
            }
        }
    }
    
    // MARK: - Text Processing Helpers
    
    private func extractNewTranscriptionPart(from fullText: String) -> String {
        // Extract only the part that hasn't been processed yet
        if fullText.count > processedTextLength {
            let startIndex = fullText.index(fullText.startIndex, offsetBy: processedTextLength)
            let newPart = String(fullText[startIndex...])
            return newPart.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
