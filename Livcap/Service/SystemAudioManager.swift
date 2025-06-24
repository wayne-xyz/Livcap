//
//  SystemAudioManager.swift
//  Livcap
//
//  System audio capture using Core Audio Taps (macOS 14.4+)
//  Based on AudioCap example: https://github.com/insidegui/AudioCap
//

import Foundation
import AudioToolbox
import AVFoundation
import OSLog
import Combine
import AppKit

@available(macOS 14.4, *)
class SystemAudioManager: ObservableObject, SystemAudioProtocol {
    
    // MARK: - Published Properties
    
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var systemAudioLevel: Float = 0.0
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livcap.systemaudio", category: "SystemAudioManager")
    private let queue = DispatchQueue(label: "SystemAudioCapture", qos: .userInitiated)
    
    // Core Audio Tap components
    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapStreamDescription: AudioStreamBasicDescription?
    
    // Audio processing
    private let targetFormat: AVAudioFormat
    private var audioBufferContinuation: AsyncStream<[Float]>.Continuation?
    private var audioStream: AsyncStream<[Float]>?
    
    // Buffer accumulation to match microphone buffer size (1024 samples)
    private var accumulatedBuffer: [Float] = []
    private let targetBufferSize = 1024  // Match microphone buffer size for SFSpeechRecognizer
    private let bufferQueue = DispatchQueue(label: "SystemAudioBuffer", qos: .userInitiated)
    
    // Configuration
    private struct Config {
        static let sampleRate: Double = 16000.0  // Target sample rate
        static let channels: UInt32 = 1          // Mono output
        static let bufferSize: Int = 1600        // 100ms at 16kHz
    }
    
    // MARK: - Initialization
    
    init() {
        // Configure target audio format for speech recognition (mono, 16kHz)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Config.sampleRate,
            channels: Config.channels,
            interleaved: false
        ) else {
            fatalError("Failed to create audio format")
        }
        
        self.targetFormat = format
        
        // Log all audio-capable processes at startup
        logAllAudioCapableProcesses()
        
