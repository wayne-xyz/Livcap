//
//  CaptionEntry.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/20/25.
//

import Foundation
@preconcurrency import AVFoundation

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
    let buffer: AVAudioPCMBuffer
    let vadResult: AudioVADResult
    let source: AudioSource
    let frameIndex: Int
    
    // Convenience properties
    var isSpeech: Bool { vadResult.isSpeech }
    var confidence: Float { vadResult.confidence }
    var rmsEnergy: Float { vadResult.rmsEnergy }
    var timestamp: Date { vadResult.timestamp }
    var sampleRate: Double { buffer.format.sampleRate }
    var frameLength: Int { Int(buffer.frameLength) }
    
    // Convenience accessor for when float samples are specifically needed (debugging, etc.)
    var samples: [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
    
    init(buffer: AVAudioPCMBuffer, vadResult: AudioVADResult, source: AudioSource, frameIndex: Int) {
        self.buffer = buffer
        self.vadResult = vadResult
        self.source = source
        self.frameIndex = frameIndex
    }
}
