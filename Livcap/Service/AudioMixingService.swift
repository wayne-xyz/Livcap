//
//  AudioMixingService.swift
//  Livcap
//
//  Real-time audio mixing service for combining microphone and system audio streams
//

import Foundation
import AVFoundation
import Accelerate
import OSLog
import Combine

class AudioMixingService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isActive = false
    @Published private(set) var microphoneLevel: Float = 0.0
    @Published private(set) var systemAudioLevel: Float = 0.0
    @Published private(set) var mixedAudioLevel: Float = 0.0
    
    // MARK: - Configuration
    
    struct MixingConfig {
        var microphoneGain: Float = 1.0      // Microphone volume multiplier
        var systemAudioGain: Float = 0.7     // System audio volume multiplier (lower to avoid feedback)
        var enableAGC: Bool = true           // Automatic Gain Control
        var maxLevel: Float = 0.95           // Maximum output level to prevent clipping
        var sampleRate: Double = 16000.0     // Target sample rate
        var bufferSize: Int = 1600           // 100ms at 16kHz
    }
    
    @Published var config = MixingConfig()
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livcap.audiomixer", category: "AudioMixingService")
    private let processingQueue = DispatchQueue(label: "AudioMixing", qos: .userInitiated)
    
    // Audio streams
    private var microphoneStreamTask: Task<Void, Error>?
    private var systemAudioStreamTask: Task<Void, Error>?
    
    // Buffer management
    private actor BufferSynchronizer {
        private var microphoneBuffer: [Float] = []
        private var systemAudioBuffer: [Float] = []
        private let maxBufferSize: Int = 3200 // 200ms buffer
        
        func addMicrophoneData(_ samples: [Float]) -> ([Float], [Float])? {
            microphoneBuffer.append(contentsOf: samples)
            return tryMixBuffers()
        }
        
        func addSystemAudioData(_ samples: [Float]) -> ([Float], [Float])? {
            systemAudioBuffer.append(contentsOf: samples)
            return tryMixBuffers()
        }
        
        private func tryMixBuffers() -> ([Float], [Float])? {
            let targetSize = 1600 // 100ms at 16kHz
            
            // Check if we have enough data from both sources
            guard microphoneBuffer.count >= targetSize && systemAudioBuffer.count >= targetSize else {
                // Trim buffers if they get too large
                if microphoneBuffer.count > maxBufferSize {
                    microphoneBuffer.removeFirst(microphoneBuffer.count - maxBufferSize)
                }
                if systemAudioBuffer.count > maxBufferSize {
                    systemAudioBuffer.removeFirst(systemAudioBuffer.count - maxBufferSize)
                }
                return nil
            }
            
            // Extract samples for mixing
            let micSamples = Array(microphoneBuffer.prefix(targetSize))
            let systemSamples = Array(systemAudioBuffer.prefix(targetSize))
            
            // Remove used samples
            microphoneBuffer.removeFirst(targetSize)
            systemAudioBuffer.removeFirst(targetSize)
            
            return (micSamples, systemSamples)
        }
        
        func reset() {
            microphoneBuffer.removeAll()
            systemAudioBuffer.removeAll()
        }
    }
    
    private let bufferSynchronizer = BufferSynchronizer()
    
    // Output stream
    private var mixedAudioContinuation: AsyncStream<[Float]>.Continuation?
    private var _mixedAudioStream: AsyncStream<[Float]>?
    
    // MARK: - Initialization
    
    init() {
        logger.info("AudioMixingService initialized")
    }
    
    deinit {
        stopMixing()
    }
    
    // MARK: - Public Interface
    
    /// Start mixing audio streams
    func startMixing(
        microphoneStream: AsyncStream<[Float]>,
        systemAudioStream: AsyncStream<[Float]>
    ) {
        guard !isActive else {
            logger.warning("Audio mixing already active")
            return
        }
        
        logger.info("Starting audio mixing")
        
        // Reset synchronizer
        Task {
            await bufferSynchronizer.reset()
        }
        
        // Start processing both streams
        startMicrophoneProcessing(microphoneStream)
        startSystemAudioProcessing(systemAudioStream)
        
        isActive = true
        logger.info("Audio mixing started")
    }
    
    /// Stop mixing audio streams
    func stopMixing() {
        guard isActive else { return }
        
        logger.info("Stopping audio mixing")
        
        // Cancel stream processing tasks
        microphoneStreamTask?.cancel()
        systemAudioStreamTask?.cancel()
        microphoneStreamTask = nil
        systemAudioStreamTask = nil
        
        // Close output stream
        mixedAudioContinuation?.finish()
        mixedAudioContinuation = nil
        _mixedAudioStream = nil
        
        // Reset levels
        Task { @MainActor in
            self.microphoneLevel = 0.0
            self.systemAudioLevel = 0.0
            self.mixedAudioLevel = 0.0
            self.isActive = false
        }
        
        logger.info("Audio mixing stopped")
    }
    
    /// Get mixed audio stream for speech recognition
    func mixedAudioStream() -> AsyncStream<[Float]> {
        if let stream = _mixedAudioStream {
            return stream
        }
        
        let stream = AsyncStream<[Float]> { continuation in
            self.mixedAudioContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopMixing()
            }
        }
        
        self._mixedAudioStream = stream
        return stream
    }
    
    // MARK: - Stream Processing
    
    private func startMicrophoneProcessing(_ stream: AsyncStream<[Float]>) {
        microphoneStreamTask = Task { [weak self] in
            guard let self = self else { return }
            
            for try await samples in stream {
                // Update microphone level
                let level = calculateRMS(samples)
                await MainActor.run {
                    self.microphoneLevel = level
                }
                
                // Add to buffer synchronizer
                if let mixedSamples = await self.bufferSynchronizer.addMicrophoneData(samples) {
                    self.processMixedAudio(micSamples: mixedSamples.0, systemSamples: mixedSamples.1)
                }
            }
        }
    }
    
    private func startSystemAudioProcessing(_ stream: AsyncStream<[Float]>) {
        systemAudioStreamTask = Task { [weak self] in
            guard let self = self else { return }
            
            for try await samples in stream {
                // Update system audio level
                let level = calculateRMS(samples)
                await MainActor.run {
                    self.systemAudioLevel = level
                }
                
                // Add to buffer synchronizer
                if let mixedSamples = await self.bufferSynchronizer.addSystemAudioData(samples) {
                    self.processMixedAudio(micSamples: mixedSamples.0, systemSamples: mixedSamples.1)
                }
            }
        }
    }
    
    // MARK: - Audio Mixing Algorithm
    
    private func processMixedAudio(micSamples: [Float], systemSamples: [Float]) {
        guard micSamples.count == systemSamples.count else {
            logger.warning("Sample count mismatch: mic=\(micSamples.count), system=\(systemSamples.count)")
            return
        }
        
        // Apply mixing algorithm
        let mixedSamples = mixAudioSamples(micSamples: micSamples, systemSamples: systemSamples)
        
        // Update mixed audio level
        let mixedLevel = calculateRMS(mixedSamples)
        Task { @MainActor in
            self.mixedAudioLevel = mixedLevel
        }
        
        // Log mixed audio buffer info
        AudioDebugLogger.shared.logBufferData(
            source: .mixed,
            bufferSize: mixedSamples.count,
            duration: Double(mixedSamples.count) / config.sampleRate
        )
        
        // Send mixed audio to output stream
        mixedAudioContinuation?.yield(mixedSamples)
    }
    
    private func mixAudioSamples(micSamples: [Float], systemSamples: [Float]) -> [Float] {
        var mixedSamples = [Float](repeating: 0.0, count: micSamples.count)
        
        // Apply gains and mix
        for i in 0..<micSamples.count {
            let micSample = micSamples[i] * config.microphoneGain
            let systemSample = systemSamples[i] * config.systemAudioGain
            
            // Simple additive mixing
            var mixed = micSample + systemSample
            
            // Apply AGC if enabled
            if config.enableAGC {
                mixed = applyAGC(mixed)
            }
            
            // Prevent clipping
            mixed = max(-config.maxLevel, min(config.maxLevel, mixed))
            
            mixedSamples[i] = mixed
        }
        
        return mixedSamples
    }
    
    // MARK: - Audio Processing Utilities
    
    private func applyAGC(_ sample: Float) -> Float {
        // Simple AGC: soft limiting using tanh
        let threshold: Float = 0.7
        if abs(sample) > threshold {
            let sign: Float = sample >= 0 ? 1.0 : -1.0
            return sign * threshold * tanh(abs(sample) / threshold)
        }
        return sample
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    // MARK: - Configuration Updates
    
    func updateMicrophoneGain(_ gain: Float) {
        self.config.microphoneGain = max(0.0, min(2.0, gain)) // Clamp between 0 and 2
        logger.info("Microphone gain updated to: \(self.config.microphoneGain)")
    }
    
    func updateSystemAudioGain(_ gain: Float) {
        self.config.systemAudioGain = max(0.0, min(2.0, gain)) // Clamp between 0 and 2
        logger.info("System audio gain updated to: \(self.config.systemAudioGain)")
    }
    
    func toggleAGC() {
        self.config.enableAGC.toggle()
        logger.info("AGC \(self.config.enableAGC ? "enabled" : "disabled")")
    }
    
    // MARK: - Monitoring
    
    func getAudioLevels() -> (microphone: Float, systemAudio: Float, mixed: Float) {
        return (microphoneLevel, systemAudioLevel, mixedAudioLevel)
    }
    
    func getMixingStats() -> MixingStats {
        return MixingStats(
            isActive: isActive,
            microphoneGain: config.microphoneGain,
            systemAudioGain: config.systemAudioGain,
            agcEnabled: config.enableAGC,
            microphoneLevel: microphoneLevel,
            systemAudioLevel: systemAudioLevel,
            mixedAudioLevel: mixedAudioLevel
        )
    }
}

// MARK: - Supporting Types

struct MixingStats {
    let isActive: Bool
    let microphoneGain: Float
    let systemAudioGain: Float
    let agcEnabled: Bool
    let microphoneLevel: Float
    let systemAudioLevel: Float
    let mixedAudioLevel: Float
    
    var microphoneLevelString: String {
        return String(format: "%.3f", microphoneLevel)
    }
    
    var systemAudioLevelString: String {
        return String(format: "%.3f", systemAudioLevel)
    }
    
    var mixedAudioLevelString: String {
        return String(format: "%.3f", mixedAudioLevel)
    }
}

// MARK: - Convenience Extensions

extension AsyncStream where Element == [Float] {
    /// Create a microphone-only stream (for backward compatibility)
    static func microphoneOnly(_ stream: AsyncStream<[Float]>) -> AsyncStream<[Float]> {
        return stream
    }
    
    /// Create a system-audio-only stream
    static func systemAudioOnly(_ stream: AsyncStream<[Float]>) -> AsyncStream<[Float]> {
        return stream
    }
} 