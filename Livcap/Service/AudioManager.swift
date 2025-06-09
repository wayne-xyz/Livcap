//
//  AudioManager.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//
import Foundation
import AVFoundation // Still needed for AVAudioEngine
import Combine
import Accelerate

/// `AudioManager` handles microphone input, audio processing, and chunking for real-time transcription **on macOS**.
///
/// This class configures an audio engine to capture audio, converts it to a standard format (16kHz, mono, Float32),
/// performs simple Voice Activity Detection (VAD), and publishes speech chunks as `Data` objects.
final class AudioManager: ObservableObject {

    // MARK: - Published Properties
    @Published private(set) var isRecording = false
    let audioChunkPublisher = PassthroughSubject<Data, Error>()

    // MARK: - Private Properties
    private var audioEngine: AVAudioEngine?
    private let inputNode: AVAudioInputNode
    private let processingQueue = DispatchQueue(label: "com.livcap.audioManager.processingQueue")
    private let vadThreshold: Float = 0.01

    // MARK: - Initialization
    init() {
        self.audioEngine = AVAudioEngine()
        self.inputNode = audioEngine!.inputNode
    }
    
    deinit {
        stop()
    }

    // MARK: - Public Methods
    func start() {
        requestMicrophonePermission { [weak self] granted in
            guard let self = self, granted else {
                print("macOS Microphone permission denied.")
                return
            }
            
            DispatchQueue.main.async {
                self.startRecording()
            }
        }
    }
    
    func stop() {
        stopRecording()
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
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            print("Failed to create processing format.")
            return
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingFormat
        ) { [weak self] buffer, time in
            guard let self = self else { return }
            
            self.processingQueue.async {
                let pcmBuffer = self.convertBuffer(buffer, to: processingFormat)
                if self.isSpeech(in: pcmBuffer) {
                    let data = self.pcmBufferToData(pcmBuffer)
                    self.audioChunkPublisher.send(data)
                }
            }
        }

        audioEngine?.prepare()
        do {
            try audioEngine?.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
            audioChunkPublisher.send(completion: .failure(error))
        }
    }

    private func stopRecording() {
        guard isRecording, let engine = audioEngine, engine.isRunning else { return }
        
        engine.stop()
        inputNode.removeTap(onBus: 0)
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    // MARK: - Helpers and Utilities

    /// **CHANGED for macOS**: Requests microphone access using AVCaptureDevice.
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    // **REMOVED for macOS**: The configureAudioSession() method is not needed.

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

    private func isSpeech(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?.pointee else { return false }
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
        let isSpeechDetected = rms > vadThreshold
        
        if isSpeechDetected {
            print("🎤 Speech detected! RMS: \(rms), Threshold: \(vadThreshold)")
        }
        
        return isSpeechDetected
    }

    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }
}
