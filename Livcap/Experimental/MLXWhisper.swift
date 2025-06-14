//
//  MLXWhisper.swift
//  Livcap
//
//  Created by Rongwei Ji on 6/9/25.
//

/// MLXWhisper.swift
///
/// Implements the architecture of the Whisper model using MLX.
/// This file includes the core model structure consisting of:
/// 1. The model architecture (encoder and decoder)
/// 2. Configuration loading through `ModelDimensions`
/// 3. Inference logic for audio-to-text transcription

//MLX Whisper.swift

import MLX
import MLXNN
import Foundation

/// MLXWhisper encapsulates the full Whisper model architecture in MLX,
/// combining the audio encoder and text decoder components for inference.
///
/// This class takes mel-spectrogram input and token input,
/// processes them through the encoder and decoder, and outputs predicted logits.
/// It also provides a placeholder method for model quantization.
class MLXWhisper{
    
    let encoder:AudioEncoder
    let decoder:TextDecoder
    
    public init (dims:ModelDimensions ){
        self.encoder=AudioEncoder(nMels: dims.nMels, nAudioCtx: dims.nAudioCtx, nAudioState: dims.nAudioState, nAudioHead: dims.nAudioHead, nAudioLayer: dims.nAudioLayer)
        self.decoder=TextDecoder(nVocab: dims.nVocab, nTextCtx: dims.nTextCtx, nTextState: dims.nTextState, nTextHead: dims.nTextHead, nTextLayer: dims.nTextLayer)
        
    }
    
    /// Runs the full Whisper model: encodes audio and decodes text tokens.
    ///
    /// - Parameters:
    ///   - x: Input mel-spectrogram (audio features).
    ///   - tokens: Input token IDs for decoding.
    /// - Returns: Predicted token logits.
    public func callAsFunction(x: MLXArray, tokens:MLXArray) -> MLXArray {
        let audioFeature=encoder(x)
        let textlogits=decoder(x: tokens, xa: audioFeature)
        return textlogits
        
    }

    //TODO: Update the implementation of the quantization
    public func applyQuantization(config:[String:Any]){
        print("Applying quantization:\(config)")
    }

}



/// Audio encoder module for processing mel-spectrogram inputs.
///
/// Applies two Conv1D layers, adds sinusoidal positional embeddings,
/// passes through a stack of residual attention blocks, and applies layer normalization.
///
/// - Parameters:
///   - nMels: Number of input mel-frequency bins.
///   - nAudioCtx: Number of time steps for the positional embedding.
///   - nAudioState: Hidden state size for the model.
///   - nAudioHead: Number of attention heads in each block.
///   - nAudioLayer: Number of residual attention blocks.
public class AudioEncoder:Module{
    @ModuleInfo var conv1:Conv1d
    @ModuleInfo var conv2:Conv1d
    
    var positionEmbedding:MLXArray
    
    @ModuleInfo var blocks:[ResidualAttentionBlock]
    @ModuleInfo var lnPost: LayerNorm
    
    public init(nMels:Int, nAudioCtx:Int, nAudioState:Int,nAudioHead:Int, nAudioLayer:Int) {
        self.conv1=Conv1d(inputChannels:  nMels, outputChannels: nAudioState, kernelSize: 3,padding: 1)
        self.conv2=Conv1d(inputChannels: nAudioState, outputChannels: nAudioState, kernelSize: 3,stride: 2,padding: 1)
        
        self.blocks=(0..<nAudioLayer).map{ _ in
            ResidualAttentionBlock(nState: nAudioState, nHead: nAudioHead)
        }
        
        self.lnPost=LayerNorm(dimensions: nAudioState)
        
        self.positionEmbedding = sinusoids(nAudioCtx, nAudioState)
    }
    
    public func callAsFunction(_ x:MLXArray) -> MLXArray {
        var x = gelu(conv1(x))
        x=gelu(conv2(x))
        x = x.transposed(0, 2, 1)//?(0,1) original code
        
        x = x + positionEmbedding[0..<x.shape[1]]

        for block in blocks {
            x = block(x)
        }
        
        x=lnPost(x)
        return x
    }
    
}



/// Text decoder module that generates logits from token inputs and encoder features.
/// Implements cross-attention and positional embeddings.
public class TextDecoder:Module{
    @ModuleInfo var tokenEmbedding:Embedding
    @ModuleInfo var posEmbedding:Embedding
    
    @ModuleInfo var blocks:[ResidualAttentionBlock]
    @ModuleInfo var ln: LayerNorm
    
    init(nVocab:Int, nTextCtx:Int,nTextState:Int, nTextHead:Int,nTextLayer:Int) {
        self.tokenEmbedding=Embedding(embeddingCount: nVocab, dimensions: nTextState)
        self.posEmbedding=Embedding(embeddingCount: nTextCtx, dimensions: nTextState)
        
        self.blocks=(0..<nTextLayer).map{_ in
                ResidualAttentionBlock(nState: nTextState, nHead: nTextHead, hasCrossAttn: true)
        }
        
        self.ln=LayerNorm(dimensions: nTextState)
        
    }
    
    /// Runs the text decoder with token and encoder inputs.
    /// - Parameters:
    ///   - x: Input token IDs.
    ///   - xa: Encoder output features (for cross-attention).
    /// - Returns: Predicted token logits.
    public func callAsFunction(x:MLXArray,xa:MLXArray)->MLXArray {
        let positions=MLXArray(0..<x.shape[1])
        var x=tokenEmbedding(x)+posEmbedding(positions)
        
        for block in blocks {
            x=block(x,xa: xa)
        }
        
        x=ln(x)
        let logits=x.matmul(tokenEmbedding.weight.T)
        return logits
    }
}



