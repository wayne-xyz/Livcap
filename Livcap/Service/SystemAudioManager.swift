//
//  SystemAudioManager.swift
//  Livcap
//
//  System audio capture using Core Audio Taps (macOS 14.4+)
//  Based on AudioCap example: https://github.com/insidegui/AudioCap
//

import Foundation
import AudioToolbox
import AVFoundation
import OSLog
import Combine

@available(macOS 14.4, *)
class SystemAudioManager: ObservableObject, SystemAudioProtocol {
    
    // MARK: - Published Properties
    
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var systemAudioLevel: Float = 0.0
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livcap.systemaudio", category: "SystemAudioManager")
    private let queue = DispatchQueue(label: "SystemAudioCapture", qos: .userInitiated)
    
    // Core Audio Tap components
    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapStreamDescription: AudioStreamBasicDescription?
    
    // Audio processing
    private let targetFormat: AVAudioFormat
    private var audioBufferContinuation: AsyncStream<[Float]>.Continuation?
    private var audioStream: AsyncStream<[Float]>?
    
    // Configuration
    private struct Config {
        static let sampleRate: Double = 16000.0  // Target sample rate
        static let channels: UInt32 = 1          // Mono output
        static let bufferSize: Int = 1600        // 100ms at 16kHz
    }
    
    // MARK: - Initialization
    
    init() {
        // Create target audio format (16kHz mono Float32)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Config.sampleRate,
            channels: Config.channels,
            interleaved: false
        ) else {
            fatalError("Failed to create target audio format")
        }
        self.targetFormat = format
        
        logger.info("SystemAudioManager initialized for macOS 14.4+ Core Audio Taps")
    }
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Public Interface
    
    /// Start system audio capture
    func startCapture() async throws {
        guard !isCapturing else {
            logger.warning("System audio capture already running")
            return
        }
        
        logger.info("Starting system audio capture...")
        
        do {
            try await setupSystemAudioTap()
            
            await MainActor.run {
                self.isCapturing = true
                self.errorMessage = nil
            }
            
            logger.info("System audio capture started successfully")
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to start system audio capture: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Stop system audio capture
    func stopCapture() {
        guard isCapturing else { return }
        
        logger.info("Stopping system audio capture...")
        
        cleanupAudioTap()
        
        Task { @MainActor in
            self.isCapturing = false
            self.systemAudioLevel = 0.0
        }
        
        logger.info("System audio capture stopped")
    }
    
    /// Get system audio stream for mixing
    func systemAudioStream() -> AsyncStream<[Float]> {
        if let stream = audioStream {
            return stream
        }
        
        let stream = AsyncStream<[Float]> { continuation in
            self.audioBufferContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopCapture()
            }
        }
        
        self.audioStream = stream
        return stream
    }
    
    // MARK: - Core Audio Tap Setup
    
    private func setupSystemAudioTap() async throws {
        // Clean up any existing tap
        cleanupAudioTap()
        
        // Get system output device for tap creation
        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        
        logger.info("Setting up system audio tap for device: \(outputUID)")
        
        // Create tap description for system-wide capture
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [systemOutputID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted // Don't mute system audio
        
        // Create process tap
        var tapID: AUAudioObjectID = .unknown
        let err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            throw SystemAudioError.tapCreationFailed(err)
        }
        
        self.processTapID = tapID
        logger.info("Created process tap: \(tapID)")
        
        // Get tap audio format
        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()
        
        // Create aggregate device
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Livcap-SystemAudio",
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
        
        // Create aggregate device
        var aggregateID = AudioObjectID.unknown
        let aggregateErr = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard aggregateErr == noErr else {
            throw SystemAudioError.aggregateDeviceCreationFailed(aggregateErr)
        }
        
        self.aggregateDeviceID = aggregateID
        logger.info("Created aggregate device: \(aggregateID)")
        
        // Setup audio processing callback
        try setupAudioProcessing()
    }
    
    private func setupAudioProcessing() throws {
        guard var streamDescription = tapStreamDescription else {
            throw SystemAudioError.invalidStreamDescription
        }
        
        guard let inputFormat = AVAudioFormat(streamDescription: &streamDescription) else {
            throw SystemAudioError.formatCreationFailed
        }
        
        logger.info("Input format: \(inputFormat)")
        logger.info("Target format: \(self.targetFormat)")
        
        // Create I/O proc for audio processing
        let targetFormatCapture = self.targetFormat
        let ioBlock: AudioDeviceIOBlock = { [weak self, inputFormat, targetFormatCapture] _, inInputData, _, _, _ in
            guard let self = self else { return }
            
            // Create input buffer
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else {
                self.logger.warning("Failed to create input buffer")
                return
            }
            
            // Convert to target format if needed
            let processedBuffer = self.convertBufferFormat(inputBuffer, to: targetFormatCapture)
            
            // Extract float samples
            guard let floatChannelData = processedBuffer.floatChannelData?[0] else {
                self.logger.warning("No float channel data available")
                return
            }
            
            let frameCount = Int(processedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: floatChannelData, count: frameCount))
            
            // Update audio level for UI
            let rms = self.calculateRMS(samples)
            Task { @MainActor in
                self.systemAudioLevel = rms
            }
            
            // Send samples to stream
            self.audioBufferContinuation?.yield(samples)
        }
        
        // Install I/O proc
        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else {
            throw SystemAudioError.ioProcCreationFailed(err)
        }
        
        // Start audio device
        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            throw SystemAudioError.deviceStartFailed(err)
        }
        
        logger.info("Audio processing started successfully")
    }
    
    // MARK: - Audio Format Conversion
    
    private func convertBufferFormat(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
        // If formats match, return original buffer
        if buffer.format.sampleRate == format.sampleRate && 
           buffer.format.channelCount == format.channelCount {
            return buffer
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            logger.warning("Failed to create audio converter, using original buffer")
            return buffer
        }
        
        // Calculate output frame capacity
        let outputFrameCapacity = AVAudioFrameCount(
            (Double(buffer.frameLength) / buffer.format.sampleRate) * format.sampleRate
        )
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: outputFrameCapacity
        ) else {
            logger.warning("Failed to create output buffer, using original buffer")
            return buffer
        }
        
        outputBuffer.frameLength = outputFrameCapacity
        
        // Perform conversion
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            logger.warning("Audio conversion failed: \(error.localizedDescription), using original buffer")
            return buffer
        }
        
        return outputBuffer
    }
    
    // MARK: - Cleanup
    
    private func cleanupAudioTap() {
        // Stop audio device
        if aggregateDeviceID.isValid {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr {
                logger.warning("Failed to stop aggregate device: \(err)")
            }
            
            // Destroy I/O proc
            if let deviceProcID = deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if err != noErr {
                    logger.warning("Failed to destroy device I/O proc: \(err)")
                }
                self.deviceProcID = nil
            }
            
            // Destroy aggregate device
            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err)")
            }
            aggregateDeviceID = .unknown
        }
        
        // Destroy process tap
        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                logger.warning("Failed to destroy audio tap: \(err)")
            }
            processTapID = .unknown
        }
        
        // Close audio stream
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        audioStream = nil
        
        logger.info("Audio tap cleanup completed")
    }
    
    // MARK: - Utilities
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

