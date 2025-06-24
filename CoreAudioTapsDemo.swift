#!/usr/bin/env swift

import Foundation
import AudioToolbox

print("\n🎵 CORE AUDIO TAPS - PROCESS DISCOVERY DEMO")
print(String(repeating: "=", count: 50))
print("This demo discovers all available audio processes that can be tapped")
print("for system audio capture using Core Audio Taps API (macOS 14.4+)")

// MARK: - AudioObjectID Extensions

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown
    
    var isValid: Bool { self != .unknown }
    
    func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else { throw CoreAudioError.dataSize(err) }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var value = [AudioObjectID](repeating: .unknown, count: count)
        
        err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        guard err == noErr else { throw CoreAudioError.readData(err) }
        
        return value
    }
    
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
    
    func readPID() throws -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = UInt32(MemoryLayout<pid_t>.size)
        var pid: pid_t = -1
        
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &pid)
        guard err == noErr else { throw CoreAudioError.readPID(err) }
        
        return pid
    }
    
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
}

// MARK: - Error Types

enum CoreAudioError: Error {
    case dataSize(OSStatus)
    case readData(OSStatus)
    case readPID(OSStatus)
}

// MARK: - Process Info Model

struct ProcessInfo {
    let objectID: AudioObjectID
    let pid: pid_t
    let name: String
    let bundleID: String?
    let isRunning: Bool
    let hasInput: Bool
    let hasOutput: Bool
    
    var displayName: String {
        if let bundleID = bundleID, !bundleID.isEmpty {
            return "\(name) (\(bundleID))"
        }
        return name
    }
}

// MARK: - Demo Functions

func getProcessName(for pid: pid_t) -> String {
    var name = [CChar](repeating: 0, count: 256)
    if proc_name(pid, &name, 256) > 0 {
        return String(cString: name)
    }
    return "Unknown Process (\(pid))"
}

func getProcessInfo(for objectID: AudioObjectID) -> ProcessInfo? {
    do {
        let pid = try objectID.readPID()
        let name = getProcessName(for: pid)
        let bundleID = objectID.readProcessBundleID()
        let isRunning = objectID.readProcessIsRunning()
        let hasInput = objectID.readProcessAudioStatus(kAudioProcessPropertyIsRunningInput)
        let hasOutput = objectID.readProcessAudioStatus(kAudioProcessPropertyIsRunningOutput)
        
        return ProcessInfo(
            objectID: objectID,
            pid: pid,
            name: name,
            bundleID: bundleID,
            isRunning: isRunning,
            hasInput: hasInput,
            hasOutput: hasOutput
        )
    } catch {
        return nil
    }
}

func runDemo() {
    do {
        print("\n🔍 Discovering audio processes...")
        
        // Get all audio process objects
        let processObjectIDs = try AudioObjectID.system.readProcessList()
        print("📋 Found \(processObjectIDs.count) audio process objects")
        
        var discoveredProcesses: [ProcessInfo] = []
        
        for objectID in processObjectIDs {
            if let processInfo = getProcessInfo(for: objectID) {
                discoveredProcesses.append(processInfo)
            }
        }
        
        // Sort by name for easier reading
        discoveredProcesses.sort { $0.name < $1.name }
        
        // Display statistics
        let runningProcesses = discoveredProcesses.filter { $0.isRunning }
        let outputProcesses = discoveredProcesses.filter { $0.hasOutput }
        let inputProcesses = discoveredProcesses.filter { $0.hasInput }
        
        print("\n📊 SUMMARY:")
        print("  Total processes: \(discoveredProcesses.count)")
        print("  🟢 Running: \(runningProcesses.count)")
        print("  🔊 With audio output: \(outputProcesses.count)")
        print("  🎤 With audio input: \(inputProcesses.count)")
        
        // Show processes with audio output (suitable for tapping)
        print("\n🔊 PROCESSES WITH AUDIO OUTPUT (Suitable for tapping):")
        print(String(repeating: "-", count: 60))
        
        if outputProcesses.isEmpty {
            print("❌ No processes with audio output found")
        } else {
            for process in outputProcesses {
                let status = process.isRunning ? "🟢" : "🔴"
                let audio = [
                    process.hasInput ? "🎤" : "",
                    process.hasOutput ? "🔊" : ""
                ].filter { !$0.isEmpty }.joined(separator: " ")
                
                print("\(status) \(process.name) \(audio)")
                print("   PID: \(process.pid)")
                if let bundleID = process.bundleID {
                    print("   Bundle: \(bundleID)")
                }
                print("   Object ID: \(process.objectID)")
                print("")
            }
        }
        
        // Show notable applications
        print("🎯 NOTABLE APPLICATIONS:")
        print(String(repeating: "-", count: 30))
        
        let interestingBundles = [
            "com.apple.Music": "Apple Music",
            "com.spotify.client": "Spotify",
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Chrome",
            "com.apple.QuickTimePlayerX": "QuickTime Player",
            "com.apple.FaceTime": "FaceTime",
            "com.discord.Discord": "Discord",
            "com.microsoft.teams": "Microsoft Teams",
            "org.videolan.vlc": "VLC",
            "com.apple.iTunes": "iTunes"
        ]
        
        for (bundleID, displayName) in interestingBundles {
            if let process = discoveredProcesses.first(where: { $0.bundleID == bundleID }) {
                let status = process.isRunning ? "🟢" : "🔴"
                let tapable = process.hasOutput ? "✅ Can tap" : "❌ No output"
                print("\(status) \(displayName): \(tapable)")
                if process.hasOutput {
                    print("   └─ PID: \(process.pid), Object ID: \(process.objectID)")
                }
            }
        }
        
        // Show system info
        print("\n💡 CORE AUDIO TAPS INFO:")
        print(String(repeating: "-", count: 30))
        print("• Core Audio Taps API is available on macOS 14.4+")
        print("• Processes with 🔊 output can be tapped for audio capture")
        print("• Requires appropriate permissions and entitlements")
        print("• Multiple processes can be tapped simultaneously")
        print("• Useful for capturing audio from specific applications")
        
        if #available(macOS 14.4, *) {
            print("✅ Your macOS version supports Core Audio Taps")
        } else {
            print("❌ Core Audio Taps requires macOS 14.4 or later")
        }
        
        // Show example usage
        if !outputProcesses.isEmpty {
            print("\n💻 EXAMPLE USAGE:")
            print(String(repeating: "-", count: 20))
            let example = outputProcesses.first!
            print("To tap audio from \(example.name):")
            print("```swift")
            print("let tapDescription = CATapDescription(stereoMixdownOfProcesses: [\(example.objectID)])")
            print("var tapID: AudioObjectID = .unknown")
            print("let err = AudioHardwareCreateProcessTap(tapDescription, &tapID)")
            print("```")
        }
        
    } catch {
        print("❌ Failed to discover audio processes: \(error)")
    }
}

// Run the demo
runDemo()