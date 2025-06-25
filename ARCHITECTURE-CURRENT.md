# LIVCAP CURRENT ARCHITECTURE DOCUMENTATION

*Last Updated: December 2024*

## 📋 **PROJECT OVERVIEW**

**Livcap** is a macOS real-time live captioning application that captures audio from microphone and system audio sources, performs speech recognition using Apple's Speech framework, and displays live transcriptions with intelligent VAD-based processing.

---

## 🏗️ **COMPONENT ARCHITECTURE OVERVIEW**

```
┌─────────────────────────────────────────────────────────────────┐
│                            UI LAYER                             │
├─────────────────┬─────────────────┬─────────────────────────────┤
│   AppRouterView │   CaptionView   │   PermissionView            │
│                 │                 │   WindowControlButtons      │
└─────────────────┴─────────────────┴─────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      VIEW MODEL LAYER                           │
├─────────────────┬─────────────────────────────────────────────┤
│ CaptionViewModel│           PermissionManager                  │
│  (Conductor)    │           (Singleton)                       │
└─────────────────┴─────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SERVICE LAYER                              │
├──────────────────┬──────────────────┬─────────────────────────┤
│  AudioCoordinator│  SpeechProcessor │      Helper.swift       │
│   (178 lines)    │   (86 lines)     │      (27 lines)        │
├──────────────────┼──────────────────┼─────────────────────────┤
│ MicAudioManager  │SystemAudioManager│   VADProcessor          │
│   (275 lines)    │  (1400+ lines)   │   (101 lines)          │
├──────────────────┼──────────────────┼─────────────────────────┤
│SpeechRecognition │SystemAudioProtocol│   CATapDescription     │
│Manager (300+ ln) │   (9 lines)      │   (186 lines)          │
└──────────────────┴──────────────────┴─────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      MODEL LAYER                                │
├─────────────────────────────────────────────────────────────────┤
│  CaptionEntry  │  AudioFrameWithVAD  │  AudioVADResult        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 **DETAILED COMPONENT ANALYSIS**

### **1. UI LAYER COMPONENTS**

#### **AppRouterView.swift** (133 lines)
- **Technology**: SwiftUI + AppKit integration
- **Role**: Main application router with permission-based navigation
- **Key Responsibilities**: 
  - Permission status-based view routing (PermissionView ↔ CaptionView)
  - Window positioning and configuration (bottom-center, above Dock)
  - Floating window setup with custom styling (borderless, rounded corners)
  - Multi-screen support (focused screen detection)
- **Communication**: 
  - **Input**: Observes `PermissionManager.shared` via `@StateObject`
  - **Output**: Window configuration via direct NSWindow manipulation

#### **CaptionView.swift** (289 lines)
- **Technology**: SwiftUI with adaptive layouts
- **Role**: Primary live caption display interface
- **Key Responsibilities**: 
  - Real-time caption rendering with auto-scroll (ScrollViewReader)
  - Adaptive UI layouts (compact ≤100px vs expanded layouts)
  - Audio source toggle controls (microphone + system audio)
  - Window control integration with hover effects
- **Communication**: 
  - **Input**: Observes `@StateObject CaptionViewModel`
  - **Output**: User actions → CaptionViewModel methods

#### **PermissionView.swift** (58 lines)
- **Technology**: SwiftUI
- **Role**: Microphone permission request interface
- **Communication**: 
  - **Input**: Observes `PermissionManager.shared`
  - **Output**: Permission requests → PermissionManager

#### **WindowControlButtons.swift** (174 lines)
- **Technology**: SwiftUI + AppKit integration
- **Role**: Custom macOS window controls for borderless windows
- **Communication**: Direct NSWindow manipulation via AppKit APIs

---

### **2. VIEW MODEL LAYER COMPONENTS**

#### **CaptionViewModel.swift** (150 lines) - **MAIN CONDUCTOR**
- **Technology**: ObservableObject + Combine
- **Role**: Central coordinator between UI and audio services
- **Architecture Pattern**: Hub-and-spoke coordinator
- **Key Properties**:
  ```swift
  @Published private(set) var isRecording = false
  @Published private(set) var isMicrophoneEnabled: Bool = false
  @Published private(set) var isSystemAudioEnabled: Bool = false
  ```
- **Communication Patterns**: 
  - **Input**: AudioCoordinator state via `assign(to:on:)` bindings
  - **Output**: SpeechProcessor coordination via dependency injection
  - **Stream Management**: Task-based AsyncStream consumption

#### **PermissionManager.swift** (90 lines) - **SINGLETON**
- **Technology**: AVFoundation + ObservableObject
- **Role**: Microphone permission management
- **Communication**: Singleton pattern with `@Published` properties

---

### **3. SERVICE LAYER COMPONENTS**

#### **AudioCoordinator.swift** (178 lines) - **FACADE PATTERN**
- **Technology**: Combine + AsyncStream + macOS version detection
- **Role**: Master audio source coordinator
- **Key Components**:
  ```swift
  private let micAudioManager = MicAudioManager()
  private var systemAudioManager: SystemAudioProtocol?
  private var audioMixingService: AudioMixingService? // Currently unused
  ```
- **Communication**: 
  - **Downstream**: Direct instantiation and management of audio managers
  - **Upstream**: AsyncStream<AudioFrameWithVAD> publication

#### **SpeechProcessor.swift** (86 lines) - **ORCHESTRATOR**
- **Technology**: Combine + Delegate Pattern
- **Role**: Speech processing orchestrator and VAD coordinator
- **Communication Patterns**: 
  - **Input**: AudioFrameWithVAD from CaptionViewModel
  - **Output**: Delegate-based speech results + ObservableObject changes

#### **SpeechRecognitionManager.swift** (300+ lines) - **CORE ENGINE**
- **Technology**: Speech Framework + AVFoundation
- **Role**: Apple Speech framework integration
- **Key Components**:
  ```swift
  private let speechRecognizer: SFSpeechRecognizer?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  ```
- **Communication**: 
  - **Input**: Audio buffers via `appendAudioBufferWithVAD()`
  - **Output**: Delegate callbacks to SpeechProcessor

#### **MicAudioManager.swift** (275 lines) - **AUDIO SOURCE**
- **Technology**: AVFoundation (AVAudioEngine) + Accelerate (vDSP)
- **Audio Processing Pipeline**:
  ```
  Microphone → AVAudioEngine (48kHz) → Format Conversion (16kHz) → VAD Processing → AsyncStream
  ```
- **Communication**: AsyncStream<AudioFrameWithVAD> publication

#### **SystemAudioManager.swift** (1400+ lines) - **PLATFORM INTEGRATION**
- **Technology**: Core Audio + AudioToolbox (Core Audio Taps)
- **Platform Requirement**: macOS 14.4+ (private Core Audio APIs)
- **Communication**: AsyncStream<AudioFrameWithVAD> publication

#### **VADProcessor.swift** (101 lines) - **SIGNAL PROCESSING**
- **Technology**: Accelerate framework (vDSP) + state machine
- **Algorithm**: Energy-based VAD with consecutive frame state machine
- **Communication**: Synchronous processing returning AudioVADResult objects

---

## 🔄 **COMMUNICATION PATTERNS & CONNECTORS**

### **Pattern 1: AsyncStream Audio Flow** (Primary Data Path)
```
MicAudioManager ────┐
                    ├─→ AudioCoordinator.audioFrameStream() ─→ CaptionViewModel ─→ SpeechProcessor
