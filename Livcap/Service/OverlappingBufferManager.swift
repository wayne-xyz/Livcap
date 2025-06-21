//
//  OverlappingBufferManager.swift
//  Livcap
//
//  Created by Implementation Plan on 6/20/25.
//

import Foundation
import Combine

/// Manages overlapping audio windows for real-time transcription
/// Implements WhisperLive's 3-second window with 1-second step approach
actor OverlappingBufferManager {
    
    // MARK: - Configuration (WhisperLive-style)
    private let windowSizeSamples: Int = AudioWindow.windowSizeSamples  // 48,000 samples (3s at 16kHz)
    private let stepSizeSamples: Int = AudioWindow.stepSizeSamples      // 16,000 samples (1s at 16kHz)
    private let overlapSamples: Int = AudioWindow.overlapSamples        // 32,000 samples (2s at 16kHz)
    private let sampleRate: Double = 16000.0
    
    // MARK: - Internal State
    private var audioBuffer: [Float] = []
    private var currentTimeMS: Int = 0
    private var lastWindowStartTimeMS: Int = 0
    private var isProcessing: Bool = false
    
    // MARK: - Published Properties
    private let windowPublisher = PassthroughSubject<AudioWindow, Never>()
    
    // MARK: - Initialization
    init() {
        print("OverlappingBufferManager: Initialized with window size: \(windowSizeSamples) samples (\(AudioWindow.windowSizeSeconds)s)")
        print("OverlappingBufferManager: Step size: \(stepSizeSamples) samples (\(AudioWindow.stepSizeSeconds)s)")
        print("OverlappingBufferManager: Overlap: \(overlapSamples) samples (\(AudioWindow.overlapSeconds)s)")
    }
    
    // MARK: - Public Interface
    
    /// Processes incoming audio chunks and emits windows when ready
    func processAudioChunk(_ samples: [Float]) async {
        // Calculate duration of incoming chunk
        let chunkDurationMS = Int(Double(samples.count) / sampleRate * 1000.0)
        
        // Add samples to buffer
        audioBuffer.append(contentsOf: samples)
        currentTimeMS += chunkDurationMS
        
        // Check if we have enough audio for a new window
        await checkAndEmitWindow()
    }
    
    /// Processes an audio stream and emits windows
    func processAudioStream<S: AsyncSequence>(_ audioStream: S) -> AsyncStream<AudioWindow> where S.Element == [Float] {
        return AsyncStream { continuation in
            Task {
                do {
                    for try await chunk in audioStream {
                        await self.processAudioChunk(chunk)
                        
                        // Check for cancellation
                        try Task.checkCancellation()
                    }
                    
                    // Process any remaining audio
                    await self.processRemainingAudio()
                    
                } catch {
                    print("OverlappingBufferManager: Error processing audio stream: \(error)")
                }
                
                continuation.finish()
            }
        }
    }
    
    /// Gets the publisher for audio windows
    var windows: AnyPublisher<AudioWindow, Never> {
        return windowPublisher.eraseToAnyPublisher()
    }
    
    /// Resets the buffer manager state
    func reset() {
        audioBuffer.removeAll()
        currentTimeMS = 0
        lastWindowStartTimeMS = 0
        isProcessing = false
        print("OverlappingBufferManager: Reset")
    }
    
    /// Gets current buffer statistics
    var bufferStats: BufferStats {
        return BufferStats(
            bufferSize: audioBuffer.count,
            bufferDurationMS: Int(Double(audioBuffer.count) / sampleRate * 1000.0),
            currentTimeMS: currentTimeMS,
            lastWindowStartTimeMS: lastWindowStartTimeMS,
            isProcessing: isProcessing
        )
    }
    
    // MARK: - Private Methods
    
    private func checkAndEmitWindow() async {
        guard !isProcessing else { return }
        
        // Check if we have enough audio for a complete window
        guard audioBuffer.count >= windowSizeSamples else { return }
        
        // Check if enough time has passed since the last window
        let timeSinceLastWindow = currentTimeMS - lastWindowStartTimeMS
        let requiredTimeMS = Int(AudioWindow.stepSizeSeconds * 1000.0) // 1000ms
        
        guard timeSinceLastWindow >= requiredTimeMS else { return }
        
        await emitWindow()
    }
    
    private func emitWindow() async {
        isProcessing = true
        
        // Extract the window audio (first windowSizeSamples)
        let windowAudio = Array(audioBuffer.prefix(windowSizeSamples))
        
        // Create the audio window
        let window = AudioWindow(
            audio: windowAudio,
            startTimeMS: lastWindowStartTimeMS,
            sampleRate: sampleRate
        )
        
        print("OverlappingBufferManager: Emitting window \(window.id.uuidString.prefix(8)) at \(window.startTimeMS)ms")
        
        // Emit the window
        windowPublisher.send(window)
        
        // Update state
        lastWindowStartTimeMS += Int(AudioWindow.stepSizeSeconds * 1000.0)
        
        // Remove processed audio (keep overlap)
        audioBuffer.removeFirst(stepSizeSamples)
        
        // Ensure buffer doesn't grow too large
        let maxBufferSize = windowSizeSamples + stepSizeSamples // Allow one extra step
        if audioBuffer.count > maxBufferSize {
            let excessSamples = audioBuffer.count - maxBufferSize
            audioBuffer.removeFirst(excessSamples)
            print("OverlappingBufferManager: Trimmed \(excessSamples) excess samples from buffer")
        }
        
        isProcessing = false
        
        // Check if we can emit another window immediately
        if audioBuffer.count >= windowSizeSamples {
            await checkAndEmitWindow()
        }
    }
    
    private func processRemainingAudio() async {
        guard !audioBuffer.isEmpty else { return }
        
        // If we have enough audio for at least a partial window, emit it
        if audioBuffer.count >= stepSizeSamples {
            let windowAudio = Array(audioBuffer)
            let window = AudioWindow(
                audio: windowAudio,
                startTimeMS: lastWindowStartTimeMS,
                sampleRate: sampleRate
            )
            
            print("OverlappingBufferManager: Emitting final window \(window.id.uuidString.prefix(8)) with \(windowAudio.count) samples")
            windowPublisher.send(window)
        }
    }
}

// MARK: - Supporting Types

/// Statistics about the current buffer state
struct BufferStats {
    let bufferSize: Int
    let bufferDurationMS: Int
    let currentTimeMS: Int
    let lastWindowStartTimeMS: Int
    let isProcessing: Bool
    
    var bufferDurationSeconds: Double {
        return Double(bufferDurationMS) / 1000.0
    }
    
    var timeSinceLastWindowMS: Int {
        return currentTimeMS - lastWindowStartTimeMS
    }
    
    var timeSinceLastWindowSeconds: Double {
        return Double(timeSinceLastWindowMS) / 1000.0
    }
}

// MARK: - CustomStringConvertible
extension BufferStats: CustomStringConvertible {
    var description: String {
        return "BufferStats(buffer: \(bufferSize) samples (\(String(format: "%.1f", bufferDurationSeconds))s), currentTime: \(currentTimeMS)ms, sinceLastWindow: \(String(format: "%.1f", timeSinceLastWindowSeconds))s, processing: \(isProcessing))"
    }
} 