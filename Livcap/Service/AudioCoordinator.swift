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
    
    // Audio source task (only one active at a time)
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
    
    // MARK: - Public Control Functions

    func toggleMicrophone() {
        logger.info("🎤 TOGGLE MICROPHONE: \(self.isMicrophoneEnabled) -> \(!self.isMicrophoneEnabled)")
        
        if isMicrophoneEnabled {
            stopMicrophone()
        } else {
            // Stop system audio first if it's running
            if isSystemAudioEnabled {
                stopSystemAudio()
            }
            startMicrophone()
        }
    }

    func toggleSystemAudio() {
        logger.info("💻 TOGGLE SYSTEM AUDIO: \(self.isSystemAudioEnabled) -> \(!self.isSystemAudioEnabled)")
        
        if isSystemAudioEnabled {
            stopSystemAudio()
        } else {
            // Stop microphone first if it's running
            if isMicrophoneEnabled {
                stopMicrophone()
            }
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

            }
        }
    }
    
    private func stopSystemAudio() {
        logger.info("💻 STOPPING SYSTEM AUDIO SOURCE")
        
        guard isSystemAudioEnabled else { return }
        
        systemAudioManager?.stopCapture()
        
        isSystemAudioEnabled = false
        logger.info("✅ SYSTEM AUDIO SOURCE STOPPED")
    }
    
    // MARK: - Stream Coordination
    
    func audioFrameStream() -> AsyncStream<AudioFrameWithVAD> {
        AsyncStream { continuation in
            
            // Create a task that switches between sources based on which is active
            self.activeAudioStreamTask = Task {
                while !Task.isCancelled {
                    if self.isMicrophoneEnabled {
                        let micStream = self.micAudioManager.audioFramesWithVAD()
                        for await frame in micStream {
                            if Task.isCancelled { break }
                            debugLog("Audio frame sending from the audioconductor: \(frame.vadResult)")
                            continuation.yield(frame)
                        }
                    } else if self.isSystemAudioEnabled {
                        if #available(macOS 14.4, *) {
                            if let systemAudioManager = self.systemAudioManager as? SystemAudioManager {
                                let systemStream = systemAudioManager.systemAudioStreamWithVAD()
                                for await frame in systemStream {
                                    if Task.isCancelled { break }
                                    continuation.yield(frame)
                                }
                            }
                        }
                    }
                    
                    // Small delay before checking again if no source is active
                    if !self.isMicrophoneEnabled && !self.isSystemAudioEnabled {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                }
            }
            
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.activeAudioStreamTask?.cancel()
                self?.logger.info("🛑 AudioCoordinator stream terminated.")
            }
        }
    }
} 
