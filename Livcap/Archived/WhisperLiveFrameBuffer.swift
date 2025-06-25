//
//  WhisperLiveFrameBuffer.swift
//  Livcap
//
//  Frame-based continuous buffer with VAD marking
//  - 100ms frames with RMS-based VAD detection
//  - 30s sliding window buffer
//  - 3s silence reset rule
//  - Per-second inference decisions
//

import Foundation
import SwiftUI

struct AudioFrame {
    let samples: [Float]        // 100ms of 16kHz audio (1600 samples)
    let vadLevel: Float         // RMS energy level
    let isVoice: Bool          // Above/below threshold
    let timestamp: TimeInterval // When this frame was captured
    let frameIndex: Int        // Sequential frame number
    let secondIndex: Int       // Which second this frame belongs to (0-based)
    
    var duration: TimeInterval {
        return TimeInterval(samples.count) / 16000.0  // Should be ~0.1s
    }
}

struct SecondSummary {
    let secondIndex: Int
    let hasVoice: Bool          // True if ANY frame in this second has voice
    let voiceFrameCount: Int    // How many frames had voice
    let totalFrames: Int        // Should be 10 for complete seconds
    let startTime: TimeInterval
    let endTime: TimeInterval
    
    var voicePercentage: Float {
        return totalFrames > 0 ? Float(voiceFrameCount) / Float(totalFrames) : 0.0
    }
    
    var isComplete: Bool {
        return totalFrames == 10  // 10 frames × 100ms = 1 second
    }
}

class WhisperLiveFrameBuffer: ObservableObject {
    
    // MARK: - Configuration
    
    private struct Config {
        static let maxBufferSeconds: Int = 30           // 30 second sliding window
        static let maxFrames: Int = 300                 // 30s × 10 frames/s = 300 frames
        static let framesPerSecond: Int = 10            // 10 × 100ms = 1 second
        static let sampleRate: Int = 16000              // 16kHz
        static let samplesPerFrame: Int = 1600          // 100ms at 16kHz
        static let vadThreshold: Float = 0.01           // RMS threshold
        static let silenceResetSeconds: Int = 3         // Reset after 3s of silence
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var frames: [AudioFrame] = []
    @Published private(set) var secondSummaries: [SecondSummary] = []
    @Published private(set) var currentBufferSeconds: Int = 0
    @Published private(set) var consecutiveSilentSeconds: Int = 0
    @Published private(set) var totalFramesProcessed: Int = 0
    @Published private(set) var sessionStartTime: Date = Date()
    
    // MARK: - Private Properties
    
    private var frameCounter: Int = 0
    private var currentSecondFrames: [AudioFrame] = []
    private var lastInferenceSecond: Int = -1
    
    // MARK: - Initialization
    
    init() {
        sessionStartTime = Date()
        print("WhisperLiveFrameBuffer: Initialized with frame-based VAD approach")
        print("- Frame size: \(Config.samplesPerFrame) samples (100ms)")
        print("- Buffer capacity: \(Config.maxFrames) frames (30s)")
        print("- VAD threshold: \(Config.vadThreshold)")
        print("- Silence reset: \(Config.silenceResetSeconds)s")
    }
    
    // MARK: - Public Interface
    
    /// Add new 100ms audio frame with VAD processing
    func addFrame(_ samples: [Float]) {
        guard samples.count == Config.samplesPerFrame else {
            print("⚠️ Frame size mismatch: expected \(Config.samplesPerFrame), got \(samples.count)")
            return
        }
        
        // Calculate VAD for this frame
        let vadLevel = calculateRMS(samples)
        let isVoice = vadLevel >= Config.vadThreshold
        
        // Create frame
        let timestamp = Date().timeIntervalSince(sessionStartTime)
        let secondIndex = frameCounter / Config.framesPerSecond
        
        let frame = AudioFrame(
            samples: samples,
            vadLevel: vadLevel,
            isVoice: isVoice,
            timestamp: timestamp,
            frameIndex: frameCounter,
            secondIndex: secondIndex
        )
        
        frameCounter += 1
        totalFramesProcessed += 1
        
        // Add to buffer
        frames.append(frame)
        currentSecondFrames.append(frame)
        
        // Debug logging for first few frames and every 50 frames
        if frameCounter <= 5 || frameCounter % 50 == 0 {
            print("📦 Frame #\(frameCounter): VAD=\(String(format: "%.4f", vadLevel)) (\(isVoice ? "VOICE" : "silence")) - Second \(secondIndex)")
        }
        
        // Check if we completed a second (10 frames)
        if currentSecondFrames.count == Config.framesPerSecond {
            processCompletedSecond()
        }
        
        // Maintain sliding window (trim if needed)
        if frames.count > Config.maxFrames {
            let framesToRemove = frames.count - Config.maxFrames
            frames.removeFirst(framesToRemove)
            print("📦 Trimmed \(framesToRemove) oldest frames - Buffer now: \(frames.count) frames")
        }
        
        updateBufferState()
    }
    
