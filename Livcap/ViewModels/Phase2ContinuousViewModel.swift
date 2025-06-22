//
//  Phase2ContinuousViewModel.swift
//  Livcap
//
//  Phase 2: Enhanced VAD + Overlapping Confirmation System
//

import Foundation
import Combine
import SwiftUI

final class Phase2ContinuousViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isRecording = false
    @Published var statusText: String = "Phase 2: Enhanced VAD + Overlapping Confirmation"
    @Published var transcriptionManager: TranscriptionDisplayManager
    
    // MARK: - Phase 2 Enhanced Properties
    
    @Published var enhancedVAD: EnhancedVAD
    @Published var stabilizationManager: TranscriptionStabilizationManager
    @Published var lastChunkInfo: String = "No chunks yet"
    @Published var transcriptionTriggerCount: Int = 0
    @Published var bufferVisualization: [Float] = []
    
    // MARK: - Metrics and Monitoring
    
    @Published var streamingMetrics: StreamingMetrics?
    @Published var vadMetrics: (speechPercentage: Float, averageConfidence: Float, segmentCount: Int)?
    @Published var stabilizationMetrics: TranscriptionStabilizationManager.StabilizationMetrics?
    
    // MARK: - Private Properties
    
    private let audioManager: AudioManager
    private let continuousStreamManager: ContinuousStreamManager
    private var whisperCppTranscriber: WhisperCppTranscriber?
    
    private var audioProcessingTask: Task<Void,Error>?
    private var transcriblerCancellable: AnyCancellable?
    private var metricsSubscription: AnyCancellable?
    private var chunkSubscription: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    private var streamStartTime: Date = Date()
    private var lastVADUpdate: Date = Date()
    
    // MARK: - Initialization
    
    init(audioManager: AudioManager = AudioManager()) {
        self.audioManager = audioManager
        self.continuousStreamManager = ContinuousStreamManager()
        self.whisperCppTranscriber = WhisperCppTranscriber()
        self.transcriptionManager = TranscriptionDisplayManager()
        self.enhancedVAD = EnhancedVAD()
        self.stabilizationManager = TranscriptionStabilizationManager()
        
        setupSubscriptions()
    }
    
    // MARK: - Subscriptions Setup
    
    private func setupSubscriptions() {
        setupTranscriptionSubscription()
        setupMetricsSubscription()
        setupChunkMonitoring()
        setupStabilizationSubscription()
    }
    
    private func setupTranscriptionSubscription() {
        guard let transcriber = whisperCppTranscriber else { return }
        
        transcriblerCancellable = transcriber.transcriptionPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("Phase2: Transcription publisher finished")
                    case .failure(let error):
                        print("Phase2: Transcription publisher error: \\(error)")
                        self.statusText = "Transcription error: \\(error.localizedDescription)"
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
    
    private func setupStabilizationSubscription() {
        // Monitor stabilization metrics
        stabilizationManager.$stabilizationMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.stabilizationMetrics = metrics
            }
            .store(in: &cancellables)
    }
    
    private func handleTranscriptionTrigger(_ chunk: ContinuousAudioChunk) async {
        print("🎯 Phase2: Processing transcription trigger with enhanced VAD check")
        
        // Enhanced decision making using VAD
        let shouldTranscribe = await shouldTriggerTranscriptionWithVAD(chunk)
        
        if shouldTranscribe {
            print("✅ VAD confirmed transcription trigger - Processing...")
            
            // Convert to TranscribableAudioSegment for compatibility
            let segment = TranscribableAudioSegment(
                audio: chunk.audio,
                startTimeMS: chunk.timestampMs,
                id: chunk.id
            )
            
            await whisperCppTranscriber?.transcribe(segment: segment)
        } else {
            print("❌ VAD rejected transcription trigger - Insufficient speech activity")
        }
    }
    
    private func shouldTriggerTranscriptionWithVAD(_ chunk: ContinuousAudioChunk) async -> Bool {
        return await MainActor.run {
            // Use enhanced VAD to make smarter transcription decisions
            let vadResult = enhancedVAD.processAudioChunk(chunk.audio)
            
            // Update VAD metrics periodically
            let now = Date()
            if now.timeIntervalSince(lastVADUpdate) >= 1.0 {
                vadMetrics = enhancedVAD.getVADMetrics()
                lastVADUpdate = now
            }
            
            // New strategy: VAD can trigger immediately OR wait for time trigger
            let hasMinimumSpeech = enhancedVAD.shouldTriggerTranscription()
            let recentSpeechActivity = vadMetrics?.speechPercentage ?? 0.0
            let currentConfidence = vadResult.confidence
            let isCurrentlySpeaking = vadResult.isSpeech
            
            // Immediate trigger on speech detection OR regular time-based trigger
            let immediateVADTrigger = isCurrentlySpeaking && currentConfidence > 0.3 && hasMinimumSpeech
            let timeBasedTrigger = chunk.isTranscriptionTrigger && hasMinimumSpeech && recentSpeechActivity > 0.2
            
            let shouldTrigger = immediateVADTrigger || timeBasedTrigger
            
            // Post VAD decision for detailed view
            let reason = shouldTrigger ? 
                        (immediateVADTrigger ? "Immediate speech trigger" : "Time-based speech trigger") :
                        !isCurrentlySpeaking ? "No speech detected" :
                        currentConfidence <= 0.3 ? "Low confidence" :
                        !hasMinimumSpeech ? "Insufficient speech duration" : "No trigger condition met"
            
            NotificationCenter.default.post(
                name: Notification.Name("VADDecision"),
                object: [
                    "timestamp": Date(),
                    "energyLevel": vadResult.energyLevel,
                    "finalDecision": shouldTrigger,
                    "confidence": currentConfidence,
                    "reason": reason
                ]
            )
            
            if shouldTrigger {
                print("🎤 Enhanced VAD: \(reason) - Speech=\(String(format: "%.1f", recentSpeechActivity * 100))%, Confidence=\(String(format: "%.3f", currentConfidence))")
            }
            
            return shouldTrigger
        }
    }
    
    private func handleTranscriptionResult(_ result: SimpleTranscriptionResult) {
        Task { @MainActor in
            // Calculate buffer start time based on current streaming position
            let bufferStartTimeMs = Int(Date().timeIntervalSince(streamStartTime) * 1000) - 5000 // 5 second buffer
            
            // Process through stabilization manager (Phase 2 enhancement)
            stabilizationManager.processNewTranscription(result, bufferStartTimeMs: bufferStartTimeMs)
            
            // Use stabilized text for display
            let stabilizedText = stabilizationManager.getStabilizedText()
        
            // Create enhanced result with stabilization info
            let enhancedResult = SimpleTranscriptionResult(
                text: stabilizedText.isEmpty ? result.text : stabilizedText,
                segmentID: result.segmentID,
                segments: result.segments
            )
            
            // Process through original display manager
            transcriptionManager.processTranscription(enhancedResult)
            
            // Update status with stabilization info
            if let metrics = stabilizationMetrics {
                let stabilizationRate = Int(metrics.stabilizationRate * 100)
                statusText = "Confidence: \(String(format: "%.2f", result.overallConfidence)) | Stabilized: \(stabilizationRate)% | \(transcriptionManager.displayStatus.description)"
            } else {
                statusText = "Confidence: \(String(format: "%.2f", result.overallConfidence)) | \(transcriptionManager.displayStatus.description)"
            }
            
            print("📝 Phase2: \(result.text) → Stabilized: \(stabilizedText)")
        }
    }
    
    private func handleChunkUpdate(_ chunk: ContinuousAudioChunk) {
        lastChunkInfo = "Chunk #\(chunk.chunkIndex) | \(chunk.timestampMs)ms | \(chunk.audio.count) samples"
        
        if chunk.isTranscriptionTrigger {
            transcriptionTriggerCount += 1
        }
        
        // Update buffer visualization (last 50 samples for visualization)
        let visualizationSamples = min(50, chunk.audio.count)
        bufferVisualization = Array(chunk.audio.suffix(visualizationSamples))
        
        // Process through enhanced VAD for every chunk
        Task { @MainActor in
            _ = enhancedVAD.processAudioChunk(chunk.audio)
        }
    }
    
    private func updateStatusFromMetrics(_ metrics: StreamingMetrics) {
        if !isRecording { return }
        
        let bufferPercent = Int(metrics.bufferUtilization * 100)
        let avgProcessing = String(format: "%.1f", metrics.averageChunkProcessingTimeMs)
        
        // Enhanced status with VAD info
        if let vadInfo = vadMetrics {
            let speechPercent = Int(vadInfo.speechPercentage * 100)
            statusText = "Streaming | Buffer: \(bufferPercent)% | Speech: \(speechPercent)% | Triggers: \(metrics.totalTranscriptionsTriggered)"
        } else {
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
        statusText = "Starting Phase 2 enhanced streaming..."
        streamStartTime = Date()
        
        // Reset all components
        transcriptionManager.clearAll()
        transcriptionManager.updateStatus(.ready)
        transcriptionTriggerCount = 0
        Task { @MainActor in
            enhancedVAD.reset()
            stabilizationManager.reset()
        }
        
        Task {
            await audioManager.start()
            await continuousStreamManager.reset()
            
            audioProcessingTask = Task { [weak self] in
                guard let self = self else { return }
                print("Phase2: Starting enhanced continuous audio processing...")
                
                do {
                    let audioFrameStream = self.audioManager.audioFrames()
                    
                    print("🎤 Phase2: Enhanced audio stream created, waiting for frames...")
                    
                    var chunkCount = 0
                    
                    for try await audioFrame in audioFrameStream {
                        chunkCount += 1
                        
                        // Process chunk through stream manager
                        await self.continuousStreamManager.processAudioChunk(audioFrame)
                        
                        // Debug every 10 chunks
                        if chunkCount % 10 == 0 {
                            print("🎤 Phase2: Processed \(chunkCount) chunks")
                        }
                        
                        try Task.checkCancellation()
                    }
                    
                    print("Phase2: Enhanced continuous audio processing finished.")
                    
                    await MainActor.run {
                        self.statusText = "Enhanced streaming stopped."
                        self.isRecording = false
                        self.transcriptionManager.updateStatus(.ready)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.statusText = "Enhanced streaming stopped by user."
                        self.isRecording = false
                        self.transcriptionManager.updateStatus(.ready)
                    }
                    print("Phase2: Enhanced streaming stopped by user.")
                } catch {
                    await MainActor.run {
                        self.statusText = "Error: \(error)"
                        self.isRecording = false
                        self.transcriptionManager.updateStatus(.error(error.localizedDescription))
                    }
                    print("Phase2: Enhanced streaming error: \(error)")
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
        Task { @MainActor in
            stabilizationManager.reset()
            enhancedVAD.reset()
        }
    }
    
    // MARK: - Computed Properties for UI
    
    var captionText: String {
        return transcriptionManager.displayCaption
    }
    
    var captionHistory: [CaptionEntry] {
        return transcriptionManager.captionHistory
    }
    
    var stabilizedText: String {
        return ""  // Will be updated via @Published properties
    }
    
    var stabilizedWords: [StabilizedWord] {
        return []  // Will be updated via @Published properties  
    }
    
    // MARK: - Phase 2 Monitoring Functions
    
    func getCurrentMetrics() async -> StreamingMetrics? {
        return await continuousStreamManager.getCurrentMetrics()
    }
    
    func getDetailedStatusReport() -> String {
        var report = ""
        
        if let metrics = streamingMetrics {
            report += """
            📊 Phase 2 Streaming Status:
            • Chunks processed: \(metrics.totalChunksProcessed)
            • Transcriptions triggered: \(metrics.totalTranscriptionsTriggered)
            • Buffer utilization: \(String(format: "%.1f", metrics.bufferUtilization * 100))%
            
            """
        }
        
        if let vadInfo = vadMetrics {
            report += """
            🎤 Enhanced VAD Status:
            • Speech activity: \(String(format: "%.1f", vadInfo.speechPercentage * 100))%
            • Average confidence: \(String(format: "%.3f", vadInfo.averageConfidence))
            • Speech segments: \(vadInfo.segmentCount)
            
            """
        }
        
        if let stabilization = stabilizationMetrics {
            report += """
            🔄 Stabilization Status:
            • Words stabilized: \(stabilization.stabilizedWordCount)
            • Stabilization rate: \(String(format: "%.1f", stabilization.stabilizationRate * 100))%
            • Overlaps analyzed: \(stabilization.totalOverlaps)
            • Conflicts resolved: \(stabilization.conflictCount)
            """
        }
        
        return report.isEmpty ? "No metrics available" : report
    }
}