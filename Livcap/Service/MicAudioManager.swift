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
    
    // Logging
    private let logger = Logger(subsystem: "com.livcap.microphone", category: "MicAudioManager")

    // MARK: - Initialization
    init() {
        self.audioEngine = AVAudioEngine()

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
        
        guard inputNode != nil else {
            logger.error("Failed to get audio input node.")
            return
        }
        
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
        guard let inputNode = inputNode else {
            throw AudioError.formatCreationFailure
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logger.info("📊 Microphone format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount) channels")
        
        // Create internal raw audio stream (like SystemAudioManager)
        let rawStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.rawAudioStreamContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                print("🛑 Raw audio stream terminated")
            }
        }
        self.rawAudioStream = rawStream
        
        // Install ultra-fast audio tap
        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(frameBufferSize),
            format: recordingFormat
        ) { [weak self] buffer, time in
            // ✅ ULTRA-FAST: Just yield to internal stream
            self?.rawAudioStreamContinuation?.yield(buffer)
        }

        audioEngine?.prepare()
        try audioEngine?.start()
        
        logger.info("✅ Audio engine started, installing processing task")
        
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
        
        // 1️⃣ Stop audio hardware first
        if let engine = audioEngine, engine.isRunning {
            inputNode?.removeTap(onBus: 0)
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
    
    func setupAudioMonitoring() {
        audioMonitor.onDeviceChanged { defaultInputName in
            if let name = defaultInputName {
                print("🎙️ Default input device changed to: \(name)")
            } else {
                print("🎙️ Audio route changed (iOS)")
            }
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