        logger.info("SystemAudioManager initialized for macOS 14.4+ Core Audio Taps")
    }
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Public Interface
    
    /// Start system audio capture
    func startCapture() async throws {
        guard !isCapturing else {
            logger.warning("System audio capture already running")
            return
        }
        
        logger.info("Starting system audio capture...")
        
        do {
            try await setupSystemAudioTap()
            
            await MainActor.run {
                self.isCapturing = true
                self.errorMessage = nil
            }
            
            logger.info("System audio capture started successfully")
            AudioDebugLogger.shared.logSystemAudioStatus(isEnabled: true)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            logger.error("Failed to start system audio capture: \(error.localizedDescription)")
            AudioDebugLogger.shared.logSystemAudioStatus(isEnabled: false, error: error.localizedDescription)
            throw error
        }
    }
    
    /// Stop system audio capture
    func stopCapture() {
        guard isCapturing else { return }
        
        logger.info("Stopping system audio capture...")
        
        cleanupAudioTap()
        
        Task { @MainActor in
            self.isCapturing = false
            self.systemAudioLevel = 0.0
        }
        
        logger.info("System audio capture stopped")
        AudioDebugLogger.shared.logSystemAudioStatus(isEnabled: false)
    }
    
    /// Get system audio stream for mixing
    func systemAudioStream() -> AsyncStream<[Float]> {
        if let stream = audioStream {
            return stream
        }
        
        let stream = AsyncStream<[Float]> { continuation in
            self.audioBufferContinuation = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stopCapture()
            }
        }
        
        self.audioStream = stream
        return stream
    }
    
    // MARK: - Process Discovery and Logging
    
    private func logAllAudioCapableProcesses() {
        logger.info("🔍 DISCOVERING AVAILABLE APPLICATIONS FOR AUDIO TAPPING...")
        
        // Get Core Audio discoverable processes
        let coreAudioProcesses = getCoreAudioTappableProcesses()
        
        // Get user-friendly application processes
        let userApps = getUserFriendlyApplications()
        
        logger.info("📋 CORE AUDIO TAPS - AVAILABLE APPLICATIONS:")
        logger.info("============================================================")
        
        if coreAudioProcesses.isEmpty {
            logger.info("❌ No applications with active audio output found")
            logger.info("💡 Try playing audio in Chrome, Spotify, or other media apps")
        } else {
            logger.info("✅ Found \(coreAudioProcesses.count) applications with active audio:")
            
            for (index, process) in coreAudioProcesses.enumerated() {
                let appName = getDisplayName(for: process)
                let appType = getAppCategory(for: process)
                let tapStatus = "🎯 READY TO TAP"
                
                logger.info("\(index + 1). \(appName)")
                logger.info("   PID: \(process.pid) | Type: \(appType)")
                logger.info("   Bundle: \(process.bundleIdentifier)")
                logger.info("   Status: \(tapStatus)")
                logger.info("   Object ID: \(process.objectID)")
                logger.info("   ──────────────────────────────────────────────────")
            }
        }
        
        logger.info("🎵 ALL RUNNING MEDIA APPLICATIONS:")
        logger.info("────────────────────────────────────────")
        
        if userApps.isEmpty {
            logger.info("⚪ No media applications currently running")
        } else {
            for (index, app) in userApps.enumerated() {
                let hasAudio = coreAudioProcesses.contains { $0.bundleIdentifier == app.bundleIdentifier }
                let status = hasAudio ? "🔊 HAS AUDIO" : "🔇 NO AUDIO"
                
                logger.info("\(index + 1). \(app.name)")
                logger.info("   Bundle: \(app.bundleIdentifier)")
                logger.info("   Status: \(status)")
                if hasAudio {
                    logger.info("   ✅ Available for tapping")
                } else {
                    logger.info("   ⚠️  Start playing audio to enable tapping")
                }
                logger.info("   ──────────────────────────────")
            }
        }
        
        // Show recommended actions
        logger.info("\n💡 RECOMMENDATIONS:")
        if coreAudioProcesses.isEmpty {
            logger.info("• Open Chrome and play a YouTube video")
            logger.info("• Start Spotify or Apple Music")
            logger.info("• Play audio in any media application")
        } else {
            let recommended = coreAudioProcesses.first!
            logger.info("• Currently targeting: \(self.getDisplayName(for: recommended))")
            logger.info("• To change target, modify findChromePIDs() method")
            logger.info("• \(coreAudioProcesses.count) applications available for tapping")
        }
    }
    
    // MARK: - Core Audio Discovery Methods
    
    private func getCoreAudioTappableProcesses() -> [AudioCapableProcess] {
        var tappableProcesses: [AudioCapableProcess] = []
        
        do {
            // Use our existing Core Audio discovery method from the demo
            let processObjectIDs = try AudioObjectID.system.readProcessList()
            
            for objectID in processObjectIDs {
                if let processInfo = getAudioCapableProcessInfo(for: objectID) {
                    // Only include processes that actually have audio output
                    if processInfo.hasOutput && processInfo.isRunning {
                        tappableProcesses.append(processInfo)
                    }
                }
            }
        } catch {
            logger.error("Failed to read Core Audio process list: \(error)")
        }
        
        return tappableProcesses.sorted { $0.name < $1.name }
    }
    
    private func getUserFriendlyApplications() -> [UserApplication] {
        let runningApps = NSWorkspace.shared.runningApplications
        var userApps: [UserApplication] = []
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName ?? app.bundleIdentifier?.components(separatedBy: ".").last,
                  app.activationPolicy == .regular,
                  isMediaCapableApplication(bundleId: bundleId, name: appName) else { continue }
            
            let userApp = UserApplication(
                name: appName,
                bundleIdentifier: bundleId,
                pid: app.processIdentifier
            )
            userApps.append(userApp)
        }
        
        return userApps.sorted { $0.name < $1.name }
    }
    
    private func getAudioCapableProcessInfo(for objectID: AudioObjectID) -> AudioCapableProcess? {
        do {
            let pid = try objectID.readPID()
            let name = getProcessName(for: pid)
            let bundleID = objectID.readProcessBundleID() ?? ""
            let isRunning = objectID.readProcessIsRunning()
            let hasInput = objectID.readProcessAudioStatus(kAudioProcessPropertyIsRunningInput)
            let hasOutput = objectID.readProcessAudioStatus(kAudioProcessPropertyIsRunningOutput)
            
            return AudioCapableProcess(
                objectID: objectID,
                pid: pid,
                name: name,
                bundleIdentifier: bundleID,
                isRunning: isRunning,
                hasInput: hasInput,
                hasOutput: hasOutput
            )
        } catch {
            return nil
        }
    }
    
    private func getProcessName(for pid: pid_t) -> String {
        var name = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &name, 256) > 0 {
            return String(cString: name)
        }
        return "Unknown Process (\(pid))"
    }
    
    private func getDisplayName(for process: AudioCapableProcess) -> String {
        // Try to get a user-friendly name
        if !process.bundleIdentifier.isEmpty {
            let bundleComponents = process.bundleIdentifier.components(separatedBy: ".")
            if let lastComponent = bundleComponents.last {
                switch lastComponent.lowercased() {
                case "chrome": return "Google Chrome"
                case "safari": return "Safari"
                case "firefox": return "Firefox"
                case "spotify": return "Spotify"
                case "music": return "Apple Music"
                case "vlc": return "VLC Media Player"
                case "discord": return "Discord"
                case "zoom": return "Zoom"
                case "teams": return "Microsoft Teams"
                default: break
                }
            }
        }
        
        // Fallback to process name
        return process.name
    }
    
    private func getAppCategory(for process: AudioCapableProcess) -> String {
        let bundle = process.bundleIdentifier.lowercased()
        let name = process.name.lowercased()
        
        if bundle.contains("chrome") || bundle.contains("safari") || bundle.contains("firefox") {
            return "Web Browser"
        } else if bundle.contains("spotify") || bundle.contains("music") || bundle.contains("vlc") {
            return "Media Player"
        } else if bundle.contains("discord") || bundle.contains("zoom") || bundle.contains("teams") {
            return "Communication"
        } else if name.contains("helper") {
            return "Browser Helper"
        } else {
            return "Application"
        }
    }
    
    private func isMediaCapableApplication(bundleId: String, name: String) -> Bool {
        let bundle = bundleId.lowercased()
        let appName = name.lowercased()
        
        let mediaBundles = [
            "com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
            "com.spotify.client", "com.apple.music", "org.videolan.vlc",
            "com.discord.discord", "us.zoom.xos", "com.microsoft.teams",
            "com.apple.quicktimeplayer", "com.netease.163music"
        ]
        
        let mediaKeywords = [
            "chrome", "safari", "firefox", "spotify", "music", "vlc",
            "discord", "zoom", "teams", "player", "audio", "media"
        ]
        
        return mediaBundles.contains { bundle.contains($0) } ||
               mediaKeywords.contains { appName.contains($0) || bundle.contains($0) }
    }
    
    // MARK: - Data Models
    
    struct AudioCapableProcess {
        let objectID: AudioObjectID
        let pid: pid_t
        let name: String
        let bundleIdentifier: String
        let isRunning: Bool
        let hasInput: Bool
        let hasOutput: Bool
    }
    
    struct UserApplication {
        let name: String
        let bundleIdentifier: String
        let pid: pid_t
    }
    
    // MARK: - AudioObjectID Extensions for Process Discovery
    
    private func getAudioCapableApplications() -> [ProcessInfo] {
        // Use NSWorkspace.shared.runningApplications for cleaner app discovery
        let runningApps = NSWorkspace.shared.runningApplications
        var audioCapableProcesses: [ProcessInfo] = []
        
        for app in runningApps {
            // Skip system processes and apps without proper names
            guard let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName ?? app.bundleIdentifier?.components(separatedBy: ".").last,
                  !bundleId.hasPrefix("com.apple."),
                  app.activationPolicy == .regular else { continue }
            
            // Check if it's a known audio-capable application
            if isAudioCapableApplication(appName: appName, bundleId: bundleId) {
                let processInfo = ProcessInfo(
                    pid: app.processIdentifier,
                    name: appName,
                    bundleIdentifier: bundleId,
                    executablePath: app.executableURL?.path ?? "",
                    isCurrentlyPlayingAudio: checkIfProcessIsPlayingAudio(pid: app.processIdentifier)
                )
                audioCapableProcesses.append(processInfo)
            }
        }
        
        return audioCapableProcesses
    }
    
    private func isAudioCapableApplication(appName: String, bundleId: String) -> Bool {
        let name = appName.lowercased()
        let bundle = bundleId.lowercased()
        
        // Known audio/media applications
        let audioApps = [
            // Browsers
            "chrome", "firefox", "safari", "edge", "opera", "brave",
            // Media players
            "spotify", "music", "itunes", "vlc", "quicktime", "plex", "netflix",
            // Communication
            "discord", "slack", "zoom", "teams", "skype", "facetime", "telegram",
            // Gaming
            "steam", "epic games", "unity", "unreal",
            // Audio tools
            "audacity", "garageband", "logic", "ableton", "reaper"
        ]
        
        let audioBundles = [
            "com.google.chrome", "org.mozilla.firefox", "com.apple.safari",
            "com.spotify.client", "com.apple.music", "org.videolan.vlc",
            "com.discord.discord", "com.tinyspeck.slackmacgap", "us.zoom.xos",
            "com.microsoft.teams", "com.skype.skype", "com.apple.facetime",
            "com.valvesoftware.steam", "com.epicgames.launcher"
        ]
        
        // Check name contains keywords or bundle ID matches
        return audioApps.contains { name.contains($0) } || 
               audioBundles.contains { bundle.contains($0) }
    }
    
    private func getAudioCapabilities(for process: ProcessInfo) -> String {
        var capabilities: [String] = []
        
        let name = process.name.lowercased()
        
        // Check for known audio applications
        if ["chrome", "firefox", "safari", "edge", "opera", "brave"].contains(where: { name.contains($0) }) {
            capabilities.append("Browser")
        }
        
        if ["spotify", "music", "itunes", "vlc", "quicktime"].contains(where: { name.contains($0) }) {
            capabilities.append("Media Player")
        }
        
        if ["discord", "slack", "zoom", "teams", "skype", "facetime"].contains(where: { name.contains($0) }) {
            capabilities.append("Communication")
        }
        
        if ["steam", "unity", "unreal"].contains(where: { name.contains($0) }) {
            capabilities.append("Gaming")
        }
        
        if name.contains("audio") || name.contains("sound") {
            capabilities.append("Audio System")
        }
        
        // Check if it's a GUI application (more likely to have audio)
        if !process.executablePath.contains("/usr/") && 
           !process.executablePath.contains("/System/") &&
           !name.hasPrefix("kernel") &&
           process.name.count > 2 {
            capabilities.append("GUI App")
        }
        
        return capabilities.isEmpty ? "Unknown" : capabilities.joined(separator: ", ")
    }
    
    private func getBundleIdentifier(for pid: pid_t) -> String {
        // Try to get bundle identifier using NSRunningApplication
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
            return app.bundleIdentifier ?? ""
        }
        return ""
    }
    
    private func checkIfProcessIsPlayingAudio(pid: pid_t) -> Bool {
        // Try to check if process has active audio sessions
        // This is a simplified implementation - in real AudioCap this would use Core Audio APIs
        
        // For now, we'll use some heuristics based on process name
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
            let name = (app.localizedName ?? app.bundleIdentifier ?? "").lowercased()
            
            // These apps are more likely to be playing audio if they're running
            let likelyPlayingApps = ["spotify", "music", "vlc", "quicktime", "youtube", "netflix"]
            return likelyPlayingApps.contains { name.contains($0) }
        }
        
        return false
    }
    
    // MARK: - Core Audio Tap Setup
    
    private func findChromeHelperObjectIDs() -> [AudioObjectID] {
        logger.info("🎯 TARGETING CHROME HELPER PROCESSES (com.google.Chrome.helper)...")
        
        // Method 1: Use Core Audio discovery to find Chrome Helper with active audio
        let coreAudioProcesses = getCoreAudioTappableProcesses()
        let chromeHelperProcesses = coreAudioProcesses.filter { process in
            process.bundleIdentifier.lowercased().contains("com.google.chrome.helper") ||
            process.bundleIdentifier.lowercased() == "com.google.chrome.helper"
        }
        
        if !chromeHelperProcesses.isEmpty {
            let objectIDs = chromeHelperProcesses.map { $0.objectID }
            let pids = chromeHelperProcesses.map { $0.pid }
            logger.info("✅ Found Chrome Helper processes with ACTIVE AUDIO: PIDs \(pids)")
            logger.info("🎯 Core Audio Object IDs: \(objectIDs)")
            
            for process in chromeHelperProcesses {
                logger.info("  • \(process.name) (PID: \(process.pid))")
                logger.info("    Bundle: \(process.bundleIdentifier)")
                logger.info("    Audio Status: 🔊 Output=\(process.hasOutput) Input=\(process.hasInput)")
                logger.info("    ✅ Object ID: \(process.objectID) <- USING FOR TAP")
            }
            
            return objectIDs
        }
        
        // Method 2: Fallback to NSWorkspace - convert PIDs to ObjectIDs
        logger.info("⚠️ No Chrome Helper with active audio found, trying to find Chrome Helper ObjectIDs...")
        
        let runningApps = NSWorkspace.shared.runningApplications
        var chromeHelperObjectIDs: [AudioObjectID] = []
        
        for app in runningApps {
            if let bundleId = app.bundleIdentifier,
               bundleId.lowercased().contains("com.google.chrome.helper") {
                
                // Try to find the AudioObjectID for this PID
                if let objectID = findAudioObjectIDForPID(app.processIdentifier) {
                    chromeHelperObjectIDs.append(objectID)
                    logger.info("  • Found Chrome Helper: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
                    logger.info("    Bundle: \(bundleId)")
                    logger.info("    ✅ Object ID: \(objectID)")
                } else {
                    logger.info("  • Found Chrome Helper: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
                    logger.info("    Bundle: \(bundleId)")
                    logger.info("    ❌ No corresponding AudioObjectID found")
                }
            }
        }
        
        if !chromeHelperObjectIDs.isEmpty {
            logger.info("✅ Found \(chromeHelperObjectIDs.count) Chrome Helper ObjectIDs: \(chromeHelperObjectIDs)")
            return chromeHelperObjectIDs
        }
        
        // No Chrome Helper processes found
        logger.warning("❌ NO CHROME HELPER PROCESSES FOUND")
        logger.info("💡 TROUBLESHOOTING:")
        logger.info("  • Make sure Google Chrome is running")
        logger.info("  • Play audio in Chrome (YouTube, etc.)")
        logger.info("  • Chrome Helper processes handle audio/video")
        logger.info("  • Only Chrome Helper processes with Core Audio presence can be tapped")
        logger.info("  • Try refreshing the page or starting new media in Chrome")
        
        return []
    }
    
    // Helper method to find AudioObjectID for a given PID
    private func findAudioObjectIDForPID(_ targetPID: pid_t) -> AudioObjectID? {
        do {
            let processObjectIDs = try AudioObjectID.system.readProcessList()
            
            for objectID in processObjectIDs {
                do {
                    let pid = try objectID.readPID()
                    if pid == targetPID {
                        return objectID
                    }
                } catch {
                    // Skip processes we can't read
                    continue
                }
            }
        } catch {
            logger.error("Failed to read process list for PID lookup: \(error)")
        }
        
        return nil
    }
    
    private func setupSystemAudioTap() async throws {
        // Clean up any existing tap
        cleanupAudioTap()

        // NEW: Find Chrome Helper ObjectIDs with precise bundle targeting
        let chromeHelperObjectIDs = findChromeHelperObjectIDs()
        guard !chromeHelperObjectIDs.isEmpty else {
            throw SystemAudioError.processNotFound("Google Chrome Helper (com.google.Chrome.helper)")
        }

        logger.info("🚀 TARGETING CHROME HELPER OBJECT IDs: \(chromeHelperObjectIDs)")

        // Create tap description using the actual Core Audio ObjectIDs
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: chromeHelperObjectIDs)
        tapDescription.isPrivate = true

        // Get system output device for aggregate device creation
        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()

        // Create process tap
        var tapID: AUAudioObjectID = .unknown
        let err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            throw SystemAudioError.tapCreationFailed(err)
        }

        self.processTapID = tapID
        logger.info("Created process tap: \(tapID) for Chrome Helper ObjectIDs \(chromeHelperObjectIDs)")

        // Get tap audio format
        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()

        // Create aggregate device
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Livcap-ChromeAudioTap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        // Create aggregate device
        var aggregateID = AudioObjectID.unknown
        let aggregateErr = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard aggregateErr == noErr else {
            throw SystemAudioError.aggregateDeviceCreationFailed(aggregateErr)
        }

        self.aggregateDeviceID = aggregateID
        logger.info("Created aggregate device: \(aggregateID) for Chrome Helper tap")

        // Setup audio processing callback
        try setupAudioProcessing()
    }
    
    private func setupAudioProcessing() throws {
        guard var streamDescription = tapStreamDescription else {
            throw SystemAudioError.invalidStreamDescription
        }
        
        guard let inputFormat = AVAudioFormat(streamDescription: &streamDescription) else {
            throw SystemAudioError.formatCreationFailed
        }
        
        logger.info("Input format: \(inputFormat)")
        logger.info("Target format: \(self.targetFormat)")
        
        // Create I/O proc for audio processing
        let targetFormatCapture = self.targetFormat
        var systemAudioFrameCounter = 0
        
        let ioBlock: AudioDeviceIOBlock = { [weak self, inputFormat, targetFormatCapture] _, inInputData, _, _, _ in
            guard let self = self else { return }
            
            systemAudioFrameCounter += 1
            
            // Create input buffer
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else {
                self.logger.warning("Failed to create input buffer")
                return
            }
            
            // Convert to target format if needed
            let processedBuffer = self.convertBufferFormat(inputBuffer, to: targetFormatCapture)
            
            // Extract float samples and convert stereo to mono
            let frameCount = Int(processedBuffer.frameLength)
            let channelCount = Int(processedBuffer.format.channelCount)
            
            let samples: [Float]
            if channelCount == 1 {
                // Mono audio - use directly
                guard let floatChannelData = processedBuffer.floatChannelData?[0] else {
                    self.logger.warning("No float channel data available for mono")
                    return
                }
                samples = Array(UnsafeBufferPointer(start: floatChannelData, count: frameCount))
            } else if channelCount == 2 {
                // Stereo audio - convert to mono by averaging left and right channels
                guard let leftChannel = processedBuffer.floatChannelData?[0],
                      let rightChannel = processedBuffer.floatChannelData?[1] else {
                    self.logger.warning("No float channel data available for stereo")
                    return
                }
                
                let leftSamples = Array(UnsafeBufferPointer(start: leftChannel, count: frameCount))
                let rightSamples = Array(UnsafeBufferPointer(start: rightChannel, count: frameCount))
                
                // Mix stereo to mono: (L + R) / 2
                samples = zip(leftSamples, rightSamples).map { (left, right) in
                    (left + right) / 2.0
                }
                
                self.logger.info("💻 STEREO TO MONO: Converted \(channelCount) channels to mono (\(frameCount) samples)")
            } else {
                self.logger.warning("Unsupported channel count: \(channelCount)")
                return
            }
            
            // Enhanced debug logging with colors
            AudioDebugLogger.shared.logAudioFrame(
                source: .systemAudio,
                frameIndex: systemAudioFrameCounter,
                samples: samples,
                sampleRate: targetFormatCapture.sampleRate,
                vadDecision: nil
            )
            
            // Update audio level for UI
            let rms = self.calculateRMS(samples)
            Task { @MainActor in
                self.systemAudioLevel = rms
            }
            
            // Accumulate samples until we reach target buffer size (like microphone)
            self.bufferQueue.async {
                self.accumulatedBuffer.append(contentsOf: samples)
                
                // Process accumulated buffer when we have enough samples
                while self.accumulatedBuffer.count >= self.targetBufferSize {
                    let bufferToYield = Array(self.accumulatedBuffer.prefix(self.targetBufferSize))
                    self.accumulatedBuffer.removeFirst(self.targetBufferSize)
                    
                    self.logger.info("💻 ACCUMULATED \(bufferToYield.count) samples, yielding to stream (target: \(self.targetBufferSize))")
                    
                    // Send accumulated buffer to stream
                    if let continuation = self.audioBufferContinuation {
                        continuation.yield(bufferToYield)
                        self.logger.info("💻 ✅ YIELDED \(bufferToYield.count) accumulated samples to AsyncStream")
                    } else {
                        self.logger.warning("💻 ❌ audioBufferContinuation is nil, samples not sent to stream")
                    }
                }
            }
        }
        
        // Install I/O proc
        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else {
            throw SystemAudioError.ioProcCreationFailed(err)
        }
        
        // Start audio device
        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            throw SystemAudioError.deviceStartFailed(err)
        }
        
        logger.info("Audio processing started successfully")
        print("✅ SYSTEM AUDIO TAP IS ACTIVE - Should start receiving buffer data now")
    }
    
    // MARK: - Audio Format Conversion
    
    private func convertBufferFormat(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
        // If formats match exactly, return original buffer
        if buffer.format.sampleRate == format.sampleRate && 
           buffer.format.channelCount == format.channelCount {
            return buffer
        }
        
        logger.info("🔄 Converting audio format:")
        logger.info("   From: \(buffer.format.channelCount) ch, \(buffer.format.sampleRate) Hz")
        logger.info("   To: \(format.channelCount) ch, \(format.sampleRate) Hz")
        
        // For stereo-to-mono conversion, we'll handle it manually in the extraction phase
        // Here we only handle sample rate conversion if needed, keeping original channel count
        let intermediateFormat: AVAudioFormat
        if buffer.format.sampleRate != format.sampleRate {
            // Create intermediate format with same channels but target sample rate
            guard let tempFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: buffer.format.channelCount,
                interleaved: false
            ) else {
                logger.warning("Failed to create intermediate format, using original buffer")
                return buffer
            }
            intermediateFormat = tempFormat
        } else {
            // No sample rate conversion needed, return original for channel conversion in extraction
            return buffer
        }
        
        // Create converter for sample rate conversion only
        guard let converter = AVAudioConverter(from: buffer.format, to: intermediateFormat) else {
            logger.warning("Failed to create sample rate converter, using original buffer")
            return buffer
        }
        
        // Calculate output frame capacity for sample rate conversion
        let outputFrameCapacity = AVAudioFrameCount(
            (Double(buffer.frameLength) / buffer.format.sampleRate) * intermediateFormat.sampleRate
        )
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: intermediateFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            logger.warning("Failed to create output buffer, using original buffer")
            return buffer
        }
        
        outputBuffer.frameLength = outputFrameCapacity
        
        // Perform sample rate conversion
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            logger.warning("Sample rate conversion failed: \(error.localizedDescription), using original buffer")
            return buffer
        }
        
        return outputBuffer
    }
    
    // MARK: - Cleanup
    
    private func cleanupAudioTap() {
        // Stop audio device
        if aggregateDeviceID.isValid {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr {
                logger.warning("Failed to stop aggregate device: \(err)")
            }
            
            // Destroy I/O proc
            if let deviceProcID = deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if err != noErr {
                    logger.warning("Failed to destroy device I/O proc: \(err)")
                }
                self.deviceProcID = nil
            }
            
            // Destroy aggregate device
            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err)")
            }
            aggregateDeviceID = .unknown
        }
        
        // Destroy process tap
        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                logger.warning("Failed to destroy audio tap: \(err)")
            }
            processTapID = .unknown
        }
        
        // Close audio stream
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        audioStream = nil
        
        // Clear accumulated buffer
        bufferQueue.async {
            self.accumulatedBuffer.removeAll()
            self.logger.info("💻 Cleared accumulated audio buffer")
        }
        
        logger.info("Audio tap cleanup completed")
    }
    
    // MARK: - Utilities
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
    
    private func isBrowserOrMediaApp(_ processName: String) -> Bool {
        let name = processName.lowercased()
        let keywords = [
            // Browsers
            "chrome", "firefox", "safari", "edge", "opera", "brave",
            // Media apps
            "spotify", "music", "vlc", "quicktime", "youtube", "netflix",
            "plex", "discord", "slack", "zoom", "teams", "skype",
            // Audio/Video apps
            "audio", "sound", "media", "player", "stream"
        ]
        
        return keywords.contains { name.contains($0) }
    }
    
    private func getExecutablePath(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let size = size_t(MAXPATHLEN)
        
        if proc_pidpath(pid, &buffer, UInt32(size)) > 0 {
            return String(cString: buffer)
        }
        
        return ""
    }
    
    // Helper struct to hold process information
    private struct ProcessInfo {
        let pid: pid_t
        let name: String
        let bundleIdentifier: String
        let executablePath: String
        let isCurrentlyPlayingAudio: Bool
    }
}

