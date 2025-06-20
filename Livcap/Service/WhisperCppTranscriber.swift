//
//  WhisperCppTranscriber.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/19/25.
//

import Foundation
import Combine

struct SimpleTranscriptionResult:Sendable {
    let text:String
    let segmentID:UUID
}


actor WhisperCppTranscriber {
    private var whisperCppContext:WhisperCpp?
    private let modelName:String
    private var canTranscribe:Bool = false
    
    let transcriptionPublisher=PassthroughSubject<SimpleTranscriptionResult,Error>()
    
    init(modelName:String = WhisperModelName().tinyEn) {
        whisperCppContext=nil
        self.modelName=modelName
        Task {
            await loadModle()
        }
    }
    
    private func loadModle() async {
        guard let modelPath = Bundle.main.path(forResource: self.modelName, ofType: "bin") else {
            print("Model file not found.")
            return
        }
        do {
            self.whisperCppContext = try WhisperCpp.createContext(path: modelPath)
            canTranscribe=true
            print("Whisper model initialized with path: \(modelName)")
        }catch{
            print("Error loading model: \(error.localizedDescription)")
        }
    }
    
    
    func transcribe(segment: TranscribableAudioSegment) async {
        
        guard canTranscribe, let whisperCppContext = whisperCppContext else {
            print("Model not loaded or not ready for transcription.")
            return
        }
    
        print("Starting Whisper transcription for segment ID: \(segment.id) starting at \(segment.startTimeMS)ms, length: \(segment.audio.count) samples")
        await whisperCppContext.fullTranscribe(samples: segment.audio)
          
        let transcriptionText = await whisperCppContext.getTranscription()
        print("Whisper result for ID \(segment.id): \"\(transcriptionText)\"")

          // Send the complete transcription text
        transcriptionPublisher.send(SimpleTranscriptionResult(text: transcriptionText, segmentID: segment.id))


    }
    
    
}
