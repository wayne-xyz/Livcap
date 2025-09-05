//
//  AudioManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//
import Foundation
import AVFoundation
import Accelerate
import OSLog

/// `AudioManager` handles microphone input and audio processing for real-time transcription **on macOS**.
///
/// This class configures an audio engine to capture audio from the system's default input device,
/// converts it to a standard format (16kHz, mono, Float32), and publishes audio chunks as `[Float]` arrays
/// through a Combine publisher.
///
///
///
final class MicAudioManager: ObservableObject {
    
    // MARK: - Configuration
    private let targetSampleRate: Double = 16000.0
    private var frameBufferSize: Int {
        guard let inputNode = inputNode else { return 1600 }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        return Int(recordingFormat.sampleRate * 0.1) // 100ms dynamically
    }

    // MARK: - Published Properties
    @Published private(set) var isRecording = false

    // MARK: - Private Properties
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode? {
        audioEngine?.inputNode
    }
    
    // VAD Processing
    private let vadProcessor = VADProcessor()
    private var frameCounter: Int = 0
    
    // SystemAudioManager Pattern: Internal raw audio stream
    private var rawAudioStreamContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var rawAudioStream: AsyncStream<AVAudioPCMBuffer>?
    
    // Enhanced audio stream with VAD (output)
    private var vadAudioStreamContinuation: AsyncStream<AudioFrameWithVAD>.Continuation?
    private var vadAudioStream: AsyncStream<AudioFrameWithVAD>?
    
    // Structured processing task
    private var audioProcessingTask: Task<Void, Never>?
    
    // Device monitoring
    private let audioMonitor = AudioDeviceMonitor()
    private var isReconfiguring = false
    private var reconfigDebounceWorkItem: DispatchWorkItem?
    
    // Logging
    private let logger = Logger(subsystem: "com.livcap.microphone", category: "MicAudioManager")

    // logger on/off switch
    private var isLoggerOn: Bool = true

    // MARK: - Initialization
    init() {
        self.audioEngine = AVAudioEngine()
        setupDeviceMonitoring()
    }
    
    deinit {
        forceCleanup()
    }

    // MARK: - Public Methods
    func start() async {
        let granted = await requestMicrophonePermission()
        guard granted else {
            logger.warning("macOS Microphone permission denied.")
            return
        }

        await MainActor.run {
            startRecording()
        }
    }
    
    func stop() {
        forceCleanup()
    }
    
    // MARK: - Stream Interface (SystemAudioManager Pattern)
    func audioFramesWithVAD() -> AsyncStream<AudioFrameWithVAD> {
        if let stream = vadAudioStream {
            logger.info("********************Returning existing vadAudioStream")
            return stream
        }
        
        logger.info("@@@@@@@@@@@@@@@@@@@@Creating new vadAudioStream")
        
        // ✅ Create local variable first, avoid self capture in closure
        let stream = AsyncStream<AudioFrameWithVAD> { continuation in
            self.vadAudioStreamContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                // ✅ Don't capture self to avoid retain cycle
                print("🛑 MicAudioManager VAD stream terminated")
            }
        }
        
