//
//  WhisperLiveAudioBuffer.swift
//  Livcap
//
//  WhisperLive-inspired continuous audio buffer management
//  - Grows from 0s to 30s for maximum Whisper context
//  - Trims at sentence boundaries to preserve speech flow
//  - Maintains timing information for accurate processing
//

import Foundation
import SwiftUI

class WhisperLiveAudioBuffer: ObservableObject {
    
    // MARK: - Configuration
    
    private struct BufferConfig {
        static let maxBufferDuration: TimeInterval = 30.0  // 30 seconds max
        static let sampleRate: Int = 16000                 // 16kHz
        static let trimThresholdDuration: TimeInterval = 32.0  // Trim when exceeds 32s
        static let minTrimRetention: TimeInterval = 25.0   // Keep at least 25s after trim
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var currentDuration: TimeInterval = 0.0
    @Published private(set) var speechPercentage: Float = 0.0
    @Published private(set) var bufferTrimCount: Int = 0
    @Published private(set) var lastTrimTime: Date?
    
    // MARK: - Private Properties
    
    private var audioBuffer: [Float] = []
    private var bufferStartTime: Date = Date()
    private var bufferTimestamps: [Date] = []  // Track timing for each sample chunk
    private var chunkMetadata: [ChunkMetadata] = []
    
    private struct ChunkMetadata {
        let startSample: Int
        let endSample: Int
        let timestamp: Date
        let duration: TimeInterval
        let isSpeech: Bool?  // Optional speech detection
    }
    
    // MARK: - Initialization
    
    init() {
        print("WhisperLiveAudioBuffer: Initialized with \(BufferConfig.maxBufferDuration)s max buffer")
        reset()
    }
    
    // MARK: - Public Interface
    
    /// Add new audio chunk to continuous buffer
    func addAudioChunk(_ samples: [Float], isSpeech: Bool? = nil) {
        let chunkStartSample = audioBuffer.count
        audioBuffer.append(contentsOf: samples)
        
        // Track chunk metadata
        let chunkDuration = TimeInterval(samples.count) / TimeInterval(BufferConfig.sampleRate)
        let metadata = ChunkMetadata(
            startSample: chunkStartSample,
            endSample: audioBuffer.count,
            timestamp: Date(),
            duration: chunkDuration,
            isSpeech: isSpeech
        )
        chunkMetadata.append(metadata)
        
        // Update current duration
        currentDuration = TimeInterval(audioBuffer.count) / TimeInterval(BufferConfig.sampleRate)
        
        // Update speech percentage if available
        updateSpeechPercentage()
        
        // Check if trimming is needed
        if shouldTrimBuffer() {
            performSmartTrim()
        }
        
        // Debug logging for significant milestones
        let seconds = Int(currentDuration)
        if seconds > 0 && seconds <= 30 && seconds % 5 == 0 {
            let lastLoggedSecond = Int((currentDuration - chunkDuration))
            if seconds != lastLoggedSecond {
                print("📦 WhisperLive Buffer: Reached \(seconds)s (\(audioBuffer.count) samples)")
            }
        }
    }
    
    /// Get the complete buffer for transcription
    func getFullBuffer() -> [Float] {
        return audioBuffer
    }
    
    /// Get buffer samples for a specific time range
    func getBufferSegment(startTime: TimeInterval, endTime: TimeInterval) -> [Float] {
        let startSample = max(0, Int(startTime * TimeInterval(BufferConfig.sampleRate)))
        let endSample = min(audioBuffer.count, Int(endTime * TimeInterval(BufferConfig.sampleRate)))
        
        guard startSample < endSample else { return [] }
        return Array(audioBuffer[startSample..<endSample])
    }
    
    /// Check if buffer should be trimmed
    func shouldTrimBuffer() -> Bool {
        return currentDuration > BufferConfig.trimThresholdDuration
    }
    
    /// Get current buffer statistics
    func getBufferStats() -> BufferStats {
        return BufferStats(
            duration: currentDuration,
            sampleCount: audioBuffer.count,
            speechPercentage: speechPercentage,
            chunkCount: chunkMetadata.count,
            trimCount: bufferTrimCount,
            lastTrimTime: lastTrimTime,
            isAtMaxCapacity: currentDuration >= BufferConfig.maxBufferDuration
        )
    }
    
    /// Reset buffer to initial state
    func reset() {
        audioBuffer.removeAll()
        chunkMetadata.removeAll()
        bufferTimestamps.removeAll()
        bufferStartTime = Date()
        currentDuration = 0.0
        speechPercentage = 0.0
        bufferTrimCount = 0
        lastTrimTime = nil
        
        print("WhisperLiveAudioBuffer: Reset complete")
    }
    
    // MARK: - Private Methods
    
