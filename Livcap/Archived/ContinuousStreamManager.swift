//
//  ContinuousStreamManager.swift
//  Livcap
//
//  Created for Phase 1 WhisperLive Implementation
//

import Foundation
import Combine

struct ContinuousStreamConfig {
    let chunkSizeMs: Int = 100          // 100ms chunks (WhisperLive style)
    let sampleRate: Int = 16000         // 16kHz sampling rate
    let bufferSizeMs: Int = 5000        // 5 second sliding window (max context for inference)
    let overlapMs: Int = 1000           // 1 second minimum buffer before transcription
    let transcriptionTriggerMs: Int = 1000  // Trigger transcription every 1 second (move stride)
    
    var samplesPerChunk: Int {
        return (sampleRate * chunkSizeMs) / 1000  // 1600 samples per 100ms
    }
    
    var bufferSizeInSamples: Int {
        return (sampleRate * bufferSizeMs) / 1000  // 80000 samples for 5 seconds
    }
    
    var overlapSizeInSamples: Int {
        return (sampleRate * overlapMs) / 1000  // 16000 samples for 1 second
    }
    
    var transcriptionTriggerSamples: Int {
        return (sampleRate * transcriptionTriggerMs) / 1000  // 16000 samples for 1 second
    }
}

struct ContinuousAudioChunk: Sendable {
    let audio: [Float]
    let chunkIndex: Int
    let timestampMs: Int
    let id: UUID
    let isTranscriptionTrigger: Bool
}

struct StreamingMetrics: Sendable {
    let totalChunksProcessed: Int
    let totalTranscriptionsTriggered: Int
    let averageChunkProcessingTimeMs: Double
    let bufferUtilization: Float
    let currentBufferSizeMs: Int
}

