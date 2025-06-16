//
//  MLXWhisper.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

/// MLXWhisper.swift
///
/// Implements the Whisper model architecture using MLX framework.
/// This implementation includes:
/// 1. Audio encoder for processing mel-spectrograms
/// 2. Text decoder for generating transcriptions
/// 3. Multi-head attention mechanisms
/// 4. Residual attention blocks
/// 5. Model configuration and quantization support

//MLX Whisper.swift

import MLX
import MLXNN
import Foundation


// String resouce for the keys values
struct ModuleKeys{

    static let tokenEmbedding="token_embedding"
    static let positionalEmbedding="positional_embedding"
    static let lnPost="ln_post"
    static let attnLn="attn_ln"
    static let crossAttn="cross_attn"
    static let crossAttnLn="cross_attn_ln"
    static let mlpln="mlp_ln"
    static let mlp1="mlp1" //?
    static let mlp2="mlp2" //?
}


/// MLXWhisper implements the complete Whisper model architecture using MLX.
/// It combines an audio encoder and text decoder to perform speech-to-text transcription.
///
/// The model processes audio input through the encoder to extract features,
/// then uses these features in the decoder to generate text transcriptions.
public class MLXWhisper:Module{
    
    @ModuleInfo var encoder:AudioEncoder
    @ModuleInfo var decoder:TextDecoder
    
    public init (dims:ModelDimensions ){
        self.encoder=AudioEncoder(nMels: dims.nMels, nAudioCtx: dims.nAudioCtx, nAudioState: dims.nAudioState, nAudioHead: dims.nAudioHead, nAudioLayer: dims.nAudioLayer)
        self.decoder=TextDecoder(nVocab: dims.nVocab, nTextCtx: dims.nTextCtx, nTextState: dims.nTextState, nTextHead: dims.nTextHead, nTextLayer: dims.nTextLayer)
        
    }
    
    /// Processes audio input and generates text transcriptions.
    ///
    /// - Parameters:
    ///   - x: Input mel-spectrogram tensor of shape [batch_size, n_mels, time_steps]
    ///   - tokens: Input token IDs tensor of shape [batch_size, sequence_length]
    /// - Returns: Logits tensor of shape [batch_size, sequence_length, vocab_size]
     public func callAsFunction(x: MLXArray, tokens:MLXArray) -> MLXArray {
        let audioFeature=encoder(x)
        let (textlogits,_)=decoder(x: tokens, xa: audioFeature)
        return textlogits
        
    }

    /// Applies quantization to the model weights to reduce memory usage and improve inference speed.
    ///
    /// - Parameters:
    ///   - config: Dictionary containing quantization parameters (group_size, bits)
    ///   - weights: Dictionary of model weights with their corresponding scaling factors
    public func applyQuantization(config:[String:Any], weights: [String: MLXArray]){
        // The `class_predicate` from the Python code is a closure that determines
        // whether a specific layer should be quantized.
        var classPredicate = { (path: String, module: Module) -> Bool in
            // Check if the module is a type that can be quantized.
            let isQuantizableType = module is Linear || module is Embedding
            
            // Check if the scaling factors for this specific layer exist in the loaded weights.
            // This ensures we only quantize layers that were prepared for it.
            let hasScales = weights["\(path).scales"] != nil
            
            return isQuantizableType && hasScales
        }
        
        // `nn.quantize` is a placeholder for the actual MLXNN Swift API.
        // You would pass the configuration and the predicate to it.
        // e.g., nn.quantize(self, groupSize: config["group_size"], bits: config["bits"], predicate: classPredicate)
        print("Applying quantization with predicate...")
    }

}



/// AudioEncoder processes mel-spectrogram inputs through convolutional layers and transformer blocks.
///
/// The encoder consists of:
/// 1. Two convolutional layers for initial feature extraction
/// 2. Sinusoidal positional embeddings
/// 3. A stack of residual attention blocks
/// 4. Final layer normalization
public class AudioEncoder:Module{
    @ModuleInfo var conv1:Conv1d
    @ModuleInfo var conv2:Conv1d
    
