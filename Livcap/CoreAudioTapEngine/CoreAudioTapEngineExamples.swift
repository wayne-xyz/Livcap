//
//  CoreAudioTapEngineExamples.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/28/25.
//

import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

@available(macOS 14.4, *)
class CoreAudioTapEngineExamples: ObservableObject {
    
    // MARK: - Published Properties for UI
    @Published var isRunning = false
    @Published var latestRMSValue: Float = 0.0
    @Published var bufferCount = 0
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var tapEngine: CoreAudioTapEngine?
    private var audioStreamTask: Task<Void, Never>?
    
    // MARK: - Simple Example Functions
    
    /// Start capturing system audio from all processes and print buffer information
    /// Call this from your SwiftUI view's onAppear
    func startSystemAudioCapture() {
        guard !isRunning else { return }
        
        Task {
            do {
                // Get all running audio processes
                let processes = try getAllAudioProcesses()
                print("Found \(processes.count) audio processes")
                
                // Create and start the tap engine
                tapEngine = CoreAudioTapEngine(forProcesses: processes)
                
                let audioStream = try tapEngine!.coreAudioTapStream()
                try await tapEngine!.start()
                
                await MainActor.run {
                    isRunning = true
                    errorMessage = nil
                }
                
                // Start processing audio buffers
                audioStreamTask = Task {
                    await processAudioStream(audioStream)
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start: \(error.localizedDescription)"
                }
                print("Error starting audio capture: \(error)")
            }
        }
    }
    
    /// Stop the audio capture
    func stopSystemAudioCapture() {
        guard isRunning else { return }
        
        audioStreamTask?.cancel()
        audioStreamTask = nil
        
        tapEngine?.stop()
        tapEngine = nil
        
        isRunning = false
        bufferCount = 0
        latestRMSValue = 0.0
    }
    
    /// Start capturing from specific processes (e.g., Safari, Chrome)
    /// Usage: startSpecificProcessCapture(["Safari", "Google Chrome"])
    func startSpecificProcessCapture(_ processNames: [String]) {
        
        print("====================Starting specific process capture...")
        
        
        guard !isRunning else { return }
        
        Task {
            do {
                let processes = try getProcessesByName(processNames)


                guard !processes.isEmpty else {
                    await MainActor.run {
                        errorMessage = "No processes found with names: \(processNames.joined(separator: ", "))"

                    }
                    return
                }
                
                print("Starting capture for processes: \(processNames)")
                
                tapEngine = CoreAudioTapEngine(forProcesses: processes)
                let audioStream = try tapEngine!.coreAudioTapStream()
                try await tapEngine!.start()
                
                await MainActor.run {
                    isRunning = true
                    errorMessage = nil
                }
                
                audioStreamTask = Task {
                    await processAudioStream(audioStream)
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start specific process capture: \(error.localizedDescription)"
                }
                print("Error: \(error)")
            }
        }
    }
    
    // MARK: - Private Helper Functions
    
    /// Process the audio stream and calculate RMS values
    private func processAudioStream(_ stream: AsyncStream<AVAudioPCMBuffer>) async {
        
        print("🎧 Starting to monitor audio stream...")
        var bufferReceived = false
        
        
        for await buffer in stream {
            if !bufferReceived {
                print("🎉 First buffer received!")
                bufferReceived = true
            }
            
            
            let rms = calculateRMS(from: buffer)
            
            await MainActor.run {
                self.latestRMSValue = rms
                self.bufferCount += 1
            }
            print("⚠️ Audio stream ended")
            // Print buffer information
            printBufferInfo(buffer, rms: rms, count: bufferCount)
        }
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
    
    /// Print detailed buffer information
    private func printBufferInfo(_ buffer: AVAudioPCMBuffer, rms: Float, count: Int) {
        let format = buffer.format
        let frameLength = buffer.frameLength
        let sampleRate = format.sampleRate
        let channelCount = format.channelCount
        
        print("""
        [Buffer #\(count)]
        - Format: \(channelCount) ch, \(sampleRate) Hz
        - Frame Length: \(frameLength)
        - RMS Value: \(String(format: "%.6f", rms))
        - Duration: \(String(format: "%.2f", Double(frameLength) / sampleRate * 1000)) ms
        """)
    }
    
    /// Get all running audio processes
    private func getAllAudioProcesses() throws -> [AudioObjectID] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            throw CoreAudioTapEngineError.tapCreationFailed(status)
        }
        
