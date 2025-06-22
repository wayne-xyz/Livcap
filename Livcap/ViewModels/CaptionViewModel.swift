//
//  CaptionViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import Foundation
import Combine
import Speech
import AVFoundation

/// CaptionViewModel for real-time speech recognition using SFSpeechRecognizer
final class CaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published var statusText: String = "Ready to record"
    @Published var captionHistory: [CaptionEntry] = []
    @Published var currentTranscription: String = ""
    
    // MARK: - Private Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        setupSpeechRecognition()
    }
    
    // MARK: - Setup
    
    private func setupSpeechRecognition() {
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.statusText = "Ready to record"
                case .denied:
                    self?.statusText = "Speech recognition permission denied"
                case .restricted:
                    self?.statusText = "Speech recognition restricted"
                case .notDetermined:
                    self?.statusText = "Speech recognition not determined"
                @unknown default:
                    self?.statusText = "Speech recognition authorization unknown"
                }
            }
        }
    }
    
    // MARK: - Main control functions
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            statusText = "Speech recognizer not available"
            return
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            statusText = "Speech recognition not authorized"
            return
        }
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            statusText = "Failed to create audio engine"
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            statusText = "Failed to create recognition request"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.statusText = "Recognition error: \(error.localizedDescription)"
                }
                return
            }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                
                DispatchQueue.main.async {
                    self.currentTranscription = transcription
                    
                    if result.isFinal {
                        // Add to history when transcription is final
                        if !transcription.isEmpty {
                            self.addToHistory(transcription)
                        }
                        self.currentTranscription = ""
                    }
                }
            }
        }
        
        // Prepare and start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            statusText = "Recording..."
            currentTranscription = ""
            
        } catch {
            statusText = "Failed to start audio engine: \(error.localizedDescription)"
            print("Audio engine start error: \(error)")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        isRecording = false
        statusText = "Recording stopped"
        
        // Add final transcription to history if not empty
        if !currentTranscription.isEmpty {
            addToHistory(currentTranscription)
            currentTranscription = ""
        }
    }
    
    private func addToHistory(_ text: String) {
        let entry = CaptionEntry(
            id: UUID(),
            text: text,
            confidence: 1.0 // SFSpeechRecognizer doesn't provide confidence scores
        )
        captionHistory.append(entry)
        
        // Keep only last 50 entries to prevent memory issues
        if captionHistory.count > 50 {
            captionHistory.removeFirst()
        }
    }
    
    func clearCaptions() {
        captionHistory.removeAll()
        currentTranscription = ""
    }
}
