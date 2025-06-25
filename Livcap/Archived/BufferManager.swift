//
//  BufferManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/19/25.
//

import Foundation
import Combine


struct TranscribableAudioSegment{
    let audio:[Float]
    let startTimeMS:Int
    let id:UUID
    
}


actor BufferManager {
    // configuration
    // receved from the audiomanage 16k , each frame 1600samples, 100ms
    private let sampleRate:Double=16000.0
    private let frameDuration:Int=100
    private let silenceTriggerFrameCount:Int=3
    private let maxAccumulationDurationMS:Int=15000
    
    //internel buffers and state
    private var accumulatedSpeechBuffer:[Float]=[]
    private var currentSegmentStartTimeMS:Int=0
    private var currentSilenceFrameCount:Int=0
    private var isCurrentlySpeaking:Bool=false
    private var currentRecordedDurationMS:Int=0
    
    private let vadProcessor: VADProcessor
    
    init(vadProcessor: VADProcessor = VADProcessor()) {
       self.vadProcessor = vadProcessor
    }

    
    
    func appendAudioSamples(_ samples:[Float]) async -> TranscribableAudioSegment?{
        let frameDuration=Int(Double(samples.count)/sampleRate*1000) // it supposed to be 100
        self.currentRecordedDurationMS+=frameDuration
        
        let isSpeechInFrame:Bool=vadProcessor.processAudioChunk(samples)
        
        var segmentToReturn:TranscribableAudioSegment?=nil
        
        if isSpeechInFrame{
            self.accumulatedSpeechBuffer.append(contentsOf: samples)
            self.currentSilenceFrameCount=0
            if !self.isCurrentlySpeaking{
                self.isCurrentlySpeaking=true
                self.currentSegmentStartTimeMS=self.currentRecordedDurationMS-frameDuration
            }
        }else{// silence detection
            if self.isCurrentlySpeaking{
                self.currentSilenceFrameCount+=1
                if self.currentSilenceFrameCount>=self.silenceTriggerFrameCount{
                    segmentToReturn=self.createAndClearCurrentSegment(reason: .silenceDetected)
                    self.isCurrentlySpeaking=false
                    self.currentSilenceFrameCount=0
                }
            }
        }
        // --- Max Accumulation Duration (for long, continuous speech) ---
        if self.isCurrentlySpeaking {
            let accumulatedDurationMs = Int(Double(self.accumulatedSpeechBuffer.count) / self.sampleRate * 1000.0)
            if accumulatedDurationMs >= self.maxAccumulationDurationMS {
                segmentToReturn = self.createAndClearCurrentSegment(reason: .maxDurationReached)
                self.isCurrentlySpeaking = false
                self.currentSilenceFrameCount = 0
            }
        }
        
        return segmentToReturn
    }
    
    
    func processFrames<S: AsyncSequence>(_ frames:S) -> AsyncStream<TranscribableAudioSegment> where S.Element == [Float] {
        AsyncStream{ continuation in
            Task {
                do {
                    for try await frame in frames {
                        if let segemt = await self.appendAudioSamples(frame) {
                            continuation.yield(segemt)
                        }
                        try Task.checkCancellation()
                    }
                    
                    if let finalSegment=await self.getRemainingSegment(){
                        continuation.yield(finalSegment)
                    }
                }catch{
                    print("Buffer Manager Error: Error processing frames: \(error)")
                }
                continuation.finish()
            }
        }
    }
    
    
    
    private func createAndClearCurrentSegment(reason: TriggerReason) -> TranscribableAudioSegment? {
        guard !self.accumulatedSpeechBuffer.isEmpty else { return nil }

        let segment = TranscribableAudioSegment(
            audio: self.accumulatedSpeechBuffer,
            startTimeMS: self.currentSegmentStartTimeMS,
            id: UUID()
        )
        print("Segment created for transcription (starting at \(segment.startTimeMS)ms, reason: \(reason))")
        self.accumulatedSpeechBuffer.removeAll()
        return segment
    }
    
    private enum TriggerReason: Sendable {
         case silenceDetected
         case maxDurationReached
         case forcedStop // For when recording ends
     }
    
    func reset() async {
        if self.createAndClearCurrentSegment(reason: .forcedStop) != nil {
            print("SpeechAccumulator reset with pending segment")
        }
        self.accumulatedSpeechBuffer.removeAll()
        self.currentSegmentStartTimeMS = 0
        self.currentSilenceFrameCount = 0
        self.isCurrentlySpeaking = false
        self.currentRecordedDurationMS = 0
        self.vadProcessor.reset()
    }
    
    func getRemainingSegment() async -> TranscribableAudioSegment? {
        return self.createAndClearCurrentSegment(reason: .forcedStop)
    }
    
}
