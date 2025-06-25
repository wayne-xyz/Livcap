import Foundation
import AVFoundation
import Combine
import os.log

final class AudioCoordinator {
    
    // MARK: - Published Properties
    @Published private(set) var isMicrophoneEnabled = false
    @Published private(set) var isSystemAudioEnabled = false

    // MARK: - Private Properties
    
    // Audio managers
    private let micAudioManager = MicAudioManager()
    private var systemAudioManager: SystemAudioProtocol?
    private var audioMixingService: AudioMixingService?
    
    // Audio source tasks
    private var microphoneStreamTask: Task<Void, Never>?
    private var systemAudioStreamTask: Task<Void, Never>?
    private var mixedAudioStreamTask: Task<Void, Never>?

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
            audioMixingService = AudioMixingService()
        }
    }
    
    // MARK: - Public Control Functions

    func toggleMicrophone() {
        logger.info("🎤 TOGGLE MICROPHONE: \(self.isMicrophoneEnabled) -> \(!self.isMicrophoneEnabled)")
        
        if isMicrophoneEnabled {
            stopMicrophone()
        } else {
            startMicrophone()
        }
    }

    func toggleSystemAudio() {
        logger.info("💻 TOGGLE SYSTEM AUDIO: \(self.isSystemAudioEnabled) -> \(!self.isSystemAudioEnabled)")
        
        if isSystemAudioEnabled {
            stopSystemAudio()
        } else {
            startSystemAudio()
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
                    self.logger.info("✅ MICROPHONE SOURCE STARTED via MicAudioManager")
                } else {
                    self.logger.error("❌ MicAudioManager failed to start recording")
                }
            }
        }
    }
    
    private func stopMicrophone() {
        logger.info("🎤 STOPPING MICROPHONE SOURCE via MicAudioManager")
        
        guard isMicrophoneEnabled else { return }
        
        // Stop MicAudioManager
        micAudioManager.stop()
        isMicrophoneEnabled = false
        
        logger.info("✅ MICROPHONE SOURCE STOPPED via MicAudioManager")
    }

    // MARK: - System Audio Control
    
    private func startSystemAudio() {
        guard !isSystemAudioEnabled else {
            logger.info("💻 System audio already enabled")
            return
        }
        
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
                AudioDebugLogger.shared.logSystemAudioStatus(isEnabled: false, error: error.localizedDescription)
            }
        }
    }
    
    private func stopSystemAudio() {
        logger.info("💻 STOPPING SYSTEM AUDIO SOURCE")
        
        guard isSystemAudioEnabled else { return }
        
        systemAudioManager?.stopCapture()
        audioMixingService?.stopMixing()
        
        isSystemAudioEnabled = false
        logger.info("✅ SYSTEM AUDIO SOURCE STOPPED")
    }
    
    // MARK: - Stream Coordination
    
    func audioFrameStream() -> AsyncStream<AudioFrameWithVAD> {
        AsyncStream { continuation in
            let micStream = micAudioManager.audioFramesWithVAD()
            
            // Task for microphone stream
            self.microphoneStreamTask = Task {
                for await frame in micStream {
                    continuation.yield(frame)
                }
            }
            
            // Task for system audio stream (only if available)
            if #available(macOS 14.4, *) {
                if let systemAudioManager = self.systemAudioManager as? SystemAudioManager {
                    self.systemAudioStreamTask = Task {
                        let systemStream = systemAudioManager.systemAudioStreamWithVAD()
                        for await frame in systemStream {
                            continuation.yield(frame)
                        }
                    }
                }
            }
            
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.microphoneStreamTask?.cancel()
                self?.systemAudioStreamTask?.cancel()
                self?.logger.info("🛑 AudioCoordinator streams terminated.")
            }
        }
    }
} 