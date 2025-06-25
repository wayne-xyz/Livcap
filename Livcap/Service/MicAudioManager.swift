//
//  AudioManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//
import Foundation
import AVFoundation // Still needed for AVAudioEngine
import Accelerate



/// `AudioManager` handles microphone input and audio processing for real-time transcription **on macOS**.
///
/// This class configures an audio engine to capture audio from the system's default input device,
/// converts it to a standard format (16kHz, mono, Float32), and publishes audio chunks as `[Float]` arrays
/// through a Combine publisher.
///
///
///
final class MicAudioManager: ObservableObject {
    // configuration constatn
    private let frameBufferSize: Int = 4800 // 100ms = 4800/48k float32 , a frame buffer is 4800sample.
    private let targetSampleRate: Double = 16000.0  // conver the 48k to 16k  , downsampling the input to the sfspeech
    
    

    // MARK: - Published Properties
    @Published private(set) var isRecording = false //for audio engine

    // MARK: - Private Properties
    private var audioEngine: AVAudioEngine?
    private let inputNode: AVAudioInputNode
    private var audioStreamContinuation: AsyncStream<[Float]>.Continuation?
    private var audioStream: AsyncStream<[Float]>?
    
    // VAD Processing
    private let vadProcessor = VADProcessor()
    private var frameCounter: Int = 0
    
    // Enhanced audio stream with VAD
    private var vadAudioStreamContinuation: AsyncStream<AudioFrameWithVAD>.Continuation?
    private var vadAudioStream: AsyncStream<AudioFrameWithVAD>?

    // MARK: - Initialization
    init() {
        self.audioEngine = AVAudioEngine()
        self.inputNode = audioEngine!.inputNode
    }
    
    deinit {
        stop()
    }

    // MARK: - Public Methods
    func start() async {
        let granted = await requestMicrophonePermission()
        guard granted else {
            print("macOS Microphone permission denied.")
            return
        }

        await MainActor.run {
            startRecording()
        }
    }
    
    func stop() {
        stopRecording()
    }
    
    
    // consumer accessibility point.
    func audioFrames()->AsyncStream<[Float]>{
        if let stream=audioStream{
            return stream
        }
        
        self.audioStream = AsyncStream { continuation in
            self.audioStreamContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopRecording()
            }
        }
        
        return self.audioStream!
    }
    
    // Enhanced consumer accessibility point with VAD metadata
    func audioFramesWithVAD() -> AsyncStream<AudioFrameWithVAD> {
        if let stream = vadAudioStream {
            return stream
        }
        
        self.vadAudioStream = AsyncStream { continuation in
            self.vadAudioStreamContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopRecording()
            }
        }
        
        return self.vadAudioStream!
    }
    

    // MARK: - Core Audio Logic
    private func startRecording() {
        guard !isRecording else {
            print("Already recording.")
            return
        }
        
        // On macOS, we don't need to configure an AVAudioSession.
        // The engine will use the system's default input device.
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("Failed to create processing format.")
            audioStreamContinuation?.finish()
            return
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(frameBufferSize),
            format: recordingFormat
        ) { [weak self] buffer, time in
            guard let self = self else { return }
            Task.detached {
                // Convert to target format (16kHz mono)
                let pcmBuffer = self.convertBuffer(buffer, to: processingFormat)
                
                // Process with new buffer-based VAD (no float conversion needed!)
                self.processAudioBufferWithVAD(pcmBuffer)
                
                // Legacy compatibility: Extract float samples only if needed
                if let continuation = self.audioStreamContinuation {
                    guard let floatChannelData = pcmBuffer.floatChannelData else { return }
                    let samples = Array(UnsafeBufferPointer(start: floatChannelData[0], count: Int(pcmBuffer.frameLength)))
                    continuation.yield(samples)
                }
            }
        }

        audioEngine?.prepare()
        do {
            try audioEngine?.start()
            Task{ @MainActor in
                self.isRecording = true
            }
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
            audioStreamContinuation?.finish()
        }
    }

    private func stopRecording() {
        guard isRecording, let engine = audioEngine, engine.isRunning else { return }
        
        engine.stop()
        inputNode.removeTap(onBus: 0)
        
        Task{ @MainActor in
            self.isRecording = false
        }
        audioStreamContinuation?.finish()
        vadAudioStreamContinuation?.finish()
        
        // Reset VAD state
        vadProcessor.reset()
        frameCounter = 0
    }
    
    // MARK: - VAD Processing
    
    private func processAudioBufferWithVAD(_ buffer: AVAudioPCMBuffer) {
        frameCounter += 1
        
        // Process VAD using new buffer-based method
        let vadResult = vadProcessor.processAudioBuffer(buffer)
        
        // Create enhanced audio frame with buffer
        let audioFrame = AudioFrameWithVAD(
            buffer: buffer,
            vadResult: vadResult,
            source: .microphone,
            frameIndex: frameCounter
        )
        
        // Yield enhanced frame
        vadAudioStreamContinuation?.yield(audioFrame)
        
        // Debug logging (using convenience samples property when needed)
        AudioDebugLogger.shared.logAudioFrame(
            source: .microphone,
            frameIndex: frameCounter,
            samples: audioFrame.samples,
            sampleRate: audioFrame.sampleRate,
            vadDecision: vadResult.isSpeech
        )
    }
    
    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
        return rms
    }

    
    
    
    
    
    // MARK: - Helpers and Utilities

    /// **CHANGED for macOS**: Requests microphone access using AVCaptureDevice.
    /// Requests microphone access using AVCaptureDevice.
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
    

    /// Converts the given `AVAudioPCMBuffer` to a different audio format using `AVAudioConverter`.
    ///
    /// - Parameters:
    ///   - buffer: The source audio buffer to be converted.
    ///   - format: The desired audio format to convert to (e.g., 16kHz mono Float32).
    /// - Returns: A new `AVAudioPCMBuffer` in the target format if conversion succeeds, otherwise the original buffer.
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return buffer }
        let outputFrameCapacity = AVAudioFrameCount((Double(buffer.frameLength) / buffer.format.sampleRate) * format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCapacity) else { return buffer }
        outputBuffer.frameLength = outputFrameCapacity

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        return error == nil ? outputBuffer : buffer
    }



}


// Define a custom error type for AudioManager
enum AudioError: Error, LocalizedError {
    case formatCreationFailure

    var errorDescription: String? {
        switch self {
        case .formatCreationFailure:
            return "Failed to create processing audio format."
        }
    }
}
