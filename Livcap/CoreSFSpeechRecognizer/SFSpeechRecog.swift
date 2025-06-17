//
//  SFSpeechRecognizer.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/17/25.
//
import Foundation
import Speech
import AVFoundation


/// A service dedicated to handling speech-to-text transcription.
/// This class is isolated from the UI and can be reused across the app.
class SFSpeechRecog {

    // MARK: - Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Initialization
    
    init(locale: Locale = Locale.current) {
        // Initialize with a specific locale, or default to the user's current one.
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Public API
    
    /// Requests user authorization for speech recognition.
    /// - Parameter completion: A closure that returns `true` if authorized, `false` otherwise.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            // Ensure the completion handler is called on the main thread.
            DispatchQueue.main.async {
                completion(authStatus == .authorized)
            }
        }
    }

    /// Transcribes an audio file from a given URL.
    /// - Parameters:
    ///   - url: The URL of the audio file to transcribe.
    ///   - onDevice: A boolean to prefer on-device transcription.
    ///   - completion: A closure that returns the transcription result or an error.
    ///   The result is a `Result<String, Error>` enum.
    func transcribe(audioURL: URL, onDevice: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        
        // 1. Check Recognizer Availability
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            completion(.failure(TranscriberError.recognizerUnavailable))
            return
        }
        
        // 2. Cancel any previous tasks to prevent overlap.
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // 3. Create the recognition request.
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        
        // 4. Configure on-device recognition if supported and requested.
        if onDevice && speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else if onDevice {
            // If on-device is requested but not supported, you can decide how to handle it.
            // Here, we'll proceed with network-based recognition but log a warning.
            print("Warning: On-device recognition requested but not supported. Using network-based recognition.")
        }
        
        // 5. Create and start the recognition task.
        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let result = result {
                // When the transcription is final, send the result.
                if result.isFinal {
                    completion(.success(result.bestTranscription.formattedString))
                }
            }
        }
    }
    
    /// Defines custom errors for the transcriber service.
    enum TranscriberError: Error, LocalizedError {
        case recognizerUnavailable
        case authorizationDenied
        case audioFileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "The speech recognizer is not available for the current locale."
            case .authorizationDenied:
                return "Speech recognition authorization was denied by the user."
            case .audioFileNotFound(let filename):
                return "The audio file '\(filename)' could not be found."
            }
        }
    }
}
