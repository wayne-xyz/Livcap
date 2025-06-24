//
//  WhisperLiveContinuousManager.swift
//  Livcap
//
//  WhisperLive-inspired continuous stream manager
//  - Uses 30s continuous buffer instead of 5s sliding windows
//  - Always triggers inference every 1s regardless of content
//  - Integrates with WhisperLiveAudioBuffer for optimal context
//

import Foundation
import Combine

struct WhisperLiveStreamConfig {
    let chunkSizeMs: Int = 100              // 100ms chunks (consistent with current)
    let sampleRate: Int = 16000             // 16kHz sampling rate
    let maxBufferSizeMs: Int = 30000        // 30 second continuous buffer
    let inferenceIntervalMs: Int = 1000     // Always infer every 1 second
    let minBufferForInference: Int = 1000   // Minimum 1s buffer before first inference
    
    var samplesPerChunk: Int {
        return (sampleRate * chunkSizeMs) / 1000  // 1600 samples per 100ms
    }
    
    var inferenceIntervalSamples: Int {
        return (sampleRate * inferenceIntervalMs) / 1000  // 16000 samples per second
    }
    
    var minSamplesForInference: Int {
        return (sampleRate * minBufferForInference) / 1000  // 16000 samples minimum
    }
}

struct WhisperLiveAudioChunk: Sendable {
    let audio: [Float]
    let chunkIndex: Int
    let timestampMs: Int
    let id: UUID
    let bufferDurationMs: Int          // Current total buffer duration
    let shouldTriggerInference: Bool   // Always true every 1s
    let bufferGrowthPhase: String      // "building", "steady_state", etc.
}

struct WhisperLiveMetrics: Sendable {
    let totalChunksProcessed: Int
    let totalInferencesTriggered: Int
    let averageChunkProcessingTimeMs: Double
    let currentBufferDurationMs: Int
    let bufferGrowthPhase: String
    let speechPercentage: Float
    let bufferTrimCount: Int
    let inferenceFrequency: Float       // Should be ~1.0 Hz
}

