//
//  CaptionViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//
// CaptionViewmodel is conductor role in the caption view for the main function
// working with MicAudioManager and SystemAudioManager to accesp two reosuces audio
// working with the display

import Foundation
import Combine
import Speech
import AVFoundation
import Accelerate
import os.log

/// CaptionViewModel for real-time speech recognition using SFSpeechRecognizer
final class CaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published var statusText: String = "Ready to record"
    
    // UI State mirrored from coordinators
    @Published private(set) var isMicrophoneEnabled: Bool = false
    @Published private(set) var isSystemAudioEnabled: Bool = false

    // Forwarded from SpeechProcessor
    var captionHistory: [CaptionEntry] { speechProcessor.captionHistory }
    var currentTranscription: String { speechProcessor.currentTranscription }
    
    // MARK: - Private Properties
    private let audioCoordinator: AudioCoordinator
    private let speechProcessor: SpeechProcessor
    
    private var cancellables = Set<AnyCancellable>()
    private var audioStreamTask: Task<Void, Never>?
    
    // MARK: - Logging
    private let logger = Logger(subsystem: "com.livcap.audio", category: "CaptionViewModel")
    
    // MARK: - Initialization
    
    init(audioCoordinator: AudioCoordinator = AudioCoordinator(), speechProcessor: SpeechProcessor = SpeechProcessor()) {
        self.audioCoordinator = audioCoordinator
        self.speechProcessor = speechProcessor
        
        // Subscribe to state changes from the AudioCoordinator
        audioCoordinator.$isMicrophoneEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isMicrophoneEnabled, on: self)
            .store(in: &cancellables)
            
        audioCoordinator.$isSystemAudioEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isSystemAudioEnabled, on: self)
            .store(in: &cancellables)
            
        // Subscribe to changes from SpeechProcessor
        speechProcessor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Main control functions
    
    func toggleMicrophone() {
        audioCoordinator.toggleMicrophone()
        manageRecordingState()
    }
    
    func toggleSystemAudio() {
        audioCoordinator.toggleSystemAudio()
        manageRecordingState()
    }
    
    // MARK: - Auto Speech Recognition Management
    
    private func manageRecordingState() {
        let shouldBeRecording = audioCoordinator.isMicrophoneEnabled || audioCoordinator.isSystemAudioEnabled
        
        if shouldBeRecording && !isRecording {
            startRecording()
        } else if !shouldBeRecording && isRecording {
            stopRecording()
        }
    }
    
    // MARK: - Recording Lifecycle
    
    private func startRecording() {
        guard !isRecording else { return }
        logger.info("🔴 STARTING RECORDING SESSION")
        isRecording = true
        
        // Start the speech processor
        speechProcessor.startProcessing()
        
        // Start consuming the audio stream
        audioStreamTask = Task {
            let stream = audioCoordinator.audioFrameStream()
            for await frame in stream {
                guard self.isRecording else { break }
                speechProcessor.processAudioFrame(frame)
            }
        }
        updateStatus()
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        logger.info("🛑 STOPPING RECORDING SESSION")
        isRecording = false
        
        // Terminate the audio stream task
        audioStreamTask?.cancel()
        audioStreamTask = nil
        
        // Stop the speech processor
        speechProcessor.stopProcessing()
        updateStatus()
    }
    
    // MARK: - Helper Functions
    
    private func updateStatus() {
        let micStatus = isMicrophoneEnabled ? "MIC:ON" : "MIC:OFF"
        let systemStatus = isSystemAudioEnabled ? "SYS:ON" : "SYS:OFF"
        
        if !isRecording {
            self.statusText = "Ready"
        } else {
            self.statusText = "\(micStatus) | \(systemStatus)"
        }
        logger.info("📊 STATUS UPDATE: \(self.statusText)")
    }

    // MARK: - Public Interface
    
    func clearCaptions() {
        speechProcessor.clearCaptions()
        logger.info("🗑️ CLEARED ALL CAPTIONS")
    }
}
