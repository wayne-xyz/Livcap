//
//  WhisperLiveFrameManager.swift
//  Livcap
//
//  Frame-based WhisperLive implementation
//  - Processes 100ms frames with VAD marking
//  - Per-second inference decisions
//  - Speech extraction before Whisper
//  - Real-time status updates
//

import Foundation
import Combine

struct WhisperLiveFrameConfig {
    let sampleRate: Int = 16000                    // 16kHz audio
    let frameSize: Int = 1600                      // 100ms at 16kHz
    let inferenceInterval: TimeInterval = 1.0      // Check every second
    let confidenceThreshold: Float = 0.3           // Minimum confidence for results
    let minSpeechDuration: TimeInterval = 0.5      // Minimum speech for inference
}

struct InferenceResult: Identifiable {
    let id = UUID()
    let secondIndex: Int
    let speechDuration: TimeInterval
    let transcriptionText: String
    let confidence: Float
    let timestamp: Date
    let processingTimeMs: Double
    let bufferDurationAtInference: TimeInterval
    let voiceFrameCount: Int
    
    var timestampString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var speechDurationString: String {
        return String(format: "%.1fs", speechDuration)
    }
    
    var bufferDurationString: String {
        return String(format: "%.1fs", bufferDurationAtInference)
    }
    
    var processingTimeString: String {
        return String(format: "%.0fms", processingTimeMs)
    }
    
    var confidenceString: String {
        return String(format: "%.2f", confidence)
    }
}

class WhisperLiveFrameManager: ObservableObject {
    
    // MARK: - Configuration
    
    private let config = WhisperLiveFrameConfig()
    
    // MARK: - Published Properties
    
    @Published private(set) var frameBuffer = WhisperLiveFrameBuffer()
    @Published private(set) var currentTranscription: String = ""
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastInferenceResult: InferenceResult?
    @Published private(set) var inferenceHistory: [InferenceResult] = []
    @Published private(set) var processingError: String?
    @Published private(set) var sessionStartTime: Date = Date()
    
    // MARK: - Core Components
    
    private let whisperTranscriber: WhisperCppTranscriber
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - State Management
    
    private var audioProcessingTask: Task<Void, Error>?
    private var inferenceTimer: Timer?
    private var totalInferences: Int = 0
    private var inferenceStartTimes: [UUID: Date] = [:]  // Track processing times
    
    // MARK: - Initialization
    
    init() {
        self.whisperTranscriber = WhisperCppTranscriber()
        setupSubscriptions()
        
        print("WhisperLiveFrameManager: Initialized")
        print("- Frame size: \(config.frameSize) samples (100ms)")
        print("- Inference interval: \(config.inferenceInterval)s")
        print("- Min speech duration: \(config.minSpeechDuration)s")
    }
    
    // MARK: - Subscription Setup
    
    private func setupSubscriptions() {
        // Listen for transcription results
        whisperTranscriber.transcriptionPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .finished:
                        print("WhisperLiveFrame: Transcription publisher finished")
                    case .failure(let error):
                        print("WhisperLiveFrame: Transcription error: \(error)")
                        self?.processingError = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] result in
                    self?.handleTranscriptionResult(result)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Main Processing Pipeline
    
    func startProcessing<S: AsyncSequence>(_ audioFrames: S) where S.Element == [Float] {
        guard audioProcessingTask == nil else {
            print("WhisperLiveFrame: Already processing")
            return
        }
        
        isProcessing = true
        processingError = nil
        sessionStartTime = Date()
        totalInferences = 0
        
        // Reset frame buffer
        frameBuffer.reset()
        
        // Start inference timer
        startInferenceTimer()
        
        print("🚀 WhisperLiveFrame: Starting frame-based processing")
        
        audioProcessingTask = Task {
            do {
                for try await audioFrame in audioFrames {
                    // Validate frame size
                    guard audioFrame.count == config.frameSize else {
                        print("⚠️ Frame size mismatch: expected \(config.frameSize), got \(audioFrame.count)")
                        continue
                    }
                    
                    // Add frame to buffer (with VAD processing)
                    await MainActor.run {
                        frameBuffer.addFrame(audioFrame)
                    }
                    
                    try Task.checkCancellation()
                }
                
                print("WhisperLiveFrame: Audio stream finished")
                
            } catch is CancellationError {
                print("WhisperLiveFrame: Processing cancelled")
            } catch {
                print("WhisperLiveFrame: Processing error: \(error)")
                await MainActor.run {
                    self.processingError = error.localizedDescription
                }
            }
            
            await MainActor.run {
                self.isProcessing = false
                self.audioProcessingTask = nil
                self.stopInferenceTimer()
            }
        }
    }
    
    func stopProcessing() {
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
        stopInferenceTimer()
        isProcessing = false
        
        print("WhisperLiveFrame: Processing stopped")
    }
    
    // MARK: - Inference Management
    