SystemAudioManager ─┘
```
- **Connector Technology**: `AsyncStream<AudioFrameWithVAD>`
- **Benefits**: Non-blocking streaming, automatic backpressure handling

### **Pattern 2: Published State Synchronization** (UI Updates)
```
AudioCoordinator.@Published ─→ CaptionViewModel.@Published ─→ SwiftUI View Updates
```
- **Connector Technology**: Combine `@Published` with `assign(to:on:)` bindings
- **Benefits**: Automatic UI updates, declarative reactive bindings

### **Pattern 3: Delegate-Based Results** (Speech Recognition)
```
SpeechRecognitionManager ─→ SpeechRecognitionManagerDelegate ─→ SpeechProcessor ─→ ObservableObject
```
- **Connector Technology**: Swift protocol delegation
- **Benefits**: Type-safe callbacks, clear ownership semantics

### **Pattern 4: Dependency Injection** (Architecture)
```
CaptionViewModel(audioCoordinator: AudioCoordinator, speechProcessor: SpeechProcessor)
```
- **Connector Technology**: Constructor injection with default parameters
- **Benefits**: Testability, loose coupling, mockable components

---

## 💻 **TECHNOLOGY STACK BREAKDOWN**

### **Core Apple Frameworks**
- **SwiftUI**: Declarative UI with adaptive layouts and automatic updates
- **Combine**: Reactive programming for state management and data binding
- **Speech Framework**: `SFSpeechRecognizer` for real-time transcription
- **AVFoundation**: `AVAudioEngine` for microphone capture and audio processing
- **Core Audio**: Low-level audio taps for system audio capture (macOS 14.4+)
- **Accelerate**: `vDSP` framework for optimized signal processing (VAD)

### **Swift Language Features**
- **Swift Concurrency**: AsyncStream, Task, async/await for modern concurrent programming
- **ObservableObject**: Automatic UI updates via `@Published` properties
- **Sendable**: Thread-safe data structures for concurrent processing
- **Protocols**: Type-safe abstractions (SystemAudioProtocol)

### **Platform-Specific Integration**
- **AppKit**: Window management for custom borderless windows
- **macOS Audio System**: Core Audio Taps for system-wide audio capture
- **Privacy Framework**: Permission management for microphone access

### **Architecture Patterns Implemented**
- **MVVM**: Clear separation between View, ViewModel, and Model layers
- **Coordinator Pattern**: AudioCoordinator orchestrates complex audio subsystem
- **Observer Pattern**: `@Published` properties enable reactive UI updates
- **Facade Pattern**: AudioCoordinator simplifies complex multi-source audio management
- **Strategy Pattern**: Protocol-based SystemAudioManager for platform abstraction

---

## 🚨 **ARCHITECTURAL CHALLENGES & RECOMMENDATIONS**

### **Challenge 1: Mixed Communication Paradigms**
- **Current State**: AsyncStream + @Published + Delegate patterns coexist
- **Problem**: Cognitive overhead for developers, inconsistent error propagation
- **Recommendation**: Standardize on AsyncStream for all async operations

### **Challenge 2: CaptionViewModel Over-Coordination**
- **Current State**: Hub-and-spoke pattern with manual data forwarding
- **Problem**: CaptionViewModel becomes a bottleneck, tight coupling
- **Recommendation**: Transform to observer-only pattern, eliminate manual forwarding

### **Challenge 3: Boolean Flag State Management**
```swift
@Published private(set) var isMicrophoneEnabled: Bool = false
@Published private(set) var isSystemAudioEnabled: Bool = false
@Published private(set) var isRecording: Bool = false
```
- **Current State**: Multiple boolean flags with implicit dependencies
- **Problem**: Possible invalid state combinations (recording=true, sources=false)
- **Recommendation**: Explicit state machine with enum-based states

---

## 📈 **TOP 3 PRIORITY NEXT STEPS**

### **🥇 Priority 1: State Machine Refactoring**
**Objective**: Replace boolean flags with explicit state machine

**Implementation**:
```swift
enum AudioCaptureState: Equatable, Sendable {
    case idle
    case recording(sources: Set<AudioSource>)
    case error(AudioCaptureError)
    
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
    
