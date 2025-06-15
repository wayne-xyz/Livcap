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


public struct WhisperLoader{
    public static func load(printWeight:Bool=false) throws -> MLXWhisper{
        
        guard let modelPath=Bundle.main.path(forResource: WHISPER_MODEL_FOLDER, ofType: nil) else {
            throw NSError(domain: "WhisperLoader", code: 1, userInfo: [NSLocalizedDescriptionKey:"Model path not found"])
        }
        
        let configPath=(modelPath as NSString).appendingPathComponent("config.json")
        guard let configData=try? Data(contentsOf: URL(fileURLWithPath: configPath)), let config=try? JSONSerialization.jsonObject(with: configData) as? [String:Any] else {
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
        
        let weightPath=(modelPath as NSString).appendingPathComponent("weights.npz")
        
        guard let flatweight = try? MLX.loadArrays(url: URL(fileURLWithPath:weightPath)) else {
            throw NSError(domain: "WhisperLoader", code: 1, userInfo: [NSLocalizedDescriptionKey:"Failed to load weight.npz"])
        }
        
        let unflattened=ModuleParameters.unflattened(flatweight)
        try model.update(parameters: unflattened,verify: [.all])
        
        eval(model)
        if printWeight{
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
