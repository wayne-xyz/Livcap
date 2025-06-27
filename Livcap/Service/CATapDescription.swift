//
//  CATapDescription.swift
//  Livcap
//
//  Core Audio Taps description helper class
//  Based on AudioCap example: https://github.com/insidegui/AudioCap
//

import Foundation
import AudioToolbox
import OSLog

// MARK: - ProcessTapMuteBehavior Enum

enum ProcessTapMuteBehavior: UInt32 {
    case muted = 0
    case unmuted = 1
}

// MARK: - ProcessTapDescription Class

@available(macOS 14.4, *)
class ProcessTapDescription: NSObject {
    
    // MARK: - Properties
    
    var uuid: UUID = UUID()
    var isPrivate: Bool = false
    var muteBehavior: ProcessTapMuteBehavior = .unmuted
    var processObjectIDs: [AudioObjectID] = []
    
    private let logger = Logger(subsystem: "com.livcap.catap", category: "CATapDescription")
    
    // MARK: - Initialization
    
    /// Create a tap description for stereo mixdown of specific processes
    /// - Parameter processObjectIDs: Array of AudioObjectID representing processes to tap
    init(stereoMixdownOfProcesses processObjectIDs: [AudioObjectID]) {
        super.init()
        self.processObjectIDs = processObjectIDs
        self.uuid = UUID()
        self.isPrivate = true
        self.muteBehavior = .unmuted
        
        logger.info("Created ProcessTapDescription for processes: \(processObjectIDs)")
    }
    
    /// Create a tap description for a single process
    /// - Parameter processObjectID: AudioObjectID of the process to tap
    convenience init(processObjectID: AudioObjectID) {
        self.init(stereoMixdownOfProcesses: [processObjectID])
    }
    
    // MARK: - Core Audio Integration
    
    /// Get the CFDictionary representation for Core Audio APIs
    var coreAudioDictionary: CFDictionary {
        let description: [String: Any] = [
            String.kAudioTapPropertyProcessObjectList: processObjectIDs,
            String.kAudioTapPropertyUUID: uuid.uuidString,
            String.kAudioTapPropertyIsPrivate: isPrivate,
            String.kAudioTapPropertyMuteBehavior: muteBehavior.rawValue
        ]
        
        return description as CFDictionary
    }
    
    // MARK: - Helper Methods
    
    /// Add a process to be tapped
    /// - Parameter processObjectID: AudioObjectID of the process to add
    func addProcess(_ processObjectID: AudioObjectID) {
        guard !processObjectIDs.contains(processObjectID) else {
            logger.warning("Process \(processObjectID) already in tap description")
            return
        }
        
        processObjectIDs.append(processObjectID)
        logger.info("Added process \(processObjectID) to tap description")
    }
    
    /// Remove a process from being tapped
    /// - Parameter processObjectID: AudioObjectID of the process to remove
    func removeProcess(_ processObjectID: AudioObjectID) {
        processObjectIDs.removeAll { $0 == processObjectID }
        logger.info("Removed process \(processObjectID) from tap description")
    }
    
    /// Clear all processes
    func clearProcesses() {
        processObjectIDs.removeAll()
        logger.info("Cleared all processes from tap description")
    }
    
    // MARK: - Debug Information
    
    override var debugDescription: String {
        return """
        ProcessTapDescription {
            UUID: \(uuid.uuidString)
            Private: \(isPrivate)
            Mute Behavior: \(muteBehavior)
            Process Count: \(processObjectIDs.count)
            Processes: \(processObjectIDs)
        }
        """
    }
}

// MARK: - Core Audio Tap Constants

extension String {
    /// Core Audio Tap property keys (these should match Apple's private constants)
    static let kAudioTapPropertyProcessObjectList = "proc"
    static let kAudioTapPropertyUUID = "uuid"
    static let kAudioTapPropertyIsPrivate = "priv" 
    static let kAudioTapPropertyMuteBehavior = "mute"
}

// MARK: - AudioHardwareCreateProcessTap Bridge

@available(macOS 14.4, *)
extension ProcessTapDescription {
    
    /// Get tap information for debugging
    func getTapInfo() -> String {
        return "ProcessTapDescription with \(processObjectIDs.count) processes: \(processObjectIDs)"
    }
}

// MARK: - Convenience Extensions

@available(macOS 14.4, *)
extension ProcessTapDescription {
    
    /// Create a tap description for Chrome processes
    /// - Returns: ProcessTapDescription configured for Chrome audio capture
    static func forChrome() -> ProcessTapDescription? {
        let chromePIDs = findChromePIDs()
        guard !chromePIDs.isEmpty else { return nil }
        
        let chromeObjectIDs = chromePIDs.map { AudioObjectID($0) }
        let description = ProcessTapDescription(stereoMixdownOfProcesses: chromeObjectIDs)
        description.isPrivate = true
        description.muteBehavior = .unmuted
        
        return description
    }
    
    /// Create a tap description for system-wide audio capture
    /// - Returns: ProcessTapDescription configured for all audio output
    static func forSystemWide() -> ProcessTapDescription {
        // This would use system-wide capture if supported
        let description = ProcessTapDescription(stereoMixdownOfProcesses: [])
        description.isPrivate = false
        description.muteBehavior = .unmuted
        
        return description
    }
    
    // Helper function to find Chrome PIDs
    private static func findChromePIDs() -> [pid_t] {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "Google Chrome"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let output = String(data: data, encoding: .utf8) ?? ""
                return output.split(separator: "\n").compactMap { pid_t(String($0)) }
            }
        } catch {
            print("Failed to find Chrome PIDs: \(error)")
        }
        
        return []
    }
}
