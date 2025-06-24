//
//  AudioDebugLogger.swift
//  Livcap
//
//  Enhanced debug logging for audio processing with colored console output
//

import Foundation
import os.log
import Accelerate

class AudioDebugLogger {
    
    // MARK: - ANSI Color Codes for Console
    
    private enum ANSIColor: String {
        case reset = "\u{001B}[0m"
        case bold = "\u{001B}[1m"
        
        // Standard colors
        case black = "\u{001B}[30m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
        case white = "\u{001B}[37m"
        
        // Bright colors
        case brightRed = "\u{001B}[91m"
        case brightGreen = "\u{001B}[92m"
        case brightYellow = "\u{001B}[93m"
        case brightBlue = "\u{001B}[94m"
        case brightMagenta = "\u{001B}[95m"
        case brightCyan = "\u{001B}[96m"
        
        // Background colors
        case redBg = "\u{001B}[41m"
        case greenBg = "\u{001B}[42m"
        case yellowBg = "\u{001B}[43m"
    }
    
    // MARK: - Configuration
    
    struct DebugConfig {
        static let vadThreshold: Float = 0.01
        static let logEveryNthFrame: Int = 10
        static let highEnergyThreshold: Float = 0.05
        static let veryHighEnergyThreshold: Float = 0.1
    }
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livcap.debug", category: "AudioDebugLogger")
    private var frameCounters: [String: Int] = [:]
    
    // MARK: - Singleton
    
    static let shared = AudioDebugLogger()
    
    private init() {}
    
    // MARK: - Public Interface
    
    func logAudioFrame(
        source: AudioSource,
        frameIndex: Int,
        samples: [Float],
        sampleRate: Double,
        vadDecision: Bool? = nil
    ) {
        let sourceKey = source.rawValue
        frameCounters[sourceKey] = frameIndex
        
        // Only log every Nth frame to avoid spam
        guard frameIndex % DebugConfig.logEveryNthFrame == 0 else { return }
        
        let rms = calculateRMS(samples)
        let frameCount = samples.count
        let isAboveThreshold = rms > DebugConfig.vadThreshold
        
        // Determine colors and status
        let (rmsColor, rmsStatus) = getRMSColorAndStatus(rms)
        let vadColor: ANSIColor = vadDecision == true ? .brightGreen : .brightRed
        let vadStatus = vadDecision == true ? "SPEECH" : "SILENCE"
        
        // Build the log message with colors
        let sourceIcon = source.icon
        let frameInfo = "FRAME[\(frameIndex)]"
        let sourceInfo = "\(source.displayName.uppercased()): \(frameCount) samples @ \(Int(sampleRate))Hz"
        let rmsInfo = "RMS=\(String(format: "%.4f", rms))"
        let thresholdInfo = isAboveThreshold ? "ABOVE_THRESHOLD" : "BELOW_THRESHOLD"
        
        var message = "\(sourceIcon) \(frameInfo) \(sourceInfo), \(rmsInfo)"
        
        // Add threshold status with color
        let thresholdColor: ANSIColor = isAboveThreshold ? .brightGreen : .cyan
        message += ", \(thresholdColor.rawValue)\(thresholdInfo)\(ANSIColor.reset.rawValue)"
        
        // Add VAD decision if provided
        if let vadDecision = vadDecision {
            message += ", VAD=\(vadColor.rawValue)\(vadStatus)\(ANSIColor.reset.rawValue)"
        }
        
        // Print colored message to console
        printColoredMessage(message, baseColor: rmsColor)
        
        // Also log to system logger (without colors)
        let cleanMessage = "\(sourceIcon) \(frameInfo) \(sourceInfo), \(rmsInfo), \(thresholdInfo)" + 
                          (vadDecision != nil ? ", VAD=\(vadStatus)" : "")
        logger.info("\(cleanMessage)")
    }
    
