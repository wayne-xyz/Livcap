import Foundation
import Combine
import os.log

final class SpeechProcessor: ObservableObject {

    // MARK: - Published Properties
    @Published private(set) var currentSpeechState: Bool = false
    
    // Forwarded from SpeechRecognitionManager
    var captionHistory: [CaptionEntry] { speechRecognitionManager.captionHistory }
    var currentTranscription: String { speechRecognitionManager.currentTranscription }
    
    // MARK: - Private Properties
    private let speechRecognitionManager = SpeechRecognitionManager()
    private var speechEventsTask: Task<Void, Never>?
    
    // Logging
    private let logger = Logger(subsystem: "com.livcap.audio", category: "SpeechProcessor")

    // MARK: - Initialization
    init() {
        startListeningToSpeechEvents()
    }
    
    deinit {
        speechEventsTask?.cancel()
    }
    
    // MARK: - Private Setup
    
    private func startListeningToSpeechEvents() {
        speechEventsTask = Task {
            let speechEvents = speechRecognitionManager.speechEvents()
            
            for await event in speechEvents {
                await handleSpeechEvent(event)
            }
        }
    }
    
    @MainActor
    private func handleSpeechEvent(_ event: SpeechEvent) {
        switch event {
        case .transcriptionUpdate(let text):
            // Trigger UI update for new transcription
            objectWillChange.send()
            
        case .sentenceFinalized(let sentence):
            // Trigger UI update for finalized sentence
            objectWillChange.send()
            logger.info("📝 FINALIZED SENTENCE: \(sentence)")
            
        case .statusChanged(let status):
            // Could publish status changes to UI if needed
            logger.info("📊 STATUS CHANGED: \(status)")
            
        case .error(let error):
            logger.error("❌ SPEECH RECOGNITION ERROR: \(error.localizedDescription)")
            // In a real app, you might want to publish this error to the UI
        }
    }
    
    // MARK: - Public Control
    
    func startProcessing() {
        Task {
            do {
                try await speechRecognitionManager.startRecording()
                logger.info("🎙️ SpeechProcessor processing started.")
            } catch {
                logger.error("❌ Failed to start speech processing: \(error.localizedDescription)")
            }
        }
    }
    
    func stopProcessing() {
        speechRecognitionManager.stopRecording()
        logger.info("🛑 SpeechProcessor processing stopped.")
    }
    
    func processAudioFrame(_ audioFrame: AudioFrameWithVAD) {
        speechRecognitionManager.appendAudioBufferWithVAD(audioFrame)
        handleSpeechStateTransition(audioFrame)
    }

    // MARK: - Private Logic
    
    private func handleSpeechStateTransition(_ audioFrame: AudioFrameWithVAD) {
        let isSpeech = audioFrame.isSpeech
        
        // Detect speech state transitions
        if isSpeech != currentSpeechState {
            Task { @MainActor in
                self.currentSpeechState = isSpeech
            }
        }
    }
    
    func clearCaptions() {
        speechRecognitionManager.clearCaptions()
        logger.info("🗑️ CLEARED ALL CAPTIONS")
    }
}
