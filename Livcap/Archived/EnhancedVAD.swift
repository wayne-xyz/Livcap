//
//  EnhancedVAD.swift
//  Livcap
//
//  Enhanced Voice Activity Detection for Phase 2
//

import Foundation
import Accelerate
import SwiftUI

struct VADConfig {
    let energyThreshold: Float = 0.01           // RMS energy threshold
    let hysteresisMs: Int = 200                 // Prevent rapid state changes
    let minSpeechDurationMs: Int = 300          // Minimum speech segment
    let minSilenceDurationMs: Int = 500         // Minimum silence for segment end
    let sampleRate: Int = 16000                 // 16kHz sampling rate
    
    var hysteresisSamples: Int {
        return (sampleRate * hysteresisMs) / 1000
    }
    
    var minSpeechSamples: Int {
        return (sampleRate * minSpeechDurationMs) / 1000
    }
    
    var minSilenceSamples: Int {
        return (sampleRate * minSilenceDurationMs) / 1000
    }
}

struct VADResult {
    let isSpeech: Bool
    let confidence: Float
    let energyLevel: Float
    let timestamp: Date
}

struct SpeechSegment {
    let startTimestamp: Date
    let endTimestamp: Date
    let duration: TimeInterval
    let averageConfidence: Float
    let id: UUID = UUID()
}

class EnhancedVAD: ObservableObject {
    private let config = VADConfig()
    
    // VAD State
    private var currentState: Bool = false      // Current speech/silence state
    private var stateHistory: [Bool] = []       // History for hysteresis
    private var speechStartTime: Date?          // Current speech segment start
    private var silenceStartTime: Date?         // Current silence segment start
    private var vadResults: [VADResult] = []    // Recent VAD results for analysis
    
    // Monitoring
    @Published var currentVADState: Bool = false
    @Published var currentConfidence: Float = 0.0
    @Published var currentEnergyLevel: Float = 0.0
    @Published var activeSpeechSegments: [SpeechSegment] = []
    
    init() {
        setupVADHistory()
    }
    
    private func setupVADHistory() {
        // Initialize state history for hysteresis
        stateHistory = Array(repeating: false, count: config.hysteresisSamples / 100) // Rough estimation
        print("EnhancedVAD: Initialized with RMS-only VAD - Energy threshold: \(config.energyThreshold)")
    }
    
    func processAudioChunk(_ samples: [Float]) -> VADResult {
        let timestamp = Date()
        
        // 1. RMS Energy-based VAD only
        let energyLevel = calculateRMSEnergy(samples)
        let isSpeech = energyLevel > config.energyThreshold
        
        // 2. Simple confidence based on energy level
        let confidence = calculateConfidence(energyLevel: energyLevel)
        
        // 3. Apply hysteresis and state management
        let finalDecision = applyHysteresis(isSpeech, confidence: confidence, timestamp: timestamp)
        
        let result = VADResult(
            isSpeech: finalDecision,
            confidence: confidence,
            energyLevel: energyLevel,
            timestamp: timestamp
        )
        
        // Update published properties
        currentVADState = finalDecision
        currentConfidence = confidence
        currentEnergyLevel = energyLevel
        
        // Store result for analysis
        vadResults.append(result)
        if vadResults.count > 100 {  // Keep only recent results
            vadResults.removeFirst()
        }
        
        return result
    }
    