    var enabledSources: Set<AudioSource> {
        if case .recording(let sources) = self { return sources }
        return []
    }
}
```

**Benefits**: 
- **Eliminates impossible state combinations**
- **Clearer state transition logic**
- **Easier testing and debugging**

**Estimated Effort**: 4-6 hours
**Risk Level**: Low (internal refactoring with computed property compatibility)
**Files to Modify**: CaptionViewModel.swift, AudioCoordinator.swift

### **🥈 Priority 2: Communication Pattern Unification**
**Objective**: Migrate delegate pattern to AsyncStream for consistency

**Implementation**:
```swift
enum SpeechEvent: Sendable {
    case transcriptionUpdate(String, isPartial: Bool)
    case sentenceFinalized(String)
    case stateChange(isSpeaking: Bool)
    case error(SpeechRecognitionError)
}

func speechEvents() -> AsyncStream<SpeechEvent> { ... }
```

**Benefits**:
- **Single communication paradigm** throughout application
- **Better error propagation** with structured error types
- **Simplified testing** with event stream mocking

**Estimated Effort**: 6-8 hours
**Risk Level**: Medium (breaking changes across SpeechProcessor integration)
**Files to Modify**: SpeechRecognitionManager.swift, SpeechProcessor.swift

### **🥉 Priority 3: Performance Buffer Optimization**
**Objective**: Eliminate unnecessary audio buffer conversions

**Current Inefficiency**:
```swift
// Current: AVAudioPCMBuffer → [Float] → VAD processing
let samples = Array(UnsafeBufferPointer(...))
vadProcessor.processAudioChunk(samples)
```

**Optimized Implementation**:
```swift
// Optimized: AVAudioPCMBuffer → Direct VAD processing
func processAudioBuffer(_ buffer: AVAudioPCMBuffer) -> AudioVADResult {
    // Direct vDSP processing on buffer memory - no array allocation
    var rms: Float = 0.0
    vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
    return AudioVADResult(isSpeech: rms > threshold, confidence: min(1.0, rms / threshold), rmsEnergy: rms)
}
```

**Benefits**:
- **Reduced memory allocations**
- **Lower CPU overhead** 
- **Better real-time performance**

**Estimated Effort**: 3-4 hours
**Risk Level**: Low (performance improvement without API changes)
**Files to Modify**: VADProcessor.swift, MicAudioManager.swift, SystemAudioManager.swift

---

## 📊 **ARCHITECTURE METRICS & SUCCESS INDICATORS**

### **Current Codebase Statistics**
- **Total Service Layer**: ~2,200 lines of code
- **Core Service Components**: 8 main service classes
- **Communication Patterns**: 3 different paradigms (AsyncStream, Combine, Delegate)
- **Platform Dependencies**: macOS 14.4+ for system audio, macOS 13+ for base functionality

### **Architecture Quality Metrics**
- ✅ **Modularity**: High (clear service class separation)
- ✅ **Performance**: High (efficient audio processing with VAD optimization)
- ✅ **Platform Integration**: Excellent (deep macOS audio system integration)
- ⚠️ **Consistency**: Medium (mixed communication patterns)
- ✅ **Testability**: Medium-High (dependency injection, some mocking capabilities)
- ✅ **Maintainability**: High (good documentation, clear component boundaries)
- ⚠️ **State Management**: Medium (boolean flags create complexity)

### **Success Criteria for Improvements**
- **Single Communication Pattern**: 100% AsyncStream adoption (eliminate delegates)
- **State Machine**: Zero invalid state combinations possible
- **Performance**: <50% reduction in memory allocations for audio processing
- **Component Independence**: CaptionViewModel <150 lines (currently at limit)

---

## 🔮 **FUTURE ARCHITECTURAL EVOLUTION**

### **Short-term (Next 2-3 weeks)**
- Complete Priority 1-3 refactoring
- Enhanced error handling with structured types
- Comprehensive unit test coverage for state machine

### **Medium-term (1-2 months)**
- Multi-language speech recognition support
- Advanced audio source mixing capabilities
- Real-time audio filtering and enhancement

### **Long-term (3-6 months)**
- iOS companion app with shared speech processing
- Cloud synchronization for caption history
- AI-powered transcription enhancement and correction

---

*Architecture Documentation maintained by: Claude Sonnet*
*Last Updated: December 2024*
*Next Review: After Priority 1-3 completion*
