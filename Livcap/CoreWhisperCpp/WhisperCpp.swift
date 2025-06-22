//
//  CppWhisper.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/16/25.
//

import whisper
import Foundation

enum WhisperError: Error {
    case couldNotInitializeContext
}

struct WhisperModelName{
    let baseEn="ggml-base.en"
    let tinyEn="ggml-tiny.en"
}


actor WhisperCpp{
    private var context:OpaquePointer
    
    init(context: OpaquePointer){
        self.context = context
    }
    
    deinit {
        whisper_free(context)
    }
    
    func fullTranscribe(samples: [Float]) {
        // Leave 2 processors free (i.e. the high-efficiency cores).
        let maxThreads = max(1, min(8, cpuCount() - 2))
        print("Selecting \(maxThreads) threads")
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        "en".withCString { en in
            // Adapted from whisper.objc
            params.print_realtime   = true
            params.print_progress   = false
            params.print_timestamps = true
            params.print_special    = false
            params.translate        = false
            params.language         = en
            params.n_threads        = Int32(maxThreads)
            params.offset_ms        = 0
            params.no_context       = true
            params.single_segment   = false

            whisper_reset_timings(context)
            print("About to run whisper_full")
            samples.withUnsafeBufferPointer { samples in
                if (whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0) {
                    print("Failed to run the model")
                } else {
                    whisper_print_timings(context)
                }
            }
        }
    }
    
    
    func getTranscription() -> String {
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String.init(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
    }
    
    func getDetailedTranscription() -> [WhisperSegmentData] {
        var segments: [WhisperSegmentData] = []
        
        for segmentIndex in 0..<whisper_full_n_segments(context) {
            let segmentText = String(cString: whisper_full_get_segment_text(context, segmentIndex))
            let segmentStartTime = whisper_full_get_segment_t0(context, segmentIndex)
            let segmentEndTime = whisper_full_get_segment_t1(context, segmentIndex)
            
            var tokens: [WhisperTokenData] = []
            let tokenCount = whisper_full_n_tokens(context, segmentIndex)
            
            for tokenIndex in 0..<tokenCount {
                let tokenText = String(cString: whisper_full_get_token_text(context, segmentIndex, tokenIndex))
                let tokenProbability = whisper_full_get_token_p(context, segmentIndex, tokenIndex)
                let tokenData = whisper_full_get_token_data(context, segmentIndex, tokenIndex)
                
                let whisperToken = WhisperTokenData(
                    text: tokenText,
                    probability: tokenProbability,
                    logProbability: tokenData.plog,
                    timestampProbability: tokenData.pt,
                    startTime: segmentStartTime,
                    endTime: segmentEndTime
                )
                tokens.append(whisperToken)
            }
            
            let averageConfidence = tokens.isEmpty ? 0.0 : tokens.map(\.probability).reduce(0, +) / Float(tokens.count)
            
            let segment = WhisperSegmentData(
                text: segmentText,
                tokens: tokens,
                averageConfidence: averageConfidence,
                startTime: segmentStartTime,
                endTime: segmentEndTime
            )
            segments.append(segment)
        }
        
        return segments
    }
    
    func getConfidenceFiltered(minConfidence: Float = 0.3) -> [WhisperSegmentData] {
        let allSegments = getDetailedTranscription()
        return allSegments.filter { $0.averageConfidence >= minConfidence }
    }
    
    func getHighConfidenceText(minConfidence: Float = 0.5) -> String {
        let segments = getConfidenceFiltered(minConfidence: minConfidence)
        return segments.map(\.text).joined(separator: " ")
    }
    
    func getWordLevelConfidence() -> [(word: String, confidence: Float)] {
        let segments = getDetailedTranscription()
        var wordConfidences: [(String, Float)] = []
        
        for segment in segments {
            for token in segment.tokens {
                let word = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !word.isEmpty && !word.hasPrefix("<") && !word.hasSuffix(">") {
                    wordConfidences.append((word, token.probability))
                }
            }
        }
        
        return wordConfidences
    }
    
    
    static func benchMemcpy(nThreads: Int32) async -> String {
        return String.init(cString: whisper_bench_memcpy_str(nThreads))
    }
    
    static func benchGgmlMulMat(nThreads: Int32) async -> String {
        return String.init(cString: whisper_bench_ggml_mul_mat_str(nThreads))
    }
    
    private func systemInfo() -> String {
        let info = ""
        //if (ggml_cpu_has_neon() != 0) { info += "NEON " }
        return String(info.dropLast())
    }
    
    
    
    func benchFull(modelName: String, nThreads: Int32) async -> String {
        let nMels = whisper_model_n_mels(context)
        if (whisper_set_mel(context, nil, 0, nMels) != 0) {
            return "error: failed to set mel"
        }

        // heat encoder
        if (whisper_encode(context, 0, nThreads) != 0) {
            return "error: failed to encode"
        }

        var tokens = [whisper_token](repeating: 0, count: 512)

        // prompt heat
        if (whisper_decode(context, &tokens, 256, 0, nThreads) != 0) {
            return "error: failed to decode"
        }

        // text-generation heat
        if (whisper_decode(context, &tokens, 1, 256, nThreads) != 0) {
            return "error: failed to decode"
        }

        whisper_reset_timings(context)

        // actual run
        if (whisper_encode(context, 0, nThreads) != 0) {
            return "error: failed to encode"
        }

        // text-generation
        for i in 0..<256 {
            if (whisper_decode(context, &tokens, 1, Int32(i), nThreads) != 0) {
                return "error: failed to decode"
            }
        }

        // batched decoding
        for _ in 0..<64 {
            if (whisper_decode(context, &tokens, 5, 0, nThreads) != 0) {
                return "error: failed to decode"
            }
        }

        // prompt processing
        for _ in 0..<16 {
            if (whisper_decode(context, &tokens, 256, 0, nThreads) != 0) {
                return "error: failed to decode"
            }
        }

        whisper_print_timings(context)
        
        
        // macOS replacement for UIDevice info
        var systemInfoStruct = utsname()
        uname(&systemInfoStruct)
        let deviceModel = withUnsafePointer(to: &systemInfoStruct.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let systemName = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        let systemInfo = self.systemInfo()  // assuming this is already defined elsewhere
        let timings: whisper_timings = whisper_get_timings(context).pointee
        let encodeMs = String(format: "%.2f", timings.encode_ms)
        let decodeMs = String(format: "%.2f", timings.decode_ms)
        let batchdMs = String(format: "%.2f", timings.batchd_ms)
        let promptMs = String(format: "%.2f", timings.prompt_ms)

        return "| \(deviceModel) | \(systemName) | \(systemInfo) | \(modelName) | \(nThreads) | 1 | \(encodeMs) | \(decodeMs) | \(batchdMs) | \(promptMs) | <todo> |"

    }
    
    
    static func createContext(path: String) throws -> WhisperCpp {
        var params = whisper_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
        print("Running on the simulator, using CPU")
#else
        params.flash_attn = true // Enabled by default for Metal
#endif
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            return WhisperCpp(context: context)
        } else {
            print("Couldn't load model at \(path)")
            throw WhisperError.couldNotInitializeContext
        }
    }
}




fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
