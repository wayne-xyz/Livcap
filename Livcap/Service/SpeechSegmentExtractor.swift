//
//  SpeechSegmentExtractor.swift
//  Livcap
//
//  Pre-inference VAD processing for WhisperLive pipeline
//  - Extracts speech-only segments from full buffer
//  - Preserves timing context while cleaning audio for Whisper
//  - Detects sentence boundaries for smart buffer trimming
//

import Foundation
import SwiftUI

struct AudioSegment {
    let samples: [Float]
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    let isSpeech: Bool
    
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    var sampleCount: Int {
        return samples.count
    }
}

struct SentenceBoundary {
    let timeOffset: TimeInterval
    let confidence: Float
    let silenceDuration: TimeInterval
    let reason: String  // "long_pause", "low_energy", "end_of_speech"
}

struct SpeechExtractionResult {
    let cleanAudio: [Float]           // Concatenated speech-only audio
    let originalDuration: TimeInterval
    let speechDuration: TimeInterval
    let speechPercentage: Float
    let segmentCount: Int
    let sentenceBoundaries: [SentenceBoundary]
    let qualityScore: Float           // Overall speech quality assessment
}

class SpeechSegmentExtractor: ObservableObject {
    
    // MARK: - Configuration
    
    private struct ExtractorConfig {
        static let sampleRate: Int = 16000
        static let energyThreshold: Float = 0.01      // RMS energy threshold
        static let confidenceThreshold: Float = 0.3   // Minimum confidence for speech
        static let minSpeechDuration: TimeInterval = 0.1  // 100ms minimum speech segment
        static let minSilenceDuration: TimeInterval = 0.5 // 500ms silence for sentence boundary
        static let sentenceBoundaryThreshold: TimeInterval = 1.0  // 1s silence = sentence end
        static let qualityScoreThreshold: Float = 0.6    // Minimum quality for good transcription
    }
    
    // MARK: - Published Properties
    
    @Published var lastExtractionResult: SpeechExtractionResult?
    @Published var processingTimeMs: Double = 0
    @Published var totalSegmentsExtracted: Int = 0
    @Published var averageSpeechQuality: Float = 0
    
    // MARK: - Private Properties
    
    private var extractionHistory: [SpeechExtractionResult] = []
    private let enhancedVAD: EnhancedVAD
    
    // MARK: - Initialization
    
    init() {
        self.enhancedVAD = EnhancedVAD()
        print("SpeechSegmentExtractor: Initialized with pre-inference VAD strategy")
    }
    
    // MARK: - Public Interface
    
    /// Extract speech-only audio from full buffer for Whisper inference
    func extractSpeechOnly(from buffer: [Float]) -> SpeechExtractionResult {
        let startTime = Date()
        
        guard !buffer.isEmpty else {
            return createEmptyResult()
        }
        
        // Analyze buffer in chunks to identify speech segments
        let chunkSize = ExtractorConfig.sampleRate / 10  // 100ms chunks
        let segments = analyzeBufferForSpeech(buffer, chunkSize: chunkSize)
        
        // Filter and merge speech segments
        let speechSegments = filterSpeechSegments(segments)
        
        // Concatenate speech-only audio
        let cleanAudio = concatenateSpeechSegments(speechSegments)
        
        // Detect sentence boundaries
        let sentenceBoundaries = detectSentenceBoundaries(segments)
        
        // Calculate metrics
        let originalDuration = TimeInterval(buffer.count) / TimeInterval(ExtractorConfig.sampleRate)
        let speechDuration = speechSegments.reduce(0) { $0 + $1.duration }
        let speechPercentage = originalDuration > 0 ? Float(speechDuration / originalDuration) : 0
        let qualityScore = calculateOverallQuality(speechSegments)
        
        // Create result
        let result = SpeechExtractionResult(
            cleanAudio: cleanAudio,
            originalDuration: originalDuration,
            speechDuration: speechDuration,
            speechPercentage: speechPercentage,
            segmentCount: speechSegments.count,
            sentenceBoundaries: sentenceBoundaries,
            qualityScore: qualityScore
        )
        
        // Update state
        processingTimeMs = Date().timeIntervalSince(startTime) * 1000
        lastExtractionResult = result
        extractionHistory.append(result)
        if extractionHistory.count > 20 {
            extractionHistory.removeFirst()
        }
        
        totalSegmentsExtracted += speechSegments.count
        updateAverageQuality()
        
        // Logging
        print("🎤 Speech Extraction: \(String(format: "%.1f", speechDuration))s speech from \(String(format: "%.1f", originalDuration))s buffer (\(String(format: "%.1f", speechPercentage * 100))%)")
        if !sentenceBoundaries.isEmpty {
            print("📝 Detected \(sentenceBoundaries.count) sentence boundaries")
        }
        
        return result
    }
    
