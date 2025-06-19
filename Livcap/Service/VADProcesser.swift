//
//  VADProcesser.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/18/25.
//
import Foundation
import AVFoundation
import Accelerate



let VAD_THRESHOLD: Float = 0.001


class VADProcesser{
    private let vadThreshold: Float = VAD_THRESHOLD
    
    // Simple VAD
    private func isSpeech(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?.pointee else { return false }
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
        let isSpeechDetected = rms > vadThreshold
        
        if isSpeechDetected {
            print("🎤 Speech detected! RMS: \(rms), Threshold: \(vadThreshold)")
        }
        
        return isSpeechDetected
    }

}
