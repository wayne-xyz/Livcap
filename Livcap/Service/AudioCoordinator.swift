import Foundation
import AVFoundation
import Combine
import os.log

final class AudioCoordinator: ObservableObject {
    
    // MARK: - Published Properties (Direct Boolean Control)
    @Published private(set) var isMicrophoneEnabled: Bool = false
    @Published private(set) var isSystemAudioEnabled: Bool = false

    // MARK: - Private Properties
    
    // Audio managers
    private let micAudioManager = MicAudioManager()
    private var systemAudioManager: SystemAudioManager?
    
    // Dynamic consumer management
    private var microphoneConsumerTask: Task<Void, Never>?
    private var systemAudioConsumerTask: Task<Void, Never>?

    // Shared continuation for aggregator stream
    private var streamContinuation: AsyncStream<AudioFrameWithVAD>.Continuation?

    // Logging
    private let logger = Logger(subsystem: "com.livcap.audio", category: "AudioCoordinator")
    
    // MARK: - Initialization
    
    init() {
        setupSystemAudioComponents()
    }
    
    // MARK: - Setup
    
    private func setupSystemAudioComponents() {
        // Initialize system audio components only if supported
        if #available(macOS 14.4, *) {
            systemAudioManager = SystemAudioManager()
        }
    }
    
    // Simplified: Direct control methods replace reactive consumers
    
    // MARK: - Public Control Functions
    
    func enableMicrophone() {
        guard !isMicrophoneEnabled else { 
            logger.info("⚡ Microphone already enabled, skipping")
            return 
        }
        
        logger.info("🎤 Enabling microphone")
        startMicrophone()
    }
    
    func disableMicrophone() {
        guard isMicrophoneEnabled else {
            logger.info("⚡ Microphone already disabled, skipping")
            return
        }
        
        logger.info("🎤 Disabling microphone")
        stopMicrophone()
    }
    
    func enableSystemAudio() {
        guard !isSystemAudioEnabled else {
            logger.info("⚡ System audio already enabled, skipping")
            return
        }
        
        logger.info("💻 Enabling system audio")
        startSystemAudio()
    }
    
    func disableSystemAudio() {
        guard isSystemAudioEnabled else {
            logger.info("⚡ System audio already disabled, skipping")
            return
        }
        
        logger.info("💻 Disabling system audio")
        stopSystemAudio()
    }
    
    func toggleMicrophone() {
        if isMicrophoneEnabled {
            disableMicrophone()
        } else {
            enableMicrophone()
        }
    }
    
    func toggleSystemAudio() {
        if isSystemAudioEnabled {
            disableSystemAudio()
        } else {
            enableSystemAudio()
        }
    }


    // MARK: - Microphone Control
    
    private func startMicrophone() {
        logger.info("🎤 STARTING MICROPHONE SOURCE via MicAudioManager")
        
        Task {
            await micAudioManager.start()
            
            await MainActor.run {
                if micAudioManager.isRecording {
                    self.isMicrophoneEnabled = true
                    // Create/replace consumer if aggregator is active
                    self.createMicrophoneConsumer()
                    self.logger.info("✅ MICROPHONE SOURCE STARTED via MicAudioManager")
                } else {
                    self.logger.error("❌ MicAudioManager failed to start recording")
                }
            }
        }
    }
    
    private func stopMicrophone() {
        logger.info("🎤 STOPPING MICROPHONE SOURCE via MicAudioManager")
        
        // Tear down consumer first
        destroyMicrophoneConsumer()
        // Stop MicAudioManager
        micAudioManager.stop()
        isMicrophoneEnabled = false
        
        logger.info("✅ MICROPHONE SOURCE STOPPED via MicAudioManager")
    }

    // MARK: - System Audio Control
    
    private func startSystemAudio() {
        guard #available(macOS 14.4, *) else {
            logger.warning("💻 System audio not supported on this macOS version")
            return
        }
        
        guard let systemAudioManager = systemAudioManager else {
            logger.error("💻 System audio manager not available")
            return
        }
        
        logger.info("💻 STARTING SYSTEM AUDIO SOURCE")
        
        Task {
            do {
                try await systemAudioManager.startCapture()
                
                await MainActor.run {
                    self.isSystemAudioEnabled = true
                    // Create/replace consumer if aggregator is active
                    self.createSystemAudioConsumer()
                    self.logger.info("✅ SYSTEM AUDIO SOURCE STARTED")
                }
                
            } catch {
                await MainActor.run {
                    self.logger.error("❌ System audio start error: \(error)")
                }

            }
        }
    }
    
    private func stopSystemAudio() {
        logger.info("💻 STOPPING SYSTEM AUDIO SOURCE")
        
        // Tear down consumer first
        destroySystemAudioConsumer()
        systemAudioManager?.stopCapture()
        isSystemAudioEnabled = false
        
        logger.info("✅ SYSTEM AUDIO SOURCE STOPPED")
    }
    
    // MARK: - Dynamic Consumer Management
    
    private func createMicrophoneConsumer() {
        // Cancel existing consumer if any
        destroyMicrophoneConsumer()
        
        guard isMicrophoneEnabled else { return }
        guard streamContinuation != nil else { return }
        
        logger.info("🎤 Creating microphone consumer")
        microphoneConsumerTask = Task { [weak self] in
            guard let self = self else { return }
            let micStream = self.micAudioManager.audioFramesWithVAD()
            for await micFrame in micStream {
                if Task.isCancelled { break }
                if self.shouldForwardFrame(micFrame, source: .microphone) {
                    self.streamContinuation?.yield(micFrame)
                }
            }
            self.logger.info("🎤 Microphone consumer ended")
        }
    }
    
    private func destroyMicrophoneConsumer() {
        microphoneConsumerTask?.cancel()
        microphoneConsumerTask = nil
        logger.info("🎤 Microphone consumer destroyed")
    }
    
    private func createSystemAudioConsumer() {
        // Cancel existing consumer if any
        destroySystemAudioConsumer()
        
        guard isSystemAudioEnabled else { return }
        guard streamContinuation != nil else { return }
        
        guard #available(macOS 14.4, *), let systemAudioManager = systemAudioManager else { return }
        
        logger.info("💻 Creating system audio consumer")
        systemAudioConsumerTask = Task { [weak self] in
            guard let self = self else { return }
            let systemStream = systemAudioManager.systemAudioStreamWithVAD()
            for await systemFrame in systemStream {
                if Task.isCancelled { break }
                if self.shouldForwardFrame(systemFrame, source: .systemAudio) {
                    self.streamContinuation?.yield(systemFrame)
                }
            }
            self.logger.info("💻 System audio consumer ended")
        }
    }
    
    private func destroySystemAudioConsumer() {
        systemAudioConsumerTask?.cancel()
        systemAudioConsumerTask = nil
        logger.info("💻 System audio consumer destroyed")
    }
    
    // MARK: - Stream Coordination
    
    func audioFrameStream() -> AsyncStream<AudioFrameWithVAD> {
        AsyncStream { continuation in
            // Store aggregator continuation
            self.streamContinuation = continuation
            self.logger.info("🔌 Aggregator stream created")
            
            // If sources are already active, create consumers now
            if self.isMicrophoneEnabled { self.createMicrophoneConsumer() }
            if self.isSystemAudioEnabled { self.createSystemAudioConsumer() }
            
            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self = self else { return }
                self.destroyMicrophoneConsumer()
                self.destroySystemAudioConsumer()
                self.streamContinuation = nil
                self.logger.info("🛑 Aggregator stream terminated")
            }
        }
    }
    
    // MARK: - Stream Router Logic
    
    private func shouldForwardFrame(_ frame: AudioFrameWithVAD, source: AudioSource) -> Bool {
        switch source {
        case .microphone:
            // Only forward if microphone is enabled
            guard isMicrophoneEnabled else { return false }
            // In dual mode, use VAD; in single mode, forward all
            return isSystemAudioEnabled ? frame.vadResult.isSpeech : true
            
        case .systemAudio:
            // Only forward if system audio is enabled  
            guard isSystemAudioEnabled else { return false }
            // In dual mode, use VAD; in single mode, forward all
            return isMicrophoneEnabled ? frame.vadResult.isSpeech : true
        }
    }
    
    // MARK: - Debug Helper
    
    private func debugLog(_ message: String) {
        #if DEBUG
        logger.debug("\(message)")
        #endif
    }
} 