    /// Get speech-only audio from current buffer for inference
    func extractSpeechForInference() -> [Float] {
        let voiceFrames = frames.filter { $0.isVoice }
        var speechAudio: [Float] = []
        
        for frame in voiceFrames {
            speechAudio.append(contentsOf: frame.samples)
            
            // Add small gap between frames to maintain natural flow
            let gapSamples = Int(0.02 * Double(Config.sampleRate))  // 20ms gap
            speechAudio.append(contentsOf: Array(repeating: 0.0, count: gapSamples))
        }
        
        let speechDuration = Double(speechAudio.count) / Double(Config.sampleRate)
        print("🎤 Speech extraction: \(voiceFrames.count) voice frames → \(String(format: "%.1f", speechDuration))s speech audio")
        
        return speechAudio
    }
    
    /// Check if we should trigger inference for current second
    func shouldTriggerInference() -> Bool {
        guard !secondSummaries.isEmpty else { return false }
        
        let currentSecond = secondSummaries.count - 1
        
        // Don't re-process the same second
        if currentSecond <= lastInferenceSecond {
            return false
        }
        
        let summary = secondSummaries[currentSecond]
        let shouldTrigger = summary.hasVoice && summary.isComplete
        
        if shouldTrigger {
            lastInferenceSecond = currentSecond
            print("⏰ Inference trigger: Second \(currentSecond) has voice (\(summary.voiceFrameCount)/\(summary.totalFrames) frames)")
        }
        
        return shouldTrigger
    }
    
    /// Get recent seconds for UI visualization (last 10 seconds)
    func getRecentSeconds() -> [SecondSummary] {
        let maxRecent = 10
        let startIndex = max(0, secondSummaries.count - maxRecent)
        return Array(secondSummaries[startIndex...])
    }
    
    /// Get current buffer statistics
    func getBufferStats() -> FrameBufferStats {
        let bufferDurationSeconds = Double(frames.count) / Double(Config.framesPerSecond)
        let voiceFrameCount = frames.filter { $0.isVoice }.count
        let voicePercentage = frames.isEmpty ? 0.0 : Float(voiceFrameCount) / Float(frames.count)
        
        return FrameBufferStats(
            totalFrames: frames.count,
            bufferDurationSeconds: bufferDurationSeconds,
            voicePercentage: voicePercentage,
            currentSecondIndex: frameCounter / Config.framesPerSecond,
            consecutiveSilentSeconds: consecutiveSilentSeconds,
            totalSecondsProcessed: secondSummaries.count,
            isAtMaxCapacity: frames.count >= Config.maxFrames
        )
    }
    
    /// Reset buffer (called after 3s of silence)
    func reset() {
        frames.removeAll()
        secondSummaries.removeAll()
        currentSecondFrames.removeAll()
        frameCounter = 0
        currentBufferSeconds = 0
        consecutiveSilentSeconds = 0
        totalFramesProcessed = 0
        lastInferenceSecond = -1
        sessionStartTime = Date()
        
        print("🔄 WhisperLiveFrameBuffer: Reset after 3s silence")
    }
    
    // MARK: - Private Methods
    
    private func processCompletedSecond() {
        let secondIndex = currentSecondFrames.first?.secondIndex ?? 0
        let voiceFrames = currentSecondFrames.filter { $0.isVoice }
        let hasVoice = !voiceFrames.isEmpty
        
        let summary = SecondSummary(
            secondIndex: secondIndex,
            hasVoice: hasVoice,
            voiceFrameCount: voiceFrames.count,
            totalFrames: currentSecondFrames.count,
            startTime: currentSecondFrames.first?.timestamp ?? 0,
            endTime: currentSecondFrames.last?.timestamp ?? 0
        )
        
        secondSummaries.append(summary)
        
        // Log second completion
        let status = hasVoice ? "🟢 VOICE" : "🔴 SILENCE"
        print("📊 Second \(secondIndex) complete: \(status) (\(voiceFrames.count)/\(currentSecondFrames.count) voice frames)")
        
        // Update silence tracking
        if hasVoice {
            consecutiveSilentSeconds = 0
        } else {
            consecutiveSilentSeconds += 1
        }
        
        // Check for silence reset
        if consecutiveSilentSeconds >= Config.silenceResetSeconds {
            print("😴 \(Config.silenceResetSeconds)s silence detected - triggering reset")
            reset()
            return
        }
        
        // Clear current second frames
        currentSecondFrames.removeAll()
    }
    
    private func updateBufferState() {
        currentBufferSeconds = frames.count / Config.framesPerSecond
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let meanSquare = sumOfSquares / Float(samples.count)
        return sqrt(meanSquare)
    }
}

// MARK: - Supporting Types

struct FrameBufferStats {
    let totalFrames: Int
    let bufferDurationSeconds: Double
    let voicePercentage: Float
    let currentSecondIndex: Int
    let consecutiveSilentSeconds: Int
    let totalSecondsProcessed: Int
    let isAtMaxCapacity: Bool
    
    var durationString: String {
        return String(format: "%.1fs", bufferDurationSeconds)
    }
    
    var voicePercentageString: String {
        return String(format: "%.1f%%", voicePercentage * 100)
    }
}