    func logVADTransition(from previousState: Bool, to newState: Bool, confidence: Float = 0.0) {
        let transition = newState ? "SILENCE → SPEECH" : "SPEECH → SILENCE"
        let transitionColor: ANSIColor = newState ? .brightGreen : .brightRed
        let confidenceInfo = confidence > 0 ? " (confidence: \(String(format: "%.3f", confidence)))" : ""
        
        let message = "🔄 VAD TRANSITION: \(transitionColor.rawValue)\(transition)\(ANSIColor.reset.rawValue)\(confidenceInfo)"
        printColoredMessage(message, baseColor: .brightYellow)
        logger.info("🔄 VAD TRANSITION: \(transition)\(confidenceInfo)")
    }
    
    func logSystemAudioStatus(isEnabled: Bool, error: String? = nil) {
        if let error = error {
            let message = "💻 SYSTEM AUDIO ERROR: \(ANSIColor.brightRed.rawValue)\(error)\(ANSIColor.reset.rawValue)"
            printColoredMessage(message, baseColor: .red)
            logger.error("💻 SYSTEM AUDIO ERROR: \(error)")
        } else {
            let status = isEnabled ? "ENABLED" : "DISABLED"
            let statusColor: ANSIColor = isEnabled ? .brightGreen : .brightRed
            let message = "💻 SYSTEM AUDIO \(statusColor.rawValue)\(status)\(ANSIColor.reset.rawValue)"
            printColoredMessage(message, baseColor: .blue)
            logger.info("💻 SYSTEM AUDIO \(status)")
        }
    }
    
    func logBufferData(source: AudioSource, bufferSize: Int, duration: TimeInterval) {
        let sourceIcon = source.icon
        let durationStr = String(format: "%.2f", duration)
        let message = "\(sourceIcon) BUFFER: \(bufferSize) samples (\(durationStr)s)"
        printColoredMessage(message, baseColor: .cyan)
        logger.info("\(message)")
    }
    
    // MARK: - Private Methods
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    private func getRMSColorAndStatus(_ rms: Float) -> (ANSIColor, String) {
        if rms >= DebugConfig.veryHighEnergyThreshold {
            return (.redBg, "VERY_HIGH")
        } else if rms >= DebugConfig.highEnergyThreshold {
            return (.brightRed, "HIGH")
        } else if rms >= DebugConfig.vadThreshold {
            return (.brightGreen, "MEDIUM")
        } else {
            return (.cyan, "LOW")
        }
    }
    
    private func printColoredMessage(_ message: String, baseColor: ANSIColor) {
        print("\(baseColor.rawValue)\(message)\(ANSIColor.reset.rawValue)")
    }
    
    // MARK: - Frame Size Analysis
    
    func analyzeFrameSize(samples: [Float], sampleRate: Double) -> FrameAnalysis {
        let frameCount = samples.count
        let duration = Double(frameCount) / sampleRate
        let expectedFrameSize = sampleRate == 48000 ? 4800 : 1600
        let isExpectedSize = frameCount == Int(expectedFrameSize)
        
        return FrameAnalysis(
            sampleCount: frameCount,
            duration: duration,
            sampleRate: sampleRate,
            isExpectedSize: isExpectedSize,
            expectedSize: Int(expectedFrameSize)
        )
    }
}

// MARK: - Supporting Types

enum AudioSource: String, CaseIterable {
    case microphone = "microphone"
    case systemAudio = "systemAudio"
    case mixed = "mixed"
    
    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        case .mixed: return "Mixed"
        }
    }
    
    var icon: String {
        switch self {
        case .microphone: return "🎤"
        case .systemAudio: return "💻"
        case .mixed: return "🎵"
        }
    }
}

struct FrameAnalysis {
    let sampleCount: Int
    let duration: TimeInterval
    let sampleRate: Double
    let isExpectedSize: Bool
    let expectedSize: Int
    
    var durationMs: Double {
        return duration * 1000
    }
    
    var description: String {
        let durationStr = String(format: "%.1f", durationMs)
        return "\(sampleCount) samples (\(durationStr)ms @ \(Int(sampleRate))Hz)"
    }
} 