//
//  WhisperCppTranscriber.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/19/25.
//

import Foundation
import Combine

struct WhisperTokenData: Sendable {
    let text: String
    let probability: Float
    let logProbability: Float
    let timestampProbability: Float
    let startTime: Int64
    let endTime: Int64
}

struct WhisperSegmentData: Sendable {
    let text: String
    let tokens: [WhisperTokenData]
    let averageConfidence: Float
    let startTime: Int64
    let endTime: Int64
}

struct SimpleTranscriptionResult: Sendable {
    let text: String
    let segmentID: UUID
    let segments: [WhisperSegmentData]
    let overallConfidence: Float
    
    init(text: String, segmentID: UUID, segments: [WhisperSegmentData] = []) {
        self.text = text
        self.segmentID = segmentID
        self.segments = segments
        self.overallConfidence = segments.isEmpty ? 1.0 : segments.map(\.averageConfidence).reduce(0, +) / Float(segments.count)
    }
}

actor WhisperCppTranscriber {
    private var whisperCppContext: WhisperCpp?
    private let modelName: String
    private var canTranscribe: Bool = false
    
    // Make the publisher accessible from outside the actor
    nonisolated let transcriptionPublisher = PassthroughSubject<SimpleTranscriptionResult, Error>()
    
    init(modelName: String = WhisperModelName().baseEn) {
        whisperCppContext = nil
        self.modelName = modelName
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
            canTranscribe = true
            print("Whisper model initialized with path: \(modelName)")
        } catch {
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
        let detailedSegments = await whisperCppContext.getDetailedTranscription()
        
        print("Whisper result for ID \(segment.id): \"\(transcriptionText)\"")
        
        if !detailedSegments.isEmpty {
            let avgConfidence = detailedSegments.map(\.averageConfidence).reduce(0, +) / Float(detailedSegments.count)
            print("Average confidence: \(String(format: "%.3f", avgConfidence))")
            
            let wordConfidences = await whisperCppContext.getWordLevelConfidence()
            if !wordConfidences.isEmpty {
                let lowConfidenceWords = wordConfidences.filter { $0.confidence < 0.5 }
                if !lowConfidenceWords.isEmpty {
                    print("Low confidence words: \(lowConfidenceWords.map { "\($0.word)(\(String(format: "%.2f", $0.confidence)))" }.joined(separator: ", "))")
                }
            }
        }

        // Send the complete transcription with confidence data
        let result = SimpleTranscriptionResult(text: transcriptionText, segmentID: segment.id, segments: detailedSegments)
        transcriptionPublisher.send(result)
    }
}