        let processCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var processes = Array<AudioObjectID>(repeating: 0, count: processCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &processes
        )
        
        guard status == noErr else {
            throw CoreAudioTapEngineError.tapCreationFailed(status)
        }
        
        return processes
    }
    
    /// Get processes by their names or bundle IDs
    private func getProcessesByName(_ names: [String]) throws -> [AudioObjectID] {
        let allProcesses = try getAllAudioProcesses()
        var matchingProcesses: [AudioObjectID] = []
        
        print("🔍 Searching through \(allProcesses.count) audio processes...")
        
        for processID in allProcesses {
            if let bundleID = try? getProcessName(processID) {
                print("Found process: \(bundleID)")
                
                // Check if this bundle ID matches any of our target names
                let isMatch = names.contains { targetName in
                    // Direct bundle ID matching
                    bundleID.localizedCaseInsensitiveContains(targetName) ||
                    
                    // Chrome-specific matching
                    (targetName.localizedCaseInsensitiveContains("chrome") && 
                     (bundleID.contains("com.google.Chrome") || bundleID.contains("com.google.chrome"))) ||
                    
                    // Safari matching
                    (targetName.localizedCaseInsensitiveContains("safari") && 
                     bundleID.contains("com.apple.Safari")) ||
                    
                    // Firefox matching
                    (targetName.localizedCaseInsensitiveContains("firefox") && 
                     bundleID.contains("org.mozilla.firefox")) ||
                     
                    // Edge matching
                    (targetName.localizedCaseInsensitiveContains("edge") && 
                     bundleID.contains("com.microsoft.edgemac"))
                }
                
                if isMatch {
                    print("✅ MATCHED: \(bundleID) for target: \(names)")
                    matchingProcesses.append(processID)
                }
            }
        }
        
        print("🎯 Found \(matchingProcesses.count) matching processes")
        return matchingProcesses
    }
    
    /// Get the bundle ID of a process by its AudioObjectID
    private func getProcessName(_ processID: AudioObjectID) throws -> String {
        // Get the bundle ID using the correct Core Audio property
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            processID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            return "Process_\(processID)"
        }
        
        let bundlePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        defer { bundlePointer.deallocate() }
        
        status = AudioObjectGetPropertyData(
            processID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            bundlePointer
        )
        
        guard status == noErr, let bundleString = bundlePointer.pointee else {
            return "Process_\(processID)"
        }
        
        return bundleString as String
    }
}

// MARK: - Convenience Extensions for SwiftUI Integration

@available(macOS 14.4, *)
extension CoreAudioTapEngineExamples {
    
    /// Quick start function for common browsers
    func startBrowserAudioCapture() {
        startSpecificProcessCapture(["Safari", "Google Chrome", "Firefox", "Microsoft Edge"])
    }
    
    /// Quick start function specifically for Chrome (using exact bundle IDs)
    func startChromeAudioCapture() {
        startSpecificProcessCapture(["com.google.Chrome.helper"])
    }
    
    /// Quick start function for media applications
    func startMediaAudioCapture() {
        startSpecificProcessCapture(["Music", "Spotify", "VLC", "QuickTime Player"])
    }
    
    /// Get current audio statistics as a formatted string
    var audioStats: String {
        return """
        Status: \(isRunning ? "Running" : "Stopped")
        Buffers Processed: \(bufferCount)
        Latest RMS: \(String(format: "%.6f", latestRMSValue))
        """
    }
}
