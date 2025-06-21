//
//  ContinuousViewModel.swift
//  Livcap
//
//  Created for Phase 1 WhisperLive Implementation
//

import Foundation
import Combine

final class ContinuousViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published var statusText: String = "Ready for continuous streaming"
    @Published var transcriptionManager: TranscriptionDisplayManager
    
    // MARK: - Phase 1 Monitoring Properties
    
    @Published var streamingMetrics: StreamingMetrics?
    @Published var lastChunkInfo: String = "No chunks yet"
    @Published var transcriptionTriggerCount: Int = 0
    @Published var bufferVisualization: [Float] = []
    
    // MARK: - Private Properties
    
    private let audioManager: AudioManager
    private let continuousStreamManager: ContinuousStreamManager
    private var whisperCppTranscriber: WhisperCppTranscriber?
    
    private var audioProcessingTask: Task<Void,Error>?
    private var transcriblerCancellable: AnyCancellable?
    private var metricsSubscription: AnyCancellable?
    private var chunkSubscription: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(audioManager: AudioManager = AudioManager()) {
        self.audioManager = audioManager
        self.continuousStreamManager = ContinuousStreamManager()
        self.whisperCppTranscriber = WhisperCppTranscriber()
        self.transcriptionManager = TranscriptionDisplayManager()
        setupSubscriptions()
    }
    
    // MARK: - Subscriptions Setup
    
    private func setupSubscriptions() {
        setupTranscriptionSubscription()
        setupMetricsSubscription()
        setupChunkMonitoring()
    }
    
    private func setupTranscriptionSubscription() {
        guard let transcriber = whisperCppTranscriber else { return }
        
        transcriblerCancellable = transcriber.transcriptionPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("Transcription publisher finished")
                    case .failure(let error):
                        print("Transcription publisher error: \(error)")
                        self.statusText = "Transcription error: \(error.localizedDescription)"
                        self.transcriptionManager.updateStatus(.error(error.localizedDescription))
                    }
                },
                receiveValue: { [weak self] result in
                    self?.handleTranscriptionResult(result)
                }
            )
    }
    
    private func setupMetricsSubscription() {
        metricsSubscription = continuousStreamManager.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.streamingMetrics = metrics
                self?.updateStatusFromMetrics(metrics)
            }
    }
    
    private func setupChunkMonitoring() {
        chunkSubscription = continuousStreamManager.chunkPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] chunk in
                    self?.handleChunkUpdate(chunk)
                }
            )
        
        // Listen for transcription triggers
        continuousStreamManager.transcriptionTriggerPublisher
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] transcriptionChunk in
                    Task {
                        await self?.handleTranscriptionTrigger(transcriptionChunk)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func handleTranscriptionTrigger(_ chunk: ContinuousAudioChunk) async {
        print("🎯 Processing transcription trigger: \(chunk.audio.count) samples")
        
        // Convert to TranscribableAudioSegment for compatibility
        let segment = TranscribableAudioSegment(
            audio: chunk.audio,
            startTimeMS: chunk.timestampMs,
            id: chunk.id
        )
        
        await whisperCppTranscriber?.transcribe(segment: segment)
    }
    
    private func handleTranscriptionResult(_ result: SimpleTranscriptionResult) {
        transcriptionManager.processTranscription(result)
        statusText = "Confidence: \(String(format: "%.2f", result.overallConfidence)) | \(transcriptionManager.displayStatus.description)"
        
        print("📝 Transcription: \(result.text) (confidence: \(String(format: "%.3f", result.overallConfidence)))")
    }
    
    private func handleChunkUpdate(_ chunk: ContinuousAudioChunk) {
        lastChunkInfo = "Chunk #\(chunk.chunkIndex) | \(chunk.timestampMs)ms | \(chunk.audio.count) samples"
        
        if chunk.isTranscriptionTrigger {
            transcriptionTriggerCount += 1
        }
        
        // Update buffer visualization (last 50 samples for visualization)
        let visualizationSamples = min(50, chunk.audio.count)
        bufferVisualization = Array(chunk.audio.suffix(visualizationSamples))
    }
    
    private func updateStatusFromMetrics(_ metrics: StreamingMetrics) {
        let bufferPercent = Int(metrics.bufferUtilization * 100)
        let avgProcessing = String(format: "%.1f", metrics.averageChunkProcessingTimeMs)
        
        if isRecording {
            statusText = "Streaming | Buffer: \(bufferPercent)% | Avg: \(avgProcessing)ms | Triggers: \(metrics.totalTranscriptionsTriggered)"
        }
    }
    
    // MARK: - Main Control Functions
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard audioProcessingTask == nil else { return }
        
        isRecording = true
        statusText = "Starting continuous streaming..."
        transcriptionManager.clearAll()
        transcriptionManager.updateStatus(.ready)
        transcriptionTriggerCount = 0
        
        Task {
            await audioManager.start()
            await continuousStreamManager.reset()
            
            audioProcessingTask = Task { [weak self] in
                guard let self = self else { return }
                print("ContinuousViewModel: Starting continuous audio processing...")
                
                do {
                    let audioFrameStream = self.audioManager.audioFrames()
                    
                    // Debug: Test if audio frames are coming through
                    print("🎤 Audio stream created, waiting for frames...")
                    
                    // Debug version: Process chunks directly and track transcription triggers
                    var chunkCount = 0
                    
                    for try await audioFrame in audioFrameStream {
                        chunkCount += 1
                        
                        // Process chunk through stream manager
                        await self.continuousStreamManager.processAudioChunk(audioFrame)
                        
                        // Debug every 10 chunks
                        if chunkCount % 10 == 0 {
                            print("🎤 Processed \(chunkCount) audio chunks")
                        }
                        
                        try Task.checkCancellation()
                    }
                    
                    // Alternative: Use the trigger-based approach
                    /*
                    let transcriptionTriggers = await self.continuousStreamManager.getTranscriptionTriggers(audioFrameStream)
                    
                    for try await transcriptionChunk in transcriptionTriggers {
                        print("🎯 Processing transcription trigger: \(transcriptionChunk.audio.count) samples")
                        
                        // Convert to TranscribableAudioSegment for compatibility
                        let segment = TranscribableAudioSegment(
                            audio: transcriptionChunk.audio,
                            startTimeMS: transcriptionChunk.timestampMs,
                            id: transcriptionChunk.id
                        )
                        
                        await self.whisperCppTranscriber?.transcribe(segment: segment)
                        try Task.checkCancellation()
                    }
                    */
                    
                    print("Continuous audio processing finished.")
                    
                    await MainActor.run {
                        self.statusText = "Streaming stopped."
                        self.isRecording = false
                        self.transcriptionManager.updateStatus(.ready)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.statusText = "Streaming stopped by user."
                        self.isRecording = false
                        self.transcriptionManager.updateStatus(.ready)
                    }
                    print("Continuous streaming stopped by user.")
                } catch {
                    await MainActor.run {
                        self.statusText = "Error: \(error)"
                        self.isRecording = false
                        self.transcriptionManager.updateStatus(.error(error.localizedDescription))
                    }
                    print("Continuous streaming error: \(error)")
                }
                self.audioProcessingTask = nil
            }
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        audioManager.stop()
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
    }
    
    func clearCaptions() {
        transcriptionManager.clearAll()
        transcriptionTriggerCount = 0
    }
    
    // MARK: - Computed Properties for UI
    
    var captionText: String {
        return transcriptionManager.displayCaption
    }
    
    var captionHistory: [CaptionEntry] {
        return transcriptionManager.captionHistory
    }
    
    // MARK: - Phase 1 Monitoring Functions
    
    func getCurrentMetrics() async -> StreamingMetrics? {
        return await continuousStreamManager.getCurrentMetrics()
    }
    
    func getDetailedStatusReport() -> String {
        guard let metrics = streamingMetrics else {
            return "No metrics available"
        }
        
        return """
        📊 Continuous Streaming Status:
        • Chunks processed: \(metrics.totalChunksProcessed)
        • Transcriptions triggered: \(metrics.totalTranscriptionsTriggered)
        • Buffer utilization: \(String(format: "%.1f", metrics.bufferUtilization * 100))%
        • Buffer size: \(metrics.currentBufferSizeMs)ms
        • Avg processing: \(String(format: "%.2f", metrics.averageChunkProcessingTimeMs))ms
        """
    }
}