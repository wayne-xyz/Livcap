//
//  CoreAudioTapEngineExamples.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/28/25.
// com.apple.WebKit.GPU safari
// com.google.Chrome.helper chrome
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
    private var autoStopTask: Task<Void, Never>?
    
    // MARK: - Process Management
    private let processSupplier = AudioProcessSupplier()
    
    // MARK: - Simple Example Functions
    
    /// Start capturing system audio from all processes and print buffer information
    /// Automatically stops after 30 seconds
    /// Call this from your SwiftUI view's onAppear
    func startSystemAudioCapture() {
        guard !isRunning else { return }
        
        Task {
            do {
                // Get all running audio processes
                let processes = try processSupplier.getProcesses(mode: .all)
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
                
                // Start auto-stop timer for 30 seconds
                autoStopTask = Task {
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30 seconds
                    if !Task.isCancelled {
                        print("⏰ Auto-stopping after 30 seconds...")
                        await MainActor.run {
                            stopSystemAudioCapture()
                        }
                    }
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
        
        autoStopTask?.cancel()
        autoStopTask = nil
        
        tapEngine?.stop()
        tapEngine = nil
        
        isRunning = false
        bufferCount = 0
        latestRMSValue = 0.0
        
        print("🛑 Audio capture stopped")
    }
    
    /// Start capturing from specific processes (e.g., Safari, Chrome)
    /// Automatically stops after 30 seconds
    /// Usage: startSpecificProcessCapture(["Safari", "Google Chrome"])
    func startSpecificProcessCapture(_ processNames: [String]) {
        
        print("====================Starting specific process capture...")
        
        
        guard !isRunning else { return }
        
        Task {
            do {
                let processes = try processSupplier.getProcesses(mode: .matching(processNames))


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
                
                // Start auto-stop timer for 30 seconds
                autoStopTask = Task {
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30 seconds
                    if !Task.isCancelled {
                        print("⏰ Auto-stopping specific process capture after 30 seconds...")
                        await MainActor.run {
                            stopSystemAudioCapture()
                        }
                    }
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