// MARK: - Error Types

enum SystemAudioError: Error, LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case invalidStreamDescription
    case formatCreationFailed
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case unsupportedMacOSVersion
    case processNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let status):
            return "Failed to create audio tap: \(status)"
        case .aggregateDeviceCreationFailed(let status):
            return "Failed to create aggregate device: \(status)"
        case .invalidStreamDescription:
            return "Invalid audio stream description"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .ioProcCreationFailed(let status):
            return "Failed to create I/O proc: \(status)"
        case .deviceStartFailed(let status):
            return "Failed to start audio device: \(status)"
        case .unsupportedMacOSVersion:
            return "System audio capture requires macOS 14.4 or later"
        case .processNotFound(let processName):
            return "Process not found: \(processName). Please ensure it is running."
        }
    }
}

// MARK: - AudioObjectID Extensions (from AudioCap example)

extension AudioObjectID {
    /// Convenience for `kAudioObjectSystemObject`.
    static let system = AudioObjectID(kAudioObjectSystemObject)
    /// Convenience for `kAudioObjectUnknown`.
    static let unknown = kAudioObjectUnknown

    /// `true` if this object has the value of `kAudioObjectUnknown`.
    var isUnknown: Bool { self == .unknown }

    /// `false` if this object has the value of `kAudioObjectUnknown`.
    var isValid: Bool { !isUnknown }
}

