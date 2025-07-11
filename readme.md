
![Frame 1](https://github.com/user-attachments/assets/2146ec4c-28a3-431e-89f8-7cf505e40066)


# Livcap


A live caption app for macOS. 
>Privacy first, light weight, friendly user experience for macOS users.
>What happens on your device, stays on your device. 


[![App Store](https://img.shields.io/badge/App%20Store-Available%20Now-blue?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/us/app/livcap/id6748108138?mt=12)  [![macOS Version](https://img.shields.io/badge/macOS-15.0+-red?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/) [![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)


## Highlights:
- Privacy first, local model, no cloud, no analytics, no ads, no need internet connection. 
- No annoying user analytics.
- Light weight and fast. One click to on/off.
- Performance concerned. 
- Free and open source. 
- Less is more. 




https://github.com/user-attachments/assets/2946aa64-c8ba-4af0-9569-295471312eeb





https://github.com/user-attachments/assets/c24fd7d4-b4e5-4843-ab81-db704b5dee30




https://github.com/user-attachments/assets/cbb2e8f6-a85c-4cce-ac33-6c737c29d9da


https://github.com/user-attachments/assets/2c438390-cc63-4c1e-a630-d1eb66276eed



## Released Notes
🎉 **v1.0 Now Available on the App Store!**

[Download Livcap from the Mac App Store](https://apps.apple.com/us/app/livcap/id6748108138?mt=12) 



## Development Introduction

### How good performance is Livcap? 


**Livcap outperforms macOS's native Live Caption with significant improvements:**

✅ **1.7x faster word-level lead rate**  
✅ **10% lower latency**  
✅ **More efficient processing with better resource utilization**

> See detailed comparison benchmarks in [`livcapComparision.md`](livcapComparision.md)

##### Technical Approach

Our performance gains come from three key optimizations:

🎯 **Single-pass inference** - Uses one SFSpeechRecognizer call instead of multiple inferences observed in native Live Caption

⚡ **Smart downsampling** - Converts audio from 48kHz to 16kHz before processing, maintaining quality while reducing computational overhead

🔇 **VAD-based silence skipping** - Voice Activity Detection prevents unnecessary processing during silent periods, saving resources and improving responsiveness 


### Why is Livcap Privacy-First?

**Complete local processing with zero external dependencies:**

🔒 **No cloud services** - Built entirely on Apple's native SFSpeechRecognizer framework, ensuring all speech processing happens locally on your device

🎵 **Direct audio access** - Uses CoreAudio Tap to capture system audio directly from the buffer, eliminating the need for ScreenCaptureKit or screen recording permissions

🛡️ **Zero data transmission** - Your conversations never leave your Mac - no servers, no analytics, no tracking 





# Development 




<details>
<summary>Development History</summary>



## History Highlight
- Compare the whisper.cpp and built-in SFSpeechRecognizer. 
- 3 Approaches audio arch: 
  - VAD-Based Silence Detection
  - 5-Second Fixed Sliding Windows  
  - 30-Second WhisperLive-Inspired Buffer


## Permission issue:
`tccutil reset All com.xxx.xx`

## Current Implementation:
Based on SFSpeechRecognizer from the apple built-in framework. 

## 3 Approaches Considerations History

<details>
<summary>Approach 1: VAD-Based Silence Detection ✅ **Most Reliable**</summary>

**Files:** `BufferManager.swift`, `VADProcessor.swift`, `EnhancedVAD.swift`

**How it works:**
- Accumulates speech until 3 consecutive silence frames
- Triggers inference on speech end or 15s maximum
- RMS threshold (0.01) with asymmetric hysteresis

**Characteristics:** Event-driven, variable buffer, speech-only segments

**Status:** ✅ Best balance of quality and usability

**Limitations:** Variable latency, potential word cutoff, VAD tuning needed
</details>

<details>
<summary>Approach 2: 5-Second Sliding Windows ❌ **Word-Level Chaos**</summary>

**Files:** `ContinuousStreamManager.swift`, `TranscriptionStabilizationManager.swift`

**How it works:**
- 5s sliding window with 1s stride (4s overlap)
- LocalAgreement algorithm for word-level stabilization
- Temporal overlap analysis for conflicts

**Characteristics:** Fixed 1s intervals, 5s buffer, word-level matching

**Status:** ❌ Overlap analysis creates transcription instability

**Limitations:** Complex word matching, frequent text changes, poor readability
</details>

<details>
<summary>Approach 3: 30-Second WhisperLive ❌ **High Latency**</summary>

**Files:** `WhisperLiveContinuousManager.swift`, `WhisperLiveAudioBuffer.swift`

**How it works:**
- Continuous 30s audio buffer
- 1s inference intervals with smart trimming
- Pre-inference VAD for speech extraction

**Characteristics:** Fixed 1s intervals, 30s context, maximum Whisper context

**Status:** ❌ >2s latency unsuitable for real-time

**Limitations:** Excessive latency, high overhead, memory intensive
</details>

## Current Conclusions

After extensive testing of all three approaches:

1. **Approach 1 (VAD-Based)** is currently the most practical solution, providing the best balance of quality and usability despite variable latency.

2. **Approach 2 (5s Sliding)** suffers from word-level chaos due to complex overlap analysis, making transcriptions unstable and hard to read.

3. **Approach 3 (30s WhisperLive)** provides excellent context but has unacceptable latency (>2s) for real-time applications.

<details>
<summary>Comparison Chart</summary>

| Aspect | Approach 1: VAD-Based | Approach 2: 5s Sliding | Approach 3: 30s WhisperLive |
|--------|----------------------|------------------------|---------------------------|
| **Trigger** | Silence detection | Fixed 1s intervals | Fixed 1s intervals |
| **Buffer Size** | Variable (up to 15s) | Fixed 5s sliding | Variable (0-30s) |
| **Overlap** | None | 4s temporal overlap | Continuous context |
| **Latency** | Variable (silence-dependent) | Predictable 1s | Predictable 1s |
| **Context** | Speech segments only | 5s windows | Maximum 30s context |
| **Stabilization** | None | LocalAgreement | Pre-inference VAD |

</details>
</details>

# Contributing

We welcome contributions! Please read our [Contributing Guidelines](CONTRIBUTION.md) before submitting PRs.

**Key Requirements:**
- Privacy first (no data collection/network features)
- Lightweight performance (maintain efficiency) 
- Simple UI design (minimal interface)
- Follow PR template with motivation, code summary, AI assistance docs, and demo(optional)

# Future Work

### Isuse Solve: 
`invalid display identifier 37D8832A-2D66-02CA-B9F7-8F30A301B230` when happend at the monitor changing. 

- [ ] Compare new API SpeechAnalyzer when macOS 26 is released (non-beta). Nov 2025.
- [ ] Implement MLX whisper and compare performance. Oct 2025.
   - [ ] Add KV cache support. 
   - [ ] Tokenizer support. 
   - [ ] Quantization support for speed up 
- [ ] Explore hybrid approaches combining the best aspects of each method
- [ ] Investigate adaptive buffer sizing based on speech patterns
- [ ] Optimize VAD parameters for different acoustic environments


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