        self.vadAudioStream = stream
        return stream
    }

    // MARK: - Core Audio Logic (SystemAudioManager Pattern)
    
    @MainActor
    private func startRecording() {
        guard !isRecording else {
            logger.warning("Already recording.")
            return
        }
        
        // ✅ Clean up first WITHOUT changing isRecording
        cleanupStreamsAndTasks()
        
        logger.info("🔴 STARTING MICROPHONE CAPTURE")
        
        do {
            try setupMicrophoneCapture()
            
            isRecording = true
            logger.info("✅ MICROPHONE CAPTURE STARTED")
            
        } catch {
            logger.error("❌ Failed to start microphone capture: \(error.localizedDescription)")
            cleanupStreamsAndTasks()
        }
    }
    
    // ✅ Setup without calling cleanup() that changes state
    private func setupMicrophoneCapture() throws {
        // Ensure we have a fresh engine
        if audioEngine == nil { audioEngine = AVAudioEngine() }
        guard let engine = audioEngine else { throw AudioError.formatCreationFailure }

        // Force-create I/O nodes in the graph
        let inputNode = engine.inputNode
        _ = engine.outputNode

        // Create internal raw audio stream (like SystemAudioManager)
        let rawStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.rawAudioStreamContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                print("🛑 Raw audio stream terminated")
            }
        }
        self.rawAudioStream = rawStream

        // Install tap BEFORE starting the engine; use node's native format (nil)
        inputNode.removeTap(onBus: 0)
        let bufferFrames: AVAudioFrameCount = 2048 // stable across devices
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferFrames,
            format: nil
        ) { [weak self] buffer, time in
            self?.rawAudioStreamContinuation?.yield(buffer)
        }

        // Prepare and start engine now that graph is complete
        engine.prepare()
        try engine.start()

        // Log final hardware format
        let hwFormat = inputNode.outputFormat(forBus: 0)
        logger.info("📊 Microphone format: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount) channels")

        logger.info("✅ Tap installed and engine started, installing processing task")

        // Start structured processing
        processMicrophoneOutput(audioStream: rawStream)
    }
    
    // SystemAudioManager Pattern: Structured concurrency processing
    private func processMicrophoneOutput(audioStream: AsyncStream<AVAudioPCMBuffer>) {
        audioProcessingTask = Task {
            logger.info("🎯 Audio processing task started")
            
            for await buffer in audioStream {
                guard !Task.isCancelled else {
                    logger.info("🛑 Audio processing task cancelled")
                    break
                }
                // Heavy processing in structured task
                await processMicrophoneBuffer(buffer)
            }
            
            logger.info("🏁 Audio processing task ended")
        }
    }
    
    // SystemAudioManager Pattern: Buffer processing
    private func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) async {
        // Convert to target format
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            logger.error("Failed to create processing format")
            return
        }
        
        let convertedBuffer = convertBuffer(buffer, to: processingFormat)
        
        // VAD processing
        frameCounter += 1
        let vadResult = vadProcessor.processAudioBuffer(convertedBuffer)
        
        
        // Visualize RMS energy as a bar: longer bar = higher energy
        if isLoggerOn {

            let maxBarLength = 30
            let normalizedEnergy = min(max(Double(vadResult.rmsEnergy) / 0.2, 0), 1) // 0.2 is a typical speech RMS, adjust as needed
            let barLength = max(3, Int(Double(maxBarLength) * normalizedEnergy))
            let bar = String(repeating: "=", count: barLength)
            logger.info("Micphone RMS Energy: \(vadResult.rmsEnergy) [\(bar)]")
        }
        
        // Create enhanced frame
        let audioFrame = AudioFrameWithVAD(
            buffer: convertedBuffer,
            vadResult: vadResult,
            source: .microphone,
            frameIndex: frameCounter
        )
        
        // Yield to output stream
        vadAudioStreamContinuation?.yield(audioFrame)
        
        // Debug log every 100 frames (~10 seconds)
        if frameCounter % 100 == 0 {
            logger.info("📦 Processed \(self.frameCounter) microphone frames")
        }
    }
    
    // MARK: - Cleanup (Fixed)
    
    // ✅ Public cleanup that respects state
    private func forceCleanup() {
        logger.info("🛑 FORCE CLEANUP MICROPHONE")
        
        // 1️⃣ Always remove tap, then stop audio hardware
        inputNode?.removeTap(onBus: 0)
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            logger.info("🛑 Audio engine stopped")
        }
        
        // 2️⃣ Cancel and clean up streams/tasks
        cleanupStreamsAndTasks()
        
        // 3️⃣ Update state
        Task { @MainActor in
            self.isRecording = false
        }
        
        // 4️⃣ Reset processing state
        vadProcessor.reset()
        frameCounter = 0
        
        logger.info("✅ MICROPHONE CLEANUP COMPLETED")
    }
    
    // ✅ Stream and task cleanup without state changes
    private func cleanupStreamsAndTasks() {
        logger.info("🧹 Cleaning up streams and tasks")
        
        // Cancel structured task
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
        
        // Clean raw audio stream
        rawAudioStreamContinuation?.finish()
        rawAudioStreamContinuation = nil
        rawAudioStream = nil
        
        // Clean VAD stream
        vadAudioStreamContinuation?.finish()
        vadAudioStreamContinuation = nil
        vadAudioStream = nil
        
        logger.info("✅ Streams and tasks cleaned")
    }
    
    // MARK: - Device Monitoring Setup
    
    private func setupDeviceMonitoring() {
        audioMonitor.onDeviceChanged { [weak self] defaultInputName in
            guard let self else { return }
            let name = defaultInputName ?? "unknown"
            self.logger.info("🔄 Default input changed to: \(name)")
            self.scheduleReconfigureAfterDeviceChange()
        }
    }

    private func scheduleReconfigureAfterDeviceChange() {
        // Debounce reconfig to coalesce change storms
        reconfigDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.performReconfigureForDeviceChange()
            }
        }
        reconfigDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @MainActor
    private func performReconfigureForDeviceChange() {
        guard isRecording else {
            logger.info("🔇 Ignoring device change because not recording")
            return
        }
        guard !isReconfiguring else {
            logger.info("⏳ Reconfigure already in progress")
            return
        }
        isReconfiguring = true
        logger.info("🛠️ Reconfiguring microphone after device change")

        // 1) Stop audio engine quickly (remove tap first)
        inputNode?.removeTap(onBus: 0)
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            logger.info("🛑 Engine stopped for reconfigure")
        }

        // 2) Cancel task and raw stream but keep VAD output alive
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
        rawAudioStreamContinuation?.finish()
        rawAudioStreamContinuation = nil
        rawAudioStream = nil
        // Keep vadAudioStreamContinuation to preserve downstream consumers
        vadProcessor.reset()
        frameCounter = 0

        // 3) Recreate engine for a clean bind to the new device
        audioEngine = AVAudioEngine()

        // 4) Start capture again after a short stabilization delay
        let delay: TimeInterval = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            do {
                try self.setupMicrophoneCapture()
                self.logger.info("✅ Reconfigure completed; capture restarted")
            } catch {
                self.logger.error("❌ Reconfigure failed: \(error.localizedDescription)")
            }
            self.isReconfiguring = false
        }
    }
    
    // MARK: - Helpers and Utilities
    
    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { 
            logger.error("Failed to create audio converter")
            return buffer 
        }
        
        let outputFrameCapacity = AVAudioFrameCount((Double(buffer.frameLength) / buffer.format.sampleRate) * format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCapacity) else { 
            logger.error("Failed to create output buffer")
            return buffer 
        }
        
        outputBuffer.frameLength = outputFrameCapacity

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            logger.error("Buffer conversion error: \(error.localizedDescription)")
            return buffer
        }
        
        return outputBuffer
    }
}

// MARK: - Error Types

enum AudioError: Error, LocalizedError {
    case formatCreationFailure

    var errorDescription: String? {
        switch self {
        case .formatCreationFailure:
            return "Failed to create processing audio format."
        }
    }
}
