# Livcap



## Highlights:
- Privacy first, local model, no cloud, no analytics, no ads. No need internet connection. Free and open source. 
- Light weight and fast. One click to on/off.
- No annoying user analytics. If you think something can be improved, email me.
- Less is more. 






# Developement:

## Future work

- [ ] Compare new api SpeechAnalyzer when macOS 26 is released(non-beta). Nov 2025.

- [ ] Implement the mlx whisper and compare the performance. Oct 2025.
   - [ ] Add KV cache support. 
   - [ ] Tokenizer support. 
   - [ ] Quantization support for speed up 


## History highlight
- Compare the whisper.cpp and built-in SFSpeechRecognizer. 
- 3 Approaches audio arhc: 
  - Dual-Layer Approach
  - Hybrid Probabilistic Stream 
  - Context-Aware Segement and Refine.

Note:
MLX-Swift only support safetensors file, using the convert.py to convert the .pt file to .safetensors file
Usage:
Add the file in : 
Livcap/CoreWhisperCpp/ggml-base.en.bin
Livcap/CoreWhisperCpp/ggml-tiny.en.bin
Livcap/CoreWhisperCpp/ggml-base.en-encoder.mlmodelc
Livcap/CoreWhisperCpp/ggml-tiny.en-encoder.mlmodelc
Livcap/CoreWhisperCpp/whisper.xcframework

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