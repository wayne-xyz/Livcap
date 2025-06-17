//
//  ASRSimpleViewModel.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/16/25.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
class ASRSimpleViewModel: ObservableObject {
    @Published var transcribedText = ""
    @Published var statusMessage = ""
    @Published var audioInfo = ""
    @Published var canTranscribe = false
    @Published var transcriptionTime: TimeInterval = 0
    @Published var audioDuration: TimeInterval = 0
    @Published var transcriberApproach: TranscriberApproach = .whisperCpp
    
    private var whisperCppContext: WhisperCpp?
    private let modelNames = whispercppModel()
    private let sampleNames = audioExampleNames()
    
    private var sfSpeechRecognizer: SFSpeechRecog=SFSpeechRecog()
    
    
    
    init() {
        Task {
            await loadModel(modelName: modelNames.baseEn,isLog: true)
            
            sfSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .init(truncating: 0):
                    print("Authorized")
                default:
                    print("Not authorized")
                }
            }
        }
    }
    
    // MARK: - Model WhisperCpp Loading
    
    private func loadModel(modelName: String = whispercppModel().baseEn, isLog: Bool = true) async {
        whisperCppContext = nil
        let loadingStartTime=Date()
        if isLog {
            debugLog("Loading model start at \(loadingStartTime)...")
            statusMessage = "Loading model...\n"
        }
        
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "bin") else {
            statusMessage = "Model file not found."
            return
        }
        
        do {
            self.whisperCppContext = try WhisperCpp.createContext(path: modelPath)
            statusMessage = "Model loaded successfully. Ready to transcribe."
            canTranscribe = true
            let loadingEndTime=Date()
            let costTime=loadingEndTime.timeIntervalSince(loadingStartTime)
            
            if isLog{
                
                debugLog("Loading model end at \(loadingEndTime)...\n")
                debugLog("Loading time spent: \(costTime) seconds\n")
            }
        } catch {
            statusMessage = "Error loading model: \(error.localizedDescription)"
            print("Error loading model: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Transcription
    
    func transcribeSample(sampleName: String) async {
        guard canTranscribe, let whisperCppContext = whisperCppContext else {
            statusMessage = "Model not loaded or not ready for transcription."
            return
        }
        
        guard let sampleURL = Bundle.main.url(forResource: sampleName, withExtension: "wav") else {
            statusMessage = "Sample audio file not found."
            return
        }
        
        do {
            // Get audio duration
            let audioFile = try AVAudioFile(forReading: sampleURL)
            audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            
            // Read audio samples
            statusMessage = "Reading audio samples..."
            let samples = try readAudioSamples(sampleURL)
            
            // Perform transcription with timing
            statusMessage = "Transcribing..."
            let startTime = Date()
            await whisperCppContext.fullTranscribe(samples: samples)
            let endTime = Date()
            transcriptionTime = endTime.timeIntervalSince(startTime)
            
            // Get transcription result
            let text = await whisperCppContext.getTranscription()
            transcribedText = text
            
            // Update status with timing information
            statusMessage = """
                Transcription completed:
                Audio duration: \(String(format: "%.2f", audioDuration))s
                Transcription time: \(String(format: "%.2f", transcriptionTime))s
                """
            
        } catch {
            statusMessage = "Error during transcription: \(error.localizedDescription)"
            print("Transcription error: \(error.localizedDescription)")
        }
    }
    
    
    func sftranscribeSample(sampleName:String) async{
        guard let sampleURL = Bundle.main.url(forResource: sampleName, withExtension: "wav") else {
            statusMessage = "Sample audio file not found."
            return
        }
        
        do {
            let audioFile = try AVAudioFile(forReading: sampleURL)
            audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            let startTime=Date()
            
            sfSpeechRecognizer.transcribe(audioURL:  sampleURL, onDevice: true) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let transcription):
                    self.transcribedText = transcription
                    self.statusMessage = "SFSpeechRecognizer transcription successful."
                    let endTime=Date()
                    let timeElapsed=endTime.timeIntervalSince(startTime)
                    self.transcriptionTime=timeElapsed
                    print("Time Elapsed : \(timeElapsed) seconds")
                case .failure(let error):
                    print("Print Error : \(error)")
                }
            }

            
        }catch{
            statusMessage="Error occurred while reading audio file."
            print("Error occurred while reading audio file. \(error.localizedDescription)")
        }

    }
    
    
    
    
    
    private func readAudioSamples(_ url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)
        
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try audioFile.read(into: buffer)
        
        // Convert to mono if needed
        let channelData = buffer.floatChannelData?[0]
        let frameLength = Int(buffer.frameLength)
        
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
}

enum TranscriberApproach{
    case whisperCpp
    case sfSpeechRecognizer
    case mlxwhisper
}

struct whispercppModel {
    let baseEn = "ggml-base.en"
    let tinyEn = "ggml-tiny.en"
}

struct audioExampleNames {
    let sample1 = "Speaker26_000"
    let sample2 = "Speaker27_000"
}
