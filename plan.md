# System Audio Capture Implementation Plan

## Overview
This plan outlines the integration of macOS system audio capture using Core Audio Taps (available in macOS 14.4+) into the existing Livcap application. The implementation will allow capturing all system audio and combining it with microphone audio for real-time speech recognition.

## Current State Analysis

### Existing Components
1. **CaptionViewModel** - Handles microphone input via SFSpeechRecognizer with AVAudioEngine
2. **AudioManager** - Manages microphone audio processing and 16kHz format conversion  
3. **VADProcessor/EnhancedVAD** - Voice Activity Detection for speech segmentation
4. **BufferManager** - Manages audio buffering and segmentation for transcription
5. **Permission System** - Already includes `NSAudioCaptureUsageDescription` in Info.plist

### Current Audio Pipeline
```
Microphone → AVAudioEngine → 16kHz conversion → VAD → SFSpeechRecognizer
```

## Implementation Plan

### Phase 1: Core Audio Tap Infrastructure

#### 1.1 Create System Audio Manager
**File**: `Livcap/Service/SystemAudioManager.swift`

**Purpose**: Manage Core Audio Tap setup and system audio capture
- Process discovery and tap creation  
- Aggregate device management
- Audio format handling and conversion
- Permission checking via TCC framework (optional with build flag)

**Key Components**:
- Process enumeration for system-wide capture
- AudioObjectID translation from PIDs
- CATapDescription configuration
- Aggregate device creation with tap integration
- Audio stream format management (convert to 16kHz mono)

#### 1.2 Audio Mixing Service  
**File**: `Livcap/Service/AudioMixingService.swift`

**Purpose**: Combine microphone and system audio streams
- Real-time audio mixing and synchronization
- Volume level management for each source
- Format standardization (16kHz mono Float32)
- Configurable mixing ratios

**Mixing Strategies**:
1. **Simple Addition**: `mixed = mic + system` (with optional gain control)
2. **Weighted Mixing**: `mixed = (mic * micGain) + (system * systemGain)`  
3. **Adaptive Mixing**: Dynamic adjustment based on signal levels

#### 1.3 Permission Management Extension
**File**: `Livcap/Service/SystemAudioPermissionManager.swift`

**Purpose**: Handle system audio capture permissions
- TCC framework integration (with build flag support)
- Permission status checking and requesting
- Fallback to runtime permission requests
- User guidance for manual permission setup

### Phase 2: UI Integration

#### 2.1 System Audio Toggle Button
**Modify**: `Livcap/Views/CaptionView.swift`

**Changes**:
- Add system audio toggle button left of microphone button
- Update button layout in both `compactLayout` and `expandedLayout`
- Add visual indicators for system audio state
- Implement hover states and animations

**Button Design**:
- Icon: `speaker.wave.2` (active) / `speaker.slash` (inactive)
- Position: Left of microphone button with consistent spacing
- State indication: Color and icon changes matching mic button style

#### 2.2 Audio Source Indicators
**New Component**: Visual indicators showing active audio sources
- Microphone activity indicator
- System audio activity indicator  
- Combined audio level visualization (optional)

### Phase 3: Audio Pipeline Integration

#### 3.1 Enhanced CaptionViewModel
**Modify**: `Livcap/ViewModels/CaptionViewModel.swift`

**New Features**:
- System audio capture toggle state management
- Integration with SystemAudioManager
- Combined audio stream handling
- Dual-source audio processing coordination

**Key Changes**:
```swift
@Published private(set) var isSystemAudioEnabled = false
private var systemAudioManager: SystemAudioManager?
private var audioMixingService: AudioMixingService?

func toggleSystemAudio() {
    if isSystemAudioEnabled {
        stopSystemAudio()
    } else {
        startSystemAudio()
    }
}
```

#### 3.2 Audio Stream Coordination
**Strategy**: Modify existing audio pipeline to handle multiple sources

**Current Pipeline**:
```
Microphone → SFSpeechRecognizer
```

**New Pipeline**:
```
Microphone ↘
              AudioMixer → SFSpeechRecognizer  
System Audio ↗
```

