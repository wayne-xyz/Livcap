//
//  CaptionViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

import Foundation
import Combine


/// `TranscriptionViewModel` acts as a bridge between the `AudioManager` and the SwiftUI `View`.
///
/// It holds the state for the UI, controls the audio recording, and listens for audio chunks
/// to provide feedback to the user.
final class CaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    /// The current recording state, published for the UI to observe.
    @Published private(set) var isRecording = false //for ui
    
    /// A status message to display in the UI (e.g., "Recording...", "Stopped", "Processing chunk...").
    @Published var statusText: String = "Ready to record"
    @Published var captionText: String = "..."
    
    
    // MARK: - Private Properties
    
    private let audioManager: AudioManager
    private let buffermanager: BufferManager
    private var whisperCppTranscriber: WhisperCppTranscriber?
    
    private var audioProcessingTask: Task<Void,Error>?
    private var transcriblerCancellable:AnyCancellable?
    // MARK: - Initialization
    
    init(audioManager: AudioManager = AudioManager()) {
        self.audioManager = audioManager
        self.buffermanager=BufferManager()
    }
    
    // MARK: - Core Pipeline subscriptions

    
    // MARK: - Main control functions
    
    /// Toggles the recording state.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        
        guard audioProcessingTask == nil else {
            return
        }
        
        isRecording=true
        
        Task{
            await audioManager.start()
            
            audioProcessingTask=Task{ [weak self] in
                guard let self=self else {return}
                print("ViewModeL; Starting audio processing...")
                
                do {
                    let audioFrameStream=self.audioManager.audioFrames()
                    
                    for try await segment in await self.buffermanager.processFrames(audioFrameStream){
                        print("ViewModelL; Got a segment: \(segment.id)")
                        
                        try Task.checkCancellation()
                        
                    }
                    
                    print("Audio frames stream finished.")
                    

                    await MainActor.run{
                        self.statusText="Recoding stopped."
                        self.isRecording=false
                    }
                }catch is CancellationError{
                    await MainActor.run{
                        self.statusText="Recording stopped by user."
                        self.isRecording=false
                    }
                    print("Recording stopped by user.")
                }catch{
                    await MainActor.run{
                        self.statusText="An error occurred: \(error)"
                        self.isRecording=false
                    }
                    print("An error occurred: \(error)")
                }
                self.audioProcessingTask=nil
            }
        }
    }
    
    
    
    private func stopRecording() {
        guard isRecording else { return }
        audioManager.stop()
        audioProcessingTask?.cancel()
        audioProcessingTask=nil
    }
}
