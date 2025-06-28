//
//  CoreAudioTapEngine.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/26/25.
//  This class encapsulates the low-level Core Audio logic for creating a process tap

import Foundation
import AudioToolbox
import AVFoundation
import OSLog

@available(macOS 14.4, *)
final class CoreAudioTapEngine {
    
    // MARK: Properties
    
    // install tap, config
    private var targetProcesses:[AudioObjectID] = []
    private var targetFormat:AVAudioFormat
    
    // status:
    private var isInstalled = false
    private var isRunning = false
        
    // steam for using
    private var streamContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var stream: AsyncStream<AVAudioPCMBuffer>?

    // setup tap
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var processTapID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapStreamDescription:AudioStreamBasicDescription?

    
    private let queue=DispatchQueue(label: "com.livcap.CoreAudioTapEngine")
    
    init(forProcesses processIDs:[AudioObjectID]) {
        self.targetProcesses = processIDs
        self.isInstalled = true
        
        // Configure target audio format for speech recognition (mono, 16kHz)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create audio format")
        }
        
        self.targetFormat = format
    }
    
    
    
    func start () async throws {
        guard isInstalled else { throw NSError(domain: "Tap not installed", code: 0) }
        guard !isRunning else { return }
        
        
        
        
        isRunning=true
    }
    
    
    func stop() {
        if !isRunning { return }

        // Tear down tap and cleanup
        streamContinuation?.finish()
        streamContinuation = nil
        stream = nil
        isRunning = false
    }

    
    // TODO:
   func coreAudioTapStream()  throws -> AsyncStream<AVAudioPCMBuffer> {
        if let stream = stream {
            return stream
       }
       
       let stream=AsyncStream<AVAudioPCMBuffer> { continuation in
           self.streamContinuation = continuation
           continuation.onTermination = { @Sendable [weak self] _ in
               //stop
               self?.stop()
           }
       }
       
       self.stream = stream
       return stream
    }
    
    
    // MARK: - Internals
    
    
    private func setupTap() throws {
        cleanupTap()
        
        // 1. Ensure we have the processes to tap
        guard !targetProcesses.isEmpty else {
            throw CoreAudioTapEngineError.noTargetProcesses
        }
        
        // 2. creat the tapdescription
        let tapDescription=CATapDescription(stereoMixdownOfProcesses: targetProcesses)
        tapDescription.isPrivate=true
        
        
        // 3. Get systemoutput for aggreate device creation
        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        
        // 4 Create process tap
        var tapID:AUAudioObjectID = .unknown
        let err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            throw CoreAudioTapEngineError.tapCreationFailed(err)
        }
        
        // 5 get the preocessTap for the proecess
        self.processTapID=tapID
        
        // 6 get the tap audio format using the format convert
        self.tapStreamDescription=try tapID.readAudioTapStreamBasicDescription()
        
        //7. creat the aggreate device
        let aggregateUID = UUID().uuidString
        let description:[String:Any] = [
                kAudioAggregateDeviceNameKey: "Livcap-ChromeAudioTap",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapDriftCompensationKey: true,
                        kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                    ]
                ]
        ]
        
        var aggreagateID = AudioObjectID.unknown
        let aggreatedErr = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggreagateID)
        guard aggreatedErr==noErr else {
            throw CoreAudioTapEngineError.aggregateCreationFailed(aggreatedErr)
        }
        
        self.aggregateDeviceID=aggreagateID
        
    }
    
    private func setupAudioProcessing() throws {
        //1. Geting the inputformat from the setup which is match with tap's
        guard var streamDescription=tapStreamDescription else {
            throw CoreAudioTapEngineError.invalidTapStreamDescription
        }
        
        guard let inputFormat=AVAudioFormat(streamDescription: &streamDescription) else{
            throw CoreAudioTapEngineError.formatCreationFailed
        }
        
        //2. create I/O proc for audio processing
        let targetFormatCapture = self.targetFormat
        var systemAudioFrameCounter=0
        
        let ioBlock: AudioDeviceIOBlock = { [weak self, inputFormat, targetFormatCapture] _, inInputData, _ ,_ ,_ in
            guard let self = self else { return }
            systemAudioFrameCounter+=1
            
            // Create input buffer based on the inputformat
            guard let inputBuffer=AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    bufferListNoCopy: inInputData,
                    deallocator: nil
            )else{
                print("Failed to create input buffer")
                return
            }
            
            // Convert to target format if needed
            let processedBuffer=self.convertBufferFormat(inputBuffer, to: targetFormatCapture)
            
            // Extrac float samples and conver stereo to mono
            let frameCount = Int(processedBuffer.frameLength)
            let channelCount=Int((processedBuffer.format.channelCount))
            
            
            
            
        }
        
        
        
        
    }
    
    private func cleanupTap() {
        
    }
    
    
    
    
    
    /// Converts the given AVAudioPCMBuffer to match the target AVAudioFormat. without channel change.
    /// - Parameters:
    ///   - buffer: The input AVAudioPCMBuffer to convert.
    ///   - format: The desired AVAudioFormat to convert the buffer to.
    /// - Returns: A converted AVAudioPCMBuffer if conversion succeeds, otherwise the original buffer.
    private func convertBufferFormat(_ buffer:AVAudioPCMBuffer , to format:AVAudioFormat) -> AVAudioPCMBuffer{
        
        // 1. if match exactly, return it
        if buffer.format.sampleRate==format.sampleRate &&
            buffer.format.channelCount==format.channelCount {
            return buffer
        }
            
        // 2. Create the target format for convertion
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt32, sampleRate: format.sampleRate, channels: buffer.format.channelCount, interleaved: false) else {
            return buffer
        }
        
        // 3. create the conveter
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return buffer
        }
        
        // 4. cacluate the requried capacity
        let outputFrameCapacity=AVAudioFrameCount(
            (Double(buffer.frameCapacity) * targetFormat.sampleRate) / Double(format.sampleRate)
        )
        
        // 5. create the buffer
        guard let outputBuffer=AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return buffer
        }
        
        outputBuffer.frameLength=outputFrameCapacity
        
        // 6.perform the conversion
        var error: NSError?
        let status=converter.convert(to: outputBuffer, error: &error){
            inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        
        if status == .error || error != nil {
            return buffer
        }
        
        return outputBuffer
    }
    
    
    
    /// Converts a stereo `AVAudioPCMBuffer` into a mono buffer by averaging the left and right channels.
    /// - Parameters:
    ///   - inputBuffer: The input buffer expected to contain stereo audio (2 channels).
    ///   - targetFormat: The desired audio format (currently unused in the conversion).
    /// - Returns: A mono `AVAudioPCMBuffer` with the same sample rate and frame length, or `nil` if conversion fails.
    private func convertToMono(from inputBuffer: AVAudioPCMBuffer, targetFormat:AVAudioFormat) -> AVAudioPCMBuffer?{
        let framelength=inputBuffer.frameLength
        guard inputBuffer.format.channelCount==2 else {return inputBuffer}
        
        // create the mono format
        guard let monoFormat=AVAudioFormat(commonFormat: inputBuffer.format.commonFormat, sampleRate: inputBuffer.format.sampleRate, channels: 1, interleaved: false)else {return nil}
        
        // create the mono buffer
        guard let monoBuffer=AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: framelength) else {return nil}
        
        monoBuffer.frameLength=framelength
        
        // Access channe data
        guard let stereoDataL=inputBuffer.floatChannelData?[0],
              let stereoDataR=inputBuffer.floatChannelData?[1],
                let monoData=monoBuffer.floatChannelData?[0] else {return nil}
        
        for i in 0..<framelength{
            monoData[Int(i)]=(stereoDataL[Int(i)]+stereoDataR[Int(i)])/2.0
        }
        
        return monoBuffer
    }
    
    
    
    
    

    
}



enum CoreAudioTapEngineError: Error, LocalizedError {
    case noTargetProcesses
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case formatCreationFailed
    case invalidTapStreamDescription
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case tapNotInstalled

    var errorDescription: String? {
        switch self {
        case .noTargetProcesses:
            return "No target audio processes were specified for the tap."
        case .tapCreationFailed(let status):
            return "Failed to create the system audio tap. Error code: \(status)"
        case .aggregateCreationFailed(let status):
            return "Failed to create the aggregate audio device. Error code: \(status)"
        case .formatCreationFailed:
            return "Unable to create AVAudioFormat from tap stream description."
        case .invalidTapStreamDescription:
            return "Invalid or missing stream description from the audio tap."
        case .ioProcCreationFailed(let status):
            return "Failed to create I/O proc for audio processing. Error code: \(status)"
        case .deviceStartFailed(let status):
            return "Failed to start audio device for capture. Error code: \(status)"
        case .tapNotInstalled:
            return "Tap must be installed before starting the engine."
        }
    }
}