    /// Get the most recent sentence boundary for buffer trimming
    func getLastSentenceBoundary(from buffer: [Float]) -> TimeInterval? {
        let result = extractSpeechOnly(from: buffer)
        return result.sentenceBoundaries.last?.timeOffset
    }
    
    /// Estimate if buffer has sufficient speech quality for transcription
    func estimateSpeechQuality(_ buffer: [Float]) -> Float {
        let result = extractSpeechOnly(from: buffer)
        return result.qualityScore
    }
    
    /// Check if buffer contains sufficient speech for meaningful transcription
    func hasSufficientSpeech(_ buffer: [Float]) -> Bool {
        let result = extractSpeechOnly(from: buffer)
        return result.speechDuration >= 1.0 && // At least 1 second of speech
               result.speechPercentage >= 0.2 && // At least 20% speech
               result.qualityScore >= ExtractorConfig.qualityScoreThreshold
    }
    
    // MARK: - Private Methods
    
    private func analyzeBufferForSpeech(_ buffer: [Float], chunkSize: Int) -> [AudioSegment] {
        var segments: [AudioSegment] = []
        
        for i in stride(from: 0, to: buffer.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, buffer.count)
            let chunkSamples = Array(buffer[i..<endIndex])
            
            // Use enhanced VAD to analyze this chunk
            let vadResult = enhancedVAD.processAudioChunk(chunkSamples)
            
            let startTime = TimeInterval(i) / TimeInterval(ExtractorConfig.sampleRate)
            let endTime = TimeInterval(endIndex) / TimeInterval(ExtractorConfig.sampleRate)
            
            let segment = AudioSegment(
                samples: chunkSamples,
                startTime: startTime,
                endTime: endTime,
                confidence: vadResult.confidence,
                isSpeech: vadResult.isSpeech
            )
            
            segments.append(segment)
        }
        
