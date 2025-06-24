# TODO: Window Reopen Crash Investigation & Fix Plan

## 🚨 Critical Issue: EXC_BAD_ACCESS on Window Reopen

### Issue Summary
- **Primary Problem**: Application crashes with `EXC_BAD_ACCESS (code=1, address=0x10)` when closing and reopening window
- **Secondary Issues**: 
  - ViewBridge disconnection errors
  - Title bar reappearing on reopen despite borderless configuration
  - Audio system state corruption

### Error Patterns

#### 1. EXC_BAD_ACCESS Crash
```
Thread 1: EXC_BAD_ACCESS (code=1, address=0x10)
```
- **When**: Only on window REOPEN, not initial launch
- **Location**: Audio processing pipeline (AVAudioEngine ↔ SFSpeechRecognizer)

#### 2. ViewBridge Error
```
ViewBridge to RemoteViewService Terminated: Error Domain=com.apple.ViewBridge Code=18 "(null)" 
UserInfo={
  com.apple.ViewBridge.error.hint=this process disconnected remote view controller -- benign unless unexpected,
  com.apple.ViewBridge.error.description=NSViewBridgeErrorCanceled
}
```

#### 3. Window Style Loss
- Title bar reappears on window reopen
- `.windowStyle(.hiddenTitleBar)` not persisting across WindowGroup instances

## 🔍 Root Cause Analysis

### Technical Architecture Issues

#### 1. Audio Engine State Management Problem
**Issue**: Incomplete cleanup of imperative audio objects in declarative SwiftUI lifecycle

**Details**:
- `AVAudioEngine` audio tap remains installed after window close
- `SFSpeechRecognitionTask` continues running in background
- Audio buffers have dangling references
- New window instance accesses deallocated memory from previous session

**Evidence**:
```swift
// Current cleanup in CaptionView.onDisappear:
if caption.isRecording {
    caption.toggleRecording()  // ❌ Only stops recording, doesn't clean up engine
}
```

#### 2. SwiftUI WindowGroup Lifecycle Mismatch
**Issue**: WindowGroup creates new instances on reopen, losing previous state

**Details**:
- SwiftUI expects stateless view recreation
- Audio engine requires explicit imperative cleanup
- Window styling configurations don't persist
- State management assumes clean initialization

#### 3. System Service Integration Conflict
**Issue**: Borderless window configuration confuses macOS window management

**Details**:
- ViewBridge manages system UI elements (title bars, toolbars)
- Non-standard window styling creates service coordination problems
- Remote view controller lifecycle becomes inconsistent
- System defaults override custom configurations on recreation

### Memory Corruption Chain

```
1. First Launch:
   ✅ Clean state, AVAudioEngine initializes properly
   ✅ SFSpeechRecognizer creates recognition task
   ✅ ViewBridge establishes proper connections

2. Window Close:
   ❌ CaptionView.onDisappear() calls toggleRecording()
   ❌ toggleRecording() calls stopRecording()
   ❌ stopRecording() stops audioEngine but doesn't remove taps
   ❌ Audio buffers and callbacks remain in memory
   ❌ ViewBridge connections not properly terminated

3. Window Reopen:
   ❌ New CaptionView instance created
   ❌ New CaptionViewModel tries to initialize audio
   ❌ Conflicts with existing audio tap installations
   ❌ Memory access to deallocated buffers → EXC_BAD_ACCESS
   ❌ ViewBridge conflicts between old/new connections
   ❌ Window styling reverts to system defaults
```

## 🎯 Fix Strategy & Implementation Plan

### Phase 1: Audio Engine Lifecycle Fix (High Priority)

#### 1.1 Complete Audio Cleanup Implementation
**File**: `CaptionViewModel.swift`

**Tasks**:
- [ ] Add proper `deinit()` method to CaptionViewModel
- [ ] Implement complete audio engine teardown in `stopRecording()`
- [ ] Remove all audio taps explicitly: `inputNode.removeTap(onBus: 0)`
- [ ] Cancel and nil out recognition task: `recognitionTask?.cancel(); recognitionTask = nil`
- [ ] Stop and nil audio engine: `audioEngine?.stop(); audioEngine = nil`
- [ ] Nil out recognition request: `recognitionRequest = nil`

**Implementation**:
```swift
// Add to CaptionViewModel
deinit {
    cleanupAudioResources()
}

private func cleanupAudioResources() {
    // Cancel recognition task
    recognitionTask?.cancel()
    recognitionTask = nil
    
    // Remove audio taps
    audioEngine?.inputNode.removeTap(onBus: 0)
    
    // Stop and cleanup audio engine
    audioEngine?.stop()
    audioEngine = nil
    
    // Cleanup recognition request
    recognitionRequest?.endAudio()
    recognitionRequest = nil
}
```

#### 1.2 Enhanced Window Close Handling
**File**: `CaptionView.swift`

**Tasks**:
- [ ] Enhance `onDisappear` to call complete cleanup
- [ ] Add explicit audio resource cleanup before view destruction
- [ ] Ensure cleanup happens even on forced window termination

### Phase 2: Window Management Fix (Medium Priority)

#### 2.1 Persistent Window Styling
**File**: `LivcapApp.swift`

