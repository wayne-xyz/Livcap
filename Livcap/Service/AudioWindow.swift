//
//  AudioWindow.swift
//  Livcap
//
//  Created by Implementation Plan on 6/20/25.
//

import Foundation

/// Represents an audio window for overlapping transcription processing
/// Based on WhisperLive's 3-second window with 1-second step approach
struct AudioWindow: Sendable {
    let id: UUID
    let audio: [Float]
    let startTimeMS: Int
    let endTimeMS: Int
    let durationMS: Int
    let sampleRate: Double
    
    /// WhisperLive configuration constants
    static let windowSizeSeconds: Double = 3.0
    static let stepSizeSeconds: Double = 1.0
    static let overlapSeconds: Double = windowSizeSeconds - stepSizeSeconds // 2.0 seconds
    
    /// Sample counts at 16kHz
    static let windowSizeSamples: Int = Int(windowSizeSeconds * 16000.0) // 48,000 samples
    static let stepSizeSamples: Int = Int(stepSizeSeconds * 16000.0)     // 16,000 samples
    static let overlapSamples: Int = Int(overlapSeconds * 16000.0)       // 32,000 samples
    
    init(audio: [Float], startTimeMS: Int, sampleRate: Double = 16000.0) {
        self.id = UUID()
        self.audio = audio
        self.startTimeMS = startTimeMS
        self.sampleRate = sampleRate
        self.durationMS = Int(Double(audio.count) / sampleRate * 1000.0)
        self.endTimeMS = startTimeMS + durationMS
    }
    
    /// Creates an audio window from a buffer with specified parameters
    static func create(from buffer: [Float], startTimeMS: Int, sampleRate: Double = 16000.0) -> AudioWindow {
        return AudioWindow(audio: buffer, startTimeMS: startTimeMS, sampleRate: sampleRate)
    }
    
    /// Checks if this window overlaps with another window
    func overlaps(with other: AudioWindow, threshold: Double = 0.3) -> Bool {
        let overlapStart = max(startTimeMS, other.startTimeMS)
        let overlapEnd = min(endTimeMS, other.endTimeMS)
        let overlapDuration = max(0, overlapEnd - overlapStart)
        
        let totalDuration = min(durationMS, other.durationMS)
        let overlapPercentage = totalDuration > 0 ? Double(overlapDuration) / Double(totalDuration) : 0.0
        
        return overlapPercentage > threshold
    }
    
    /// Calculates overlap percentage with another window
    func overlapPercentage(with other: AudioWindow) -> Double {
        let overlapStart = max(startTimeMS, other.startTimeMS)
        let overlapEnd = min(endTimeMS, other.endTimeMS)
        let overlapDuration = max(0, overlapEnd - overlapStart)
        
        let totalDuration = min(durationMS, other.durationMS)
        return totalDuration > 0 ? Double(overlapDuration) / Double(totalDuration) : 0.0
    }
    
    /// Gets the overlap duration in milliseconds
    func overlapDuration(with other: AudioWindow) -> Int {
        let overlapStart = max(startTimeMS, other.startTimeMS)
        let overlapEnd = min(endTimeMS, other.endTimeMS)
        return max(0, overlapEnd - overlapStart)
    }
    
    /// Checks if this window contains a specific timestamp
    func contains(timestampMS: Int) -> Bool {
        return timestampMS >= startTimeMS && timestampMS <= endTimeMS
    }
    
    /// Gets the relative position of a timestamp within this window (0.0 to 1.0)
    func relativePosition(timestampMS: Int) -> Double {
        guard contains(timestampMS: timestampMS) else { return 0.0 }
        return Double(timestampMS - startTimeMS) / Double(durationMS)
    }
}

// MARK: - Equatable and Hashable
extension AudioWindow: Equatable {
    static func == (lhs: AudioWindow, rhs: AudioWindow) -> Bool {
        return lhs.id == rhs.id
    }
}

extension AudioWindow: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible
extension AudioWindow: CustomStringConvertible {
    var description: String {
        return "AudioWindow(id: \(id.uuidString.prefix(8)), start: \(startTimeMS)ms, duration: \(durationMS)ms, samples: \(audio.count))"
    }
} 