        return segments
    }
    
    private func filterSpeechSegments(_ segments: [AudioSegment]) -> [AudioSegment] {
        return segments.filter { segment in
            segment.isSpeech && 
            segment.confidence >= ExtractorConfig.confidenceThreshold &&
            segment.duration >= ExtractorConfig.minSpeechDuration
        }
    }
    
    private func concatenateSpeechSegments(_ speechSegments: [AudioSegment]) -> [Float] {
        var cleanAudio: [Float] = []
        
        for segment in speechSegments {
            cleanAudio.append(contentsOf: segment.samples)
            
            // Add small gap between segments to maintain natural flow
            // This helps Whisper understand word boundaries
            let gapSamples = Int(0.05 * Double(ExtractorConfig.sampleRate))  // 50ms gap
            cleanAudio.append(contentsOf: Array(repeating: 0.0, count: gapSamples))
        }
        
        return cleanAudio
    }
    
    private func detectSentenceBoundaries(_ segments: [AudioSegment]) -> [SentenceBoundary] {
        var boundaries: [SentenceBoundary] = []
        var currentSilenceStart: TimeInterval?
        var currentSilenceDuration: TimeInterval = 0
        
        for i in 0..<segments.count {
            let segment = segments[i]
            
            if segment.isSpeech {
                // End of silence period - check if it was long enough for sentence boundary
                if let silenceStart = currentSilenceStart, currentSilenceDuration >= ExtractorConfig.sentenceBoundaryThreshold {
                    let boundary = SentenceBoundary(
                        timeOffset: silenceStart + currentSilenceDuration / 2,  // Middle of silence
                        confidence: 0.8,  // High confidence for long silence
                        silenceDuration: currentSilenceDuration,
                        reason: currentSilenceDuration >= 2.0 ? "long_pause" : "speech_break"
                    )
                    boundaries.append(boundary)
                }
                
                // Reset silence tracking
                currentSilenceStart = nil
                currentSilenceDuration = 0
                
            } else {
                // Silence detected
                if currentSilenceStart == nil {
                    currentSilenceStart = segment.startTime
                    currentSilenceDuration = segment.duration
                } else {
                    currentSilenceDuration += segment.duration
                }
            }
        }
        
        // Handle end-of-buffer silence
        if let silenceStart = currentSilenceStart, currentSilenceDuration >= ExtractorConfig.minSilenceDuration {
            let boundary = SentenceBoundary(
                timeOffset: silenceStart + currentSilenceDuration / 2,
                confidence: 0.6,
                silenceDuration: currentSilenceDuration,
                reason: "end_of_speech"
            )
            boundaries.append(boundary)
        }
        
        return boundaries
    }
    
    private func calculateOverallQuality(_ speechSegments: [AudioSegment]) -> Float {
        guard !speechSegments.isEmpty else { return 0.0 }
        
        // Quality factors:
        // 1. Average confidence of speech segments
        let avgConfidence = speechSegments.map { $0.confidence }.reduce(0, +) / Float(speechSegments.count)
        
        // 2. Speech continuity (fewer segments = more continuous speech)
        let continuityScore = speechSegments.count <= 5 ? 1.0 : max(0.3, 1.0 - Float(speechSegments.count - 5) * 0.1)
        
        // 3. Duration adequacy (longer speech = better)
        let totalDuration = speechSegments.reduce(0) { $0 + $1.duration }
        let durationScore = min(1.0, Float(totalDuration / 2.0))  // Optimal at 2+ seconds
        
        // Combined quality score
        let qualityScore = (avgConfidence * 0.4 + continuityScore * 0.3 + durationScore * 0.3)
        
        return min(1.0, qualityScore)
    }
    
    private func updateAverageQuality() {
        guard !extractionHistory.isEmpty else { return }
        
        let totalQuality = extractionHistory.map { $0.qualityScore }.reduce(0, +)
        averageSpeechQuality = totalQuality / Float(extractionHistory.count)
    }
    
    private func createEmptyResult() -> SpeechExtractionResult {
        return SpeechExtractionResult(
            cleanAudio: [],
            originalDuration: 0,
            speechDuration: 0,
            speechPercentage: 0,
            segmentCount: 0,
            sentenceBoundaries: [],
            qualityScore: 0
        )
    }
    
    // MARK: - Public Utility Methods
    
    /// Get extraction statistics for monitoring
    func getExtractionStats() -> ExtractionStats {
        let recentResults = extractionHistory.suffix(10)
        let avgSpeechPercentage = recentResults.isEmpty ? 0 : 
            recentResults.map { $0.speechPercentage }.reduce(0, +) / Float(recentResults.count)
        
        return ExtractionStats(
            totalExtractions: extractionHistory.count,
            averageSpeechPercentage: avgSpeechPercentage,
            averageQualityScore: averageSpeechQuality,
            lastProcessingTimeMs: processingTimeMs,
            totalSegmentsExtracted: totalSegmentsExtracted
        )
    }
    
    /// Reset extraction history and metrics
    func reset() {
        extractionHistory.removeAll()
        lastExtractionResult = nil
        processingTimeMs = 0
        totalSegmentsExtracted = 0
        averageSpeechQuality = 0
        
        enhancedVAD.reset()
        
        print("SpeechSegmentExtractor: Reset complete")
    }
}

// MARK: - Supporting Types

struct ExtractionStats {
    let totalExtractions: Int
    let averageSpeechPercentage: Float
    let averageQualityScore: Float
    let lastProcessingTimeMs: Double
    let totalSegmentsExtracted: Int
    
    var speechPercentageString: String {
        return String(format: "%.1f%%", averageSpeechPercentage * 100)
    }
    
    var qualityScoreString: String {
        return String(format: "%.2f", averageQualityScore)
    }
}