actor ContinuousStreamManager {
    private let config = ContinuousStreamConfig()
    private var slidingBuffer: [Float] = []
    private var chunkCounter: Int = 0
    private var totalSamplesProcessed: Int = 0
    private var lastTranscriptionTriggerTime: Int = 0
    private var streamStartTime: Date = Date()
    
    // Metrics
    private var totalChunksProcessed: Int = 0
    private var totalTranscriptionsTriggered: Int = 0
    private var chunkProcessingTimes: [Double] = []
    
    // Publishers for monitoring
    nonisolated let chunkPublisher = PassthroughSubject<ContinuousAudioChunk, Error>()
    nonisolated let transcriptionTriggerPublisher = PassthroughSubject<ContinuousAudioChunk, Error>()
    nonisolated let metricsPublisher = PassthroughSubject<StreamingMetrics, Never>()
    
    init() {
        print("ContinuousStreamManager initialized with config:")
        print("- Chunk size: \(config.chunkSizeMs)ms (\(config.samplesPerChunk) samples)")
        print("- Buffer size: \(config.bufferSizeMs)ms (\(config.bufferSizeInSamples) samples)")
        print("- Overlap: \(config.overlapMs)ms (\(config.overlapSizeInSamples) samples)")
        print("- Transcription trigger: \(config.transcriptionTriggerMs)ms (1s stride, 4s overlap)")
    }
    
    func processAudioChunk(_ samples: [Float]) async {
        let startTime = Date()
        
        // Add samples to sliding buffer
        slidingBuffer.append(contentsOf: samples)
        totalSamplesProcessed += samples.count
        
        // Debug logging for first few chunks and periodically
        if chunkCounter < 5 || chunkCounter % 50 == 0 {
            print("📦 Chunk #\(chunkCounter): \(samples.count) samples, buffer now: \(slidingBuffer.count) samples")
        }
        
        // Maintain sliding window size
        if slidingBuffer.count > config.bufferSizeInSamples {
            let excessSamples = slidingBuffer.count - config.bufferSizeInSamples
            slidingBuffer.removeFirst(excessSamples)
        }
        
        // Create chunk for monitoring
        let currentTimeMs = Int(Date().timeIntervalSince(streamStartTime) * 1000)
        let shouldTriggerTranscription = shouldTriggerTranscription(currentTimeMs: currentTimeMs)
        
        let chunk = ContinuousAudioChunk(
            audio: samples,
            chunkIndex: chunkCounter,
            timestampMs: currentTimeMs,
            id: UUID(),
            isTranscriptionTrigger: shouldTriggerTranscription
        )
        
        chunkCounter += 1
        totalChunksProcessed += 1
        
        // Publish chunk for monitoring
        chunkPublisher.send(chunk)
        
        // Handle transcription trigger
        if shouldTriggerTranscription {
            await handleTranscriptionTrigger(currentTimeMs: currentTimeMs)
        }
        
        // Update metrics
        let processingTime = Date().timeIntervalSince(startTime) * 1000  // ms
        chunkProcessingTimes.append(processingTime)
        if chunkProcessingTimes.count > 100 {  // Keep only last 100 measurements
            chunkProcessingTimes.removeFirst()
        }
        
        await publishMetrics()
    }
    
    private func shouldTriggerTranscription(currentTimeMs: Int) -> Bool {
        let timeSinceLastTrigger = currentTimeMs - lastTranscriptionTriggerTime
        let hasMinimumBuffer = slidingBuffer.count >= config.overlapSizeInSamples
        let shouldTrigger = timeSinceLastTrigger >= config.transcriptionTriggerMs && hasMinimumBuffer
        
        // Debug logging every few seconds
        if currentTimeMs % 1000 < 100 {  // Log roughly every second
            print("🔍 Debug - Time: \(currentTimeMs)ms, Last trigger: \(lastTranscriptionTriggerTime)ms, Time since: \(timeSinceLastTrigger)ms, Buffer: \(slidingBuffer.count)/\(config.overlapSizeInSamples) samples")
        }
        
        if shouldTrigger {
            print("⏰ Transcription trigger conditions met: \(timeSinceLastTrigger)ms since last trigger, buffer: \(slidingBuffer.count) samples")
        }
        
        return shouldTrigger
    }
    
    private func handleTranscriptionTrigger(currentTimeMs: Int) async {
        guard slidingBuffer.count >= config.overlapSizeInSamples else {
            print("Not enough audio in buffer for transcription")
            return
        }
        
        // Create transcription chunk with overlap for context
        let transcriptionAudio = Array(slidingBuffer)
        
        let transcriptionChunk = ContinuousAudioChunk(
            audio: transcriptionAudio,
            chunkIndex: chunkCounter,
            timestampMs: currentTimeMs,
            id: UUID(),
            isTranscriptionTrigger: true
        )
        
        lastTranscriptionTriggerTime = currentTimeMs
        totalTranscriptionsTriggered += 1
        
        print("🎯 Transcription triggered at \(currentTimeMs)ms - Buffer: \(transcriptionAudio.count) samples (\(transcriptionAudio.count / config.sampleRate)s)")
        
        transcriptionTriggerPublisher.send(transcriptionChunk)
    }
    
    private func publishMetrics() async {
        let currentBufferMs = (slidingBuffer.count * 1000) / config.sampleRate
        let bufferUtilization = Float(slidingBuffer.count) / Float(config.bufferSizeInSamples)
        let avgProcessingTime = chunkProcessingTimes.isEmpty ? 0.0 : chunkProcessingTimes.reduce(0, +) / Double(chunkProcessingTimes.count)
        
        let metrics = StreamingMetrics(
            totalChunksProcessed: totalChunksProcessed,
            totalTranscriptionsTriggered: totalTranscriptionsTriggered,
            averageChunkProcessingTimeMs: avgProcessingTime,
            bufferUtilization: bufferUtilization,
            currentBufferSizeMs: currentBufferMs
        )
        
        metricsPublisher.send(metrics)
    }
    
    func getStreamingWindow<S: AsyncSequence>(_ frames: S) -> AsyncStream<ContinuousAudioChunk> where S.Element == [Float] {
        AsyncStream { continuation in
            Task {
                do {
                    for try await frame in frames {
                        await self.processAudioChunk(frame)
                        try Task.checkCancellation()
                    }
                    print("ContinuousStreamManager: Audio stream finished")
                } catch {
                    print("ContinuousStreamManager Error: \(error)")
                    continuation.finish()
                }
            }
        }
    }
    
    func getTranscriptionTriggers<S: AsyncSequence>(_ frames: S) -> AsyncStream<ContinuousAudioChunk> where S.Element == [Float] {
        AsyncStream { continuation in
            Task {
                let chunkStream = getStreamingWindow(frames)
                
                do {
                    for try await chunk in chunkStream {
                        if chunk.isTranscriptionTrigger {
                            continuation.yield(chunk)
                        }
                        try Task.checkCancellation()
                    }
                    continuation.finish()
                } catch {
                    print("ContinuousStreamManager Transcription Error: \(error)")
                    continuation.finish()
                }
            }
        }
    }
    
    func reset() async {
        slidingBuffer.removeAll()
        chunkCounter = 0
        totalSamplesProcessed = 0
        lastTranscriptionTriggerTime = 0
        streamStartTime = Date()
        totalChunksProcessed = 0
        totalTranscriptionsTriggered = 0
        chunkProcessingTimes.removeAll()
        
        print("ContinuousStreamManager reset")
    }
    
    func getCurrentMetrics() async -> StreamingMetrics {
        let currentBufferMs = (slidingBuffer.count * 1000) / config.sampleRate
        let bufferUtilization = Float(slidingBuffer.count) / Float(config.bufferSizeInSamples)
        let avgProcessingTime = chunkProcessingTimes.isEmpty ? 0.0 : chunkProcessingTimes.reduce(0, +) / Double(chunkProcessingTimes.count)
        
        return StreamingMetrics(
            totalChunksProcessed: totalChunksProcessed,
            totalTranscriptionsTriggered: totalTranscriptionsTriggered,
            averageChunkProcessingTimeMs: avgProcessingTime,
            bufferUtilization: bufferUtilization,
            currentBufferSizeMs: currentBufferMs
        )
    }
}
