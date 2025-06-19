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
    @Published private(set) var isRecording = false //for ui
    
    /// A status message to display in the UI (e.g., "Recording...", "Stopped", "Processing chunk...").
    @Published var statusText: String = "Ready to record"
    
    
    // MARK: - Private Properties
    
    private let audioManager: AudioManager
    private var cancellables = Set<AnyCancellable>()
    private var audioProcessingTask: Task<Void,Error>?
    
    // MARK: - Initialization
    
    init(audioManager: AudioManager = AudioManager()) {
        self.audioManager = audioManager
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
        
        guard audioProcessingTask == nil else {
            return
        }
        
        isRecording=true
        
        audioProcessingTask=Task{
            do {
                await audioManager.start()
                
                for try await samples in audioManager.audioFrames(){
                    let sampleCount=samples.count
                    await MainActor.run{
                        self.statusText="Processing \(sampleCount) samples..."
                    }
                    try Task.checkCancellation( )
                }
                
                await MainActor.run{
                    self.statusText="Recoding stopped."
                    self.isRecording=false
                }
                
            }catch is CancellationError{
                await MainActor.run{
                    statusText="Recording stopped by user."
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
    
    
    
    private func stopRecording() {
        guard isRecording else { return }
        audioManager.stop()
        audioProcessingTask?.cancel()
    }
}