// MARK: - Error Types

enum SystemAudioError: Error, LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case invalidStreamDescription
    case formatCreationFailed
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case unsupportedMacOSVersion
    
    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let status):
            return "Failed to create audio tap: \(status)"
        case .aggregateDeviceCreationFailed(let status):
            return "Failed to create aggregate device: \(status)"
        case .invalidStreamDescription:
            return "Invalid audio stream description"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .ioProcCreationFailed(let status):
            return "Failed to create I/O proc: \(status)"
        case .deviceStartFailed(let status):
            return "Failed to start audio device: \(status)"
        case .unsupportedMacOSVersion:
            return "System audio capture requires macOS 14.4 or later"
        }
    }
}

// MARK: - AudioObjectID Extensions (from AudioCap example)

extension AudioObjectID {
    /// Convenience for `kAudioObjectSystemObject`.
    static let system = AudioObjectID(kAudioObjectSystemObject)
    /// Convenience for `kAudioObjectUnknown`.
    static let unknown = kAudioObjectUnknown

    /// `true` if this object has the value of `kAudioObjectUnknown`.
    var isUnknown: Bool { self == .unknown }

    /// `false` if this object has the value of `kAudioObjectUnknown`.
    var isValid: Bool { !isUnknown }
}

extension AudioObjectID {
    /// Reads the value for `kAudioHardwarePropertyDefaultSystemOutputDevice`.
    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioDeviceID.system.readDefaultSystemOutputDevice()
    }
    
    /// Reads the value for `kAudioHardwarePropertyDefaultSystemOutputDevice`, should only be called on the system object.
    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }
    
    /// Reads the value for `kAudioDevicePropertyDeviceUID` for the device represented by this audio object ID.
    func readDeviceUID() throws -> String {
        try readString(kAudioDevicePropertyDeviceUID)
    }
    
    /// Reads the value for `kAudioTapPropertyFormat` for the device represented by this audio object ID.
    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }
    
    private func requireSystemObject() throws {
        if self != .system { throw "Only supported for the system object." }
    }
    
    // Generic property access methods
    func read<T>(_ selector: AudioObjectPropertySelector,
                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                defaultValue: T) throws -> T {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: defaultValue)
    }
    
    func readString(_ selector: AudioObjectPropertySelector,
                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                   element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: "" as CFString) as String
    }
    
    private func read<T>(_ address: AudioObjectPropertyAddress, defaultValue: T) throws -> T {
        var inAddress = address
        var dataSize: UInt32 = 0
        
        var err = AudioObjectGetPropertyDataSize(self, &inAddress, 0, nil, &dataSize)
        guard err == noErr else {
            throw "Error reading data size for \(address): \(err)"
        }
        
        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &inAddress, 0, nil, &dataSize, ptr)
        }
        
        guard err == noErr else {
            throw "Error reading data for \(address): \(err)"
        }
        
        return value
    }
}

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { self }
} 