    private func calculateRMSEnergy(_ samples: [Float]) -> Float {
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    private func calculateConfidence(energyLevel: Float) -> Float {
        // Simple confidence based on how much energy exceeds threshold
        // Scale from threshold to 3x threshold for full confidence
        let maxEnergyForFullConfidence = config.energyThreshold * 3.0
        let confidence = min(1.0, energyLevel / maxEnergyForFullConfidence)
        return confidence
    }
    
    private func applyHysteresis(_ rawDecision: Bool, confidence: Float, timestamp: Date) -> Bool {
        // Update state history
        stateHistory.append(rawDecision)
        if stateHistory.count > config.hysteresisSamples / 100 {
            stateHistory.removeFirst()
        }
        
        // New asymmetric hysteresis strategy:
        // Silence → Speech: IMMEDIATE (no hysteresis for quick response)
        // Speech → Silence: HYSTERESIS (keep more context for model)
        
        let hysteresisDecision: Bool
        if currentState {
            // Currently in SPEECH - use hysteresis to avoid cutting off words
            // Need sustained silence before switching to silence
            let recentSpeechCount = stateHistory.suffix(8).filter { $0 }.count // 800ms window
            hysteresisDecision = recentSpeechCount >= 2 || confidence > 0.3
            
            if !hysteresisDecision {
                print("🔇 Speech→Silence: Sustained silence detected, switching to silence")
            }
        } else {
            // Currently in SILENCE - immediate response to speech
            // Any frame above threshold immediately triggers speech
            hysteresisDecision = rawDecision && confidence > 0.3
            
            if hysteresisDecision {
                print("🎤 Silence→Speech: Immediate speech detection, triggering inference")
            }
        }
        
        // Update state and manage speech segments
        if hysteresisDecision != currentState {
            updateSpeechSegments(newState: hysteresisDecision, timestamp: timestamp, confidence: confidence)
            currentState = hysteresisDecision
        }
        
        return hysteresisDecision
    }
    
    private func updateSpeechSegments(newState: Bool, timestamp: Date, confidence: Float) {
        if newState {
            // Starting speech
            speechStartTime = timestamp
            silenceStartTime = nil
            print("🎤 VAD: Speech started at \(timestamp) (confidence: \(String(format: "%.3f", confidence)))")
        } else {
            // Starting silence
            if let startTime = speechStartTime {
                let duration = timestamp.timeIntervalSince(startTime)
                
                // Only create segment if it meets minimum duration
                if duration >= Double(config.minSpeechDurationMs) / 1000.0 {
                    let segment = SpeechSegment(
                        startTimestamp: startTime,
                        endTimestamp: timestamp,
                        duration: duration,
                        averageConfidence: confidence
                    )
                    
                    activeSpeechSegments.append(segment)
                    
                    // Keep only recent segments
                    if activeSpeechSegments.count > 20 {
                        activeSpeechSegments.removeFirst()
                    }
                    
                    print("🔇 VAD: Speech ended - Duration: \(String(format: "%.2f", duration))s")
                }
            }
            
            speechStartTime = nil
            silenceStartTime = timestamp
        }
    }
    
    // MARK: - Public Interface
    
    func isCurrentlySpeaking() -> Bool {
        return currentState
    }
    
    func getCurrentSpeechDuration() -> TimeInterval? {
        guard let startTime = speechStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }
    
    func getRecentVADHistory(seconds: Int = 5) -> [VADResult] {
        let cutoffTime = Date().addingTimeInterval(-Double(seconds))
        return vadResults.filter { $0.timestamp >= cutoffTime }
    }
    
    func shouldTriggerTranscription() -> Bool {
        // More sophisticated transcription triggering
        guard let speechDuration = getCurrentSpeechDuration() else { return false }
        
        // Trigger if we've had continuous speech for minimum duration
        let minDuration = Double(config.minSpeechDurationMs) / 1000.0
        return speechDuration >= minDuration
    }
    
    func getVADMetrics() -> (speechPercentage: Float, averageConfidence: Float, segmentCount: Int) {
        let recentResults = getRecentVADHistory(seconds: 10)
        guard !recentResults.isEmpty else { return (0.0, 0.0, 0) }
        
        let speechCount = recentResults.filter { $0.isSpeech }.count
        let speechPercentage = Float(speechCount) / Float(recentResults.count)
        let averageConfidence = recentResults.map { $0.confidence }.reduce(0, +) / Float(recentResults.count)
        
        return (speechPercentage, averageConfidence, activeSpeechSegments.count)
    }
    
    func reset() {
        currentState = false
        stateHistory.removeAll()
        speechStartTime = nil
        silenceStartTime = nil
        vadResults.removeAll()
        activeSpeechSegments.removeAll()
        
        setupVADHistory()
        print("EnhancedVAD: Reset complete")
    }
}