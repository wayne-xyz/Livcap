# Livcap

Inspired by whisper-live using the overlap strategy. 

## Highlights:
- Privacy first, local model, no cloud, no analytics, no ads. No need internet connection. Free and open source. 
- Light weight and fast. One click to on/off.
- No annoying user analytics. If you think something can be improved, email me.
- Less is more. 



# Development Introduction



## Current Implementation: Three Real-Time Transcription Approaches

This project implements and evaluates three different strategies for real-time speech transcription using Whisper models. Each approach has been implemented and tested with different trade-offs between latency, accuracy, and context management.

### Approach 1: VAD-Based Silence Detection (Currently Most Reliable)

**Core Files:**
- `Service/BufferManager.swift` - Main VAD-based segmentation logic
- `Service/VADProcessor.swift` - Basic RMS-based voice activity detection
- `Service/EnhancedVAD.swift` - Advanced VAD with hysteresis and confidence scoring

**How it works:**
- Accumulates speech audio until silence is detected (3 consecutive silence frames)
- Triggers inference when speech segment ends or reaches 15-second maximum
- Uses RMS energy threshold (0.01) for voice/silence classification
- Implements asymmetric hysteresis: immediate speech detection, delayed silence confirmation

**Key Characteristics:**
- **Trigger**: Event-driven based on silence detection
- **Buffer**: Variable size (speech segments only)
- **Latency**: Variable (depends on speech patterns)
- **Context**: Speech-only segments

**Current Status:** ✅ **Most reliable approach** - Provides good quality transcriptions with reasonable latency for most use cases.

**Limitations:** 
- Variable latency due to silence dependency
- May cut off words at segment boundaries
- Requires careful VAD tuning for different environments

### Approach 2: 5-Second Fixed Sliding Windows (Word-Level Chaos)

**Core Files:**
- `Service/ContinuousStreamManager.swift` - 5-second sliding window implementation
- `Service/TranscriptionStabilizationManager.swift` - Overlap analysis and word-level matching
- `ViewModels/Phase2ContinuousViewModel.swift` - Integration and VAD enhancement

**How it works:**
- Maintains 5-second sliding window with 1-second stride
- Creates 4-second overlap between consecutive windows
- Uses LocalAgreement algorithm for word-level stabilization
- Implements temporal overlap analysis for conflict resolution

**Key Characteristics:**
- **Trigger**: Fixed 1-second intervals
- **Buffer**: 5-second sliding window with 4-second overlap
- **Stabilization**: Word-level matching across overlapping windows

**Current Status:** ❌ **Word-level chaos** - The overlap analysis creates confusion at word boundaries, leading to inconsistent transcriptions and poor user experience.

**Limitations:**
- Complex word-level matching creates transcription instability
- Overlap conflicts cause frequent text changes
- Difficult to achieve smooth, readable output

### Approach 3: 30-Second WhisperLive-Inspired Buffer (High Latency)

**Core Files:**
- `Service/WhisperLiveContinuousManager.swift` - 30-second continuous buffer manager
- `Service/WhisperLiveAudioBuffer.swift` - Incremental buffer growth and smart trimming
- `Service/WhisperLiveFrameBuffer.swift` - Frame-based 30-second buffer with VAD marking
- `Service/WhisperLiveTranscriptionManager.swift` - Complete pipeline integration
- `Service/SpeechSegmentExtractor.swift` - Pre-inference VAD processing

**How it works:**
- Maintains continuous 30-second audio buffer
- Triggers inference every 1 second regardless of content
- Grows buffer from 0 to 30 seconds, then smart trimming
- Uses pre-inference VAD to extract speech-only segments

**Key Characteristics:**
- **Trigger**: Fixed 1-second intervals
- **Buffer**: 30-second continuous context
- **Strategy**: Maximum Whisper context with predictable timing

**Current Status:** ❌ **High latency** - 30-second buffer requires >2 seconds for inference, making it unsuitable for real-time applications.

**Limitations:**
- Excessive latency (>2s) for real-time use
- High computational overhead
- Memory intensive with large buffer
- Not suitable for live captioning scenarios

## Current Conclusions

After extensive testing of all three approaches:

1. **Approach 1 (VAD-Based)** is currently the most practical solution, providing the best balance of quality and usability despite variable latency.

2. **Approach 2 (5s Sliding)** suffers from word-level chaos due to complex overlap analysis, making transcriptions unstable and hard to read.

3. **Approach 3 (30s WhisperLive)** provides excellent context but has unacceptable latency (>2s) for real-time applications.

## Comparison Chart

| Aspect | Approach 1: VAD-Based | Approach 2: 5s Sliding | Approach 3: 30s WhisperLive |
|--------|----------------------|------------------------|---------------------------|
| **Trigger** | Silence detection | Fixed 1s intervals | Fixed 1s intervals |
| **Buffer Size** | Variable (up to 15s) | Fixed 5s sliding | Variable (0-30s) |
| **Overlap** | None | 4s temporal overlap | Continuous context |
| **Latency** | Variable (silence-dependent) | Predictable 1s | Predictable 1s |
| **Context** | Speech segments only | 5s windows | Maximum 30s context |
| **Stabilization** | None | LocalAgreement | Pre-inference VAD |

## Future Work

- [ ] Compare new API SpeechAnalyzer when macOS 26 is released (non-beta). Nov 2025.
- [ ] Implement MLX whisper and compare performance. Oct 2025.
   - [ ] Add KV cache support. 
   - [ ] Tokenizer support. 
   - [ ] Quantization support for speed up 
- [ ] Explore hybrid approaches combining the best aspects of each method
- [ ] Investigate adaptive buffer sizing based on speech patterns
- [ ] Optimize VAD parameters for different acoustic environments

## History Highlight
- Compare the whisper.cpp and built-in SFSpeechRecognizer. 
- 3 Approaches audio arch: 
  - VAD-Based Silence Detection
  - 5-Second Fixed Sliding Windows  
  - 30-Second WhisperLive-Inspired Buffer

## Technical Notes

MLX-Swift only supports safetensors files. Use `Utilities/convert.py` to convert .pt files to .safetensors format.

**Required Files:**
```
Livcap/CoreWhisperCpp/ggml-base.en.bin
Livcap/CoreWhisperCpp/ggml-tiny.en.bin
Livcap/CoreWhisperCpp/ggml-base.en-encoder.mlmodelc
Livcap/CoreWhisperCpp/ggml-tiny.en-encoder.mlmodelc
Livcap/CoreWhisperCpp/whisper.xcframework
```

# Citation

```
@article{Whisper
  title = {Robust Speech Recognition via Large-Scale Weak Supervision},
  url = {https://arxiv.org/abs/2212.04356},
  author = {Radford, Alec and Kim, Jong Wook and Xu, Tao and Brockman, Greg and McLeavey, Christine and Sutskever, Ilya},
  publisher = {arXiv},
  year = {2022},
}
```