actor WhisperLiveContinuousManager {
    private let config = WhisperLiveStreamConfig()
    private let audioBuffer = WhisperLiveAudioBuffer()
    
    // State tracking
    private var chunkCounter: Int = 0
    private var totalSamplesProcessed: Int = 0
    private var lastInferenceTime: Int = 0
    private var streamStartTime: Date = Date()
    
    // Metrics
    private var totalChunksProcessed: Int = 0
    private var totalInferencesTriggered: Int = 0
    private var chunkProcessingTimes: [Double] = []
    
    // Publishers for monitoring
    nonisolated let chunkPublisher = PassthroughSubject<WhisperLiveAudioChunk, Error>()
    nonisolated let inferencePublisher = PassthroughSubject<WhisperLiveAudioChunk, Error>()
    nonisolated let metricsPublisher = PassthroughSubject<WhisperLiveMetrics, Never>()
    nonisolated let bufferStatePublisher = PassthroughSubject<BufferStats, Never>()
    
    init() {
        print("WhisperLiveContinuousManager initialized:")
        print("- Chunk size: \(config.chunkSizeMs)ms (\(config.samplesPerChunk) samples)")
        print("- Max buffer: \(config.maxBufferSizeMs)ms (30 seconds)")
        print("- Inference interval: \(config.inferenceIntervalMs)ms (every 1 second)")
        print("- Strategy: Continuous 30s buffer with 1s inference triggers")
    }
    
    func processAudioChunk(_ samples: [Float]) async {
        let startTime = Date()
        let currentTimeMs = Int(Date().timeIntervalSince(streamStartTime) * 1000)
        
        // Add chunk to continuous buffer (no VAD filtering here)
        await MainActor.run {
            audioBuffer.addAudioChunk(samples)
        }
        
        totalSamplesProcessed += samples.count
        
        // Debug logging for significant milestones
        if chunkCounter < 5 || chunkCounter % 50 == 0 {
            let bufferStats = await MainActor.run { audioBuffer.getBufferStats() }
            print("📦 WhisperLive Chunk #\(chunkCounter): \(samples.count) samples, buffer: \(bufferStats.durationString)")
        }
        
        // Determine if inference should be triggered (every 1 second)
        let shouldTriggerInference = await shouldTriggerInference(currentTimeMs: currentTimeMs)
        
        // Get current buffer state
        let bufferStats = await MainActor.run { audioBuffer.getBufferStats() }
        
        // Create chunk for monitoring
        let chunk = WhisperLiveAudioChunk(
            audio: samples,
            chunkIndex: chunkCounter,
            timestampMs: currentTimeMs,
            id: UUID(),
            bufferDurationMs: Int(bufferStats.duration * 1000),
            shouldTriggerInference: shouldTriggerInference,
            bufferGrowthPhase: await MainActor.run { audioBuffer.growthPhase.rawValue }
        )
        
        chunkCounter += 1
        totalChunksProcessed += 1
        
        // Publish chunk for monitoring
        chunkPublisher.send(chunk)
        
        // Publish buffer state updates
        bufferStatePublisher.send(bufferStats)
        
        // Handle inference trigger
        if shouldTriggerInference {
            await handleInferenceTrigger(currentTimeMs: currentTimeMs, bufferStats: bufferStats)
        }
        
        // Update processing metrics
        let processingTime = Date().timeIntervalSince(startTime) * 1000  // ms
        chunkProcessingTimes.append(processingTime)
        if chunkProcessingTimes.count > 100 {
            chunkProcessingTimes.removeFirst()
        }
        
        await publishMetrics(bufferStats: bufferStats)
    }
    
    private func shouldTriggerInference(currentTimeMs: Int) async -> Bool {
        // Check if enough time has passed (1 second interval)
        let timeSinceLastInference = currentTimeMs - lastInferenceTime
        let timeCondition = timeSinceLastInference >= config.inferenceIntervalMs
        
        // Check if we have minimum buffer for inference
        let bufferStats = await MainActor.run { audioBuffer.getBufferStats() }
        let bufferCondition = bufferStats.sampleCount >= config.minSamplesForInference
        
        let shouldTrigger = timeCondition && bufferCondition
        
        // Debug logging for inference decisions
        if currentTimeMs % 5000 < 100 {  // Log every 5 seconds
            print("🔍 Inference Check - Time: \(currentTimeMs)ms, Last: \(lastInferenceTime)ms, Buffer: \(bufferStats.durationString)")
        }
        
        if shouldTrigger {
            print("⏰ WhisperLive Inference triggered at \(currentTimeMs)ms - Buffer: \(bufferStats.durationString)")
        }
        
        return shouldTrigger
    }
    
    private func handleInferenceTrigger(currentTimeMs: Int, bufferStats: BufferStats) async {
        // Get complete buffer for transcription
        let fullBuffer = await MainActor.run { audioBuffer.getFullBuffer() }
        
        guard !fullBuffer.isEmpty else {
            print("⚠️ Cannot trigger inference: buffer is empty")
            return
        }
        
        // Create inference chunk with full buffer
        let inferenceChunk = WhisperLiveAudioChunk(
            audio: fullBuffer,
            chunkIndex: chunkCounter,
            timestampMs: currentTimeMs,
            id: UUID(),
            bufferDurationMs: Int(bufferStats.duration * 1000),
            shouldTriggerInference: true,
            bufferGrowthPhase: await MainActor.run { audioBuffer.growthPhase.rawValue }
        )
        
        lastInferenceTime = currentTimeMs
        totalInferencesTriggered += 1
        
        print("🎯 WhisperLive Inference: \(String(format: "%.1f", bufferStats.duration))s buffer (\(fullBuffer.count) samples)")
        
        // Publish for transcription processing
        inferencePublisher.send(inferenceChunk)
    }
    
    private func publishMetrics(bufferStats: BufferStats) async {
        let currentBufferMs = Int(bufferStats.duration * 1000)
        let avgProcessingTime = chunkProcessingTimes.isEmpty ? 0.0 : 
            chunkProcessingTimes.reduce(0, +) / Double(chunkProcessingTimes.count)
        
        // Calculate inference frequency (should be ~1.0 Hz in steady state)
        let elapsedTime = Date().timeIntervalSince(streamStartTime)
        let inferenceFrequency = elapsedTime > 0 ? Float(totalInferencesTriggered) / Float(elapsedTime) : 0.0
        
        let metrics = WhisperLiveMetrics(
            totalChunksProcessed: totalChunksProcessed,
            totalInferencesTriggered: totalInferencesTriggered,
            averageChunkProcessingTimeMs: avgProcessingTime,
            currentBufferDurationMs: currentBufferMs,
            bufferGrowthPhase: await MainActor.run { audioBuffer.growthPhase.rawValue },
            speechPercentage: bufferStats.speechPercentage,
            bufferTrimCount: bufferStats.trimCount,
            inferenceFrequency: inferenceFrequency
        )
        
        metricsPublisher.send(metrics)
    }
    
    // MARK: - Public Interface
    
    func reset() async {
        await MainActor.run {
            audioBuffer.reset()
        }
        
        chunkCounter = 0
        totalSamplesProcessed = 0
        lastInferenceTime = 0
        streamStartTime = Date()
        totalChunksProcessed = 0
        totalInferencesTriggered = 0
        chunkProcessingTimes.removeAll()
        
        print("WhisperLiveContinuousManager: Reset complete")
    }
    
    func getCurrentMetrics() async -> WhisperLiveMetrics {
        let bufferStats = await MainActor.run { audioBuffer.getBufferStats() }
        let currentBufferMs = Int(bufferStats.duration * 1000)
        let avgProcessingTime = chunkProcessingTimes.isEmpty ? 0.0 : 
            chunkProcessingTimes.reduce(0, +) / Double(chunkProcessingTimes.count)
        
        let elapsedTime = Date().timeIntervalSince(streamStartTime)
        let inferenceFrequency = elapsedTime > 0 ? Float(totalInferencesTriggered) / Float(elapsedTime) : 0.0
        
        return WhisperLiveMetrics(
            totalChunksProcessed: totalChunksProcessed,
            totalInferencesTriggered: totalInferencesTriggered,
            averageChunkProcessingTimeMs: avgProcessingTime,
            currentBufferDurationMs: currentBufferMs,
            bufferGrowthPhase: await MainActor.run { audioBuffer.growthPhase.rawValue },
            speechPercentage: bufferStats.speechPercentage,
            bufferTrimCount: bufferStats.trimCount,
            inferenceFrequency: inferenceFrequency
        )
    }
    
    func getBufferStats() async -> BufferStats {
        return await MainActor.run { audioBuffer.getBufferStats() }
    }
    
    func getFullAudioBuffer() async -> [Float] {
        return await MainActor.run { audioBuffer.getFullBuffer() }
    }
    
    // MARK: - Stream Creation Methods (Compatible with existing code)
    
    func getStreamingWindow<S: AsyncSequence>(_ frames: S) -> AsyncStream<WhisperLiveAudioChunk> where S.Element == [Float] {
        AsyncStream { continuation in
            Task {
                do {
                    for try await frame in frames {
                        await self.processAudioChunk(frame)
                        try Task.checkCancellation()
                    }
                    print("WhisperLiveContinuousManager: Audio stream finished")
                    continuation.finish()
                } catch {
                    print("WhisperLiveContinuousManager Error: \(error)")
                    continuation.finish()
                }
            }
        }
    }
    
    func getInferenceTriggers<S: AsyncSequence>(_ frames: S) -> AsyncStream<WhisperLiveAudioChunk> where S.Element == [Float] {
        AsyncStream { continuation in
            Task {
                // Subscribe to inference publisher
                let cancellable = inferencePublisher.sink(
                    receiveCompletion: { _ in continuation.finish() },
                    receiveValue: { chunk in continuation.yield(chunk) }
                )
                
                // Process frames to trigger the publisher
                do {
                    for try await frame in frames {
                        await self.processAudioChunk(frame)
                        try Task.checkCancellation()
                    }
                } catch {
                    print("WhisperLiveContinuousManager Inference Error: \(error)")
                }
                
                cancellable.cancel()
                continuation.finish()
            }
        }
    }
}