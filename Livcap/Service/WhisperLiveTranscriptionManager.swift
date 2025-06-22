//
//  WhisperLiveTranscriptionManager.swift
//  Livcap
//
//  WhisperLive-inspired transcription pipeline
//  - Integrates all WhisperLive components: buffer, extractor, agreement
//  - Processes continuous audio with 1s inference intervals
//  - Uses pre-inference VAD and LocalAgreement for optimal results
//

import Foundation
import Combine
import SwiftUI

struct WhisperLiveConfig {
    let bufferMaxDuration: TimeInterval = 30.0      // 30s continuous buffer
    let inferenceInterval: TimeInterval = 1.0       // Process every 1 second
    let speechQualityThreshold: Float = 0.6         // Minimum quality for transcription
    let confidenceThreshold: Float = 0.3            // Minimum confidence for results
    let enablePreInferenceVAD: Bool = true          // Extract speech before Whisper
    let enableLocalAgreement: Bool = true           // Use prefix matching stabilization
}

struct WhisperLiveStatus {
    let isProcessing: Bool
    let bufferDuration: TimeInterval
    let bufferGrowthPhase: String
    let speechPercentage: Float
    let lastInferenceTime: Date?
    let totalInferences: Int
    let averageProcessingTime: Double
    let currentConfidence: Float
    let stabilizationMethod: String
}

class WhisperLiveTranscriptionManager: ObservableObject {
    
    // MARK: - Configuration
    
    private let config = WhisperLiveConfig()
    
    // MARK: - Published Properties
    
    @Published private(set) var currentTranscription: String = ""
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var status: WhisperLiveStatus
    @Published private(set) var processingError: String?
    
    // MARK: - Core Components
    
    private let continuousManager: WhisperLiveContinuousManager
    private let speechExtractor: SpeechSegmentExtractor
    private let localAgreement: LocalAgreementManager
    private let whisperTranscriber: WhisperCppTranscriber
    
    // MARK: - State Management
    
    private var audioProcessingTask: Task<Void, Error>?
    private var inferenceSubscription: AnyCancellable?
    private var metricsSubscription: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // Metrics tracking
    private var totalInferences: Int = 0
    private var processingTimes: [Double] = []
    private var lastInferenceTime: Date?
    private var sessionStartTime: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        self.continuousManager = WhisperLiveContinuousManager()
        self.speechExtractor = SpeechSegmentExtractor()
        self.localAgreement = LocalAgreementManager()
        self.whisperTranscriber = WhisperCppTranscriber()
        
        // Initialize status
        self.status = WhisperLiveStatus(
            isProcessing: false,
            bufferDuration: 0,
            bufferGrowthPhase: "Initializing",
            speechPercentage: 0,
            lastInferenceTime: nil,
            totalInferences: 0,
            averageProcessingTime: 0,
            currentConfidence: 0,
            stabilizationMethod: "none"
        )
        
        setupSubscriptions()
        
