# WhisperLive-Style Overlapping Windows Implementation Plan

## Overview
This document tracks the implementation of the WhisperLive-style overlapping windows approach for real-time speech recognition in Livcap.

## Phase 1: Core Infrastructure ✅
- [x] Create implementation plan
- [x] **AudioWindow.swift** - Data structure for audio windows
- [x] **TranscriptionUpdate.swift** - Data structure for transcription updates
- [x] **OverlappingBufferManager.swift** - Manages 3s sliding windows with 1s step
- [x] **StreamingWhisperTranscriber.swift** - Handles overlapping transcription

## Phase 2: Word-Level Processing
- [ ] **WordLevelDiffing.swift** - Extracts new words from overlapping results
- [ ] **LocalAgreementPolicy.swift** - Implements LocalAgreement-2 stabilization
- [ ] **RealTimeCaptionViewModel.swift** - Coordinates real-time updates

## Phase 3: Enhanced UI
- [ ] **RealTimeCaptionView.swift** - Animated word-by-word UI
- [ ] **WordAnimationView.swift** - Individual word animations
- [ ] **RealTimeStatusView.swift** - Live status indicators

## Phase 4: Integration & Testing
- [ ] **AppRouterView.swift** - Update to use new pipeline
- [ ] **LivcapApp.swift** - Configure for overlapping windows
- [ ] **Performance testing** - Measure latency and accuracy
- [ ] **A/B testing** - Compare with segmented approach

## Phase 5: Optimization
- [ ] **Buffer optimization** - Pre-allocated buffers
- [ ] **Memory management** - Efficient audio buffer handling
- [ ] **Concurrent processing** - Parallel window processing
- [ ] **Error handling** - Robust error recovery

## Implementation Details

### WhisperLive Configuration
- **Window Size**: 3 seconds (48,000 samples at 16kHz)
- **Step Size**: 1 second (16,000 samples at 16kHz)
- **Overlap**: 2 seconds (32,000 samples)
- **Update Frequency**: Every 1 second
- **Stabilization**: LocalAgreement-2 (longest common prefix)

### Key Components
1. **OverlappingBufferManager**: Maintains sliding audio windows ✅
2. **StreamingWhisperTranscriber**: Processes overlapping segments ✅
3. **WordLevelDiffing**: Extracts new words from overlapping results
4. **LocalAgreementPolicy**: Stabilizes output using longest common prefix
5. **RealTimeCaptionViewModel**: Coordinates real-time updates
6. **RealTimeCaptionView**: Animated word-by-word display

### Success Criteria
- [ ] Latency ≤ 1.5 seconds
- [ ] Word-by-word updates
- [ ] Smooth animations
- [ ] No word duplication
- [ ] Maintains accuracy
- [ ] Handles continuous speech

## Progress Tracking
- **Phase 1**: 4/4 completed ✅
- **Phase 2**: 0/3 completed
- **Phase 3**: 0/3 completed
- **Phase 4**: 0/4 completed
- **Phase 5**: 0/4 completed

**Overall Progress**: 4/18 tasks completed (22%)

## Phase 1 Summary ✅
- ✅ Created AudioWindow data structure with WhisperLive configuration
- ✅ Created TranscriptionUpdate data structure with word-level diffing
- ✅ Implemented OverlappingBufferManager with 3s windows and 1s steps
- ✅ Implemented StreamingWhisperTranscriber with LocalAgreement-2 policy

**Next: Phase 2 - Word-Level Processing** 