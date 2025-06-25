# CaptionViewModel Redesign Implementation Plan

## 🎯 **Overview**

This document outlines a comprehensive redesign plan for `CaptionViewModel.swift` to address critical bugs, implement state machine patterns, and align with the project's architectural goals outlined in CLAUDE.md.

## 🚨 **Critical Issues to Fix**

### **Issue 1: Inverted Recording Logic (CRITICAL BUG)**
**Location**: Line 84 in `CaptionViewModel.swift`
```swift
// CURRENT (BROKEN):
let shouldBeRecording = !audioCoordinator.isMicrophoneEnabled && !audioCoordinator.isSystemAudioEnabled

// SHOULD BE:
let shouldBeRecording = audioCoordinator.isMicrophoneEnabled || audioCoordinator.isSystemAudioEnabled
```
**Impact**: App doesn't record when audio sources are enabled
**Priority**: IMMEDIATE FIX REQUIRED

### **Issue 2: State Management Complexity**
- Multiple boolean flags create invalid state combinations
- Manual state synchronization via Combine
- No enforcement of single-source audio (mutual exclusivity)

### **Issue 3: Hub-and-Spoke Over-Coordination**
- CaptionViewModel acts as central hub for everything
- Tight coupling between UI and services
- Complex dependency management
- Testing difficulties

---

## 📋 **Implementation Plan**

### **Phase 1: Critical Bug Fix (30 minutes)**

#### **Step 1.1: Fix Recording Logic**
```swift
// In manageRecordingState() method
private func manageRecordingState() {
    // FIX: Correct the inverted logic
    let shouldBeRecording = audioCoordinator.isMicrophoneEnabled || audioCoordinator.isSystemAudioEnabled
    
    if shouldBeRecording && !isRecording {
        startRecording()
    } else if !shouldBeRecording && isRecording {
        stopRecording()
    }
}
```

#### **Step 1.2: Test the Fix**
- Verify microphone toggle starts recording
- Verify system audio toggle starts recording
- Verify disabling both sources stops recording
- Test source switching behavior

---

### **Phase 2: State Machine Implementation (2-3 hours)**

#### **Step 2.1: Define State Machine**
Create new enum above the CaptionViewModel class:

```swift
// MARK: - Caption State Machine

enum CaptionState: Equatable, Sendable {
    case idle
    case recordingMicrophone
    case recordingSystemAudio
    case error(String)
    
    var isRecording: Bool {
        switch self {
        case .recordingMicrophone, .recordingSystemAudio:
            return true
        case .idle, .error:
            return false
        }
    }
    
    var activeSource: AudioSource? {
        switch self {
        case .recordingMicrophone:
            return .microphone
        case .recordingSystemAudio:
            return .systemAudio
        case .idle, .error:
            return nil
        }
    }
    
    var statusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recordingMicrophone:
            return "Recording Microphone"
        case .recordingSystemAudio:
            return "Recording System Audio"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var displayStatusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recordingMicrophone:
            return "MIC:ON"
        case .recordingSystemAudio:
            return "SYS:ON"
        case .error(let message):
            return "ERROR: \(message)"
        }
    }
}
```

#### **Step 2.2: Replace Published Properties**
```swift
// REPLACE THESE:
@Published private(set) var isRecording = false
@Published var statusText: String = "Ready to record"
@Published private(set) var isMicrophoneEnabled: Bool = false
@Published private(set) var isSystemAudioEnabled: Bool = false

// WITH THIS:
@Published private(set) var state: CaptionState = .idle

// COMPUTED PROPERTIES:
var isRecording: Bool { state.isRecording }
var statusText: String { state.statusText }
var activeSource: AudioSource? { state.activeSource }
```

