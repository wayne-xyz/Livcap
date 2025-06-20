//
//  VADProcesser.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/18/25.
//
import Foundation
import AVFoundation
import Accelerate


// VADProcessor.swift
final class VADProcessor {
    private let energyThreshold: Float = 0.005
    private let speechCountThreshold = 3 // Number of consecutive speech frames to confirm speech
    private let silenceCountThreshold = 5 // Number of consecutive silence frames to confirm silence

    private var consecutiveSpeechFrames: Int = 0
    private var consecutiveSilenceFrames: Int = 0
    private var lastIsSpeechDecision: Bool = false // State variable

    func processAudioChunk(_ samples: [Float]) -> Bool {
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        let currentChunkIsAboveThreshold = rms > energyThreshold // Instantaneous decision

        if currentChunkIsAboveThreshold {
            consecutiveSpeechFrames += 1
            consecutiveSilenceFrames = 0
        } else {
            consecutiveSilenceFrames += 1
            consecutiveSpeechFrames = 0
        }

        var newIsSpeechDecision = lastIsSpeechDecision // Default to current state

        if consecutiveSpeechFrames >= speechCountThreshold {
            newIsSpeechDecision = true
        } else if consecutiveSilenceFrames >= silenceCountThreshold {
            newIsSpeechDecision = false
        }
        
        lastIsSpeechDecision = newIsSpeechDecision
        return newIsSpeechDecision
    }

    func reset() { // Resets internal state
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        lastIsSpeechDecision = false
    }
}
