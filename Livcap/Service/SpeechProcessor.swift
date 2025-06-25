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
    private var cancellables = Set<AnyCancellable>()
    
    // Logging
    private let logger = Logger(subsystem: "com.livcap.audio", category: "SpeechProcessor")

    // MARK: - Initialization
    init() {
        speechRecognitionManager.delegate = self
    }
    
    // MARK: - Public Control
    
    func startProcessing() {
        speechRecognitionManager.startRecording()
        logger.info("🎙️ SpeechProcessor processing started.")
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
            AudioDebugLogger.shared.logVADTransition(from: currentSpeechState, to: isSpeech)
            
            if isSpeech {
                logger.info("🗣️ \(audioFrame.source.rawValue.uppercased()) SPEECH START detected")
            } else {
                logger.info("🤫 \(audioFrame.source.rawValue.uppercased()) SPEECH END detected")
            }
            currentSpeechState = isSpeech
        }
    }
    
    func clearCaptions() {
        speechRecognitionManager.clearCaptions()
        logger.info("🗑️ CLEARED ALL CAPTIONS")
    }
}

// MARK: - SpeechRecognitionManagerDelegate
extension SpeechProcessor: SpeechRecognitionManagerDelegate {
    func speechRecognitionDidUpdateTranscription(_ manager: SpeechRecognitionManager, newText: String) {
        self.objectWillChange.send()
    }
    
    func speechRecognitionDidFinalizeSentence(_ manager: SpeechRecognitionManager, sentence: String) {
        self.objectWillChange.send()
        logger.info("📝 FINALIZED SENTENCE: \(sentence)")
    }
    
    func speechRecognitionDidEncounterError(_ manager: SpeechRecognitionManager, error: Error) {
        logger.error("❌ SPEECH RECOGNITION ERROR: \(error.localizedDescription)")
        // In a real app, you might want to publish this error to the UI
    }
    
    func speechRecognitionStatusDidChange(_ manager: SpeechRecognitionManager, status: String) {
        // This could also be published to the UI if needed
    }
} 