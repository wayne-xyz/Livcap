//
//  OverlappingCaptionViewModel.swift
//  Livcap
//
//  Created by Implementation Plan on 6/20/25.
//

import Foundation
import Combine

/// Test ViewModel for the overlapping windows approach
/// This allows us to test the new pipeline in Xcode
@MainActor
class OverlappingCaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    @Published private(set) var isRecording = false
    @Published var statusText: String = "Ready to test overlapping windows"
    @Published var currentTranscription: String = ""
    @Published var newWords: [String] = []
    @Published var bufferStats: String = ""
    
    // MARK: - Private Properties
    private let audioManager: AudioManager
    private let overlappingBufferManager: OverlappingBufferManager
    private let streamingTranscriber: StreamingWhisperTranscriber
    
    private var audioProcessingTask: Task<Void, Error>?
    private var transcriptionCancellable: AnyCancellable?
    
    // MARK: - Initialization
    init(audioManager: AudioManager = AudioManager()) {
        self.audioManager = audioManager
        self.overlappingBufferManager = OverlappingBufferManager()
        self.streamingTranscriber = StreamingWhisperTranscriber()
        setupTranscriptionSubscription()
    }
    
    // MARK: - Public Interface
    
    func startRecording() {
        guard audioProcessingTask == nil else { return }
        
        isRecording = true
        statusText = "Starting overlapping windows test..."
        currentTranscription = ""
        newWords.removeAll()
        
        Task {
            await audioManager.start()
            await overlappingBufferManager.reset()
            await streamingTranscriber.reset()
            
            audioProcessingTask = Task { [weak self] in
                guard let self = self else { return }
                
                do {
                    let audioFrameStream = self.audioManager.audioFrames()
                    let windowStream = await self.overlappingBufferManager.windowStream()
                    
                    // Start processing audio in background
                    Task {
                        await self.overlappingBufferManager.processAudioStream(audioFrameStream)
                    }
                    
                    // Process windows as they come
                    for try await window in windowStream {
                        print("OverlappingCaptionViewModel: Processing window \(window.id.uuidString.prefix(8))")
                        
                        let update = await self.streamingTranscriber.transcribeWindow(window)
                        
                        await MainActor.run {
                            self.handleTranscriptionUpdate(update)
                        }
                        
                        try Task.checkCancellation()
                    }
                    
                    await MainActor.run {
                        self.statusText = "Overlapping windows test completed"
                        self.isRecording = false
                    }
                    
                } catch {
                    await MainActor.run {
                        self.statusText = "Error: \(error.localizedDescription)"
                        self.isRecording = false
                    }
                    print("OverlappingCaptionViewModel: Error: \(error)")
                }
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioManager.stop()
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
        
        isRecording = false
        statusText = "Stopped overlapping windows test"
    }
    
    func clearTranscription() {
        currentTranscription = ""
        newWords.removeAll()
        statusText = "Cleared transcription"
    }
    
    // MARK: - Private Methods
    
    private func setupTranscriptionSubscription() {
        transcriptionCancellable = streamingTranscriber.transcriptionPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("Transcription publisher finished")
                    case .failure(let error):
                        print("Transcription publisher error: \(error)")
                        self.statusText = "Transcription error: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] update in
                    self?.handleTranscriptionUpdate(update)
                }
            )
    }
    
    private func handleTranscriptionUpdate(_ update: TranscriptionUpdate) {
        // Update current transcription
        currentTranscription = update.fullTranscription
        
        // Add new words with animation
        if update.hasNewWords {
            newWords.append(contentsOf: update.newWords)
            
            // Remove new words after 3 seconds (for animation effect)
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                await MainActor.run {
                    self.newWords.removeAll()
                }
            }
        }
        
        // Update status
        statusText = "Window \(update.windowID.uuidString.prefix(8)): \(update.newWordCount) new words, status: \(update.status)"
        
        // Update buffer stats
        Task {
            let stats = await overlappingBufferManager.bufferStats
            await MainActor.run {
                self.bufferStats = stats.description
            }
        }
        
        print("OverlappingCaptionViewModel: Update - \(update.newWordCount) new words, status: \(update.status)")
    }
}

// MARK: - Test Helper Extensions

extension OverlappingCaptionViewModel {
    
    /// Gets debug information about the current state
    var debugInfo: String {
        return """
        Recording: \(isRecording)
        Current Transcription: "\(currentTranscription)"
        New Words: \(newWords)
        Buffer Stats: \(bufferStats)
        """
    }
    
    /// Simulates a test window for debugging
    func simulateTestWindow() {
        Task {
            let testAudio = Array(repeating: Float(0.1), count: 16000) // 1 second of test audio
            let testWindow = AudioWindow(audio: testAudio, startTimeMS: 0)
            
            let update = await streamingTranscriber.transcribeWindow(testWindow)
            
            await MainActor.run {
                self.handleTranscriptionUpdate(update)
            }
        }
    }
} 