    var positionEmbedding:MLXArray
    
    @ModuleInfo var blocks:[ResidualAttentionBlock]
    @ModuleInfo(key: ModuleKeys.lnPost) var lnPost: LayerNorm
    
    public init(nMels:Int, nAudioCtx:Int, nAudioState:Int,nAudioHead:Int, nAudioLayer:Int) {
        self.conv1=Conv1d(inputChannels:  nMels, outputChannels: nAudioState, kernelSize: 3,padding: 1)
        self.conv2=Conv1d(inputChannels: nAudioState, outputChannels: nAudioState, kernelSize: 3,stride: 2,padding: 1)
        
        self.blocks=(0..<nAudioLayer).map{ _ in
            ResidualAttentionBlock(nState: nAudioState, nHead: nAudioHead)
        }
        
        self._lnPost.wrappedValue=LayerNorm(dimensions: nAudioState)
        
        self.positionEmbedding = sinusoids(nAudioCtx, nAudioState)
    }
    
    /// Processes mel-spectrogram input through the encoder.
    ///
    /// - Parameter x: Input mel-spectrogram tensor of shape [batch_size, n_mels, time_steps]
    /// - Returns: Encoded features tensor of shape [batch_size, time_steps, n_audio_state]
    public func callAsFunction(_ x:MLXArray) -> MLXArray {
        var x = gelu(conv1(x))
        x=gelu(conv2(x))
        x = x.transposed(0, 2, 1)//?(0,1) original code
        
        x = x + positionEmbedding[0..<x.shape[1]]

        for block in blocks {
            (x,_) = block(x)
        }
        
        x=lnPost(x)
        return x
    }
    
}



/// TextDecoder generates text transcriptions using the encoded audio features.
///
/// The decoder implements:
/// 1. Token and positional embeddings
/// 2. Cross-attention with encoder features
/// 3. Self-attention blocks
/// 4. Final layer normalization and projection
public class TextDecoder:Module{
    @ModuleInfo(key: ModuleKeys.tokenEmbedding) var tokenEmbedding: Embedding
    @ParameterInfo(key: ModuleKeys.positionalEmbedding) var positionalEmbedding:MLXArray
    
    @ModuleInfo var blocks:[ResidualAttentionBlock]
    @ModuleInfo var ln: LayerNorm
    
    init(nVocab:Int, nTextCtx:Int,nTextState:Int, nTextHead:Int,nTextLayer:Int) {
        self._tokenEmbedding.wrappedValue=Embedding(embeddingCount: nVocab, dimensions: nTextState)
        self._positionalEmbedding.wrappedValue=MLXArray.zeros([nTextCtx,nTextState])
        
        self.blocks=(0..<nTextLayer).map{_ in
                ResidualAttentionBlock(nState: nTextState, nHead: nTextHead, hasCrossAttn: true)
        }
        
        self.ln=LayerNorm(dimensions: nTextState)
        
    }
    
    /// Generates text transcriptions from input tokens and encoder features.
    ///
    /// - Parameters:
    ///   - x: Input token IDs tensor of shape [batch_size, sequence_length]
    ///   - xa: Encoder features tensor of shape [batch_size, audio_steps, n_audio_state]
    /// - Returns: Tuple containing:
    ///   - Logits tensor of shape [batch_size, sequence_length, vocab_size]
    ///   - Cross-attention scores for visualization/analysis
    public func callAsFunction(x:MLXArray,xa:MLXArray)->(MLXArray, [MLXArray?]) {
        
        var x=tokenEmbedding(x)+positionalEmbedding[0..<x.shape[1]]
        
        var crossQKs=[MLXArray?]()
        for block in blocks {
            let (newX,crossQk)=block(x,xa: xa)
            x = newX
            crossQKs.append(crossQk)
        }
        
        x=ln(x)
        let logits=x.matmul(tokenEmbedding.weight.T)
        return (logits,crossQKs)
    }
}



