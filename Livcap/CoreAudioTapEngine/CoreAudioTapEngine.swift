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
import Accelerate

@available(macOS 14.4, *)
final class CoreAudioTapEngine {
    
    // MARK: Properties
    
    // Logging
    private let logger = Logger(subsystem: "com.waynexyz.Livcap", category: "CoreAudioTapEngine")
    
    // init
    private var targetProcesses:[AudioObjectID] = []
    private var targetFormat:AVAudioFormat
    private var targetBufferSize=1600 // for the audio 16k, match the micphone buffer size
    
    
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
    
    // setup at the stream processing
    private var bufferAaccumulator:CoreAudioBufferAccumulator?
    
    // setup a queue for the AudioDeviceCreateIOProcIDWithBlock access the tap
    private let ioProcQueue=DispatchQueue(label: "com.waynexyz.Livcap.ioProcQueue")

    
    init(forProcesses processIDs:[AudioObjectID]) {
        self.targetProcesses = processIDs
        self.isInstalled = true
        
        logger.info("🎯 CoreAudioTapEngine initializing with \(processIDs.count) target processes: \(processIDs)")
        
        // Configure target audio format for speech recognition (mono, 16kHz)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("❌ Failed to create audio format")
            fatalError("Failed to create audio format")
        }
        
        self.targetFormat = format
        logger.info("✅ CoreAudioTapEngine initialized with target format: \(format)")
    }
    
    
    // Main funciotn to start
    func start () async throws {
        logger.info("🚀 Starting CoreAudioTapEngine...")
        
        guard isInstalled else { 
            logger.error("❌ Tap not installed")
            throw NSError(domain: "Tap not installed", code: 0) 
        }
        guard !isRunning else { 
            logger.warning("⚠️ Engine already running")
            return 
        }
        
        do{
            logger.info("📋 Step 1: Setting up tap...")
            try setupTap()
            logger.info("✅ Tap setup complete")
            
            logger.info("📋 Step 2: Setting up audio processing...")
            try setupAudioProcessing()
            logger.info("✅ Audio processing setup complete")
            
            logger.info("📋 Step 3: Starting audio device...")
            try startAudioDevice()
            logger.info("✅ Audio device started")
            
            await MainActor.run{
                self.isRunning=true
            }
            
            logger.info("🎉 CoreAudioTapEngine started successfully!")
            
        }catch{
            logger.error("❌ Failed to start CoreAudioTapEngine: \(error)")
            cleanupTap()
            throw error
        }
    }
    
    
    func stop()   {
        guard isRunning else{ 
            logger.warning("⚠️ Engine not running, nothing to stop")
            return
        }
        
        logger.info("🛑 Stopping CoreAudioTapEngine...")
        
        do {
            try stopAudioDevice()
            logger.info("✅ Audio device stopped")
        }catch {
            logger.error("❌ Audio device stop failed: \(error)")
        }

        Task{ [weak self] in
            await self?.bufferAaccumulator?.reset()
        }
        bufferAaccumulator=nil
        logger.info("🗑️ Buffer accumulator cleaned")
        
        cleanupTap()

        // Tear down tap and cleanup
        streamContinuation?.finish()
        streamContinuation = nil
        stream = nil
        isRunning = false
        
        logger.info("✅ CoreAudioTapEngine stopped successfully")
    }

    
    // TODO:
   func coreAudioTapStream()  throws -> AsyncStream<AVAudioPCMBuffer> {
        logger.info("📺 Creating core audio tap stream...")
        
        if let stream = stream {
            logger.info("✅ Returning existing stream")
            return stream
       }
       
       logger.info("📋 Creating new AsyncStream...")
       let stream=AsyncStream<AVAudioPCMBuffer> { continuation in
           self.streamContinuation = continuation
           continuation.onTermination = { @Sendable [weak self] _ in
               //stop
               self?.logger.info("🔚 Stream terminated, stopping engine...")
               self?.stop()
           }
       }
       
       self.stream = stream
       logger.info("✅ AsyncStream created successfully")
       return stream
    }
    
    
    // MARK: - Internals
    
    
    private func setupTap() throws {
        logger.info("🔧 Setting up tap...")
        cleanupTap()
        
        // 1. Ensure we have the processes to tap
        guard !targetProcesses.isEmpty else {
            logger.error("❌ No target processes provided")
            throw CoreAudioTapEngineError.noTargetProcesses
        }
        logger.info("✅ Target processes validated: \(self.targetProcesses.count) processes")
        
        // 2. creat the tapdescription
        logger.info("📋 Creating tap description for processeself.s: \(self.targetProcesses)")
        let tapDescription=CATapDescription(stereoMixdownOfProcesses: targetProcesses)
        tapDescription.isPrivate=true
        logger.info("✅ Tap description created with UUID: \(tapDescription.uuid)")
        
        // 3. Get systemoutput for aggreate device creation
        logger.info("📋 Getting system output device...")
        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        logger.info("✅ System output device: \(systemOutputID), UID: \(outputUID)")
        
        // 4 Create process tap
        logger.info("📋 Creating process tap...")
        var tapID:AUAudioObjectID = kAudioObjectUnknown
        let err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            logger.error("❌ Failed to create process tap, error: \(err)")
            throw CoreAudioTapEngineError.tapCreationFailed(err)
        }
        logger.info("✅ Process tap created with ID: \(tapID)")
        
        // 5 get the preocessTap for the proecess
        self.processTapID=tapID
        
        // 6 get the tap audio format using the format convert
        logger.info("📋 Reading tap stream description...")
        self.tapStreamDescription=try tapID.readAudioTapStreamBasicDescription()
        logger.info("✅ Tap stream description obtained: \(self.tapStreamDescription?.mSampleRate ?? 0) Hz, \(self.tapStreamDescription?.mChannelsPerFrame ?? 0) channels")
        
        //7. creat the aggreate device
        logger.info("📋 Creating aggregate device...")
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
            logger.error("❌ Failed to create aggregate device, error: \(aggreatedErr)")
            throw CoreAudioTapEngineError.aggregateCreationFailed(aggreatedErr)
        }
        
        self.aggregateDeviceID=aggreagateID
        logger.info("✅ Aggregate device created with ID: \(aggreagateID)")
        
    }
    
    private func setupAudioProcessing() throws {
        logger.info("🎛️ Setting up audio processing...")
        
        //1. Geting the inputformat from the setup which is match with tap's
        logger.info("📋 Step 1: Getting input format from tap stream description...")
        guard var streamDescription=tapStreamDescription else {
            logger.error("❌ Tap stream description is nil")
            throw CoreAudioTapEngineError.invalidTapStreamDescription
        }
        logger.info("✅ Tap stream description obtained: \(streamDescription.mSampleRate) Hz, \(streamDescription.mChannelsPerFrame) channels")
        
        guard let inputFormat=AVAudioFormat(streamDescription: &streamDescription) else{
            logger.error("❌ Failed to create AVAudioFormat from stream description")
            throw CoreAudioTapEngineError.formatCreationFailed
        }
        logger.info("✅ Input format created: \(inputFormat)")

        
        //2. set the accumulator
        logger.info("📋 Step 2: Setting up buffer accumulator...")
        guard let continuation=streamContinuation else{
            logger.error("❌ Stream continuation is nil - tap not properly installed")
            throw CoreAudioTapEngineError.tapNotInstalled
        }
        logger.info("✅ Stream continuation available")
        
        bufferAaccumulator=CoreAudioBufferAccumulator(format: targetFormat, targetFrameCount: AVAudioFrameCount(targetBufferSize), continuation: continuation)
        logger.info("✅ Buffer accumulator created with target format: \(self.targetFormat), buffer size: \(self.targetBufferSize)")
        
        //3. create I/O proc for audio processing
        logger.info("📋 Step 3: Creating I/O proc for audio processing...")
        let targetFormatCapture = self.targetFormat
        var systemAudioFrameCounter=0
        logger.info("✅ Target format captured: \(targetFormatCapture)")
        
        // 4. set up the Block process the data
        logger.info("📋 Step 4: Setting up I/O processing block...")
        let ioBlock: AudioDeviceIOBlock = { [weak self, inputFormat, targetFormatCapture] _, inInputData, _ ,_ ,_ in
            guard let self = self else { return }
            systemAudioFrameCounter+=1
            
            // Create input buffer based on the inputformat
            guard let inputBuffer=AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: inInputData,
                deallocator: nil
            )else{
                return
            }
            
            print("=============buffer rms before convert : \(calculateRMS(from: inputBuffer))")
            
            // Convert to target format if needed
            var processedBuffer=self.convertBufferFormat(inputBuffer, to: targetFormatCapture)
            
            print("=============buffer rms after convert : \(calculateRMS(from: processedBuffer))")
            // Convert to mono
            if processedBuffer.format.channelCount==2 && targetFormatCapture.channelCount==1{
                if let monoBuffer=self.convertToMono(from: processedBuffer, targetFormat: targetFormatCapture){
                    processedBuffer=monoBuffer
                }
            }
            
            Task{ [weak self] in
                await self?.bufferAaccumulator?.append(buffer: processedBuffer)
            }
        }
        
        logger.info("✅ I/O processing block configured")
        
        // 5. install the I/O proc
        logger.info("📋 Step 5: Installing I/O proc...")
        var ioProcID: AudioDeviceIOProcID?
        let err=AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID,ioProcQueue, ioBlock)
        
        guard err == noErr, let procID = ioProcID else {
            logger.error("❌ Failed to create I/O proc ID, error: \(err)")
            throw CoreAudioTapEngineError.ioProcCreationFailed(err)
        }
        logger.info("✅ I/O proc created with ID: \(String(describing: procID))")
        
        self.deviceProcID = procID
        logger.info("✅ Audio processing setup completed successfully")
        


    }
    
    
    
    
    private func startAudioDevice() throws {
        logger.info("🎵 Starting audio device...")
        
        guard let procID = deviceProcID else {
            logger.error("❌ Device proc ID is nil - I/O proc not installed")
            throw CoreAudioTapEngineError.tapNotInstalled
        }
        logger.info("✅ Device proc ID available: \(String(describing: procID))")
        
        logger.info("📋 Starting audio device with aggregself.ate ID: \(self.aggregateDeviceID)")
        let err = AudioDeviceStart(aggregateDeviceID, procID)
        guard err == noErr else {
            logger.error("❌ Failed to start audio device, error: \(err)")
            throw CoreAudioTapEngineError.deviceStartFailed(err)
        }
        logger.info("✅ Audio device started successfully")
    }
    
     private func stopAudioDevice() throws {
        logger.info("🛑 Stopping audio device...")
        
        guard let procID = deviceProcID else { 
            logger.warning("⚠️ Device proc ID is nil, nothing to stop")
            return 
        }
        logger.info("📋 Stopping device with proc ID: \(String(describing: procID))")
        
        logger.info("📋 Stopping audio device...")
        AudioDeviceStop(aggregateDeviceID, procID)
        logger.info("✅ Audio device stopped")
        
        logger.info("📋 Destroying I/O proc ID...")
        AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        logger.info("✅ I/O proc ID destroyed")
    }
    
    
    
    private func cleanupTap() {
        logger.info("🧹 Cleaning up tap resources...")
        
        // Clean up aggregate device
        if aggregateDeviceID != .unknown {
            logger.info("📋 Destroying aggregate device: \(self.aggregateDeviceID)")
            let err = AudioHardwareDestroyAggregateDevice(self.aggregateDeviceID)
            if err == noErr {
                logger.info("✅ Aggregate device destroyed")
            } else {
                logger.error("❌ Failed to destroy aggregate device, error: \(err)")
            }
            aggregateDeviceID = .unknown
        }
        
        // Clean up process tap
        if processTapID != .unknown {
            logger.info("📋 Destroying proceself.ss tap: \(self.processTapID)")
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err == noErr {
                logger.info("✅ Process tap destroyed")
            } else {
                logger.error("❌ Failed to destroy process tap, error: \(err)")
            }
            processTapID = .unknown
        }
        
        // Reset other properties
        deviceProcID = nil
        tapStreamDescription = nil
        
        logger.info("✅ Tap cleanup completed")
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
            commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: buffer.format.channelCount, interleaved: false) else {
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
    
    
    

    /// Calculate RMS (Root Mean Square) value from audio buffer
    private func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0.0 }
        
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        
        return rms
    }
    
    
    
}