#### **Step 2.3: Update State Observation**
```swift
private func observeAudioCoordinatorState() {
    audioCoordinator.$isMicrophoneEnabled
        .combineLatest(audioCoordinator.$isSystemAudioEnabled)
        .receive(on: DispatchQueue.main)
        .map { [weak self] (micEnabled, systemEnabled) -> CaptionState in
            guard let self = self else { return .idle }
            
            switch (micEnabled, systemEnabled) {
            case (true, false):
                return .recordingMicrophone
            case (false, true):
                return .recordingSystemAudio
            case (false, false):
                return .idle
            case (true, true):
                // Should never happen with mutual exclusivity in AudioCoordinator
                self.logger.error("Invalid state: Both audio sources enabled simultaneously")
                return .error("Multiple audio sources active")
            }
        }
        .assign(to: \.state, on: self)
        .store(in: &cancellables)
}
```

#### **Step 2.4: Simplify manageRecordingState()**
```swift
private func manageRecordingState() {
    // State is now managed reactively by observeAudioCoordinatorState()
    // This method can be simplified or removed entirely
    switch state {
    case .recordingMicrophone, .recordingSystemAudio:
        if !isRecording {
            startRecording()
        }
    case .idle, .error:
        if isRecording {
            stopRecording()
        }
    }
}
```

---

### **Phase 3: Communication Pattern Unification (2-3 hours)**

#### **Step 3.1: Replace Delegate-Style ObjectWillChange**
```swift
// REMOVE THIS COMPLEX BINDING:
speechProcessor.objectWillChange
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.objectWillChange.send()
    }
    .store(in: &cancellables)

// REPLACE WITH DIRECT STREAM CONSUMPTION:
private func observeSpeechEvents() {
    speechEventsTask = Task { @MainActor in
        let speechEvents = speechProcessor.speechRecognitionManager.speechEvents()
        
        for await event in speechEvents {
            switch event {
            case .transcriptionUpdate(_):
                self.objectWillChange.send()
                
            case .sentenceFinalized(_):
                self.objectWillChange.send()
                
            case .error(let error):
                self.state = .error(error.localizedDescription)
                
            case .statusChanged(let status):
                self.logger.info("Speech status: \(status)")
            }
        }
    }
}
```

#### **Step 3.2: Unified Stream Management**
```swift
private var speechEventsTask: Task<Void, Never>?

// Add to init():
observeAudioCoordinatorState()
observeSpeechEvents()

// Add to deinit:
deinit {
    audioStreamTask?.cancel()
    speechEventsTask?.cancel()
}
```

---

### **Phase 4: Error Handling & Resource Management (1 hour)**

#### **Step 4.1: Async Function Signatures**
```swift
// UPDATE PUBLIC INTERFACE:
func toggleMicrophone() async {
    audioCoordinator.toggleMicrophone()
    // State management now handled reactively
}

func toggleSystemAudio() async {
    audioCoordinator.toggleSystemAudio()
    // State management now handled reactively
}
```

#### **Step 4.2: Proper Error Handling**
```swift
private func startRecording() async {
    guard !state.isRecording else { return }
    logger.info("🔴 STARTING RECORDING SESSION")
    
    do {
        // Start the speech processor with proper error handling
        speechProcessor.startProcessing()
        
        // Start consuming the audio stream
        audioStreamTask = Task {
            let stream = audioCoordinator.audioFrameStream()
            for await frame in stream {
                guard self.state.isRecording else { break }
                speechProcessor.processAudioFrame(frame)
            }
        }
        
    } catch {
        await MainActor.run {
            self.state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }
}
```

#### **Step 4.3: Clean Resource Management**
```swift
private func stopRecording() async {
    guard state.isRecording else { return }
    logger.info("🛑 STOPPING RECORDING SESSION")
    
    // Terminate the audio stream task
    audioStreamTask?.cancel()
    audioStreamTask = nil
    
    // Stop the speech processor
    speechProcessor.stopProcessing()
    
    logger.info("✅ Recording session stopped")
}
```

---

### **Phase 5: Testing & Validation (1-2 hours)**

#### **Step 5.1: Create Test Cases**
```swift
// Test file: CaptionViewModelTests.swift

class CaptionViewModelTests: XCTestCase {
    func testStateTransitions() {
        // Test idle -> recording microphone
        // Test idle -> recording system audio
        // Test recording -> idle
        // Test error states
    }
    
    func testMutualExclusivity() {
        // Test that only one source can be active
        // Test proper state when switching sources
    }
    
    func testRecordingLogic() {
        // Test that recording starts when source is enabled
        // Test that recording stops when all sources disabled
    }
}
```