extension AudioObjectID {
    /// Reads the process list from the system audio object
    func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else { throw "Failed to get process list size: \(err)" }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var value = [AudioObjectID](repeating: .unknown, count: count)
        
        err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        guard err == noErr else { throw "Failed to read process list: \(err)" }
        
        return value
    }
    
    /// Reads the PID for a process object
    func readPID() throws -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = UInt32(MemoryLayout<pid_t>.size)
        var pid: pid_t = -1
        
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &pid)
        guard err == noErr else { throw "Failed to read PID: \(err)" }
        
        return pid
    }
    
    /// Reads the bundle ID for a process object
    func readProcessBundleID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr, dataSize > 0 else { return nil }
        
        var cfString: CFString = "" as CFString
        let err2 = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &cfString)
        guard err2 == noErr else { return nil }
        
        let result = cfString as String
        return result.isEmpty ? nil : result
    }
    
    /// Reads whether the process is currently running
    func readProcessIsRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        return err == noErr && value == 1
    }
    
    /// Reads audio status for a process (input/output)
    func readProcessAudioStatus(_ property: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: property,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        return err == noErr && value == 1
    }
    
    /// Reads the value for `kAudioHardwarePropertyDefaultSystemOutputDevice`.
    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioDeviceID.system.readDefaultSystemOutputDevice()
    }
    
    /// Reads the value for `kAudioHardwarePropertyDefaultSystemOutputDevice`, should only be called on the system object.
    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }
    
    /// Reads the value for `kAudioDevicePropertyDeviceUID` for the device represented by this audio object ID.
    func readDeviceUID() throws -> String {
        try readString(kAudioDevicePropertyDeviceUID)
    }
    
    /// Reads the value for `kAudioTapPropertyFormat` for the device represented by this audio object ID.
    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }
    
    private func requireSystemObject() throws {
        if self != .system { throw "Only supported for the system object." }
    }
    
    // Generic property access methods
    func read<T>(_ selector: AudioObjectPropertySelector,
                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                defaultValue: T) throws -> T {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: defaultValue)
    }
    
    func readString(_ selector: AudioObjectPropertySelector,
                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                   element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: "" as CFString) as String
    }
    
    private func read<T>(_ address: AudioObjectPropertyAddress, defaultValue: T) throws -> T {
        var inAddress = address
        var dataSize: UInt32 = 0
        
        var err = AudioObjectGetPropertyDataSize(self, &inAddress, 0, nil, &dataSize)
        guard err == noErr else {
            throw "Error reading data size for \(address): \(err)"
        }
        
        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &inAddress, 0, nil, &dataSize, ptr)
        }
        
        guard err == noErr else {
            throw "Error reading data for \(address): \(err)"
        }
        
        return value
    }
}

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { self }
} 