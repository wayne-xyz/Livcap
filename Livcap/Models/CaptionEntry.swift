//
//  CaptionEntry.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/20/25.
//

import Foundation

/// Simplified caption entry for clean display
struct CaptionEntry: Identifiable, Sendable {
    let id: UUID
    let text: String
    let confidence: Float? // Optional confidence score
    
    init(id: UUID = UUID(), text: String, confidence: Float? = nil) {
        self.id = id
        self.text = text
        self.confidence = confidence
    }
}

// MARK: - Audio Frame with VAD Metadata

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

struct AudioVADResult: Sendable {
    let isSpeech: Bool
    let confidence: Float
    let rmsEnergy: Float
    let timestamp: Date
    
    init(isSpeech: Bool, confidence: Float, rmsEnergy: Float, timestamp: Date = Date()) {
        self.isSpeech = isSpeech
        self.confidence = confidence
        self.rmsEnergy = rmsEnergy
        self.timestamp = timestamp
    }
}

struct AudioFrameWithVAD: Sendable {
    let samples: [Float]
    let vadResult: AudioVADResult
    let source: AudioSource
    let frameIndex: Int
    let sampleRate: Double
    
    // Convenience properties
    var isSpeech: Bool { vadResult.isSpeech }
    var confidence: Float { vadResult.confidence }
    var rmsEnergy: Float { vadResult.rmsEnergy }
    var timestamp: Date { vadResult.timestamp }
    
    init(samples: [Float], vadResult: AudioVADResult, source: AudioSource, frameIndex: Int, sampleRate: Double = 16000.0) {
        self.samples = samples
        self.vadResult = vadResult
        self.source = source
        self.frameIndex = frameIndex
        self.sampleRate = sampleRate
    }
}
