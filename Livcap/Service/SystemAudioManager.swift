//
//  SystemAudioManager.swift
//  Livcap
//
//  System audio capture using CoreAudioTapEngine for system-wide audio capture (macOS 14.4+)
//

import Foundation
import AudioToolbox
import AVFoundation
import OSLog
import Combine
import AppKit

@available(macOS 14.4, *)
class SystemAudioManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var systemAudioLevel: Float = 0.0
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livcap.systemaudio", category: "SystemAudioManager")
    
    // Engine Integration - Use CoreAudioTapEngine AS-IS
    private var tapEngine: CoreAudioTapEngine?
    
    // VAD Processing - Manager Level
    private let vadProcessor = VADProcessor()
    private var frameCounter: Int = 0
    
    // Enhanced audio stream with VAD - Manager Level
    private var vadAudioStreamContinuation: AsyncStream<AudioFrameWithVAD>.Continuation?
    private var vadAudioStream: AsyncStream<AudioFrameWithVAD>?
    
    // Legacy audio stream for compatibility
    private var audioBufferContinuation: AsyncStream<[Float]>.Continuation?
    private var audioStream: AsyncStream<[Float]>?
    
    // MARK: - Initialization
    
    init() {
        logger.info("SystemAudioManager initialized for system-wide audio capture using CoreAudioTapEngine")
    }
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Public Interface
    
    /// Start system-wide audio capture
    func startCapture() async throws {
        guard !isCapturing else {
            logger.warning("System audio capture already running")
            return
        }
        
        logger.info("Starting system-wide audio capture...")
        
        do {
            try await setupSystemWideAudioCapture()
            
            await MainActor.run {
                self.isCapturing = true
                self.errorMessage = nil
            }
            
            logger.info("System-wide audio capture started successfully")
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to start system audio capture: \(error.localizedDescription)")
            
            throw error
        }
    }
    
    /// Stop system audio capture
    func stopCapture() {
        guard isCapturing else { return }
        
        logger.info("Stopping system audio capture...")
        
        cleanup()
        
        Task { @MainActor in
            self.isCapturing = false
            self.systemAudioLevel = 0.0
        }
        
        logger.info("System audio capture stopped")
    }
    
    /// Get system audio stream (legacy compatibility)
    func systemAudioStream() -> AsyncStream<[Float]> {
        if let stream = audioStream {
            return stream
        }
        
        let stream = AsyncStream<[Float]> { continuation in
            self.audioBufferContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopCapture()
            }
        }
        
        self.audioStream = stream
        return stream
    }
    
    /// Get enhanced system audio stream with VAD metadata
    func systemAudioStreamWithVAD() -> AsyncStream<AudioFrameWithVAD> {
        if let stream = vadAudioStream {
            return stream
        }
        
        let stream = AsyncStream<AudioFrameWithVAD> { continuation in
            self.vadAudioStreamContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopCapture()
            }
        }
        
        self.vadAudioStream = stream
        return stream
    }
    
    // MARK: - System-Wide Audio Capture Setup
    
    private func setupSystemWideAudioCapture() async throws {
        // Clean up any existing engine
        cleanup()
        
        // Get all system processes using AudioProcessSupplier
        let processSupplier = AudioProcessSupplier()
        let allProcesses = try processSupplier.getProcesses(mode: .all)
        
        guard !allProcesses.isEmpty else {
            throw CoreAudioTapEngineError.noTargetProcesses
        }
        
        logger.info("🎯 Found \(allProcesses.count) system audio processes for capture")
        
        // Initialize CoreAudioTapEngine with all system processes
        tapEngine = CoreAudioTapEngine(forProcesses: allProcesses)
        
        // CRITICAL: Get the audio stream BEFORE starting the engine
        // This creates the streamContinuation that the engine needs during start()
        guard let engine = tapEngine else { throw CoreAudioTapEngineError.noTargetProcesses }
        let audioStream = try engine.coreAudioTapStream()
        
        // Now start the engine - it will use the streamContinuation we just created
        try await engine.start()
        
        // Start processing the audio stream we obtained earlier
        processEngineOutput(audioStream: audioStream)
    }
    
    // MARK: - Manager-Level Audio Processing
    
    private func processEngineOutput(audioStream: AsyncStream<AVAudioPCMBuffer>) {
        Task {
            do {
                for await buffer in audioStream {
                    // Manager-level audio processing
                    await processAudioBuffer(buffer)
                }
            } catch {
                logger.error("Failed to process engine output: \(error)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        // Audio level monitoring - Manager Level
        let rms = calculateRMS(from: buffer)
        await MainActor.run {
            self.systemAudioLevel = rms
        }
        
        // VAD processing - Manager Level (use engine buffer directly)
        frameCounter += 1
        let vadResult = vadProcessor.processAudioBuffer(buffer)
        
        // Create enhanced frame - Manager Level
        let audioFrame = AudioFrameWithVAD(
            buffer: buffer,  // Use engine buffer directly (already 16kHz mono)
            vadResult: vadResult,
            source: .systemAudio,
            frameIndex: frameCounter
        )
        
        // Yield enhanced frame to VAD stream
        vadAudioStreamContinuation?.yield(audioFrame)
        
        // Legacy compatibility: extract float samples for legacy stream
        if let continuation = audioBufferContinuation {
            let samples = extractFloatSamples(from: buffer)
            continuation.yield(samples)
        }
    }
    
    // MARK: - Audio Utilities
    
    private func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameCount = Int(buffer.frameLength)
        
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        return sqrt(sum / Float(frameCount))
    }
    
    private func extractFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameCount = Int(buffer.frameLength)
        
        return Array(UnsafeBufferPointer(start: channelData, count: frameCount))
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        // Stop engine
        tapEngine?.stop()
        tapEngine = nil
        
        // Close audio streams
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        audioStream = nil
        
        vadAudioStreamContinuation?.finish()
        vadAudioStreamContinuation = nil
        vadAudioStream = nil
        
        // Reset VAD state
        vadProcessor.reset()
        frameCounter = 0
        
        logger.info("System audio manager cleanup completed")
    }
    
    // MARK: - Utilities
    
    private func updateErrorMessage(_ message: String) {
        Task { @MainActor in
            self.errorMessage = message
        }
    }
}
