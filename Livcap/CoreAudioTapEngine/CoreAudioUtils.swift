//
//  CoreAudioUtils.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/29/25.
//  Shared Core Audio utilities and extensions
//  Based on https://github.com/insidegui/AudioCap
//

import Foundation
import AudioToolbox
import AVFoundation
import Accelerate

// MARK: - AudioObjectID Extensions

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
    /// Reads the process list from the system audio object
    func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else { throw "Failed to get process list size: \(err)" }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var value = [AudioObjectID](repeating: .unknown, count: count)
        
        err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        guard err == noErr else { throw "Failed to read process list: \(err)" }
        
        return value
    }
    
    /// Reads the PID for a process object
    func readPID() throws -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = UInt32(MemoryLayout<pid_t>.size)
        var pid: pid_t = -1
        
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &pid)
        guard err == noErr else { throw "Failed to read PID: \(err)" }
        
        return pid
    }
    
    /// Reads the bundle ID for a process object
    func readProcessBundleID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr, dataSize > 0 else { return nil }
        
        var cfString: CFString = "" as CFString
        let err2 = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &cfString)
        guard err2 == noErr else { return nil }
        
        let result = cfString as String
        return result.isEmpty ? nil : result
    }
    
    /// Reads whether the process is currently running
    func readProcessIsRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        return err == noErr && value == 1
    }
    
    /// Reads audio status for a process (input/output)
    func readProcessAudioStatus(_ property: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: property,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        return err == noErr && value == 1
    }
    
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

// MARK: - AudioDeviceID Extensions

extension AudioDeviceID {
    func getDeviceName() -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyElementName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        var name: CFString = "" as CFString
        
        let err1 = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        if err1 == noErr {
            let err2 = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &name)
            if err2 == noErr {
                return name as String
            }
        }
        
        return "Unknown Device"
    }
}

// MARK: - Audio Processing Utilities

/// Calculate RMS (Root Mean Square) value from audio buffer
func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
    
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0 else { return 0.0 }
    
    var rms: Float = 0.0
    vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
    
    return rms
}

/// Converts the given AVAudioPCMBuffer to match the target AVAudioFormat sample rate.
func convertBufferFormat(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
    // If formats match exactly, return original buffer
    if buffer.format.sampleRate == format.sampleRate && 
       buffer.format.channelCount == format.channelCount {
        return buffer
    }
    
    // For stereo-to-mono conversion, we'll handle it manually in the extraction phase
    // Here we only handle sample rate conversion if needed, keeping original channel count
    let intermediateFormat: AVAudioFormat
    if buffer.format.sampleRate != format.sampleRate {
        // Create intermediate format with same channels but target sample rate
        guard let tempFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: buffer.format.channelCount,
            interleaved: false
        ) else {
            return buffer
        }
        intermediateFormat = tempFormat
    } else {
        // No sample rate conversion needed, return original for channel conversion in extraction
        return buffer
    }
    
    // Create converter for sample rate conversion only
    guard let converter = AVAudioConverter(from: buffer.format, to: intermediateFormat) else {
        return buffer
    }
    
    // Calculate output frame capacity for sample rate conversion
    let outputFrameCapacity = AVAudioFrameCount(
        (Double(buffer.frameLength) / buffer.format.sampleRate) * intermediateFormat.sampleRate
    )
    
    guard let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: intermediateFormat,
        frameCapacity: outputFrameCapacity
    ) else {
        return buffer
    }
    
    outputBuffer.frameLength = outputFrameCapacity
    
    // Perform sample rate conversion
    var error: NSError?
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return buffer
    }
    
    if let error = error {
        print("Sample rate conversion failed: \(error.localizedDescription), using original buffer")
        return buffer
    }
    
    return outputBuffer
}

/// Converts a stereo `AVAudioPCMBuffer` into a mono buffer by averaging the left and right channels.
func convertToMono(from inputBuffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frameLength = inputBuffer.frameLength
    guard inputBuffer.format.channelCount == 2 else { return inputBuffer }
    
    // Create the mono format
    guard let monoFormat = AVAudioFormat(
        commonFormat: inputBuffer.format.commonFormat,
        sampleRate: inputBuffer.format.sampleRate,
        channels: 1,
        interleaved: false
    ) else { return nil }
    
    // Create the mono buffer
    guard let monoBuffer = AVAudioPCMBuffer(
        pcmFormat: monoFormat,
        frameCapacity: frameLength
    ) else { return nil }
    
    monoBuffer.frameLength = frameLength
    
    // Access channel data
    guard let stereoDataL = inputBuffer.floatChannelData?[0],
          let stereoDataR = inputBuffer.floatChannelData?[1],
          let monoData = monoBuffer.floatChannelData?[0] else { return nil }
    
    for i in 0..<frameLength {
        monoData[Int(i)] = (stereoDataL[Int(i)] + stereoDataR[Int(i)]) / 2.0
    }
    
    return monoBuffer
}

// Helper to get the default output device ID
func getDefaultOutputDeviceID() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    var deviceID: AudioDeviceID = 0
    
    let err = AudioObjectGetPropertyDataSize(AudioObjectID.system, &address, 0, nil, &dataSize)
    if err == noErr {
        let err2 = AudioObjectGetPropertyData(AudioObjectID.system, &address, 0, nil, &dataSize, &deviceID)
        if err2 == noErr {
            return deviceID
        }
    }
    
    throw CoreAudioTapEngineError.processNotFound("Failed to get default output device ID")
}

// MARK: - String Error Extension

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { self }
}
