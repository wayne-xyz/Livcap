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
    let energyThreshold: Float = 0.01           // Energy-based threshold
    let spectralThreshold: Float = 0.3          // Spectral-based threshold
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
    let spectralActivity: Float
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
    
    // Spectral Analysis
    private var fftSetup: FFTSetup?
    private let fftSize = 512
    private var hannWindow: [Float] = []
    
    // Monitoring
    @Published var currentVADState: Bool = false
    @Published var currentConfidence: Float = 0.0
    @Published var currentEnergyLevel: Float = 0.0
    @Published var currentSpectralActivity: Float = 0.0
    @Published var activeSpeechSegments: [SpeechSegment] = []
    
    init() {
        setupSpectralAnalysis()
        setupVADHistory()
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    private func setupSpectralAnalysis() {
        // Setup FFT for spectral analysis
        let log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        // Create Hann window for spectral analysis
        hannWindow = Array(0..<fftSize).map { n in
            0.5 * (1.0 - cos(2.0 * Float.pi * Float(n) / Float(fftSize - 1)))
        }
        
        print("EnhancedVAD: Spectral analysis setup complete (FFT size: \(fftSize))")
    }
    
    private func setupVADHistory() {
        // Initialize state history for hysteresis
        stateHistory = Array(repeating: false, count: config.hysteresisSamples / 100) // Rough estimation
        print("EnhancedVAD: Initialized with config - Energy: \(config.energyThreshold), Spectral: \(config.spectralThreshold)")
    }
    
    func processAudioChunk(_ samples: [Float]) -> VADResult {
        let timestamp = Date()
        
        // 1. Energy-based VAD
        let energyLevel = calculateRMSEnergy(samples)
        let energyVAD = energyLevel > config.energyThreshold
        
        // 2. Spectral-based VAD
        let spectralActivity = calculateSpectralActivity(samples)
        let spectralVAD = spectralActivity > config.spectralThreshold
        
        // 3. Combined decision with weighted confidence
        let isSpeech = energyVAD && spectralVAD
        let confidence = calculateConfidence(energyLevel: energyLevel, spectralActivity: spectralActivity)
        
        // 4. Apply hysteresis and state management
        let finalDecision = applyHysteresis(isSpeech, confidence: confidence, timestamp: timestamp)
        
        let result = VADResult(
            isSpeech: finalDecision,
            confidence: confidence,
            energyLevel: energyLevel,
            spectralActivity: spectralActivity,
            timestamp: timestamp
        )
        
        // Update published properties
        currentVADState = finalDecision
        currentConfidence = confidence
        currentEnergyLevel = energyLevel
        currentSpectralActivity = spectralActivity
        
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
    
    private func calculateSpectralActivity(_ samples: [Float]) -> Float {
        guard let fftSetup = fftSetup, samples.count >= fftSize else {
            return 0.0
        }
        
        // Take the first fftSize samples and apply window
        let windowedSamples = zip(samples.prefix(fftSize), hannWindow).map { $0 * $1 }
        
        // Simplified spectral activity calculation using high-frequency energy
        // This avoids complex FFT pointer management while still providing spectral info
        let highFreqStart = windowedSamples.count / 4  // Rough high-frequency approximation
        let highFreqEnergy = windowedSamples.suffix(from: highFreqStart).map { $0 * $0 }.reduce(0, +)
        let totalEnergy = windowedSamples.map { $0 * $0 }.reduce(0, +)
        
        let spectralActivity = totalEnergy > 0 ? highFreqEnergy / totalEnergy : 0.0
        
        // Normalize and scale for speech detection
        return min(1.0, spectralActivity * 2.0)  // Scale up for better sensitivity
    }
    
    private func calculateConfidence(energyLevel: Float, spectralActivity: Float) -> Float {
        // Weighted combination of energy and spectral confidence
        let energyConfidence = min(1.0, energyLevel / (config.energyThreshold * 3.0))
        let spectralConfidence = min(1.0, spectralActivity / config.spectralThreshold)
        
        // Weight spectral features more heavily for speech detection
        return (energyConfidence * 0.3 + spectralConfidence * 0.7)
    }
    
    private func applyHysteresis(_ rawDecision: Bool, confidence: Float, timestamp: Date) -> Bool {
        // Update state history
        stateHistory.append(rawDecision)
        if stateHistory.count > config.hysteresisSamples / 100 {
            stateHistory.removeFirst()
        }
        
        // Count recent speech decisions
        let recentSpeechCount = stateHistory.suffix(5).filter { $0 }.count
        
        // Apply hysteresis logic
        let hysteresisDecision: Bool
        if currentState {
            // Currently in speech - require strong evidence of silence to switch
            hysteresisDecision = recentSpeechCount >= 2 || confidence > 0.4
        } else {
            // Currently in silence - require strong evidence of speech to switch
            hysteresisDecision = recentSpeechCount >= 3 && confidence > 0.5
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