//
//  CaptionViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//
// CaptionViewmodel is conductor role in the caption view for the main function
// working with MicAudioManager and SystemAudioManager to accesp two reosuces audio
// working with the display

import Foundation
import Combine
import Speech
import AVFoundation
import Accelerate
import os.log

/// CaptionViewModel for real-time speech recognition using SFSpeechRecognizer
final class CaptionViewModel: ObservableObject, SpeechRecognitionManagerDelegate {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published private(set) var isMicrophoneEnabled = false
    @Published private(set) var isSystemAudioEnabled = false
    @Published var statusText: String = "Ready to record"
    
    // Forwarded from SpeechRecognitionManager
    var captionHistory: [CaptionEntry] { speechRecognitionManager.captionHistory }
    var currentTranscription: String { speechRecognitionManager.currentTranscription }
    
    // MARK: - Private Properties
    
    // Audio managers
    private let micAudioManager = MicAudioManager()
    private let speechRecognitionManager = SpeechRecognitionManager()
    
    // System audio components (available on macOS 14.4+)
    private var systemAudioManager: SystemAudioProtocol?
    private var audioMixingService: AudioMixingService?
    
    private var cancellables = Set<AnyCancellable>()
    
    // Audio source tasks
    private var microphoneStreamTask: Task<Void, Never>?
    private var systemAudioStreamTask: Task<Void, Never>?
    private var mixedAudioStreamTask: Task<Void, Never>?
    
    
    // MARK: - Speech State Tracking
    
    private var currentSpeechState: Bool = false
    
    // MARK: - Logging
    private let logger = Logger(subsystem: "com.livcap.audio", category: "CaptionViewModel")
    private var frameCounter = 0
    
    // MARK: - Initialization
    
    init() {
        setupSpeechRecognition()
        setupSystemAudioComponents()
    }
    
    // MARK: - Setup
    
    private func setupSpeechRecognition() {
        // Set up delegate relationship
        speechRecognitionManager.delegate = self
    }
    
    private func setupSystemAudioComponents() {
        // Initialize system audio components only if supported
        if #available(macOS 14.4, *) {
            systemAudioManager = SystemAudioManager()
            audioMixingService = AudioMixingService()
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
        logger.info("🔴 STARTING SPEECH RECOGNITION ENGINE")
        
        // Start speech recognition manager
        speechRecognitionManager.startRecording()
        
        isRecording = speechRecognitionManager.isRecording
        updateStatus()
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
        
        // Stop speech recognition manager
        speechRecognitionManager.stopRecording()
        
        isRecording = speechRecognitionManager.isRecording
        updateStatus()
        
        // Reset speech state
        currentSpeechState = false
        
        logger.info("✅ SPEECH RECOGNITION ENGINE STOPPED")
    }
    
    // MARK: - Microphone Control
    
    private func startMicrophone() {
        logger.info("🎤 STARTING MICROPHONE SOURCE via MicAudioManager")
        
        Task {
            await micAudioManager.start()
            
            await MainActor.run {
                if micAudioManager.isRecording {
                    self.isMicrophoneEnabled = true
                    self.updateStatus()
                    
                    // Start processing microphone stream
                    self.startMicrophoneStreamProcessing()
                    
                    // Restart mixed stream if recording
                    if self.isRecording {
                        self.startMixedAudioStream()
                    }
                    
                    self.logger.info("✅ MICROPHONE SOURCE STARTED via MicAudioManager")
                } else {
                    self.statusText = "Failed to start microphone"
                    self.logger.error("❌ MicAudioManager failed to start recording")
                }
            }
        }
    }
    
    private func stopMicrophone() {
        logger.info("🎤 STOPPING MICROPHONE SOURCE via MicAudioManager")
        
        guard isMicrophoneEnabled else { return }
        
        // Stop microphone stream processing
        stopMicrophoneStreamProcessing()
        
        // Stop MicAudioManager
        micAudioManager.stop()
        
        isMicrophoneEnabled = false
        updateStatus()
        
        // Restart mixed stream if recording (will use system audio only)
        if isRecording {
            startMixedAudioStream()
        }
        
        logger.info("✅ MICROPHONE SOURCE STOPPED via MicAudioManager")
    }
    
    // MARK: - Microphone Stream Processing
    
