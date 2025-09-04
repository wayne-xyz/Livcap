import Foundation
import AVFoundation
import os.log

final class AudioCoordinator: ObservableObject {
    
    // MARK: - Published Properties (Direct Boolean Control)
    @Published private(set) var isMicrophoneEnabled: Bool = false
    @Published private(set) var isSystemAudioEnabled: Bool = false

    // MARK: - Private Properties
    
    // Audio managers
    private let micAudioManager = MicAudioManager()
    private var systemAudioManager: SystemAudioManager?
    
    
    // Simplified stream management
    private var activeAudioStreamTask: Task<Void, Never>?
    

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
    
    // Removed: Complex state update logic replaced with direct control

    // MARK: - Microphone Control
    
    private func startMicrophone() {
        logger.info("🎤 STARTING MICROPHONE SOURCE via MicAudioManager")
        
        Task {
            await micAudioManager.start()
            
            await MainActor.run {
                if micAudioManager.isRecording {
                    self.isMicrophoneEnabled = true
                    self.logger.info("✅ MICROPHONE SOURCE STARTED via MicAudioManager")
                } else {
                    self.logger.error("❌ MicAudioManager failed to start recording")
                }
            }
        }
    }
    
    private func stopMicrophone() {
        logger.info("🎤 STOPPING MICROPHONE SOURCE via MicAudioManager")
        
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
        
        systemAudioManager?.stopCapture()
        isSystemAudioEnabled = false
        
        logger.info("✅ SYSTEM AUDIO SOURCE STOPPED")
    }
    
    // Removed: Complex dynamic consumer management
    
    // MARK: - Stream Coordination
    
    func audioFrameStream() -> AsyncStream<AudioFrameWithVAD> {
        AsyncStream { continuation in
            
            self.activeAudioStreamTask = Task {
                await withTaskGroup(of: Void.self) { group in
                    
                    // Add microphone task if enabled
                    if self.isMicrophoneEnabled {
                        group.addTask {
                            let micStream = self.micAudioManager.audioFramesWithVAD()
                            for await micFrame in micStream {
                                guard !Task.isCancelled else { break }
                                
                                if self.shouldForwardFrame(micFrame, source: .microphone) {
                                    continuation.yield(micFrame)
                                }
                            }
                        }
                    }
                    
                    // Add system audio task if enabled and available
                    if self.isSystemAudioEnabled {
                        if #available(macOS 14.4, *), let systemAudioManager = self.systemAudioManager {
                            group.addTask {
                                let systemStream = systemAudioManager.systemAudioStreamWithVAD()
                                for await systemFrame in systemStream {
                                    guard !Task.isCancelled else { break }
                                    
                                    if self.shouldForwardFrame(systemFrame, source: .systemAudio) {
                                        continuation.yield(systemFrame)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Wait for all tasks
                    await group.waitForAll()
                }
            }
            
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.activeAudioStreamTask?.cancel()
                self?.logger.info("🛑 AudioCoordinator stream terminated.")
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