        print("WhisperLiveTranscriptionManager: Initialized with WhisperLive pipeline")
        print("- Buffer: \(config.bufferMaxDuration)s continuous")
        print("- Inference: Every \(config.inferenceInterval)s")
        print("- Pre-inference VAD: \(config.enablePreInferenceVAD)")
        print("- LocalAgreement: \(config.enableLocalAgreement)")
    }
    
    // MARK: - Subscription Setup
    
    private func setupSubscriptions() {
        setupTranscriptionSubscription()
        setupMetricsSubscription()
        setupInferenceSubscription()
    }
    
    private func setupTranscriptionSubscription() {
        whisperTranscriber.transcriptionPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .finished:
                        print("WhisperLive: Transcription publisher finished")
                    case .failure(let error):
                        print("WhisperLive: Transcription error: \(error)")
                        self?.processingError = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] result in
                    self?.handleTranscriptionResult(result)
                }
            )
            .store(in: &cancellables)
    }
    
    private func setupMetricsSubscription() {
        metricsSubscription = continuousManager.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.updateStatusFromMetrics(metrics)
            }
    }
    
    private func setupInferenceSubscription() {
        inferenceSubscription = continuousManager.inferencePublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] chunk in
                    Task {
                        await self?.processInferenceChunk(chunk)
                    }
                }
            )
    }
    
    // MARK: - Main Processing Pipeline
    
    func startProcessing<S: AsyncSequence>(_ audioFrames: S) where S.Element == [Float] {
        guard audioProcessingTask == nil else {
            print("WhisperLive: Already processing")
            return
        }
        
        isProcessing = true
        processingError = nil
        sessionStartTime = Date()
        totalInferences = 0
        processingTimes.removeAll()
        
        // Reset all components
        Task {
            await continuousManager.reset()
            speechExtractor.reset()
            localAgreement.reset()
        }
        
        print("🚀 WhisperLive: Starting processing pipeline")
        
        audioProcessingTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Create inference trigger stream
                _ = await self.continuousManager.getInferenceTriggers(audioFrames)
                
                print("🎯 WhisperLive: Inference stream created, waiting for triggers...")
                
                // The inference triggers are automatically handled by setupInferenceSubscription
                // This task just needs to keep the audio processing alive
                try await Task.sleep(nanoseconds: UInt64.max) // Keep alive indefinitely
                
            } catch is CancellationError {
                print("WhisperLive: Processing cancelled by user")
            } catch {
                print("WhisperLive: Processing error: \(error)")
                await MainActor.run {
                    self.processingError = error.localizedDescription
                }
            }
            
            await MainActor.run {
                self.isProcessing = false
                self.audioProcessingTask = nil
            }
        }
    }
    
    func stopProcessing() {
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
        isProcessing = false
        
        print("WhisperLive: Processing stopped")
    }
    
    // MARK: - Core Processing Methods
    
    private func processInferenceChunk(_ chunk: WhisperLiveAudioChunk) async {
        let startTime = Date()
        
        let bufferSeconds = Double(chunk.bufferDurationMs) / 1000.0
        print("🎯 WhisperLive: Processing inference trigger - Buffer: \(String(format: "%.1f", bufferSeconds))s")
        
        // Step 1: Pre-inference VAD - Extract speech-only audio
        var audioToTranscribe = chunk.audio
        var speechQuality: Float = 1.0
        
        if config.enablePreInferenceVAD {
            let extractionResult = speechExtractor.extractSpeechOnly(from: chunk.audio)
            
            speechQuality = extractionResult.qualityScore
            
            // Check if we have sufficient speech quality
            if speechQuality >= config.speechQualityThreshold && !extractionResult.cleanAudio.isEmpty {
                audioToTranscribe = extractionResult.cleanAudio
                let durationStr = String(format: "%.1f", extractionResult.speechDuration)
                let qualityStr = String(format: "%.2f", speechQuality)
                print("   🎤 Pre-inference VAD: \(durationStr)s speech extracted (quality: \(qualityStr))")
            } else {
                let qualityStr = String(format: "%.2f", speechQuality)
                print("   ⚠️ Pre-inference VAD: Insufficient speech quality (\(qualityStr)) - skipping transcription")
                return
            }
        }
        
        // Step 2: Create transcription segment
        let segment = TranscribableAudioSegment(
            audio: audioToTranscribe,
            startTimeMS: chunk.timestampMs,
            id: chunk.id
        )
        
        // Step 3: Trigger Whisper transcription
        totalInferences += 1
        lastInferenceTime = Date()
        
        await whisperTranscriber.transcribe(segment: segment)
        
        // Update processing time
        let processingTime = Date().timeIntervalSince(startTime) * 1000
        processingTimes.append(processingTime)
        if processingTimes.count > 20 {
            processingTimes.removeFirst()
        }
        
        let processingTimeStr = String(format: "%.1f", processingTime)
        print("   ⚡ Inference completed in \(processingTimeStr)ms")
    }
    
    private func handleTranscriptionResult(_ result: SimpleTranscriptionResult) {
        print("📝 WhisperLive: Raw transcription: \"\(result.text)\"")
        
        // Check confidence threshold
        guard result.overallConfidence >= config.confidenceThreshold else {
            let confidenceStr = String(format: "%.2f", result.overallConfidence)
            print("   ❌ Confidence too low (\(confidenceStr)) - discarding")
            return
        }
        
        // Step 3: LocalAgreement stabilization
        var finalText = result.text
        var stabilizationMethod = "raw"
        
        if config.enableLocalAgreement {
            let bufferDuration = status.bufferDuration
            let agreementResult = localAgreement.processTranscription(result, bufferDuration: bufferDuration)
            
            finalText = agreementResult.stabilizedText
            stabilizationMethod = agreementResult.stabilizationMethod
            
            print("   🔄 LocalAgreement: \"\(finalText)\" (method: \(stabilizationMethod))")
            
            if !agreementResult.newWords.isEmpty {
                let newWordsStr = agreementResult.newWords.joined(separator: " ")
                print("     ➕ New words: \(newWordsStr)")
            }
        }
        
        // Update current transcription
        currentTranscription = finalText
        
        // Update status
        updateStatus(
            confidence: result.overallConfidence,
            stabilizationMethod: stabilizationMethod
        )
        
        print("✅ WhisperLive: Final output: \"\(finalText)\"")
    }
    
    // MARK: - Status Updates
    
    private func updateStatusFromMetrics(_ metrics: WhisperLiveMetrics) {
        let avgProcessingTime = processingTimes.isEmpty ? 0.0 :
            processingTimes.reduce(0, +) / Double(processingTimes.count)
        
        status = WhisperLiveStatus(
            isProcessing: isProcessing,
            bufferDuration: Double(metrics.currentBufferDurationMs) / 1000.0,
            bufferGrowthPhase: metrics.bufferGrowthPhase,
            speechPercentage: metrics.speechPercentage,
            lastInferenceTime: lastInferenceTime,
            totalInferences: totalInferences,
            averageProcessingTime: avgProcessingTime,
            currentConfidence: status.currentConfidence,
            stabilizationMethod: status.stabilizationMethod
        )
    }
    
    private func updateStatus(confidence: Float, stabilizationMethod: String) {
        status = WhisperLiveStatus(
            isProcessing: status.isProcessing,
            bufferDuration: status.bufferDuration,
            bufferGrowthPhase: status.bufferGrowthPhase,
            speechPercentage: status.speechPercentage,
            lastInferenceTime: status.lastInferenceTime,
            totalInferences: status.totalInferences,
            averageProcessingTime: status.averageProcessingTime,
            currentConfidence: confidence,
            stabilizationMethod: stabilizationMethod
        )
    }
    
    // MARK: - Public Interface
    
    /// Get current transcription text for display
    func getCurrentTranscription() -> String {
        return currentTranscription
    }
    
    /// Get detailed status for monitoring
    func getDetailedStatus() -> String {
        var report = ""
        
        report += """
        🎯 WhisperLive Status:
        • Processing: \(status.isProcessing ? "Active" : "Stopped")
        • Buffer: \(String(format: "%.1f", status.bufferDuration))s (\(status.bufferGrowthPhase))
        • Speech: \(String(format: "%.1f", status.speechPercentage * 100))%
        • Inferences: \(status.totalInferences)
        • Avg processing: \(String(format: "%.1f", status.averageProcessingTime))ms
        • Current confidence: \(String(format: "%.2f", status.currentConfidence))
        • Stabilization: \(status.stabilizationMethod)
        
        """
        
        // Add component stats
        let speechStats = speechExtractor.getExtractionStats()
        report += """
        🎤 Speech Extraction:
        • Quality: \(speechStats.qualityScoreString)
        • Speech rate: \(speechStats.speechPercentageString)
        • Processing: \(String(format: "%.1f", speechStats.lastProcessingTimeMs))ms
        
        """
        
        let agreementStats = localAgreement.getAgreementStats()
        report += """
        🔄 LocalAgreement:
        • Agreements: \(agreementStats.totalAgreements)
        • Confidence: \(agreementStats.confidenceString)
        • Quality: \(agreementStats.qualityString)
        • Active candidates: \(agreementStats.activeCandidates)
        """
        
        return report
    }
    
    /// Check if transcription contains complete sentence
    func hasCompleteSentence() -> Bool {
        return localAgreement.hasCompleteSentence()
    }
    
    /// Reset the entire pipeline
    func reset() {
        stopProcessing()
        
        currentTranscription = ""
        processingError = nil
        totalInferences = 0
        processingTimes.removeAll()
        lastInferenceTime = nil
        
        Task {
            await continuousManager.reset()
            speechExtractor.reset()
            localAgreement.reset()
        }
        
        status = WhisperLiveStatus(
            isProcessing: false,
            bufferDuration: 0,
            bufferGrowthPhase: "Initializing",
            speechPercentage: 0,
            lastInferenceTime: nil,
            totalInferences: 0,
            averageProcessingTime: 0,
            currentConfidence: 0,
            stabilizationMethod: "none"
        )
        
        print("WhisperLiveTranscriptionManager: Reset complete")
    }
    
    // MARK: - Performance Monitoring
    
    /// Get performance metrics for analysis
    func getPerformanceMetrics() -> WhisperLivePerformanceMetrics {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        let inferenceFrequency = sessionDuration > 0 ? Float(totalInferences) / Float(sessionDuration) : 0.0
        
        let avgProcessingTime = processingTimes.isEmpty ? 0.0 :
            processingTimes.reduce(0, +) / Double(processingTimes.count)
        
        return WhisperLivePerformanceMetrics(
            sessionDuration: sessionDuration,
            totalInferences: totalInferences,
            inferenceFrequency: inferenceFrequency,
            averageProcessingTimeMs: avgProcessingTime,
            bufferDuration: status.bufferDuration,
            speechPercentage: status.speechPercentage,
            currentConfidence: status.currentConfidence,
            stabilizationMethod: status.stabilizationMethod
        )
    }
}

// MARK: - Supporting Types

struct WhisperLivePerformanceMetrics {
    let sessionDuration: TimeInterval
    let totalInferences: Int
    let inferenceFrequency: Float       // Hz (should be ~1.0)
    let averageProcessingTimeMs: Double
    let bufferDuration: TimeInterval
    let speechPercentage: Float
    let currentConfidence: Float
    let stabilizationMethod: String
    
    var sessionDurationString: String {
        return String(format: "%.0fs", sessionDuration)
    }
    
    var frequencyString: String {
        return String(format: "%.1f Hz", inferenceFrequency)
    }
    
    var processingString: String {
        return String(format: "%.1fms", averageProcessingTimeMs)
    }
}