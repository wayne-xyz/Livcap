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
    private var targetFormat:AVAudioFormat?
    
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
    

    
    func installTap(forProcesses processIDs:[AudioObjectID]) throws {
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
            
            
            
                
            
        }
        
        
        
    }
    
    private func cleanupTap() {
        
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