**Tasks**:
- [ ] Research SwiftUI window state persistence
- [ ] Implement custom window management to maintain borderless state
- [ ] Consider using NSWindow directly for better control
- [ ] Add window restoration handling

#### 2.2 ViewBridge Integration Fix
**Tasks**:
- [ ] Research ViewBridge lifecycle best practices for borderless windows
- [ ] Implement proper cleanup coordination with system services
- [ ] Consider alternative borderless implementation approaches
- [ ] Test with different macOS versions for compatibility

### Phase 3: Architecture Improvement (Long-term)

#### 3.1 Audio System Abstraction
**Tasks**:
- [ ] Create dedicated AudioManager singleton
- [ ] Separate audio lifecycle from UI lifecycle
- [ ] Implement proper resource management patterns
- [ ] Add audio session state validation

#### 3.2 Window Management Service
**Tasks**:
- [ ] Create WindowManager for consistent styling
- [ ] Implement window state persistence
- [ ] Handle multi-window scenarios properly
- [ ] Coordinate with system services appropriately

## 🧪 Testing Strategy

### Test Cases

#### 1. Basic Lifecycle Tests
- [ ] Launch app → Works normally
- [ ] Close window → No background processes remain
- [ ] Reopen window → No crashes, clean state
- [ ] Repeat cycle 10+ times → Consistent behavior

#### 2. Audio System Tests
- [ ] Start recording → Audio engine initializes
- [ ] Stop recording → Complete cleanup
- [ ] Window close during recording → Graceful shutdown
- [ ] Resource monitoring → No memory leaks

#### 3. Window Management Tests
- [ ] Initial launch → Borderless window
- [ ] Close/reopen → Maintains borderless style
- [ ] Multiple reopens → Consistent appearance
- [ ] System integration → No ViewBridge errors

### Debugging Tools

#### Memory Debugging
- [ ] Enable Address Sanitizer in Xcode
- [ ] Use Instruments to monitor audio object lifecycle
- [ ] Track memory allocation/deallocation patterns
- [ ] Monitor for retain cycles

#### Audio Debugging
- [ ] Add comprehensive logging in audio callbacks
- [ ] Monitor AVAudioEngine state transitions
- [ ] Track SFSpeechRecognizer task lifecycle
- [ ] Validate buffer management

## 📝 Investigation Notes

### Current State Analysis

#### Working Components ✅
- Initial app launch and basic functionality
- Speech recognition when working properly
- UI layout and styling (when not corrupted)
- Basic audio processing pipeline

#### Broken Components ❌
- Window close/reopen lifecycle
- Audio resource management
- ViewBridge system service integration
- Window styling persistence
- Memory management between sessions

### Technical Debt

#### Immediate Issues
- Missing deinit in CaptionViewModel
- Incomplete audio cleanup in stopRecording()
- No explicit resource management patterns
- SwiftUI lifecycle assumptions about stateless recreation

#### Architectural Issues
- Mixing imperative audio APIs with declarative UI
- No separation between audio engine and UI lifecycle
- Direct integration with system services without proper coordination
- State management scattered across multiple components

## 🔧 Implementation Priority

### Critical (Fix First)
1. **Audio Engine Cleanup** - Prevents crashes
2. **Memory Management** - Prevents corruption
3. **Resource Lifecycle** - Ensures clean state

### Important (Fix Soon)
1. **Window Styling Persistence** - User experience
2. **ViewBridge Integration** - System compatibility
3. **Error Handling** - Graceful degradation

### Nice to Have (Future)
1. **Architecture Refactoring** - Long-term maintainability
2. **Audio System Abstraction** - Better separation of concerns
3. **Advanced Window Management** - Enhanced features

## 📚 Research References

### Apple Documentation
- [AVAudioEngine Lifecycle Management](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [SFSpeechRecognizer Best Practices](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [SwiftUI Window Management](https://developer.apple.com/documentation/swiftui/windowgroup)
- [macOS Window Services](https://developer.apple.com/documentation/appkit/nswindow)

### Community Solutions
- Stack Overflow: "AVAudioEngine cleanup best practices"
- Swift Forums: "SwiftUI window lifecycle management"
- GitHub Issues: Similar crash patterns in audio apps

## 🎯 Success Criteria

### Functional Requirements
- [ ] App launches without errors
- [ ] Window can be closed and reopened indefinitely without crashes
- [ ] Title bar remains hidden across all window sessions
- [ ] Audio recording works consistently across reopens
- [ ] No memory leaks or resource accumulation

### Technical Requirements
- [ ] Clean audio engine teardown on window close
- [ ] Proper ViewBridge service coordination
- [ ] Consistent window styling persistence
- [ ] No EXC_BAD_ACCESS errors in any scenario
- [ ] No ViewBridge disconnection warnings

### Performance Requirements
- [ ] Fast window reopen (< 500ms)
- [ ] Low memory footprint after multiple open/close cycles
- [ ] No background processes after window close
- [ ] Efficient audio resource usage

---

**Last Updated**: 2024-06-24  
**Priority**: Critical  
**Estimated Effort**: 2-3 days for Phase 1, 1 week for complete fix  
**Risk Level**: High (affects core functionality)