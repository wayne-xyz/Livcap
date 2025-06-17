//
//  WhisperLoader.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/14/25.
//

import Foundation
import MLX
import MLXNN

let WHISPER_MODEL_FOLDER="WhisperModelTiny"
let CONGIG_FILE="config.json"
let WEIGHT_FILE="weights.safetensors"


public struct WhisperLoader{
    public static func load(printLog:Bool=false) throws -> MLXWhisper{
        
        guard let configPath = Bundle.main.path(forResource: CONGIG_FILE, ofType: nil) else {
            throw NSError(domain: "WhisperLoader", code: 1, userInfo: [NSLocalizedDescriptionKey:"Config file not found"])
        }
        
        guard let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONSerialization.jsonObject(with: configData) as? [String:Any] else {
            throw NSError(domain: "WhisperLoader", code: 1, userInfo: [NSLocalizedDescriptionKey:"Failed to load config.json"])
        }
        
        // Create ModelDimensions from config
         let dimensions = ModelDimensions(
             nMels: config["n_mels"] as? Int ?? 80,
             nVocab: config["n_vocab"] as? Int ?? 51865,
             nAudioCtx: config["n_audio_ctx"] as? Int ?? 1500,
             nAudioState: config["n_audio_state"] as? Int ?? 384,
             nAudioHead: config["n_audio_head"] as? Int ?? 6,
             nAudioLayer: config["n_audio_layer"] as? Int ?? 4,
             nTextCtx: config["n_text_ctx"] as? Int ?? 448,
             nTextState: config["n_text_state"] as? Int ?? 384,
             nTextHead: config["n_text_head"] as? Int ?? 6,
             nTextLayer: config["n_text_layer"] as? Int ?? 4
         )
        
        let model=MLXWhisper(dims: dimensions)
        
        guard let weightPath = Bundle.main.path(forResource: WEIGHT_FILE, ofType: nil) else {
            throw NSError(domain: "WhisperLoader", code: 1, userInfo: [NSLocalizedDescriptionKey:"Failed to load weight.npz"])
        }
        
        guard let flatweight = try? loadArrays(url: URL(fileURLWithPath: weightPath)) else {
            throw NSError(domain: "WhisperLoader", code: 1, userInfo: [NSLocalizedDescriptionKey:"Failed to convert weight.npz"])
        }
        
        if printLog{
            debugWeight(flatweight: flatweight)
        }
        
        let unflattened=ModuleParameters.unflattened(flatweight)
        try model.update(parameters: unflattened,verify: [.all])
        
        eval(model)
        if printLog{
            // Print NPZ weight information
            print("📊 NPZ Weight Information:")
            print("   • Total weight arrays: \(flatweight.count)")
            
            let totalParams = flatweight.values.reduce(0) { sum, array in
                return sum + array.size
            }
            print("   • Total parameters: \(String(format: "%.2fM", Double(totalParams) / 1_000_000))")
            
            // Print weight shapes and types
            print("   • Weight details:")
            for (key, array) in flatweight.sorted(by: { $0.key < $1.key }) {
                let shape = array.shape.map(String.init).joined(separator: "×")
                let size = array.size
                print("     - \(key): [\(shape)] (\(size) params)")
            }
        }
        
        return model
    
        
    }
    
}



public func debugWeight(flatweight:[String:MLXArray]){
    // Add this debug section to print all keys
    print("🔑 Available weight keys:")
    for key in flatweight.keys.sorted() {
        print("   - \(key)")
    }

    // Print detailed information about each weight
    print("\n📊 Detailed weight information:")
    for (key, array) in flatweight.sorted(by: { $0.key < $1.key }) {
        let shape = array.shape.map(String.init).joined(separator: "×")
        let size = array.size
        let dtype = array.dtype
        print("   • \(key):")
        print("     - Shape: [\(shape)]")
        print("     - Size: \(size) parameters")
        print("     - Data type: \(dtype)")
    }
    
}