/// A residual block combining self-attention, optional cross-attention,
/// and a feedforward MLP with skip connections and layer normalization.
/// Used in transformer-based architectures.
public class ResidualAttentionBlock:Module{
    @ModuleInfo var attn:MultiHeadAttention
    @ModuleInfo var attnLn:LayerNorm
    
    @ModuleInfo var crossAttn:MultiHeadAttention?
    @ModuleInfo var crossAttnLn:LayerNorm?
    
    @ModuleInfo var mlp:[any UnaryLayer]
    @ModuleInfo var mlpLn:LayerNorm
    
    public init(nState: Int,nHead:Int, hasCrossAttn:Bool=false){
        self.attnLn=LayerNorm(dimensions: nState)
        self.attn=MultiHeadAttention(nState: nState, nHead: nHead)
        
        if hasCrossAttn{
            self.crossAttnLn=LayerNorm(dimensions: nState)
            self.crossAttn=MultiHeadAttention(nState: nState, nHead: nHead)
        }
        
        self.mlpLn=LayerNorm(dimensions: nState)
        self.mlp=[
            Linear(nState,nState*4),
            GELU(),
            Linear(nState*4,nState)
        ]
    }
    
    /// - Parameter x: The input sequence.
    /// - Parameter xa: The context sequence from the encoder (only for cross-attention).
    /// - Parameter mask: Optional mask to prevent attention to future tokens.
    public func callAsFunction(_ x:MLXArray,xa:MLXArray?=nil, mask:MLXArray?=nil) -> MLXArray{
        var x = x + attn(attnLn(x),mask:mask)
        
        if let crossAttn, let crossAttnLn, let xa{
            x = x + crossAttn(crossAttnLn(x),kv:xa)
        }
        
        x = x + mlp.reduce(mlpLn(x)){ $1($0) }
        return x
    }
    
}




/// A Multi-Head Attention module that implements the attention mechanism used in transformer architectures.
/// This class performs scaled dot-product attention across multiple heads in parallel.
///
/// The attention mechanism allows the model to focus on different parts of the input sequence
/// simultaneously through multiple attention heads. Each head can learn different aspects of
/// the relationships between elements in the sequence.
///
/// Key components:
/// - Query, Key, and Value linear transformations
/// - Multi-head attention computation
/// - Scaled dot-product attention with optional masking
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
    
    public func callAsFunction(_ x:MLXArray, kv:MLXArray?=nil, mask:MLXArray?=nil) -> MLXArray {
        let q=query(x)
        let k=key(kv ?? x)
        let v=value(kv ?? x)
        
        let (output, _) = MultiHeadAttention.applyAttention(
            queries: q, keys: k, values: v, nHead: nHead, mask: mask)

        return out(output)
    }
    
    
    
    /**
    Performs scaled dot-product attention with multiple heads.

    Reshapes inputs for multi-head computation, calculates attention
    scores via scaled dot-product, applies optional mask, then uses
    softmax to weight values.

    - Parameters:
      - queries: (B, L, D) query tensor
      - keys: (B, S, D) key tensor
      - values: (B, S, D) value tensor
      - n_head: number of attention heads
      - mask: optional mask (broadcastable to score shape)

    - Returns:
      - output: (B, L, D) attention output
      - scores: (B, n_head, L, S) attention weights
    */
    public static func applyAttention(
        queries: MLXArray, keys: MLXArray, values: MLXArray, nHead: Int, mask: MLXArray? = nil
    ) -> (MLXArray, MLXArray) {
        
        // batch size(number of sequence in para), length of sequence, hidden dimension
        let (B, L, D) = (queries.shape[0], queries.shape[1], queries.shape[2])
        let (S) = (keys.shape[1])
        
        // 1. Reshape and transpose for multi-head computation
        let queries = queries.reshaped(B, L, nHead, D / nHead).transposed(0, 2, 1, 3)
        let keys = keys.reshaped(B, S, nHead, D / nHead).transposed(0, 2, 3, 1)
        let values = values.reshaped(B, S, nHead, D / nHead).transposed(0, 2, 1, 3)
        
        // 2. Scaled dot-product attention
        let scale = Float(1.0 / sqrt(Double(D / nHead)))
        var scores = (queries * scale).matmul(keys)
        if let mask {
            scores = scores + mask.asType(scores.dtype)
        }
        
        scores = softmax(scores, axis: -1)
        
        // 3. Apply attention scores to values
        let output = scores.matmul(values).transposed(0, 2, 1, 3).reshaped(B, L, D)
        
        return (output, scores)
    }
    
}


/// A struct to hold the model dimensions, deserialized from `config.json`.
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


/// Generates sinusoidal positional embeddings, a fixed (non-learned) component.
private func sinusoids(_ length: Int, _ channels: Int, max_timescale: Float = 10000.0) -> MLXArray {
    let log_timescale_increment = log(max_timescale) / Float(channels / 2 - 1)
    let inv_timescales = exp(MLXArray(0..<channels/2) * -log_timescale_increment)
    let scaled_time = MLXArray(0..<length).expandedDimensions(axis: 1) * inv_timescales.expandedDimensions(axis: 0)
    let signal = concatenated([sin(scaled_time), cos(scaled_time)], axis: 1)
    return signal.reshaped(length, channels)
}
