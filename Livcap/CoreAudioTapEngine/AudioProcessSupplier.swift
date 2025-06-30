//
//  AudioProcessSupplier.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/29/25.
//

import Foundation
import AudioToolbox

@available(macOS 14.4, *)
public enum ProcessSelectionMode {
    case all
    case matching([String])
}

@available(macOS 14.4, *)
public class AudioProcessSupplier {
    
    public init() {}
    
    /// Get processes based on selection mode
    public func getProcesses(mode: ProcessSelectionMode) throws -> [AudioObjectID] {
        switch mode {
        case .all:
            return try getAllAudioProcesses()
        case .matching(let names):
            return try getProcessesByName(names)
        }
    }
    
    // MARK: - Private Process Discovery Logic
    
    /// Get all running audio processes
    private func getAllAudioProcesses() throws -> [AudioObjectID] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            throw CoreAudioTapEngineError.tapCreationFailed(status)
        }
        
        let processCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var processes = Array<AudioObjectID>(repeating: 0, count: processCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &processes
        )
        
        guard status == noErr else {
            throw CoreAudioTapEngineError.tapCreationFailed(status)
        }
        
        return processes
    }
    
    /// Get the bundle ID of a process by its AudioObjectID
    private func getProcessName(_ processID: AudioObjectID) throws -> String {
        // Get the bundle ID using the correct Core Audio property
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            processID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            return "Process_\(processID)"
        }
        
        let bundlePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        defer { bundlePointer.deallocate() }
        
        status = AudioObjectGetPropertyData(
            processID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            bundlePointer
        )
        
        guard status == noErr, let bundleString = bundlePointer.pointee else {
            return "Process_\(processID)"
        }
        
        return bundleString as String
    }
    
    // MARK: - Private Process Matching Logic
    
    /// Get processes by their names or bundle IDs
    private func getProcessesByName(_ names: [String]) throws -> [AudioObjectID] {
        let allProcesses = try getAllAudioProcesses()
        var matchingProcesses: [AudioObjectID] = []
        
        print("🔍 Searching through \(allProcesses.count) audio processes...")
        
        for processID in allProcesses {
            if let bundleID = try? getProcessName(processID) {
                print("Found process: \(bundleID)")
                
                // Check if this bundle ID matches any of our target names
                let isMatch = names.contains { targetName in
                    // Direct bundle ID matching
                    bundleID.localizedCaseInsensitiveContains(targetName) ||
                    
                    // Chrome-specific matching
                    (targetName.localizedCaseInsensitiveContains("chrome") && 
                     (bundleID.contains("com.google.Chrome") || bundleID.contains("com.google.chrome"))) ||
                    
                    // Safari matching
                    (targetName.localizedCaseInsensitiveContains("safari") && 
                     bundleID.contains("com.apple.WebKit.GPU")) ||
                    
                    // Firefox matching
                    (targetName.localizedCaseInsensitiveContains("firefox") && 
                     bundleID.contains("org.mozilla.firefox")) ||
                     
                    // Edge matching
                    (targetName.localizedCaseInsensitiveContains("edge") && 
                     bundleID.contains("com.microsoft.edgemac"))
                }
                
                if isMatch {
                    print("✅ MATCHED: \(bundleID) for target: \(names)")
                    matchingProcesses.append(processID)
                }
            }
        }
        
        print("🎯 Found \(matchingProcesses.count) matching processes")
        return matchingProcesses
    }
}