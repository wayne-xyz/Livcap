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
import os.log

/// CaptionViewModel for real-time speech recognition using SFSpeechRecognizer
final class CaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published private(set) var isMicrophoneEnabled = false
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
    
    // Audio source tasks
    private var microphoneStreamTask: Task<Void, Never>?
    private var systemAudioStreamTask: Task<Void, Never>?
    private var mixedAudioStreamTask: Task<Void, Never>?
    
    
    // MARK: - VAD and Sentence Segmentation Properties
    
    private let vadProcessor = VADProcessor()
    private var currentSpeechState: Bool = false
    private var silenceStartTime: Date = Date()
    private let sentenceTimeoutDuration: TimeInterval = 2.0 // 2 seconds of silence to end sentence
    
    // Track processed text to avoid duplication
    private var processedTextLength: Int = 0
    private var fullTranscriptionText: String = ""
    
    // MARK: - Logging
    private let logger = Logger(subsystem: "com.livcap.audio", category: "CaptionViewModel")
    private var frameCounter = 0
    
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
    
    private func setupSystemAudioComponents() {
        // Initialize system audio components only if supported
        if #available(macOS 14.4, *) {
            if systemAudioPermissionManager.isSystemAudioCaptureSupported() {
                systemAudioManager = SystemAudioManager()
                audioMixingService = AudioMixingService()
            }
        }
    }
    
    // MARK: - Main control functions
    
    func toggleMicrophone() {
        logger.info("🎤 TOGGLE MICROPHONE: \(self.isMicrophoneEnabled) -> \(!self.isMicrophoneEnabled)")
        
        if isMicrophoneEnabled {
            stopMicrophone()
        } else {
            startMicrophone()
        }
        
        // Auto-manage speech recognition based on active sources
        manageRecordingState()
    }
    
    func toggleSystemAudio() {
        logger.info("💻 TOGGLE SYSTEM AUDIO: \(self.isSystemAudioEnabled) -> \(!self.isSystemAudioEnabled)")
        
        if isSystemAudioEnabled {
            stopSystemAudio()
        } else {
            startSystemAudio()
        }
        
        // Auto-manage speech recognition based on active sources
        manageRecordingState()
    }
    
    // MARK: - Auto Speech Recognition Management
    
    private func manageRecordingState() {
        let shouldBeRecording = isMicrophoneEnabled || isSystemAudioEnabled
        
        if shouldBeRecording && !isRecording {
            startRecording()
        } else if !shouldBeRecording && isRecording {
            stopRecording()
        }
    }
    
    // MARK: - Speech Recognition Control (Always Running When Recording)
    
    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            statusText = "Speech recognizer not available"
            return
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusText = "Speech recognition not authorized"
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
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
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
        
        isRecording = true
        updateStatus()
        currentTranscription = ""
        frameCounter = 0
        
        // Start system audio processing if enabled
        if isSystemAudioEnabled {
            startSystemAudioProcessing()
        }
        
        // Mixed audio stream is only needed for complex mixing scenarios
        // For now, we process sources independently
        if isMicrophoneEnabled || isSystemAudioEnabled {
            startMixedAudioStream()
        }
        
        logger.info("✅ SPEECH RECOGNITION ENGINE STARTED")
    }
    
    private func stopRecording() {
        logger.info("⏹️ STOPPING SPEECH RECOGNITION ENGINE")
        
        guard isRecording else { return }
        
        // Stop system audio processing
        if isSystemAudioEnabled {
            stopSystemAudioProcessing()
        }
        
        // Stop mixed audio stream
        stopMixedAudioStream()
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        isRecording = false
        updateStatus()
        
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
        
        logger.info("✅ SPEECH RECOGNITION ENGINE STOPPED")
    }
    
    // MARK: - Microphone Control
    
    private func startMicrophone() {
        logger.info("🎤 STARTING MICROPHONE SOURCE")
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            statusText = "Failed to create audio engine"
            logger.error("❌ Failed to create audio engine")
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        logger.info("🎤 Microphone format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processMicrophoneBuffer(buffer)
        }
        
        // Prepare and start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            isMicrophoneEnabled = true
            updateStatus()
            
            // Restart mixed stream if recording
            if isRecording {
                startMixedAudioStream()
            }
            
            logger.info("✅ MICROPHONE SOURCE STARTED")
            
        } catch {
            statusText = "Failed to start microphone: \(error.localizedDescription)"
            logger.error("❌ Microphone start error: \(error)")
        }
    }
    
    private func stopMicrophone() {
        logger.info("🎤 STOPPING MICROPHONE SOURCE")
        
        guard isMicrophoneEnabled else { return }
        
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        isMicrophoneEnabled = false
        updateStatus()
        
        // Restart mixed stream if recording (will use system audio only)
        if isRecording {
            startMixedAudioStream()
        }
        
        logger.info("✅ MICROPHONE SOURCE STOPPED")
    }
    
    // MARK: - System Audio Control
    
    private func startSystemAudio() {
        guard !isSystemAudioEnabled else {
            logger.info("💻 System audio already enabled")
            return
        }
        
        guard #available(macOS 14.4, *) else {
            statusText = "System audio requires macOS 14.4+"
            logger.warning("💻 System audio not supported on this macOS version")
            return
        }
        
        guard let systemAudioManager = systemAudioManager else {
            statusText = "System audio not available"
            logger.error("💻 System audio manager not available")
            return
        }
        
        logger.info("💻 STARTING SYSTEM AUDIO SOURCE")
        
        Task {
            do {
                // Check/request permission first
                let hasPermission = await systemAudioPermissionManager.requestPermission()
                guard hasPermission else {
                    await MainActor.run {
                        self.statusText = "System audio permission denied"
                        self.logger.warning("💻 System audio permission denied")
                    }
                    AudioDebugLogger.shared.logSystemAudioStatus(isEnabled: false, error: "Permission denied")
                    return
                }
                
                // Start system audio capture
                try await systemAudioManager.startCapture()
                
                await MainActor.run {
                    self.isSystemAudioEnabled = true
                    self.updateStatus()
                    
                    // Start system audio processing if recording
                    if self.isRecording {
                        self.startSystemAudioProcessing()
                        self.startMixedAudioStream()
                    }
                    
                    self.logger.info("✅ SYSTEM AUDIO SOURCE STARTED")
                }
                
            } catch {
                await MainActor.run {
                    self.statusText = "Failed to start system audio: \(error.localizedDescription)"
                    self.logger.error("❌ System audio start error: \(error)")
                }
                AudioDebugLogger.shared.logSystemAudioStatus(isEnabled: false, error: error.localizedDescription)
            }
        }
    }
    
    private func stopSystemAudio() {
        logger.info("💻 STOPPING SYSTEM AUDIO SOURCE")
        
        guard isSystemAudioEnabled else { return }
        
        // Stop system audio processing
        stopSystemAudioProcessing()
        
        systemAudioManager?.stopCapture()
        audioMixingService?.stopMixing()
        
        isSystemAudioEnabled = false
        updateStatus()
        
        // Restart mixed stream if recording (will use microphone only)
        if isRecording {
            startMixedAudioStream()
        }
        
        logger.info("✅ SYSTEM AUDIO SOURCE STOPPED")
    }
    
    // MARK: - Mixed Audio Stream Management
    
    private func startMixedAudioStream() {
        // Stop any existing stream
        stopMixedAudioStream()
        
        guard isRecording else { return }
        
        let activeSources = (isMicrophoneEnabled ? 1 : 0) + (isSystemAudioEnabled ? 1 : 0)
        logger.info("🎵 STARTING MIXED AUDIO STREAM (Sources: mic=\(self.isMicrophoneEnabled), system=\(self.isSystemAudioEnabled))")
        
        guard activeSources > 0 else {
            logger.warning("🎵 No audio sources enabled")
            return
        }
        
        // Start mixed audio processing
        mixedAudioStreamTask = Task { [weak self] in
            await self?.processMixedAudioStream()
        }
    }
    
    private func stopMixedAudioStream() {
        logger.info("🎵 STOPPING MIXED AUDIO STREAM")
        
        mixedAudioStreamTask?.cancel()
        mixedAudioStreamTask = nil
        
        audioMixingService?.stopMixing()
    }
    
    private func processMixedAudioStream() async {
        guard let audioMixingService = audioMixingService else {
            logger.error("🎵 Audio mixing service not available")
            return
        }
        
        logger.info("🎵 STARTING MIXED AUDIO STREAM")
        logger.info("   - Microphone enabled: \(self.isMicrophoneEnabled)")
        logger.info("   - System audio enabled: \(self.isSystemAudioEnabled)")
        
        // Create audio streams based on enabled sources
        let microphoneStream = self.isMicrophoneEnabled ? getMicrophoneAudioStream() : createEmptyAudioStream()
        let systemAudioStream = self.isSystemAudioEnabled ? self.systemAudioManager?.systemAudioStream() ?? createEmptyAudioStream() : createEmptyAudioStream()
        
        // Start mixing
        audioMixingService.startMixing(
            microphoneStream: microphoneStream,
            systemAudioStream: systemAudioStream
        )
        
        // Process mixed audio stream
        let mixedStream = audioMixingService.mixedAudioStream()
        
        for try await audioSamples in mixedStream {
            guard !Task.isCancelled else { break }
            
            // Convert to AVAudioPCMBuffer and send to recognizer
            if let buffer = self.createAudioBuffer(from: audioSamples) {
                self.recognitionRequest?.append(buffer)
                self.processAudioBufferForVAD(buffer, samples: audioSamples)
            }
        }
        
        logger.info("🎵 MIXED AUDIO STREAM ENDED")
    }
    
    // MARK: - System Audio Processing
    
    private func startSystemAudioProcessing() {
        guard let systemAudioManager = systemAudioManager else {
            logger.error("💻 System audio manager not available")
            return
        }
        
        logger.info("💻 STARTING DIRECT SYSTEM AUDIO PROCESSING")
        
        // Create a task to process system audio stream directly
        systemAudioStreamTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let systemStream = systemAudioManager.systemAudioStream()
                
                for try await audioSamples in systemStream {
                    guard !Task.isCancelled, self.isRecording, self.isSystemAudioEnabled else { 
                        self.logger.info("💻 Breaking system audio processing: cancelled=\(Task.isCancelled), recording=\(self.isRecording), enabled=\(self.isSystemAudioEnabled)")
                        break 
                    }
                    
                    self.logger.info("💻 RECEIVED \(audioSamples.count) samples from AsyncStream")
                    
                    // Convert system audio samples to AVAudioPCMBuffer
                    if let buffer = self.createAudioBuffer(from: audioSamples) {
                        // Send directly to speech recognition on main thread
                        DispatchQueue.main.async { [weak self] in
                            self?.recognitionRequest?.append(buffer)
                            self?.logger.info("💻 System audio buffer sent to speech recognition: \(buffer.frameLength) frames, \(buffer.format.channelCount) channels, \(buffer.format.sampleRate) Hz")
                        }
                        
                        // Process for VAD and debugging
                        self.processSystemAudioForVAD(buffer, samples: audioSamples)
                    }
                }
                
                self.logger.info("💻 SYSTEM AUDIO PROCESSING ENDED")
            } catch {
                self.logger.error("💻 System audio processing error: \(error)")
            }
        }
    }
    
    private func stopSystemAudioProcessing() {
        logger.info("💻 STOPPING SYSTEM AUDIO PROCESSING")
        systemAudioStreamTask?.cancel()
        systemAudioStreamTask = nil
    }
    
    private func processSystemAudioForVAD(_ buffer: AVAudioPCMBuffer, samples: [Float]) {
        let isSpeech = vadProcessor.processAudioChunk(samples)
        
        self.frameCounter += 1
        
        // Enhanced debug logging for system audio
        AudioDebugLogger.shared.logAudioFrame(
            source: .systemAudio,
            frameIndex: self.frameCounter,
            samples: samples,
            sampleRate: 16000, // System audio is converted to 16kHz
            vadDecision: isSpeech
        )
        
        // Detect speech state transitions for system audio
        if isSpeech != currentSpeechState {
            AudioDebugLogger.shared.logVADTransition(from: currentSpeechState, to: isSpeech)
            
            if isSpeech {
                logger.info("🗣️ SYSTEM AUDIO SPEECH START detected")
                onSpeechStart()
            } else {
                logger.info("🤫 SYSTEM AUDIO SPEECH END detected")
                onSpeechEnd()
            }
            currentSpeechState = isSpeech
        }
        
        // Check for sentence timeout during silence
        if !isSpeech && !currentTranscription.isEmpty {
            let silenceDuration = Date().timeIntervalSince(silenceStartTime)
            if silenceDuration >= sentenceTimeoutDuration {
                logger.info("⏰ SYSTEM AUDIO SENTENCE TIMEOUT after \(String(format: "%.1f", silenceDuration))s silence")
                finalizeSentence()
            }
        }
    }
    
    // MARK: - Audio Buffer Processing with Detailed Logging
    
    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        let sampleRate = buffer.format.sampleRate
        
        self.frameCounter += 1
        
        // Enhanced debug logging with colors
        AudioDebugLogger.shared.logAudioFrame(
            source: .microphone,
            frameIndex: self.frameCounter,
            samples: samples,
            sampleRate: sampleRate,
            vadDecision: nil
        )
        
        // Send microphone audio directly to speech recognizer when enabled
        if isMicrophoneEnabled && isRecording {
            DispatchQueue.main.async { [weak self] in
                self?.recognitionRequest?.append(buffer)
            }
            processAudioBufferForVAD(buffer, samples: samples)
        }
    }
    
    private func processAudioBufferForVAD(_ buffer: AVAudioPCMBuffer, samples: [Float]) {
        let isSpeech = vadProcessor.processAudioChunk(samples)
        
        self.frameCounter += 1
        
        // Enhanced debug logging with colors and VAD decision
        AudioDebugLogger.shared.logAudioFrame(
            source: .mixed,
            frameIndex: self.frameCounter,
            samples: samples,
            sampleRate: 16000, // Mixed audio is always 16kHz
            vadDecision: isSpeech
        )
        
        // Detect speech state transitions
        if isSpeech != currentSpeechState {
            AudioDebugLogger.shared.logVADTransition(from: currentSpeechState, to: isSpeech)
            
            if isSpeech {
                logger.info("🗣️ SPEECH START detected")
                onSpeechStart()
            } else {
                logger.info("🤫 SPEECH END detected")
                onSpeechEnd()
            }
            currentSpeechState = isSpeech
        }
        
        // Check for sentence timeout during silence
        if !isSpeech && !currentTranscription.isEmpty {
            let silenceDuration = Date().timeIntervalSince(silenceStartTime)
            if silenceDuration >= sentenceTimeoutDuration {
                logger.info("⏰ SENTENCE TIMEOUT after \(String(format: "%.1f", silenceDuration))s silence")
                finalizeSentence()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func updateStatus() {
        let micStatus = isMicrophoneEnabled ? "MIC:ON" : "MIC:OFF"
        let systemStatus = isSystemAudioEnabled ? "SYS:ON" : "SYS:OFF"
        
        self.statusText = "\(micStatus) | \(systemStatus)"
        logger.info("📊 STATUS UPDATE: \(self.statusText)")
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    private func getMicrophoneAudioStream() -> AsyncStream<[Float]> {
        return AsyncStream { continuation in
            // This stream will be fed from the processMicrophoneBuffer function
            // For now, we'll use the existing buffer processing
            continuation.finish()
        }
    }
    
    private func createEmptyAudioStream() -> AsyncStream<[Float]> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    private func createAudioBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        logger.info("💻 createAudioBuffer called with \(samples.count) samples")
        
        // Create audio format
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { 
            logger.error("💻 ❌ Failed to create audio format")
            return nil 
        }
        
        // Create buffer
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { 
            logger.error("💻 ❌ Failed to create AVAudioPCMBuffer")
            return nil 
        }
        
        // Copy samples
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
            logger.info("💻 ✅ Successfully created buffer with \(buffer.frameLength) frames")
        } else {
            logger.error("💻 ❌ No channel data available in buffer")
            return nil
        }
        
        return buffer
    }

    // MARK: - Legacy Functions (Keep for compatibility)
    
    func addToHistory(_ text: String) {
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
    
    func clearCaptions() {
        captionHistory.removeAll()
        currentTranscription = ""
        logger.info("🗑️ CLEARED ALL CAPTIONS")
    }
    
    private func onSpeechStart() {
        // Speech started, no immediate action needed
    }
    
    private func onSpeechEnd() {
        silenceStartTime = Date()
    }
    
    private func finalizeSentence() {
        DispatchQueue.main.async {
            if !self.currentTranscription.isEmpty {
                self.logger.info("📝 FINALIZING SENTENCE: \(self.currentTranscription)")
                
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
