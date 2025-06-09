//
//  CaptionViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import Foundation
import Combine // Needed for Combine framework elements like Cancellable

/// `TranscriptionViewModel` acts as a bridge between the `AudioManager` and the SwiftUI `View`.
///
/// It holds the state for the UI, controls the audio recording, and listens for audio chunks
/// to provide feedback to the user.
final class CaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    /// The current recording state, published for the UI to observe.
    @Published private(set) var isRecording = false
    
    /// A status message to display in the UI (e.g., "Recording...", "Stopped", "Processing chunk...").
    @Published var statusText: String = "Ready to record"
    
    // MARK: - Private Properties
    
    private let audioManager: AudioManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(audioManager: AudioManager = AudioManager()) {
        self.audioManager = audioManager
        
        // Subscribe to the isRecording publisher from the AudioManager
        // to automatically update our own isRecording property.
        audioManager.$isRecording
            .receive(on: DispatchQueue.main) // Ensure UI updates are on the main thread
            .assign(to: \.isRecording, on: self)
            .store(in: &cancellables)
        
        // Subscribe to the audio chunk publisher to know when new data is available.
        audioManager.audioChunkPublisher
            .receive(on: DispatchQueue.main) // Ensure UI updates are on the main thread
            .sink(receiveCompletion: { [weak self] completion in
                // Handle errors if they occur
                if case .failure(let error) = completion {
                    self?.statusText = "Error: \(error.localizedDescription)"
                }
            }, receiveValue: { [weak self] dataChunk in
                // For this example, we'll just update the status text.
                // In a real app, you would send this 'dataChunk' to a transcription service.
                let chunkSize = String(format: "%.2f", Double(dataChunk.count) / 1024.0)
                self?.statusText = "🎤 Processing audio chunk (\(chunkSize) KB)..."
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Public Control Methods
    
    /// Toggles the recording state.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        audioManager.start()
        statusText = "Recording... Speak now!"
    }
    
    private func stopRecording() {
        audioManager.stop()
        statusText = "Recording stopped."
    }
}
