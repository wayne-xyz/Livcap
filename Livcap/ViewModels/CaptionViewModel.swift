//
//  CaptionViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//
// CaptionViewmodel is conductor role in the caption view for the main function
//

import Foundation
import Combine
import Speech
import AVFoundation
import Accelerate
import os.log

protocol CaptionViewModelProtocol: ObservableObject {
    var captionHistory: [CaptionEntry] { get }
    var currentTranscription: String { get }
}

/// CaptionViewModel for real-time speech recognition using SFSpeechRecognizer
final class CaptionViewModel: ObservableObject, CaptionViewModelProtocol {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published var statusText: String = "Ready to record"
    
    // Direct boolean flags - simplified approach
    var isMicrophoneEnabled: Bool { audioCoordinator.isMicrophoneEnabled }
    var isSystemAudioEnabled: Bool { audioCoordinator.isSystemAudioEnabled }

    // Forwarded from SpeechProcessor
    var captionHistory: [CaptionEntry] { speechProcessor.captionHistory }
    var currentTranscription: String { speechProcessor.currentTranscription }
    
    // MARK: - Private Properties
    private let audioCoordinator: AudioCoordinator
    private let speechProcessor: SpeechProcessor
    private let permissionManager = PermissionManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var audioStreamTask: Task<Void, Never>?
    
    // MARK: - Logging
    private let logger = Logger(subsystem: "com.livcap.audio", category: "CaptionViewModel")
    
    // MARK: - Initialization
    
    init(audioCoordinator: AudioCoordinator = AudioCoordinator(), speechProcessor: SpeechProcessor = SpeechProcessor()) {
        self.audioCoordinator = audioCoordinator
        self.speechProcessor = speechProcessor
        
        // Subscribe to audio coordinator changes and manage recording state
        audioCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.manageRecordingState()
                self?.updateStatus()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        // Subscribe to changes from SpeechProcessor
        speechProcessor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Audio Control Methods
    
    private func enableMicrophoneWithPermissionCheck() {
        // Check permissions before enabling microphone
        if permissionManager.hasEssentialPermissionsDenied() {
            logger.warning("🚫 Microphone enable cancelled - essential permissions denied")
            
            // Open system settings for denied permissions
            if permissionManager.isMicrophoneDenied() {
                permissionManager.openSystemSettingsForMicPermission()
            } else if permissionManager.isSpeechRecognitionDenied() {
                permissionManager.openSystemSettingsForSpeechPermission()
            }
            return
        }
        
        logger.info("🎤 Enabling microphone - permissions granted")
        audioCoordinator.enableMicrophone()
    }
    
    func toggleMicrophone() {
        if isMicrophoneEnabled {
            audioCoordinator.disableMicrophone()
        } else {
            enableMicrophoneWithPermissionCheck()
        }
    }
    
    func toggleSystemAudio() {
        if isSystemAudioEnabled {
            audioCoordinator.disableSystemAudio()
        } else {
            audioCoordinator.enableSystemAudio()
        }
    }
    
    // MARK: - Auto Speech Recognition Management
    
    private func manageRecordingState() {
        let shouldBeRecording = self.isMicrophoneEnabled || self.isSystemAudioEnabled
        
        logger.info("🔄 REACTIVE STATE CHECK: mic=\(self.isMicrophoneEnabled), sys=\(self.isSystemAudioEnabled), shouldRecord=\(shouldBeRecording), isRecording=\(self.isRecording)")
        
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
    }
    
    // Removed: Stream restart handling no longer needed
    
    // MARK: - Helper Functions
    
    private func updateStatus() {
        if !isRecording {
            self.statusText = "Ready"
        } else {
            switch (self.isMicrophoneEnabled, self.isSystemAudioEnabled) {
            case (false, false):
                self.statusText = "Ready"
            case (true, false):
                self.statusText = "MIC:ON"
            case (false, true):
                self.statusText = "SYS:ON"
            case (true, true):
                self.statusText = "MIC:ON | SYS:ON"
            }
        }
        logger.info("📊 STATUS UPDATE: \(self.statusText)")
    }

    // MARK: - Public Interface
    
    func clearCaptions() {
        speechProcessor.clearCaptions()
        logger.info("🗑️ CLEARED ALL CAPTIONS")
    }
}