    private func startInferenceTimer() {
        inferenceTimer = Timer.scheduledTimer(withTimeInterval: config.inferenceInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.checkAndTriggerInference()
            }
        }
    }
    
    private func stopInferenceTimer() {
        inferenceTimer?.invalidate()
        inferenceTimer = nil
    }
    
    private func checkAndTriggerInference() async {
        await MainActor.run {
            guard frameBuffer.shouldTriggerInference() else {
                return
            }
            
            // Extract speech-only audio
            let speechAudio = frameBuffer.extractSpeechForInference()
            
            // Check minimum speech duration
            let speechDuration = Double(speechAudio.count) / Double(config.sampleRate)
            guard speechDuration >= config.minSpeechDuration else {
                print("⚠️ Speech too short: \(String(format: "%.1f", speechDuration))s < \(config.minSpeechDuration)s")
                return
            }
            
            // Trigger inference
            triggerInference(speechAudio: speechAudio, speechDuration: speechDuration)
        }
    }
    
    private func triggerInference(speechAudio: [Float], speechDuration: TimeInterval) {
        let stats = frameBuffer.getBufferStats()
        let secondIndex = stats.currentSecondIndex
        let inferenceStartTime = Date()
        
        print("🎯 Inference trigger: Second \(secondIndex), Speech: \(String(format: "%.1f", speechDuration))s")
        
        // Create transcription segment
        let segment = TranscribableAudioSegment(
            audio: speechAudio,
            startTimeMS: Int(Date().timeIntervalSince(sessionStartTime) * 1000),
            id: UUID()
        )
        
        totalInferences += 1
        
        // Store inference start time for processing time calculation
        inferenceStartTimes[segment.id] = inferenceStartTime
        
        // Send to Whisper
        Task {
            await whisperTranscriber.transcribe(segment: segment)
        }
    }
    
    private func handleTranscriptionResult(_ result: SimpleTranscriptionResult) {
        print("📝 WhisperLiveFrame: Raw transcription: \"\(result.text)\"")
        
        // Calculate processing time
        let processingTimeMs: Double
        if let startTime = inferenceStartTimes[result.segmentID] {
            processingTimeMs = Date().timeIntervalSince(startTime) * 1000
            inferenceStartTimes.removeValue(forKey: result.segmentID)
        } else {
            processingTimeMs = 0
        }
        
        // Check confidence threshold
        guard result.overallConfidence >= config.confidenceThreshold else {
            let confidenceStr = String(format: "%.2f", result.overallConfidence)
            print("   ❌ Confidence too low (\(confidenceStr)) - discarding")
            return
        }
        
        // Update current transcription
        let cleanText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanText.isEmpty {
            currentTranscription = cleanText
            
            // Create inference result for tracking
            let stats = frameBuffer.getBufferStats()
            
            // Calculate speech duration from segments or estimate
            let speechDuration: TimeInterval
            if !result.segments.isEmpty {
                speechDuration = Double(result.segments.reduce(0) { total, segment in
                    total + Int(segment.endTime - segment.startTime)
                }) / 1000.0  // Convert ms to seconds
            } else {
                speechDuration = Double(cleanText.split(separator: " ").count) * 0.3  // Rough estimate
            }
            
            // Count voice frames in current buffer
            let voiceFrameCount = frameBuffer.frames.filter { $0.isVoice }.count
            
            let inferenceResult = InferenceResult(
                secondIndex: stats.currentSecondIndex,
                speechDuration: speechDuration,
                transcriptionText: cleanText,
                confidence: result.overallConfidence,
                timestamp: Date(),
                processingTimeMs: processingTimeMs,
                bufferDurationAtInference: stats.bufferDurationSeconds,
                voiceFrameCount: voiceFrameCount
            )
            
            lastInferenceResult = inferenceResult
            inferenceHistory.append(inferenceResult)
            
            // Keep only last 50 inference results for performance
            if inferenceHistory.count > 50 {
                inferenceHistory.removeFirst()
            }
            
            let confidenceStr = String(format: "%.2f", result.overallConfidence)
            let processingStr = String(format: "%.0f", processingTimeMs)
            print("✅ WhisperLiveFrame: \"\(cleanText)\" (confidence: \(confidenceStr), processing: \(processingStr)ms)")
        }
    }
    
    // MARK: - Public Interface
    
    /// Get current transcription text for display
    func getCurrentTranscription() -> String {
        return currentTranscription
    }
    
    /// Get recent seconds for UI visualization
    func getRecentSeconds() -> [SecondSummary] {
        return frameBuffer.getRecentSeconds()
    }
    
    /// Get buffer statistics
    func getBufferStats() -> FrameBufferStats {
        return frameBuffer.getBufferStats()
    }
    
    /// Reset the entire pipeline
    func reset() {
        stopProcessing()
        
        currentTranscription = ""
        processingError = nil
        totalInferences = 0
        lastInferenceResult = nil
        inferenceHistory.removeAll()
        
        frameBuffer.reset()
        
        print("WhisperLiveFrameManager: Reset complete")
    }
    
    /// Get detailed status for debugging
    func getDetailedStatus() -> String {
        let stats = frameBuffer.getBufferStats()
        let recentSeconds = getRecentSeconds()
        
        var report = """
        🎯 WhisperLive Frame Status:
        • Processing: \(isProcessing ? "Active" : "Stopped")
        • Buffer: \(stats.durationString) (\(stats.totalFrames) frames)
        • Voice: \(stats.voicePercentageString)
        • Silent seconds: \(stats.consecutiveSilentSeconds)/3
        • Total inferences: \(totalInferences)
        
        """
        
        if let lastResult = lastInferenceResult {
            let confidenceStr = String(format: "%.2f", lastResult.confidence)
            report += """
            🎤 Last Inference:
            • Second: \(lastResult.secondIndex)
            • Text: "\(lastResult.transcriptionText)"
            • Confidence: \(confidenceStr)
            
            """
        }
        
        report += "📊 Recent Seconds: "
        for summary in recentSeconds.suffix(5) {
            let status = summary.hasVoice ? "🟢" : "🔴"
            report += "\(status)"
        }
        
        return report
    }
}