#### **Step 5.2: Manual Testing Checklist**
- [ ] Microphone toggle starts recording
- [ ] System audio toggle starts recording  
- [ ] Disabling both sources stops recording
- [ ] Switching between sources works correctly
- [ ] Status text updates properly
- [ ] Error states display correctly
- [ ] Caption history persists correctly
- [ ] Clear captions function works

---

## 📁 **File Structure After Changes**

```
Livcap/
├── ViewModels/
│   └── CaptionViewModel.swift (redesigned)
├── Models/
│   └── CaptionEntry.swift (no changes needed)
├── Service/
│   ├── AudioCoordinator.swift (no changes needed)
│   ├── SpeechProcessor.swift (no changes needed) 
│   └── SpeechRecognitionManager.swift (no changes needed)
└── Tests/
    └── CaptionViewModelTests.swift (new)
```

---

## 🎯 **Success Criteria**

### **Functional Requirements**
- [ ] Recording starts when any audio source is enabled
- [ ] Recording stops when all audio sources are disabled
- [ ] Only one audio source can be active at a time
- [ ] Status text accurately reflects current state
- [ ] Error states are properly handled and displayed
- [ ] Caption history is preserved during source switches

### **Technical Requirements**
- [ ] Single state machine replaces multiple boolean flags
- [ ] AsyncStream communication pattern throughout
- [ ] Proper resource management and cancellation
- [ ] Error handling with user-friendly messages
- [ ] Comprehensive unit test coverage

### **Code Quality**
- [ ] No force unwrapping or unsafe code
- [ ] Proper use of @MainActor for UI updates
- [ ] Clear separation of concerns
- [ ] Consistent logging and debugging info

---

## 🔄 **Migration Strategy**

### **Backwards Compatibility**
During development, maintain existing public interface:
```swift
// Keep these computed properties for UI compatibility
var isRecording: Bool { state.isRecording }
var statusText: String { state.statusText }
var isMicrophoneEnabled: Bool { state.activeSource == .microphone }
var isSystemAudioEnabled: Bool { state.activeSource == .systemAudio }
```

### **Rollback Plan**
If issues arise:
1. Revert to git commit before changes
2. Apply only the critical bug fix (Phase 1)
3. Plan incremental approach for state machine

---

## 📊 **Estimated Timeline**

| Phase | Description | Time Estimate | Priority |
|-------|-------------|---------------|----------|
| 1 | Critical Bug Fix | 30 minutes | CRITICAL |
| 2 | State Machine Implementation | 2-3 hours | HIGH |
| 3 | Communication Unification | 2-3 hours | MEDIUM |
| 4 | Error Handling & Resource Mgmt | 1 hour | MEDIUM |
| 5 | Testing & Validation | 1-2 hours | HIGH |

**Total Estimated Time: 6.5-9.5 hours**

---

## ⚠️ **Important Notes**

1. **Start with Phase 1** - The critical bug fix should be implemented immediately
2. **Test thoroughly** after each phase before proceeding
3. **Commit frequently** to allow easy rollback if needed
4. **Update CLAUDE.md** after completion to reflect state machine implementation
5. **Consider this as Priority 1** completion from the original architectural plan

---

## 🎉 **Expected Benefits**

After completion, the CaptionViewModel will:
- ✅ Have correct recording logic (no more inverted behavior)
- ✅ Use type-safe state machine (eliminates invalid states)
- ✅ Follow consistent AsyncStream communication pattern
- ✅ Have simplified, testable architecture
- ✅ Provide better error handling and user feedback
- ✅ Align with project architectural goals from CLAUDE.md

This redesign addresses **Challenge 2** (Boolean State Management) and **Challenge 3** (Over-Coordination) from the architectural improvement plan, bringing the CaptionViewModel in line with modern Swift concurrency patterns and the project's overall architecture.