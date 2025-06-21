//
//  RealTimeCaptionViewModel.swift
//  Livcap
//
//  Created by Implementation Plan on 6/21/25.
//

import Foundation
import Combine

/// Enhanced ViewModel for real-time captioning with overlapping windows
/// Integrates WordLevelDiffing and LocalAgreementPolicy for optimal results
@MainActor
class RealTimeCaptionViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    @Published private(set) var isRecording = false
    @Published var currentTranscription: String = ""
    @Published var stableTranscription: String = ""
    @Published var newWords: [String] = []
    @Published var wordAnimations: [WordAnimation] = []
    @Published var statusText: String = "Ready for real-time captioning"
    @Published var confidence: Float = 1.0
    @Published var stabilityStats: StabilityStats = StabilityStats()
    
    // MARK: - Private Properties
    private let audioManager: AudioManager
    private let overlappingBufferManager: OverlappingBufferManager
    private let streamingTranscriber: StreamingWhisperTranscriber
    private let wordLevelDiffing: WordLevelDiffing
    private let localAgreementPolicy: LocalAgreementPolicy
    
    private var audioProcessingTask: Task<Void, Error>?
    private var transcriptionCancellable: AnyCancellable?
    private var animationTimer: Timer?
    
    // MARK: - Data Structures
    struct WordAnimation: Identifiable {
        let id = UUID()
        let word: String
        let confidence: Float
        let timestamp: Date
        var isVisible: Bool = true
        
        var age: TimeInterval {
            return Date().timeIntervalSince(timestamp)
        }
    }
    
    struct StabilityStats {
        var agreementRate: Float = 0.0
        var averageConfidence: Float = 0.0
        var stabilityDuration: TimeInterval = 0.0
        var windowCount: Int = 0
        var isStable: Bool = false
    }
    
    // MARK: - Initialization
    init(audioManager: AudioManager = AudioManager()) {
        self.audioManager = audioManager
        self.overlappingBufferManager = OverlappingBufferManager()
        self.streamingTranscriber = StreamingWhisperTranscriber()
        self.wordLevelDiffing = WordLevelDiffing()
        self.localAgreementPolicy = LocalAgreementPolicy()
        
        setupTranscriptionSubscription()
        setupAnimationTimer()
    }
    
    deinit {
        animationTimer?.invalidate()
    }
    
    // MARK: - Public Interface
    
    func startRecording() {
        guard audioProcessingTask == nil else { return }
        
        isRecording = true
        statusText = "Starting real-time captioning..."
        resetState()
        
        Task {
            await audioManager.start()
            await overlappingBufferManager.reset()
            await streamingTranscriber.reset()
            localAgreementPolicy.reset()
            
            audioProcessingTask = Task { [weak self] in
                guard let self = self else { return }
                
                do {
                    let audioFrameStream = self.audioManager.audioFrames()
                    
                    // Subscribe to window updates
                    let windowCancellable = await self.overlappingBufferManager.windows
                        .sink { window in
                            Task { [weak self] in
                                guard let self = self else { return }
                                
                                print("RealTimeCaptionViewModel: Processing window \(window.id.uuidString.prefix(8))")
                                
                                let update = await self.processWindowWithStabilization(window)
                                
                                await MainActor.run {
                                    self.handleStabilizedUpdate(update)
                                }
                            }
                        }
                    
                    // Start processing audio
                    await self.overlappingBufferManager.processAudioStream(audioFrameStream)
                    
                    // Keep the task alive until cancelled
                    try await Task.sleep(nanoseconds: 1_000_000_000_000) // 1000 seconds
                    
                    await MainActor.run {
                        self.statusText = "Real-time captioning completed"
                        self.isRecording = false
                    }
                    
                } catch {
                    await MainActor.run {
                        self.statusText = "Error: \(error.localizedDescription)"
                        self.isRecording = false
                    }
                    print("RealTimeCaptionViewModel: Error: \(error)")
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
        statusText = "Stopped real-time captioning"
    }
    
    func clearTranscription() {
        resetState()
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
                    // This will be handled by the stabilized processing
                }
            )
    }
    
    private func setupAnimationTimer() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAnimations()
        }
    }
    
    private func resetState() {
        currentTranscription = ""
        stableTranscription = ""
        newWords.removeAll()
        wordAnimations.removeAll()
        confidence = 1.0
        stabilityStats = StabilityStats()
    }
    
    private func processWindowWithStabilization(_ window: AudioWindow) async -> LocalAgreementPolicy.StabilizationResult {
        // Get transcription from Whisper
        let transcriptionUpdate = await streamingTranscriber.transcribeWindow(window)
        
        // Apply LocalAgreement-2 policy
        let stabilizationResult = localAgreementPolicy.processWindow(
            transcription: transcriptionUpdate.fullTranscription,
            confidence: transcriptionUpdate.confidence,
            windowStartTime: Double(window.startTimeMS) / 1000.0,
            windowEndTime: Double(window.endTimeMS) / 1000.0
        )
        
        print("RealTimeCaptionViewModel: Stabilization result - \(stabilizationResult)")
        
        return stabilizationResult
    }
    
    private func handleStabilizedUpdate(_ result: LocalAgreementPolicy.StabilizationResult) {
        // Update stable transcription
        stableTranscription = result.stablePrefix
        
        // Update current transcription (latest window)
        if let latestWindow = localAgreementPolicy.history.last {
            currentTranscription = latestWindow.transcription
        }
        
        // Handle new words with animations
        if result.hasNewContent {
            addNewWordAnimations(result.newWords, confidence: result.confidence)
        }
        
        // Update confidence
        confidence = result.confidence
        
        // Update stability stats
        let stats = localAgreementPolicy.getStabilityStats()
        stabilityStats = StabilityStats(
            agreementRate: stats.agreementRate,
            averageConfidence: stats.averageConfidence,
            stabilityDuration: stats.stabilityDuration,
            windowCount: localAgreementPolicy.history.count,
            isStable: result.isStable
        )
        
        // Update status
        statusText = "Window \(localAgreementPolicy.history.count): \(result.newWords.count) new words, stability: \(String(format: "%.1f", result.stabilityPercentage * 100))%"
        
        print("RealTimeCaptionViewModel: Update - \(result.newWords.count) new words, stable: \(result.isStable)")
    }
    
    private func addNewWordAnimations(_ words: [String], confidence: Float) {
        let newAnimations = words.map { word in
            WordAnimation(
                word: word,
                confidence: confidence,
                timestamp: Date()
            )
        }
        
        wordAnimations.append(contentsOf: newAnimations)
        
        // Remove old animations after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.removeOldAnimations()
        }
    }
    
    private func removeOldAnimations() {
        let cutoffTime = Date().timeIntervalSince1970 - 3.0
        wordAnimations.removeAll { animation in
            animation.timestamp.timeIntervalSince1970 < cutoffTime
        }
    }
    
    private func updateAnimations() {
        // Update animation states based on age
        for i in wordAnimations.indices {
            let age = wordAnimations[i].age
            if age > 2.5 {
                wordAnimations[i].isVisible = false
            }
        }
        
        // Remove invisible animations
        wordAnimations.removeAll { !$0.isVisible }
    }
}

// MARK: - Debug Extensions

extension RealTimeCaptionViewModel {
    
    /// Gets debug information about the current state
    var debugInfo: String {
        return """
        Recording: \(isRecording)
        Stable Transcription: "\(stableTranscription)"
        Current Transcription: "\(currentTranscription)"
        New Words: \(newWords)
        Word Animations: \(wordAnimations.count)
        Confidence: \(String(format: "%.2f", confidence))
        Stability: \(stabilityStats.isStable ? "Stable" : "Unstable")
        Agreement Rate: \(String(format: "%.1f", stabilityStats.agreementRate * 100))%
        """
    }
    
    /// Gets detailed stability information
    var stabilityInfo: String {
        return """
        Agreement Rate: \(String(format: "%.1f", stabilityStats.agreementRate * 100))%
        Average Confidence: \(String(format: "%.2f", stabilityStats.averageConfidence))
        Stability Duration: \(String(format: "%.1f", stabilityStats.stabilityDuration))s
        Window Count: \(stabilityStats.windowCount)
        Is Stable: \(stabilityStats.isStable)
        """
    }
} 