/// ResidualAttentionBlock implements a transformer block with optional cross-attention.
///
/// Each block contains:
/// 1. Self-attention with layer normalization
/// 2. Optional cross-attention for encoder-decoder interaction
/// 3. Feed-forward network with GELU activation
/// 4. Residual connections throughout
public class ResidualAttentionBlock:Module{
    @ModuleInfo var attn:MultiHeadAttention
    @ModuleInfo(key: ModuleKeys.attnLn) var attnLn:LayerNorm
    @ModuleInfo(key: ModuleKeys.crossAttn) var crossAttn:MultiHeadAttention?
    @ModuleInfo(key: ModuleKeys.crossAttnLn) var crossAttnLn:LayerNorm?
    
    @ModuleInfo var mlp1:Linear
    @ModuleInfo var mlp2:Linear
    @ModuleInfo(key: ModuleKeys.mlpln) var mlpLn:LayerNorm
    
    public init(nState: Int,nHead:Int, hasCrossAttn:Bool=false){
        self._attnLn.wrappedValue=LayerNorm(dimensions: nState)
        self.attn=MultiHeadAttention(nState: nState, nHead: nHead)
        
        if hasCrossAttn{
            self._crossAttnLn.wrappedValue=LayerNorm(dimensions: nState)
            self._crossAttn.wrappedValue=MultiHeadAttention(nState: nState, nHead: nHead)
        }
        
        
        let nMlp=nState*4
        self.mlp1=Linear(inputDimensions: nState, outputDimensions: nMlp)
        self.mlp2=Linear(inputDimensions: nMlp, outputDimensions: nState)
        self._mlpLn.wrappedValue=LayerNorm(dimensions: nState)
    }
    
    /// Processes input through the attention block.
    ///
    /// - Parameters:
    ///   - x: Input tensor of shape [batch_size, sequence_length, hidden_size]
    ///   - xa: Optional encoder features for cross-attention
    ///   - mask: Optional attention mask
    /// - Returns: Tuple containing:
    ///   - Processed output tensor
    ///   - Optional cross-attention scores
    public func callAsFunction(_ x:MLXArray,xa:MLXArray?=nil, mask:MLXArray?=nil) -> (MLXArray,MLXArray?){
        var x=x
        var (y,_) = attn(attnLn(x),mask:mask)
        x=x+y
        var crossQK:MLXArray?
        if let crossAttn, let crossAttnLn, let xa{
            let (y,qk) = crossAttn(crossAttnLn(x),kv:xa)
            x = x + y
            crossQK = qk
        }
        x = x + mlp2(gelu(mlp1(mlpLn(x))))

        return (x, crossQK)
    }
    
}




/// MultiHeadAttention implements the scaled dot-product attention mechanism.
///
/// Features:
/// 1. Multi-head parallel attention computation
/// 2. Scaled dot-product attention
/// 3. Optional attention masking
/// 4. Linear projections for queries, keys, and values
public class MultiHeadAttention:Module {
    @ModuleInfo var query:Linear
    @ModuleInfo var key:Linear
    @ModuleInfo var value:Linear
    @ModuleInfo var out:Linear
    
    let nHead:Int
    
    public init(nState:Int, nHead:Int){
        self.nHead=nHead
        self.query=Linear(nState,nState)
        self.key=Linear(nState,nState,bias: false)
        self.value=Linear(nState,nState)
        self.out=Linear(nState,nState)
    }
    
    /// Computes attention between input sequences.
    ///
    /// - Parameters:
    ///   - x: Input tensor for self-attention or query tensor for cross-attention
    ///   - kv: Optional key-value tensor for cross-attention
    ///   - mask: Optional attention mask
    /// - Returns: Tuple containing:
    ///   - Attention output tensor
    ///   - Attention scores for analysis
    public func callAsFunction(_ x:MLXArray, kv:MLXArray?=nil, mask:MLXArray?=nil) -> (MLXArray,MLXArray) {
        let q=query(x)
        let k=key(kv ?? x)
        let v=value(kv ?? x)
        
        let (output, qk) = MultiHeadAttention.applyQKVAttention(
            queries: q, keys: k, values: v, nHead: nHead, mask: mask)

        return (out(output),qk)
    }
    
    
    