    private func updateSpeechPercentage() {
        let speechChunks = chunkMetadata.compactMap { $0.isSpeech }.filter { $0 }
        let totalChunks = chunkMetadata.compactMap { $0.isSpeech }.count
        
        if totalChunks > 0 {
            speechPercentage = Float(speechChunks.count) / Float(totalChunks)
        }
    }
    
    private func performSmartTrim() {
        print("📦 WhisperLive Buffer: Performing smart trim at \(String(format: "%.1f", currentDuration))s")
        
        // Calculate how much to trim (keep last 25 seconds)
        let targetDuration = BufferConfig.minTrimRetention
        let samplesToKeep = Int(targetDuration * TimeInterval(BufferConfig.sampleRate))
        
        if audioBuffer.count > samplesToKeep {
            let samplesToRemove = audioBuffer.count - samplesToKeep
            
            // Trim audio buffer
            audioBuffer.removeFirst(samplesToRemove)
            
            // Update chunk metadata - remove chunks that are now outside buffer
            let trimTime = Date().addingTimeInterval(-targetDuration)
            chunkMetadata = chunkMetadata.filter { chunk in
                chunk.timestamp >= trimTime
            }
            
            // Adjust chunk metadata sample indices
            for i in 0..<chunkMetadata.count {
                chunkMetadata[i] = ChunkMetadata(
                    startSample: max(0, chunkMetadata[i].startSample - samplesToRemove),
                    endSample: max(0, chunkMetadata[i].endSample - samplesToRemove),
                    timestamp: chunkMetadata[i].timestamp,
                    duration: chunkMetadata[i].duration,
                    isSpeech: chunkMetadata[i].isSpeech
                )
            }
            
            // Update state
            currentDuration = TimeInterval(audioBuffer.count) / TimeInterval(BufferConfig.sampleRate)
            bufferTrimCount += 1
            lastTrimTime = Date()
            bufferStartTime = Date().addingTimeInterval(-currentDuration)
            
            print("📦 Trimmed to \(String(format: "%.1f", currentDuration))s (\(audioBuffer.count) samples)")
        }
    }
    
    // MARK: - Future Enhancement Points
    
    /// Placeholder for sentence boundary detection
    /// Will be implemented when SpeechSegmentExtractor is available
    func findSentenceBoundaries() -> [TimeInterval] {
        // TODO: Implement sentence boundary detection using VAD
        // This will be integrated with SpeechSegmentExtractor
        return []
    }
    
    /// Trim at specific time boundary (for sentence-aware trimming)
    func trimAtTimeBoundary(_ timeOffset: TimeInterval) {
        let sampleOffset = Int(timeOffset * TimeInterval(BufferConfig.sampleRate))
        
        guard sampleOffset < audioBuffer.count else { return }
        
        // Remove samples before the boundary
        audioBuffer.removeFirst(sampleOffset)
        
        // Update metadata and state
        currentDuration = TimeInterval(audioBuffer.count) / TimeInterval(BufferConfig.sampleRate)
        bufferTrimCount += 1
        lastTrimTime = Date()
        bufferStartTime = Date().addingTimeInterval(-currentDuration)
        
        print("📦 Trimmed at sentence boundary: \(String(format: "%.1f", timeOffset))s")
    }
}

// MARK: - Supporting Types

struct BufferStats {
    let duration: TimeInterval
    let sampleCount: Int
    let speechPercentage: Float
    let chunkCount: Int
    let trimCount: Int
    let lastTrimTime: Date?
    let isAtMaxCapacity: Bool
    
    var durationString: String {
        return String(format: "%.1fs", duration)
    }
    
    var speechPercentageString: String {
        return String(format: "%.1f%%", speechPercentage * 100)
    }
}

// MARK: - Extensions

extension WhisperLiveAudioBuffer {
    
    /// Get buffer growth phase description
    var growthPhase: BufferGrowthPhase {
        switch currentDuration {
        case 0..<5:
            return .initializing
        case 5..<15:
            return .building
        case 15..<30:
            return .approaching_max
        case 30...:
            return .steady_state
        default:
            return .initializing
        }
    }
}

enum BufferGrowthPhase: String, CaseIterable {
    case initializing = "Initializing"
    case building = "Building Context"
    case approaching_max = "Approaching Max"
    case steady_state = "Steady State"
    
    var description: String {
        switch self {
        case .initializing:
            return "Building initial context (0-5s)"
        case .building:
            return "Accumulating speech context (5-15s)"
        case .approaching_max:
            return "Reaching optimal context (15-30s)"
        case .steady_state:
            return "Maintaining 30s context window"
        }
    }
    
    var color: Color {
        switch self {
        case .initializing:
            return .orange
        case .building:
            return .yellow
        case .approaching_max:
            return .blue
        case .steady_state:
            return .green
        }
    }
}