**Implementation**: 
- Maintain existing microphone-only functionality
- Add system audio as optional additional source
- Use AudioMixingService to combine streams before sending to SFSpeechRecognizer
- Preserve all existing VAD and buffering logic

### Phase 4: Core Audio Tap Implementation

#### 4.1 System-Wide Audio Capture
**Approach**: Capture all system audio processes instead of individual apps

**Implementation Steps**:
1. Enumerate all audio processes using `kAudioHardwarePropertyProcessObjectList`
2. Create taps for system output device to capture mixed system audio
3. Configure aggregate device with system output + all process taps
4. Handle audio format conversion and synchronization

**Key Code Structure** (based on AudioCap examples):
```swift
// Process discovery
let processes = try AudioObjectID.readProcessList()

// System output capture  
let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()

// Aggregate device with system audio tap
let description: [String: Any] = [
    kAudioAggregateDeviceNameKey: "Livcap-SystemCapture",
    kAudioAggregateDeviceMainSubDeviceKey: outputUID,
    kAudioAggregateDeviceTapListKey: [/* tap configurations */]
]
```

#### 4.2 Audio Format Consistency
**Requirement**: Convert all audio sources to consistent 16kHz mono Float32 format

**Implementation**:
- Use existing `convertBuffer(_:to:)` method from AudioManager
- Apply format conversion to system audio before mixing
- Maintain sample rate synchronization between sources

### Phase 5: Testing and Validation

#### 5.1 Permission Testing
- Test permission flow with and without TCC framework
- Validate fallback behavior for permission denials
- Test permission persistence across app launches

#### 5.2 Audio Quality Testing  
- Test various mixing ratios and volume levels
- Validate audio synchronization between sources
- Test system audio capture from different apps (music, video, etc.)
- Ensure speech recognition accuracy with mixed audio

#### 5.3 Performance Testing
- Monitor CPU usage with dual audio capture
- Test buffer management under continuous operation
- Validate memory usage and potential leaks
- Test stability during extended capture sessions

### Phase 6: Error Handling and Edge Cases

#### 6.1 Device State Management
- Handle audio device changes (headphone connect/disconnect)
- Manage system audio routing changes
- Handle process termination and restart scenarios

#### 6.2 Graceful Degradation
- Fallback to microphone-only mode if system audio fails
- Maintain app functionality when permissions are denied
- Handle Core Audio Tap API availability (macOS 14.4+ requirement)

## Implementation Priority

### High Priority (Core Functionality)
1. SystemAudioManager creation
2. Basic system audio capture
3. AudioMixingService implementation  
4. UI toggle button integration
5. Permission management

### Medium Priority (Polish)
1. Advanced mixing options
2. Audio level indicators
3. Performance optimizations
4. Error handling improvements

### Low Priority (Future Enhancements)
1. Per-app audio capture selection
2. Audio source isolation controls
3. Advanced audio processing options

## Technical Considerations

### macOS Version Requirements
- Core Audio Taps require macOS 14.4+
- Implement version checking and graceful fallback
- Display appropriate error messages for unsupported systems

### Performance Impact
- System audio capture adds computational overhead
- Monitor and optimize buffer management
- Consider implementing quality/performance trade-offs

### Privacy and Security
- System audio capture requires explicit user permission
- Clearly communicate audio source usage to users
- Respect user privacy settings and permissions

## Success Criteria

1. **Functional**: System audio toggle works reliably
2. **Quality**: Mixed audio maintains speech recognition accuracy  
3. **Performance**: No significant impact on app responsiveness
4. **UX**: Intuitive interface consistent with existing design
5. **Stability**: Robust error handling and edge case management

## Testing Validation Plan

### Unit Tests
- Audio format conversion accuracy
- Mixing algorithm correctness  
- Permission state management

### Integration Tests
- End-to-end audio capture and recognition
- UI state synchronization
- Error recovery scenarios

### User Acceptance Tests
- Real-world usage scenarios
- Mixed audio source recognition accuracy
- System compatibility across different macOS versions 