    /// Applies scaled dot-product attention across multiple heads.
    ///
    /// - Parameters:
    ///   - queries: Query tensor of shape [batch_size, query_length, hidden_size]
    ///   - keys: Key tensor of shape [batch_size, key_length, hidden_size]
    ///   - values: Value tensor of shape [batch_size, value_length, hidden_size]
    ///   - nHead: Number of attention heads
    ///   - mask: Optional attention mask
    /// - Returns: Tuple containing:
    ///   - Attention output tensor
    ///   - Attention scores tensor
    public static func applyQKVAttention(
        queries: MLXArray, keys: MLXArray, values: MLXArray, nHead: Int, mask: MLXArray? = nil
    ) -> (MLXArray, MLXArray) {
        
        // batch size, length of sequence, hidden dimension
        let (B, L, D) = (queries.shape[0], queries.shape[1], queries.shape[2])
        let (S) = (keys.shape[1])
        let headDim = D / nHead
        
        // 1. Calculate scaling factor (aligned with python version: (n_state // self.n_head) ** -0.25)
        let scale = Float(pow(Double(headDim), -0.25))

        // 2. Reshape, transpose, and apply scale for multi-head computation
        // Scale is applied to Q and K before matmul, just like the python version
        let queries = queries.reshaped(B, L, nHead, headDim).transposed(0, 2, 1, 3) * scale
        let keys = keys.reshaped(B, S, nHead, headDim).transposed(0, 2, 3, 1) * scale
        let values = values.reshaped(B, S, nHead, headDim).transposed(0, 2, 1, 3)
        
        // 3. Scaled dot-product attention (qk)
        // No additional scaling needed here as it was applied above
        var qk = queries.matmul(keys)
        
        if let mask {
            // Apply a slice of the mask, mirroring python's mask[:n_ctx, :n_ctx]
            // Assuming L (query length) and S (key length) correspond to n_ctx
            qk = qk + mask[0..<L, 0..<S].asType(qk.dtype)
        }
        
        // 4. Apply softmax to get attention weights
        // Note: Python's `precise=True` is not available in MLX Swift's softmax
        let scores = softmax(qk, axis: -1)
        
        // 5. Apply attention weights to values
        let output = scores.matmul(values).transposed(0, 2, 1, 3).reshaped(B, L, D)
        
        // 6. Return output and pre-softmax scores (qk), matching the python version
        return (output, qk)
    }
    
}


/// ModelDimensions defines the architectural parameters of the Whisper model.
///
/// These dimensions are loaded from the model's configuration file and determine:
/// - Audio processing parameters (mel bins, context size)
/// - Model capacity (state sizes, number of layers)
/// - Attention configuration (number of heads)
public struct ModelDimensions {
    let nMels: Int
    let nVocab: Int
    let nAudioCtx: Int
    let nAudioState: Int
    let nAudioHead: Int
    let nAudioLayer: Int
    let nTextCtx: Int
    let nTextState: Int
    let nTextHead: Int
    let nTextLayer: Int
}


/// Generates sinusoidal positional embeddings for sequence position encoding.
///
/// - Parameters:
///   - length: Sequence length
///   - channels: Embedding dimension
///   - max_timescale: Maximum time scale for frequency generation
/// - Returns: Positional embeddings tensor of shape [length, channels]
private func sinusoids(_ length: Int, _ channels: Int, max_timescale: Float = 10000.0) -> MLXArray {
    let log_timescale_increment = log(max_timescale) / Float(channels / 2 - 1)
    let inv_timescales = exp(MLXArray(0..<channels/2) * -log_timescale_increment)
    let scaled_time = MLXArray(0..<length).expandedDimensions(axis: 1) * inv_timescales.expandedDimensions(axis: 0)
    let signal = concatenated([sin(scaled_time), cos(scaled_time)], axis: 1)
    return signal.reshaped(length, channels)
}
