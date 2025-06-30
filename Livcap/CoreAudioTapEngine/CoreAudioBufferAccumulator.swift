//
//  CoreAudioBufferAccumulator.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/28/25.
//

import AVFoundation

/// An actor that accumulates incoming `AVAudioPCMBuffer` samples until a target frame count is reached,
/// then yields a full buffer to the provided `AsyncStream<AVAudioPCMBuffer>.Continuation`.
///
/// This is useful when incoming audio buffers are smaller than the target buffer size expected by
/// downstream consumers (e.g., speech recognition or audio processing pipelines).
///
/// - Parameters:
///   - format: The `AVAudioFormat` to use for all internal buffers, never change in this accumulator processing.
///   - targetFrameCount: The number of frames to accumulate before yielding.
///   - continuation: An `AsyncStream.Continuation` used to emit completed buffers downstream.
///
/// Usage example:
/// ```swift
/// let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
///     let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
///     let accumulator = CoreAudioBufferAccumulator(format: format,
///                                                  targetFrameCount: 1024,
///                                                  continuation: continuation)
///
///     // In your audio callback:
///     accumulator.append(buffer: incomingBuffer)
/// }
/// ```
actor CoreAudioBufferAccumulator{
    private var workingBuffer: AVAudioPCMBuffer
    private var format:AVAudioFormat
    private let targetFrameCount:AVAudioFrameCount
    private let continuation:AsyncStream<AVAudioPCMBuffer>.Continuation
    
    
    init(format:AVAudioFormat, targetFrameCount:AVAudioFrameCount, continuation:AsyncStream<AVAudioPCMBuffer>.Continuation)
    {
        self.format = format
        self.targetFrameCount = targetFrameCount
        self.continuation = continuation
        self.workingBuffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: targetFrameCount)!
    }
    
    func append(buffer incoming: AVAudioPCMBuffer) {
        let incomingFrameLength=incoming.frameLength
        let avaiableSpace=workingBuffer.frameCapacity-workingBuffer.frameLength
        
        guard let inData=incoming.floatChannelData?[0],
              let outData=workingBuffer.floatChannelData?[0]else {
            return
        }
        
        if incomingFrameLength<=avaiableSpace {
            memcpy(outData.advanced(by:Int(workingBuffer.frameLength)),
                   inData,
                   Int(incomingFrameLength)*MemoryLayout<Float>.size
            )
            workingBuffer.frameLength+=incomingFrameLength
        }else{
            let framesToCopy=avaiableSpace
            memcpy(outData.advanced(by:Int(workingBuffer.frameLength)),
                   inData,
                   Int(framesToCopy)*MemoryLayout<Float>.size
            )
            workingBuffer.frameLength+=framesToCopy
           
            // Yield buffer
            let yieldBuffer=cloneBuffer(from: workingBuffer, frameCount: targetFrameCount)
            continuation.yield(yieldBuffer)

            // Prepare working buffer for next round
            workingBuffer.frameLength = 0

            // Copy leftovers (if any)
            let remainingFrames = incomingFrameLength - framesToCopy
            if remainingFrames > 0 {
                memcpy(
                    outData,
                    inData.advanced(by: Int(framesToCopy)),
                    Int(remainingFrames) * MemoryLayout<Float>.size
                )
                workingBuffer.frameLength = remainingFrames
            }
            
        }
            
    }
    
    private func cloneBuffer(from buffer: AVAudioPCMBuffer, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        guard let newBuffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: frameCount) else {
            fatalError("Failed to allocate new buffer")
        }
        newBuffer.frameLength = frameCount
        if let src = buffer.floatChannelData?[0], let dst = newBuffer.floatChannelData?[0] {
            memcpy(dst, src, Int(frameCount) * MemoryLayout<Float>.size)
        }
        return newBuffer
    }

    func reset() {
        workingBuffer.frameLength = 0
    }
        
    
    
}