    private func startMicrophoneStreamProcessing() {
        logger.info("🎤 STARTING MICROPHONE STREAM PROCESSING WITH VAD")
        
        microphoneStreamTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let micStreamWithVAD = self.micAudioManager.audioFramesWithVAD()
                
                for try await audioFrame in micStreamWithVAD {
                    guard !Task.isCancelled, self.isRecording, self.isMicrophoneEnabled else { 
                        self.logger.info("🎤 Breaking microphone processing: cancelled=\(Task.isCancelled), recording=\(self.isRecording), enabled=\(self.isMicrophoneEnabled)")
                        break 
                    }
                    
                    self.logger.info("🎤 RECEIVED \(audioFrame.samples.count) samples with VAD: speech=\(audioFrame.isSpeech), rms=\(String(format: "%.4f", audioFrame.rmsEnergy))")
                    
                    // Send audio frame with VAD to speech recognition on main thread
                    DispatchQueue.main.async { [weak self] in
                        self?.speechRecognitionManager.appendAudioBufferWithVAD(audioFrame)
                        self?.logger.info("🎤 Microphone frame sent to speech recognition: \(audioFrame.samples.count) samples, VAD: \(audioFrame.isSpeech)")
                    }
                    
                    // Track speech state transitions
                    self.handleSpeechStateTransition(audioFrame)
                }
                
                self.logger.info("🎤 MICROPHONE STREAM PROCESSING ENDED")
            } catch {
                self.logger.error("🎤 Microphone stream processing error: \(error)")
            }
        }
    }
    
    private func stopMicrophoneStreamProcessing() {
        logger.info("🎤 STOPPING MICROPHONE STREAM PROCESSING")
        microphoneStreamTask?.cancel()
        microphoneStreamTask = nil
    }
    
    // MARK: - Speech State Management
    
    private func handleSpeechStateTransition(_ audioFrame: AudioFrameWithVAD) {
        let isSpeech = audioFrame.isSpeech
        
        // Detect speech state transitions
        if isSpeech != currentSpeechState {
            AudioDebugLogger.shared.logVADTransition(from: currentSpeechState, to: isSpeech)
            
            if isSpeech {
                logger.info("🗣️ \(audioFrame.source.rawValue.uppercased()) SPEECH START detected")
            } else {
                logger.info("🤫 \(audioFrame.source.rawValue.uppercased()) SPEECH END detected")
            }
            currentSpeechState = isSpeech
        }
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
                // Start system audio capture (permission handling is now integrated)
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
                self.speechRecognitionManager.appendAudioBuffer(buffer)
                // Mixed stream VAD processing would go here if needed
            }
        }
        
        logger.info("🎵 MIXED AUDIO STREAM ENDED")
    }
    
    // MARK: - System Audio Processing
    
    private func startSystemAudioProcessing() {
        guard #available(macOS 14.4, *),
              let systemAudioManager = systemAudioManager as? SystemAudioManager else {
            logger.error("💻 System audio manager not available")
            return
        }
        
        logger.info("💻 STARTING SYSTEM AUDIO PROCESSING WITH VAD")
        
        // Create a task to process system audio stream with VAD
        systemAudioStreamTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let systemStreamWithVAD = systemAudioManager.systemAudioStreamWithVAD()
                
                for try await audioFrame in systemStreamWithVAD {
                    guard !Task.isCancelled, self.isRecording, self.isSystemAudioEnabled else { 
                        self.logger.info("💻 Breaking system audio processing: cancelled=\(Task.isCancelled), recording=\(self.isRecording), enabled=\(self.isSystemAudioEnabled)")
                        break 
                    }
                    
                    self.logger.info("💻 RECEIVED \(audioFrame.samples.count) samples with VAD: speech=\(audioFrame.isSpeech), rms=\(String(format: "%.4f", audioFrame.rmsEnergy))")
                    
                    // Send audio frame with VAD to speech recognition on main thread
                    DispatchQueue.main.async { [weak self] in
                        self?.speechRecognitionManager.appendAudioBufferWithVAD(audioFrame)
                        self?.logger.info("💻 System audio frame sent to speech recognition: \(audioFrame.samples.count) samples, VAD: \(audioFrame.isSpeech)")
                    }
                    
                    // Track speech state transitions
                    self.handleSpeechStateTransition(audioFrame)
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
    

    
    // MARK: - Helper Functions
    
    private func updateStatus() {
        let micStatus = isMicrophoneEnabled ? "MIC:ON" : "MIC:OFF"
        let systemStatus = isSystemAudioEnabled ? "SYS:ON" : "SYS:OFF"
        
        self.statusText = "\(micStatus) | \(systemStatus)"
        logger.info("📊 STATUS UPDATE: \(self.statusText)")
    }
    

    
    private func getMicrophoneAudioStream() -> AsyncStream<[Float]> {
        if isMicrophoneEnabled {
            return micAudioManager.audioFrames()
        } else {
            return createEmptyAudioStream()
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

    // MARK: - Public Interface
    
    func clearCaptions() {
        speechRecognitionManager.clearCaptions()
        logger.info("🗑️ CLEARED ALL CAPTIONS")
    }
    
    // MARK: - SpeechRecognitionManagerDelegate
    
    func speechRecognitionDidUpdateTranscription(_ manager: SpeechRecognitionManager, newText: String) {
        // Trigger UI updates by accessing the computed properties
        objectWillChange.send()
    }
    
    func speechRecognitionDidFinalizeSentence(_ manager: SpeechRecognitionManager, sentence: String) {
        logger.info("📝 FINALIZED SENTENCE: \(sentence)")
        objectWillChange.send()
    }
    
    func speechRecognitionDidEncounterError(_ manager: SpeechRecognitionManager, error: Error) {
        logger.error("❌ SPEECH RECOGNITION ERROR: \(error.localizedDescription)")
        statusText = "Recognition error: \(error.localizedDescription)"
    }
    
    func speechRecognitionStatusDidChange(_ manager: SpeechRecognitionManager, status: String) {
        statusText = status
    }
    
}
